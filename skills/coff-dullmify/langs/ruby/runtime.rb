# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "securerandom"
require "set"
require "time"

# 再実行される workflow に、記録付きの問いと副作用を提供する。
module Dullmify
  SIGNAL = Object.new.freeze

  class Runtime
    attr_reader :records

    def initialize(run_dir)
      @run_dir = File.expand_path(run_dir)
      @records_path = File.join(@run_dir, "records.jsonl")
      @records = load_records
      @cursor = 0
      @inside_block = false
      @verifying = false
    end

    def execute
      prepare_answer
      Dir.chdir(read_required("cwd"))
      Dullmify.runtime = self
      # 中断の合図は workflow の中からも、report の検査や確認の再実行からも投げられる。
      outcome = catch(SIGNAL) do
        report = check_report(Object.new.send(:workflow))
        ensure_all_records_consumed
        @cursor = 0
        @verifying = true
        second_report = check_report(Object.new.send(:workflow))
        ensure_all_records_consumed
        nondeterministic!("確認の再実行で report が変わりました") unless report == second_report
        [:done, report]
      end
      case outcome[0]
      when :done
        finish({ "done" => true, "report" => outcome[1] })
      when :ask
        emit({ "run" => @run_dir, "prompt" => outcome[1], "input" => outcome[2],
               "write" => File.join(@run_dir, "answer") })
      else
        failed!(outcome[1])
      end
    rescue SignalException
      # 外から終了された run は、次の continue で再開できるよう残す。
      raise
    rescue Exception => e # rubocop:disable Lint/RescueException
      failed!("workflow で例外が発生しました: #{e.class}: #{e.message}")
    ensure
      Dullmify.runtime = nil
    end

    def arguments
      reject_nested!
      clean_text(trim_one_newline(File.binread(File.join(@run_dir, "args"))))
    end

    def ask(prompt, input = "")
      reject_nested!
      key = normalize([prompt, input])
      if (record = replay("ask", key))
        throw SIGNAL, [:ask, *key] unless record.key?("result")
        return record.fetch("result")
      end
      nondeterministic!("確認の再実行で新しい問いが現れました") if @verifying
      @records << { "type" => "ask", "key" => key }
      save_records
      throw SIGNAL, [:ask, *key]
    end

    def once(key, &block)
      recorded("once", key, reserve: false, &block)
    end

    def effect(key, &block)
      recorded("effect", key, reserve: true, &block)
    end

    def fail(reason)
      throw SIGNAL, [:failed, reason]
    end

    def now
      once(["now"]) { Time.now.utc.iso8601(6) }
    end

    def random(length)
      once(["random", length]) { SecureRandom.hex(Integer(length)) }
    end

    def env(name)
      once(["env", name]) { ENV[name] }
    end

    def read(path)
      once(["read", path]) { File.exist?(path) ? File.binread(path) : nil }
    end

    def write(path, content)
      effect(["write", path, content]) do
        parent = File.dirname(path)
        FileUtils.mkdir_p(parent) unless parent == "."
        File.binwrite(path, content)
        nil
      end
      nil
    end

    def command(argv, stdin = "")
      effect(["command", argv, stdin]) do
        begin
          stdout, stderr, status = Open3.capture3(*argv, stdin_data: stdin)
          { "exit_code" => status.exitstatus || 128 + status.termsig.to_i,
            "stdout" => stdout, "stderr" => stderr }
        rescue SystemCallError => e
          { "exit_code" => 127, "stdout" => "",
            "stderr" => "コマンドを起動できません: #{e.message}" }
        end
      end
    end

    def save_records
      temporary = File.join(@run_dir, ".records-#{Process.pid}.tmp")
      body = @records.map { |record| JSON.generate(record) }.join("\n")
      body << "\n" unless body.empty?
      File.binwrite(temporary, body)
      File.rename(temporary, @records_path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary)
    end

    private

    def recorded(type, key, reserve:)
      reject_nested!
      key = normalize(key)
      if (record = replay(type, key))
        # 結果のない記録は、実行前に予約した effect が途中で殺された場合だけにできる。
        throw SIGNAL, [:failed, "前回の副作用が途中で中断されました"] unless record.key?("result")
        return record.fetch("result")
      end
      nondeterministic!("確認の再実行で新しい #{type} が現れました") if @verifying

      record = { "type" => type, "key" => key }
      if reserve
        @records << record
        save_records
      end
      @inside_block = true
      begin
        value = normalize(yield)
      rescue SignalException
        raise
      rescue Exception => e # rubocop:disable Lint/RescueException
        throw SIGNAL, [:failed, "#{type} の処理で例外が発生しました: #{e.class}: #{e.message}"]
      ensure
        @inside_block = false
      end
      record["result"] = value
      @records << record unless reserve
      save_records
      @cursor += 1
      value
    end

    def replay(type, key)
      return nil if @cursor == @records.length
      record = @records.fetch(@cursor)
      unless record["type"] == type && record["key"] == key
        nondeterministic!("記録と補助関数の呼び出しが一致しません")
      end
      @cursor += 1
      record
    end

    def reject_nested!
      throw SIGNAL, [:failed, "once または effect の中で補助関数を呼べません"] if @inside_block
    end

    def ensure_all_records_consumed
      nondeterministic!("workflow が記録を最後まで消費しませんでした") unless @cursor == @records.length
    end

    def nondeterministic!(detail)
      throw SIGNAL, [:failed, "workflow が非決定です: #{detail}"]
    end

    def check_report(value)
      throw SIGNAL, [:failed, "report は文字列でなければなりません"] unless value.is_a?(String)
      value
    end

    def normalize(value)
      JSON.parse(JSON.generate(sanitize(value)))
    rescue JSON::JSONError, EncodingError, TypeError => e
      throw SIGNAL, [:failed, "JSON に記録できない値です: #{e.message}"]
    end

    def sanitize(value)
      case value
      when String then clean_text(value)
      when Symbol then clean_text(value.to_s)
      when Array then value.map { |item| sanitize(item) }
      when Hash then value.each_with_object({}) { |(key, item), out| out[clean_text(key.to_s)] = sanitize(item) }
      else value
      end
    end

    def clean_text(value)
      value.dup.force_encoding(Encoding::UTF_8).scrub
    end

    def trim_one_newline(value)
      value.sub(/\r?\n\z/, "")
    end

    def read_required(name)
      File.binread(File.join(@run_dir, name)).sub(/\r?\n\z/, "")
    end

    def load_records
      return [] unless File.exist?(@records_path)
      File.binread(@records_path).lines.map { |line| JSON.parse(line) }
    rescue JSON::JSONError, EncodingError => e
      raise "記録を読めません: #{e.message}"
    end

    def prepare_answer
      answer_path = File.join(@run_dir, "answer")
      return unless File.exist?(answer_path)
      pending = @records.find { |record| record["type"] == "ask" && !record.key?("result") }
      if pending
        pending["result"] = clean_text(trim_one_newline(File.binread(answer_path)))
        save_records
      end
      FileUtils.rm_f(answer_path)
    end

    def emit(object)
      puts JSON.generate(sanitize(object))
      object
    end

    def finish(object)
      FileUtils.rm_rf(@run_dir)
      emit(object)
    end

    def failed!(reason)
      FileUtils.rm_rf(@run_dir)
      emit({ "failed" => reason.to_s })
    end
  end

  class << self
    attr_writer :runtime

    def runtime
      @runtime || raise("Dullmify のランタイムが開始されていません")
    end

    %i[arguments ask once effect fail now random env read write command].each do |name|
      define_method(name) { |*args, &block| runtime.public_send(name, *args, &block) }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  run_dir = ARGV.fetch(0)
  begin
    require_relative "workflow"
    Dullmify::Runtime.new(run_dir).execute
  rescue SignalException
    raise
  rescue Exception => e # rubocop:disable Lint/RescueException
    FileUtils.rm_rf(run_dir)
    message = "ランタイムを開始できません: #{e.class}: #{e.message}".dup.force_encoding(Encoding::UTF_8).scrub
    puts JSON.generate({ "failed" => message })
  end
end
