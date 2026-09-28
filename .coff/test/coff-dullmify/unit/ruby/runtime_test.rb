# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "stringio"
require_relative "../../../../src/coff-dullmify.skill/langs/ruby/runtime"

class DullmifyRubyRuntimeTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("coff-dullmify-unit-")
    File.write(File.join(@directory, "workflow-key"), "キー")
  end

  def teardown
    FileUtils.remove_entry(@directory) if File.exist?(@directory)
  end

  def test_問いの記録を書いて読み戻す
    runtime = Dullmify::Runtime.new(@directory, "キー")
    assert_raises(Dullmify::Pending) { runtime.ask("判断", "対象") }
    assert_equal 1, runtime.records.length

    File.binwrite(File.join(@directory, "answer"), "回答\n")
    replay = Dullmify::Runtime.new(@directory, "キー")
    replay.prepare!
    assert_equal "回答", replay.ask("判断", "対象")
    replay.finish!
    refute File.exist?(File.join(@directory, "answer"))
  end

  def test_照合キーの食い違いを検出する
    runtime = Dullmify::Runtime.new(@directory, "キー")
    assert_raises(Dullmify::Pending) { runtime.ask("判断", "対象") }

    replay = Dullmify::Runtime.new(@directory, "キー")
    assert_raises(Dullmify::Nondeterminism) { replay.ask("別の判断", "対象") }
  end

  def test_壊れた記録を拒否する
    File.binwrite(File.join(@directory, "records.jsonl"), "{壊れた記録\n")
    assert_raises(Dullmify::Failure) { Dullmify::Runtime.new(@directory, "キー") }
  end

  def test_不正な_utf8_を正しい_json_にする
    previous = $stdout
    output = StringIO.new
    $stdout = output
    Dullmify.emit("値" => "\xFF".b)
    parsed = JSON.parse(output.string)
    assert_equal "�", parsed.fetch("値")
  ensure
    $stdout = previous
  end
end
