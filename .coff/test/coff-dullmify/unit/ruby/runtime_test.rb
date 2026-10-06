# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../../../src/coff-dullmify.skill/langs/ruby/runtime"

class DullmifyRuntimeTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("dullmify-ruby-unit-")
    File.write(File.join(@directory, "args"), "引数\n")
    File.write(File.join(@directory, "cwd"), Dir.pwd)
  end

  def teardown
    FileUtils.rm_rf(@directory)
  end

  # Runtime は private_constant なので const_get で取る。
  def runtime_class
    Dullmify.const_get(:Runtime)
  end

  def test_record_write_read_and_type_normalization
    first = runtime_class.new(@directory)
    value = first.once([:key]) { :value }
    assert_equal "value", value
    assert_equal({ "type" => "once", "key" => ["key"], "result" => "value" }, first.records.first)

    second = runtime_class.new(@directory)
    replayed = second.once(["key"]) { flunk "記録済みのブロックが再実行された" }
    assert_equal "value", replayed
  end

  def test_key_mismatch_becomes_nondeterministic_failure
    runtime_class.new(@directory).once(["a"]) { 1 }
    signal = catch(Dullmify.const_get(:SIGNAL)) do
      runtime_class.new(@directory).once(["b"]) { 2 }
      nil
    end
    assert_equal :failed, signal.first
    assert_includes signal.last, "非決定"
  end

  def test_command_does_not_use_shell
    runtime = runtime_class.new(@directory)
    assert_equal 127, runtime.command(["echo $HOME"]).fetch("exit_code")
    assert_equal "$HOME\n", runtime.command(["echo", "$HOME"]).fetch("stdout")
    assert_equal 127, runtime.command([]).fetch("exit_code")
    piped = runtime.command(["sh", "-c", "cat; echo err >&2; exit 3"], "入力")
    assert_equal({ "exit_code" => 3, "stdout" => "入力", "stderr" => "err\n" }, piped)
    assert_equal 128 + Signal.list.fetch("TERM"), runtime.command(["sh", "-c", "kill -TERM $$"]).fetch("exit_code")
  end

  def test_invalid_utf8_is_valid_json
    runtime = runtime_class.new(@directory)
    runtime.once(["bytes"]) { "a\xFFb".b }
    File.foreach(File.join(@directory, "records.jsonl")) { |line| JSON.parse(line) }
    assert_equal "a�b", runtime.records.first.fetch("result")
  end
end
