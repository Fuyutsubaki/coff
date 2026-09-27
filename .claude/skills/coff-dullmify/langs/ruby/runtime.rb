# dullmify Ruby runtime.
#
# Usage (normally through `run`):
#   ruby runtime.rb start             creates a run directory, prints where to write the arguments
#   ruby runtime.rb continue <run>    takes in what was written (args, or the pending answer) and re-runs
#
# The workflow (`workflow.rb`, next to this file) is re-run from the top on every
# `continue`. Recorded questions and side effects return their recorded results;
# the first unanswered question is recorded, printed as JSON, and the process
# exits. Arguments and answers arrive as files in the run directory, written by
# the caller, so no command line has to carry them.
#
# Run directory (under ${TMPDIR:-/tmp}):
#   .dullmify-run   marker
#   cwd             working directory at start
#   workflow.hash   SHA-256 of workflow.rb at start
#   args            the skill's arguments, verbatim (written by the caller)
#   answer.<n>      the answer to ask <n> (written by the caller, consumed by continue)
#   records         one record per helper call (see Records)
#
# Record format (parsable without a JSON library):
#   <kind> <ask_no> <key_len> <result_len>\n<key>\n<result>\n
#   result_len is -1 for an unanswered ask, and then the result line is absent.

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'set'
require 'tmpdir'

