# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

# The engine, the formatter and the linter each load on their own, in any order, without a warning: each test runs
# in a process of its own, where nothing else was loaded first.
class EntryPointsTest < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)
  FORMAT = 'p SuperSlim::Formatter.call("- if !x\n  p Hi\n")'
  LINT = 'p SuperSlim::Linter.new.call("page.slim", "p Hi  \n").map(&:rule)'
  FORMATTED = %("- unless x\\n  p Hi\\n")
  LINTED = %(["TrailingWhitespace"])

  def test_the_formatter_alone
    assert_loads FORMATTED, %w[super_slim/formatter], FORMAT
  end

  def test_the_linter_alone
    assert_loads LINTED, %w[super_slim/linter], LINT
  end

  def test_the_formatter_after_the_engine
    assert_loads FORMATTED, %w[super_slim super_slim/formatter], FORMAT
  end

  def test_the_formatter_autoloaded_by_the_engine
    assert_loads FORMATTED, %w[super_slim], FORMAT
  end

  def test_the_linter_and_the_formatter_in_either_order
    assert_loads "#{LINTED}\n#{FORMATTED}", %w[super_slim/linter super_slim/formatter], LINT, FORMAT
    assert_loads "#{LINTED}\n#{FORMATTED}", %w[super_slim/formatter super_slim/linter], LINT, FORMAT
  end

  def test_the_engine_alone_leaves_the_formatter_and_the_linter_out
    assert_loads "[false, false]", %w[super_slim], 'p [$LOADED_FEATURES.any?(%r{super_slim/formatter\.rb}), defined?(SuperSlim::Linter) ? true : false]'
  end

  # A spec helper may load the linter or the formatter before the app boots Rails, then Bundler requires the gem.
  def test_rails_renders_slim_views_with_superslim_after_the_linter_or_the_formatter
    boot = ["SuperSlim::Railtie.instance.run_initializers", "ActionView::Base", "p ActionView::Template.handler_for_extension(:slim).class"]
    %w[super_slim/linter super_slim/formatter].each do |feature|
      assert_loads "SuperSlim::RailsHandler", [feature, "rails", "action_view", "super-slim"], *boot
    end
  end

  private

  def assert_loads(expected, features, *code)
    script = [*features.map { "require #{_1.dump}" }, *code].join("\n")
    output, errors, status = Open3.capture3(RbConfig.ruby, "-w", "-I", LIB, "-e", script)

    assert status.success?, errors
    assert_equal "#{expected}\n", output
    assert_empty errors.lines.select { _1.start_with?(LIB) || _1.include?("circular require") }, errors
  end
end
