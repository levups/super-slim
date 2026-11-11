# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "fileutils"
require "open3"
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

  def test_lint_links_each_rule_it_reports_to_its_entry_on_the_website_on_stderr
    in_templates("ul \n  li Home\n") do
      File.write(template_name(1), "/ super-slim:disable Nothing\np Hello \n")

      _, _, errors = run_cli_with_errors("lint", ".")

      url = "https://levups.github.io/super-slim/tools.html"
      assert_equal ["TrailingWhitespace: #{url}#TrailingWhitespace"], errors.lines(chomp: true)
    end
  end

  def test_lint_passes_clean_templates
    in_templates("p Hello\n") { assert_equal [0, ""], run_cli("lint", ".") }
  end

  def test_fmt_check_lists_templates_to_reformat_without_writing_them
    in_templates("ul\n   li Home\n") do |directory|
      status, output = run_cli("format", "--check", ".")

      assert_equal 1, status
      assert_equal TEMPLATE_COUNT, output.lines.size
      assert_equal "ul\n   li Home\n", File.read(File.join(directory, template_name(1)))
    end
  end

  def test_fmt_rewrites_templates_then_finds_nothing_left
    in_templates("ul\n   li Home\n") do |directory|
      assert_equal 0, run_cli("format", ".").first
      assert_equal "ul\n  li Home\n", File.read(File.join(directory, template_name(TEMPLATE_COUNT)))
      assert_equal [0, ""], run_cli("format", "--check", ".")
    end
  end

  def test_fmt_wraps_lines_longer_than_the_configured_length
    in_templates(%(a.btn href="/posts/1" data-turbo="false" Edit\n)) do |directory|
      File.write(".super-slim.yml", "format:\n  max_line_length: 30\n  attribute_delimiters: \"{}\"\n")

      assert_equal 0, run_cli("format", ".").first
      assert_equal %(a.btn {\n  href="/posts/1"\n  data-turbo="false"\n} Edit\n), File.read(File.join(directory, template_name(1)))
    end
  end

  def test_fmt_and_its_configuration_key_still_format
    in_templates(%(a.btn href="/posts/1" data-turbo="false" Edit\n)) do |directory|
      File.write(".super-slim.yml", "fmt:\n  max_line_length: 30\n")

      assert_equal 0, run_cli("fmt", ".").first
      assert_equal %(a.btn(\n  href="/posts/1"\n  data-turbo="false"\n) Edit\n), File.read(File.join(directory, template_name(1)))
    end
  end

  def test_help_prints_the_usage_and_succeeds
    [["--help"], ["-h"], ["help"], ["fmt", "--help"], ["lint", "-h", "app"]].each do |arguments|
      assert_equal [0, SuperSlim::CLI::USAGE], run_cli(*arguments), arguments.join(" ")
    end
  end

  def test_unknown_options_fail_with_the_usage
    assert_output("", "Unknown option --chek\n#{SuperSlim::CLI::USAGE}") do
      assert_equal SuperSlim::CLI::EX_USAGE, SuperSlim::CLI.new.call(["format", "--chek", "."])
    end
    assert_output("", /Unknown option --check/) { SuperSlim::CLI.new.call(["lint", "--check"]) }
  end

  def test_an_unknown_preset_fails_with_a_usage_error
    in_templates("p Hello\n") do |directory|
      File.write(File.join(directory, ".super-slim.yml"), "linters:\n  DeprecatedClasses:\n    preset: bootstrap4\n")

      assert_output("", "DeprecatedClasses: unknown preset `bootstrap4`, use one of: bootstrap5\n") do
        assert_equal SuperSlim::CLI::EX_USAGE, SuperSlim::CLI.new.call(["lint", "."])
      end
    end
  end

  def test_a_configuration_of_the_wrong_shape_fails_with_a_usage_error
    {
      "linters: 5\n" => ".super-slim.yml: `linters` must be a mapping",
      "linters:\n  LineLength:\n    include: 3\n" => ".super-slim.yml: `LineLength: include` must be a list of globs",
      "linters:\n  LineLength:\n    max: \"120\"\n" => ".super-slim.yml: `LineLength: max` must be a whole number",
      "linters:\n  LineLength:\n    enabled: \"false\"\n" => ".super-slim.yml: `LineLength: enabled` must be true or false",
      "linters:\n  DeprecatedClasses:\n    classes: [close]\n" => ".super-slim.yml: `DeprecatedClasses: classes` must be a mapping",
      "linters:\n  EmbeddedEngines:\n    forbidden_engines: css\n" => ".super-slim.yml: `EmbeddedEngines: forbidden_engines` must be a list",
      "format:\n  max_line_length: \"120\"\n" => ".super-slim.yml: `format: max_line_length` must be a whole number above 0",
      "fmt:\n  max_line_length: 0\n" => ".super-slim.yml: `fmt: max_line_length` must be a whole number above 0",
      "format:\n  attribute_delimiters: \"<>\"\n" => ".super-slim.yml: `format: attribute_delimiters` must be one of (), [], {}",
      "tailwind_classes: maybe\n" => ".super-slim.yml: `tailwind_classes` must be true or false",
      "x: !ruby/object:Object {}\n" => "Tried to load unspecified class: Object"
    }.each do |configuration, message|
      in_templates("p Hello\n") do |directory|
        File.write(File.join(directory, ".super-slim.yml"), configuration)

        assert_output("", "#{message}\n") { assert_equal SuperSlim::CLI::EX_USAGE, SuperSlim::CLI.new.call(["lint", "."]) }
      end
    end
  end

  def test_a_preset_table_and_a_line_length_left_empty_are_no_error
    in_templates("p Hello\n") do |directory|
      File.write(File.join(directory, ".super-slim.yml"), "linters:\n  DeprecatedAttributes:\n    preset: bootstrap5\n    attributes:\nformat:\n  max_line_length:\n")

      assert_equal [0, ""], run_cli("lint", ".")
      assert_equal [0, ""], run_cli("format", "--check", ".")
    end
  end

  def test_include_and_exclude_globs_match_paths_from_the_configuration_directory
    in_templates("p style=\"color: red\" Hello\n") do |directory|
      FileUtils.mkdir_p(File.join(directory, "mailers"))
      File.write(File.join(directory, "mailers", "welcome.html.slim"), "p style=\"color: red\" Hello\n")
      File.write(File.join(directory, ".super-slim.yml"), <<~YAML)
        linters:
          InlineStyles:
            enabled: true
            include: ["**/*.slim"]
            exclude: ["mailers/**/*"]
      YAML
      status, output = run_cli("lint", ".")

      assert_equal 1, status
      assert_equal TEMPLATE_COUNT, output.lines.size
      refute_includes output, "mailers"
    end
  end

  def test_fmt_leaves_symlinks_and_special_files_found_in_a_directory_alone
    Dir.mktmpdir do |outside|
      victim = File.join(outside, "victim.slim")
      File.write(victim, "div.a\n")
      in_templates("p Hello\n") do |directory|
        File.symlink(victim, File.join(directory, "link.slim"))
        File.mkfifo(File.join(directory, "fifo.slim"))

        assert_equal [0, ""], run_cli("format", ".")
        assert_equal "div.a\n", File.read(victim)
      end
    end
  end

  def test_fmt_keeps_the_mode_of_the_template_it_rewrites
    in_templates("ul\n   li Home\n") do |directory|
      path = File.join(directory, template_name(1))
      File.chmod(0o640, path)

      assert_equal 0, run_cli("format", ".").first
      assert_equal 0o640, File.stat(path).mode & 0o7777
      assert_equal [template_name(1)], Dir.children(directory).grep(/super-slim|\A#{template_name(1)}\z/)
    end
  end

  def test_control_characters_are_escaped_in_what_lint_prints
    Dir.mktmpdir do |directory|
      Dir.chdir(directory) do
        File.write("a\e[2Jb\n::error::x.slim", "p Hello \n")
        status, output = run_cli("lint", ".")

        assert_equal 1, status
        assert_equal ["./a\\e[2Jb\\n::error::x.slim:1: [TrailingWhitespace] Trailing whitespace renders: write it with `'` or `>` instead"], output.lines(chomp: true)
      end
    end
  end

  # `exe/super-slim` loads the checkout it sits in by path: with the gem installed too, a formatter looked up on
  # the load path would be the installed one.
  def test_the_formatter_comes_from_the_copy_of_the_gem_that_was_loaded
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, "super_slim"))
      File.write(File.join(directory, "super_slim/formatter.rb"), "raise 'the formatter of another copy of the gem'\n")
      script = "require #{File.expand_path("../lib/super_slim", __dir__).dump}; print SuperSlim::Formatter.call(%(p\\n   | Hello\\n))"
      output, status = Open3.capture2e(RbConfig.ruby, "-I", directory, "-e", script)

      assert_predicate status, :success?, output
      assert_equal "p\n  | Hello\n", output
    end
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
    run_cli_with_errors(*arguments).first(2)
  end

  def run_cli_with_errors(*arguments)
    stdout, stderr = $stdout, $stderr
    $stdout, $stderr = StringIO.new, StringIO.new
    status = SuperSlim::CLI.new.call(arguments)
    [status, $stdout.string, $stderr.string]
  ensure
    $stdout, $stderr = stdout, stderr
  end
end
