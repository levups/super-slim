# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

# The engine, the formatter and the linter each load on their own, in any order, without a warning: each test runs
# in a process of its own, where nothing else was loaded first.
class EntryPointsTest < Minitest::Test
  FORMAT = 'p SuperSlim::Formatter.call("- if !x\n  p Hi\n")'
  LINT = 'p SuperSlim::Linter.new.call("page.slim", "p Hi  \n").map(&:rule)'
  FORMATTED = %("- unless x\\n  p Hi\\n")
  LINTED = %(["TrailingWhitespace"])

  def test_the_formatter_alone
    assert_loads FORMATTED, "super_slim/formatter", FORMAT
  end

  def test_the_linter_alone
    assert_loads LINTED, "super_slim/linter", LINT
  end

  def test_the_formatter_after_the_engine
    assert_loads FORMATTED, "super_slim", "super_slim/formatter", FORMAT
  end

  def test_the_formatter_autoloaded_by_the_engine
    assert_loads FORMATTED, "super_slim", FORMAT
  end

  def test_the_linter_and_the_formatter_in_either_order
    assert_loads "#{LINTED}\n#{FORMATTED}", "super_slim/linter", "super_slim/formatter", LINT, FORMAT
    assert_loads "#{LINTED}\n#{FORMATTED}", "super_slim/formatter", "super_slim/linter", LINT, FORMAT
  end

  def test_the_engine_alone_leaves_the_formatter_and_the_linter_out
    assert_loads "[false, false]", "super_slim", 'p [$LOADED_FEATURES.any?(%r{super_slim/formatter\.rb}), defined?(SuperSlim::Linter) ? true : false]'
  end

  private

  def assert_loads(expected, *features_then_code)
    features, code = features_then_code.partition { _1.match?(%r{\Asuper_slim(/\w+)?\z}) }
    script = [*features.map { "require #{_1.dump}" }, *code].join("\n")
    output, errors, status = Open3.capture3(RbConfig.ruby, "-w", "-I", File.expand_path("../lib", __dir__), "-e", script)

    assert status.success?, errors
    assert_equal "#{expected}\n", output
    assert_empty errors.lines.grep(/super_slim|circular/), errors
  end
end
