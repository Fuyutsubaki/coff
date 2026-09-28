require "json"
require "open3"
require "fileutils"
require "set"

module Dullmify
  # 未回答の問いで今回の実行を終えるための合図。workflow の通常の rescue には捕まらない。
  class Pending < Exception
    attr_reader :record

    def initialize(record)
      @record = record
      super()
    end
  end

  class Failure < StandardError; end
  class Nondeterminism < StandardError; end

  # 一回の再実行で、記録を先頭から照合しながら補助関数を提供する。
  class Runtime
    attr_reader :run_dir, :records, :cursor

    def initialize(run_dir, workflow_key)
      @run_dir = File.expand_path(run_dir)
      @workflow_key = clean(workflow_key)
      @records_path = File.join(@run_dir, "records.jsonl")
      @cursor = 0
      @records = load_records
    end

    def prepare!
      expected = read_binary(File.join(@run_dir, "workflow-key"))
      raise Nondeterminism, "workflow またはランタイムが実行途中で変更されました" unless clean(expected) == @workflow_key

      answer_path = File.join(@run_dir, "answer")
      return unless File.file?(answer_path)

      pending = @records.find { |record| record["type"] == "ask" && !record.key?("result") }
      raise Nondeterminism, "回答の対象になる問いが記録にありません" unless pending

      pending["result"] = clean(trim_one_newline(read_binary(answer_path)))
      save_records
      File.delete(answer_path)
    end

    def arguments
      path = File.join(@run_dir, "args")
      raise Failure, "引数ファイルがありません" unless File.file?(path)

      clean(trim_one_newline(read_binary(path)))
    end

    def ask(prompt, input)
      key = { "prompt" => clean(prompt.to_s), "input" => clean(input.to_s) }
      record = consume("ask", key) do
        append_record("type" => "ask", "key" => key)
      end
      raise Pending, record unless record.key?("result")

      record["result"]
    end

    def run_command(argv, stdin_data = "")
      command = Array(argv).map { |part| clean(part.to_s) }
      raise Failure, "コマンドの argv が空です" if command.empty?

      input = clean(stdin_data.to_s)
      key = { "argv" => command, "stdin" => input }
      record = consume("command", key) do
        stdout, stderr, status = Open3.capture3(*command, stdin_data: input)
        append_record(
          "type" => "command",
          "key" => key,
          "result" => {
            "exit_code" => status.exitstatus,
            "stdout" => clean(stdout),
            "stderr" => clean(stderr)
          }
        )
      end
      record["result"]
    end

    def read_file(path)
      normalized = clean(path.to_s)
      key = { "path" => normalized }
      record = consume("read", key) do
        value = File.file?(normalized) ? clean(read_binary(normalized)) : nil
        append_record("type" => "read", "key" => key, "result" => value)
      end
      record["result"]
    end

    def write_file(path, content)
      normalized = clean(path.to_s)
      value = clean(content.to_s)
      key = { "path" => normalized, "content" => value }
      record = consume("write", key) do
        parent = File.dirname(normalized)
        FileUtils.mkdir_p(parent) unless parent == "."
        File.binwrite(normalized, value)
        append_record("type" => "write", "key" => key, "result" => true)
      end
      record["result"]
    end

    def fail(reason)
      raise Failure, clean(reason.to_s)
    end

    def finish!
      return if @cursor == @records.length

      raise Nondeterminism, "記録をすべて消費せずに workflow が終了しました"
    end

    def save_records
      temporary = File.join(@run_dir, ".records.#{$PROCESS_ID}.tmp")
      File.open(temporary, "wb") do |file|
        @records.each do |record|
          file.write(JSON.generate(clean_value(record)))
          file.write("\n")
        end
      end
      File.rename(temporary, @records_path)
    ensure
      File.delete(temporary) if temporary && File.exist?(temporary)
    end

    private

    def consume(type, key)
      if @cursor < @records.length
        record = @records[@cursor]
        unless record["type"] == type && record["key"] == key
          raise Nondeterminism, "記録と今回の実行が一致しません（#{type}）"
        end
        @cursor += 1
        return record
      end

      record = yield
      @cursor += 1
      record
    end

    def append_record(record)
      normalized = clean_value(record)
      @records << normalized
      File.open(@records_path, "ab") do |file|
        file.write(JSON.generate(normalized))
        file.write("\n")
      end
      normalized
    end

    def load_records
      return [] unless File.exist?(@records_path)

      File.readlines(@records_path, chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
    rescue JSON::ParserError, SystemCallError => error
      raise Failure, "記録を読めません: #{clean(error.message)}"
    end

    def read_binary(path)
      File.binread(path)
    end

    def trim_one_newline(value)
      return value.byteslice(0, value.bytesize - 2) if value.end_with?("\r\n")
      return value.byteslice(0, value.bytesize - 1) if value.end_with?("\n")

      value
    end

    def clean(value)
      value.to_s.dup.force_encoding(Encoding::UTF_8).scrub("�")
    end

    def clean_value(value)
      case value
      when String then clean(value)
      when Array then value.map { |item| clean_value(item) }
      when Hash then value.to_h { |key, item| [clean(key.to_s), clean_value(item)] }
      else value
      end
    end
  end

  class << self
    attr_accessor :runtime

    def arguments = runtime.arguments
    def ask(prompt, input) = runtime.ask(prompt, input)
    def run_command(argv, stdin_data = "") = runtime.run_command(argv, stdin_data)
    def read_file(path) = runtime.read_file(path)
    def write_file(path, content) = runtime.write_file(path, content)
    def fail(reason) = runtime.fail(reason)
  end

  def self.clean_value(value)
    case value
    when String then value.dup.force_encoding(Encoding::UTF_8).scrub("�")
    when Array then value.map { |item| clean_value(item) }
    when Hash then value.to_h { |key, item| [clean_value(key.to_s), clean_value(item)] }
    else value
    end
  end

  def self.emit(value)
    puts JSON.generate(clean_value(value))
  end

  def self.remove_run(run_dir)
    FileUtils.remove_entry(run_dir) if File.exist?(run_dir)
  end

  def self.main(argv)
    unless argv.length == 2
      warn "ランタイムの引数が正しくありません"
      return 2
    end

    run_dir, workflow_key = argv
    unless File.file?(File.join(run_dir, "args"))
      emit("run" => File.expand_path(run_dir), "write" => File.join(File.expand_path(run_dir), "args"))
      return 0
    end
    self.runtime = Runtime.new(run_dir, workflow_key)
    runtime.prepare!
    cwd = File.binread(File.join(run_dir, "cwd")).sub(/\r?\n\z/, "")
    Dir.chdir(cwd)
    require_relative "workflow"
    report = workflow
    runtime.finish!
    emit("done" => true, "report" => report.to_s.scrub)
    remove_run(run_dir)
    0
  rescue Pending => pending
    key = pending.record.fetch("key")
    emit(
      "run" => File.expand_path(run_dir),
      "prompt" => key.fetch("prompt"),
      "input" => key.fetch("input"),
      "write" => File.join(File.expand_path(run_dir), "answer")
    )
    0
  rescue Failure, Nondeterminism, StandardError => error
    emit("failed" => error.message.to_s.scrub)
    remove_run(run_dir) if run_dir
    0
  end
end

exit(Dullmify.main(ARGV)) if $PROGRAM_NAME == __FILE__
