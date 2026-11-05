# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"
require "super_slim/cli"

class CLITest < Minitest::Test
  # Enough templates to split them between processes.
  TEMPLATE_COUNT = 250

  def test_lint_reports_offenses_in_template_order_with_its_exit_status
    in_templates("p Hello \n") do
      status, output = run_cli("lint", ".")

      assert_equal 1, status
      expected = (1..TEMPLATE_COUNT).map { "./#{template_name(_1)}:1: [TrailingWhitespace] Trailing whitespace renders: write it with `'` or `>` instead" }
      assert_equal expected, output.lines(chomp: true)
    end
  end

  def test_lint_passes_clean_templates
    in_templates("p Hello\n") { assert_equal [0, ""], run_cli("lint", ".") }
  end

  def test_fmt_check_lists_templates_to_reformat_without_writing_them
    in_templates("ul\n   li Home\n") do |directory|
      status, output = run_cli("fmt", "--check", ".")

      assert_equal 1, status
      assert_equal TEMPLATE_COUNT, output.lines.size
      assert_equal "ul\n   li Home\n", File.read(File.join(directory, template_name(1)))
    end
  end

  def test_fmt_rewrites_templates_then_finds_nothing_left
    in_templates("ul\n   li Home\n") do |directory|
      assert_equal 0, run_cli("fmt", ".").first
      assert_equal "ul\n  li Home\n", File.read(File.join(directory, template_name(TEMPLATE_COUNT)))
      assert_equal [0, ""], run_cli("fmt", "--check", ".")
    end
  end

  def test_fmt_wraps_lines_longer_than_the_configured_length
    in_templates(%(a.btn href="/posts/1" data-turbo="false" Edit\n)) do |directory|
      File.write(".super-slim.yml", "fmt:\n  max_line_length: 30\n  attribute_delimiters: \"{}\"\n")

      assert_equal 0, run_cli("fmt", ".").first
      assert_equal %(a.btn {\n  href="/posts/1"\n  data-turbo="false"\n} Edit\n), File.read(File.join(directory, template_name(1)))
    end
  end

  def test_help_prints_the_usage_and_succeeds
    [["--help"], ["-h"], ["help"], ["fmt", "--help"], ["lint", "-h", "app"]].each do |arguments|
      assert_equal [0, SuperSlim::CLI::USAGE], run_cli(*arguments), arguments.join(" ")
    end
  end

  def test_unknown_options_fail_with_the_usage
    assert_output("", "Unknown option --chek\n#{SuperSlim::CLI::USAGE}") do
      assert_equal SuperSlim::CLI::EX_USAGE, SuperSlim::CLI.new.call(["fmt", "--chek", "."])
    end
    assert_output("", /Unknown option --check/) { SuperSlim::CLI.new.call(["lint", "--check"]) }
  end

  private

  def template_name(number) = format("template_%03d.html.slim", number)

  def in_templates(source)
    Dir.mktmpdir do |directory|
      (1..TEMPLATE_COUNT).each { File.write(File.join(directory, template_name(_1)), source) }
      Dir.chdir(directory) { yield directory }
    end
  end

  def run_cli(*arguments)
    stdout = $stdout
    $stdout = StringIO.new
    status = SuperSlim::CLI.new.call(arguments)
    [status, $stdout.string]
  ensure
    $stdout = stdout
  end
end
