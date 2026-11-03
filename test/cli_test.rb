# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"
require "slimx/cli"

class CLITest < Minitest::Test
  # Enough templates to split them between processes.
  TEMPLATE_COUNT = 250

  def test_lint_reports_offenses_in_template_order_with_its_exit_status
    in_templates("p Hello \n") do
      status, output = run_cli("lint", ".")

      assert_equal 1, status
      expected = (1..TEMPLATE_COUNT).map { "./#{template_name(it)}:1: [TrailingWhitespace] Trailing whitespace renders: write it with `'` or `>` instead" }
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

  private

  def template_name(number) = format("template_%03d.html.slim", number)

  def in_templates(source)
    Dir.mktmpdir do |directory|
      (1..TEMPLATE_COUNT).each { File.write(File.join(directory, template_name(it)), source) }
      Dir.chdir(directory) { yield directory }
    end
  end

  def run_cli(*arguments)
    stdout = $stdout
    $stdout = StringIO.new
    status = SlimX::CLI.new.call(arguments)
    [status, $stdout.string]
  ensure
    $stdout = stdout
  end
end