module Dullmify
  # Leaves the workflow when an unanswered question is reached. Not a
  # StandardError, so `rescue => e` in the workflow cannot catch it.
  class Suspend < Exception
    attr_reader :ask_no, :prompt, :input

    def initialize(ask_no, prompt, input)
      super('dullmify: waiting for an answer')
      @ask_no = ask_no
      @prompt = prompt
      @input = input
    end
  end

  # Stops the run as failed. Not a StandardError for the same reason.
  class Failure < Exception
    attr_reader :reason

    def initialize(reason)
      super(reason)
      @reason = reason
    end
  end

  Record = Struct.new(:kind, :ask_no, :key, :result) # result nil = unanswered
  CommandResult = Struct.new(:status, :out, :err)

  class Runtime
    MARKER = '.dullmify-run'

    attr_reader :args

    def self.current
      @current
    end

    def self.current=(runtime)
      @current = runtime
    end

    def initialize(run_dir)
      @run_dir = run_dir
      @cwd = File.read(File.join(run_dir, 'cwd')).chomp
      @args = self.class.read_input(File.join(run_dir, 'args'))
      @records = load_records
      @cursor = 0
      @suspended = false
      @pending = nil
    end

    # --- run lifecycle ---------------------------------------------------

    # Creates the run directory. The caller writes the arguments to <run>/args
    # and then calls `continue`.
    def self.start(workflow_path)
      run_dir = Dir.mktmpdir('dullmify-run.', ENV['TMPDIR'] || '/tmp')
      File.write(File.join(run_dir, MARKER), '')
      File.write(File.join(run_dir, 'cwd'), Dir.pwd + "\n")
      File.write(File.join(run_dir, 'workflow.hash'), workflow_hash(workflow_path) + "\n")
      File.write(File.join(run_dir, 'records'), '')
      run_dir
    end

    # A file written by the caller, minus one trailing newline. nil if absent.
    def self.read_input(path)
      return nil unless File.file?(path)

      data = File.binread(path).force_encoding('UTF-8')
      data.end_with?("\n") ? data[0...-1] : data
    end

    # Validates the call, takes in the pending answer if one was written, and
    # returns the runtime ready to execute. Exits 2 with a message on stderr
    # when the caller still has something to write; the run is left untouched.
    def self.continue(run_dir, workflow_path)
      unless File.file?(File.join(run_dir, MARKER))
        warn "not a dullmify run: #{run_dir}"
        exit 2
      end
      stored = File.read(File.join(run_dir, 'workflow.hash')).chomp
      if stored != workflow_hash(workflow_path)
        $stdout.write(JSON.generate('failed' => 'workflow changed since the run started') + "\n")
        FileUtils.rm_rf(run_dir)
        exit 0
      end
      begin
        runtime = new(run_dir)
      rescue Failure => e
        $stdout.write(JSON.generate('failed' => e.reason) + "\n")
        FileUtils.rm_rf(run_dir)
        exit 0
      end
      if runtime.args.nil?
        warn "write the arguments to #{File.join(run_dir, 'args')} first (an empty file if there are none), then continue"
        exit 2
      end
      last = runtime.records.last
      if last && last.kind == 'ask' && last.result.nil?
        answer_path = File.join(run_dir, "answer.#{last.ask_no}")
        answer = read_input(answer_path)
        if answer.nil?
          warn "write the answer to ask #{last.ask_no} to #{answer_path} first, then continue"
          exit 2
        end
        last.result = answer
        runtime.rewrite_records
        File.delete(answer_path)
      end
      runtime
    end

    def self.workflow_hash(path)
      Digest::SHA256.file(path).hexdigest
    end

    def records
      @records
    end

    # Runs the workflow and prints exactly one JSON line. Always exits 0.
    def execute(workflow_path)
      Runtime.current = self
      Dir.chdir(@cwd)
      load workflow_path
      # Run at the top level so that helper calls resolve to the wrappers below,
      # not to this object's methods.
      report = TOPLEVEL_BINDING.eval('workflow')
      if @cursor < @records.size
        raise Failure, "nondeterministic replay: the workflow finished after reusing #{@cursor} of #{@records.size} records"
      end
      emit('done' => true, 'report' => report.to_s)
      remove_run
    rescue Suspend => e
      emit('run' => @run_dir, 'ask' => e.ask_no, 'prompt' => e.prompt, 'input' => e.input,
           'write' => File.join(@run_dir, "answer.#{e.ask_no}"))
    rescue Failure => e
      emit('failed' => e.reason)
      remove_run
    rescue SignalException
      raise # killed from outside: leave the run so that `continue` can resume it
    rescue Exception => e # rubocop:disable Lint/RescueException -- any workflow error ends the run
      emit('failed' => "#{e.class}: #{e.message}")
      remove_run
    end

    # --- helpers ---------------------------------------------------------

    def ask(prompt, input)
      key = digest('ask', prompt, input)
      return '' if @suspended

      rec = replay('ask', key)
      return rec.result if rec

      ask_no = @records.count { |r| r.kind == 'ask' } + 1
      rec = Record.new('ask', ask_no, key, nil)
      @records << rec
      append_record(rec)
      @suspended = true
      @pending = Suspend.new(ask_no, prompt, input)
      raise @pending
    end

    def run_command(argv, stdin)
      argv = argv.map(&:to_s)
      stdin = stdin.to_s
      key = digest('cmd', argv.join("\0"), stdin)
      return CommandResult.new(0, '', '') if @suspended
      return CommandResult.new(127, '', 'empty argv') if argv.empty?

      rec = replay('cmd', key)
      return decode_command(rec.result) if rec

      result = begin
        # [argv[0], argv[0]] forces argv semantics: no shell, even for one word.
        out, err, status = Open3.capture3([argv[0], argv[0]], *argv[1..], stdin_data: stdin)
        CommandResult.new(status.exitstatus || (128 + status.termsig.to_i), out, err)
      rescue SystemCallError => e
        CommandResult.new(127, '', e.message)
      end
      record('cmd', key, encode_command(result))
      result
    end

    def read_file(path)
      key = digest('read', path)
      return nil if @suspended

      rec = replay('read', key)
      return decode_read(rec.result) if rec

      content = File.file?(path) ? File.binread(path).force_encoding('UTF-8') : nil
      record('read', key, content ? "1#{content}" : '0')
      content
    end

    def write_file(path, content)
      content = content.to_s
      key = digest('write', path, Digest::SHA256.hexdigest(content))
      return nil if @suspended

      rec = replay('write', key)
      return nil if rec

      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
      record('write', key, '')
      nil
    end

    def fail_run(reason)
      # Called from an ensure block while the question propagates: raising
      # Failure here would replace the question. Re-raise the question instead.
      raise @pending if @suspended

      raise Failure, reason.to_s
    end

    # --- records ---------------------------------------------------------

    def rewrite_records
      File.binwrite(records_path, @records.map { |r| format_record(r) }.join)
    end

    def emit(hash)
      $stdout.write(JSON.generate(hash) + "\n")
      $stdout.flush
    end

    def remove_run
      FileUtils.rm_rf(@run_dir)
    end

    private

    def replay(kind, key)
      return nil if @cursor >= @records.size

      rec = @records[@cursor]
      if rec.kind != kind || rec.key != key
        raise Failure, "nondeterministic replay: record #{@cursor + 1} is #{rec.kind}, but the workflow requested a different #{kind}"
      end
      raise Failure, "nondeterministic replay: record #{@cursor + 1} has no answer" if rec.result.nil?

      @cursor += 1
      rec
    end

    def record(kind, key, result)
      rec = Record.new(kind, 0, key, result)
      @records << rec
      @cursor += 1
      append_record(rec)
    end

    def digest(*parts)
      Digest::SHA256.hexdigest(parts.join("\0"))
    end

    def encode_command(res)
      "#{res.status}\n#{res.out.bytesize}\n#{res.out}#{res.err}"
    end

    def decode_command(data)
      status, out_len, rest = data.split("\n", 3)
      out_len = out_len.to_i
      CommandResult.new(status.to_i, rest.byteslice(0, out_len).force_encoding('UTF-8'),
                        rest.byteslice(out_len..-1).force_encoding('UTF-8'))
    end

    def decode_read(data)
      data.start_with?('1') ? data.byteslice(1..-1).force_encoding('UTF-8') : nil
    end

    def records_path
      File.join(@run_dir, 'records')
    end

    def format_record(rec)
      key = rec.key.b
      if rec.result.nil?
        "#{rec.kind} #{rec.ask_no} #{key.bytesize} -1\n#{key}\n"
      else
        result = rec.result.b
        "#{rec.kind} #{rec.ask_no} #{key.bytesize} #{result.bytesize}\n#{key}\n#{result}\n"
      end
    end

    def append_record(rec)
      File.open(records_path, 'ab') { |f| f.write(format_record(rec)) }
    end

    def load_records
      data = File.binread(records_path)
      records = []
      pos = 0
      while pos < data.bytesize
        nl = data.index("\n", pos)
        raise Failure, 'corrupt records' unless nl

        kind, ask_no, key_len, result_len = data.byteslice(pos...nl).split(' ')
        pos = nl + 1
        key = data.byteslice(pos, key_len.to_i)
        pos += key_len.to_i + 1
        result = nil
        if result_len.to_i >= 0
          result = data.byteslice(pos, result_len.to_i).force_encoding('UTF-8')
          pos += result_len.to_i + 1
        end
        records << Record.new(kind, ask_no.to_i, key, result)
      end
      records
    end

  end

  # Entry point. Exit code 2 means the call itself was wrong or the caller still
  # has a file to write; everything else is reported on stdout as JSON with
  # exit code 0.
  def self.main(argv)
    workflow_path = File.join(__dir__, 'workflow.rb')
    usage = 'usage: run start | run continue <run>'
    case argv[0]
    when 'start'
      (warn usage; exit 2) unless argv.size == 1
      run_dir = Runtime.start(workflow_path)
      $stdout.write(JSON.generate('run' => run_dir, 'write' => File.join(run_dir, 'args')) + "\n")
    when 'continue'
      (warn usage; exit 2) unless argv.size == 2
      Runtime.continue(argv[1], workflow_path).execute(workflow_path)
    else
      warn usage
      exit 2
    end
    exit 0
  end
end

# Helpers available to workflow.rb.
def args
  Dullmify::Runtime.current.args
end

def ask(prompt, input = '')
  Dullmify::Runtime.current.ask(prompt.to_s, input.to_s)
end

def run_command(argv, stdin = nil)
  Dullmify::Runtime.current.run_command(Array(argv), stdin)
end

def read_file(path)
  Dullmify::Runtime.current.read_file(path.to_s)
end

def write_file(path, content)
  Dullmify::Runtime.current.write_file(path.to_s, content)
end

def fail_run(reason)
  Dullmify::Runtime.current.fail_run(reason)
end

Dullmify.main(ARGV) if __FILE__ == $PROGRAM_NAME
