# frozen_string_literal: true

# Reference data for every template under test/golden: one .snap next to each .slim holds the rendered HTML,
# the compiled Ruby (Tilt and Rails), the formatted source and the lint offenses. A change in any of them fails
# until it is reviewed and the snapshots rewritten:
#   UPDATE_GOLDEN=1 bundle exec rake test
#
# Each template must also hold these, whatever its snapshot says:
# - Slim 5 renders the same HTML (or fails with the same message), with and without html_safe;
# - Rails renders what Tilt renders with html_safe;
# - the compiled Ruby parses;
# - formatting is idempotent, renders the same HTML, and passes the layout rules.
#
# Templates under corpus/ come from real projects and call helpers we do not have: they are compiled, formatted
# and linted, not rendered.
require "minitest/autorun"
require "action_dispatch"
require "action_view"
require "active_support/core_ext/string/output_safety"
require "prism"
require "slim"
require "slimx"
require "slimx/linter"
require "slimx/rails_handler"
require_relative "support/tilt"
require_relative "golden/scope"

class GoldenTest < Minitest::Test
  GOLDEN_DIRECTORY = File.join(__dir__, "golden")
  UPDATE = ENV["UPDATE_GOLDEN"] == "1"
  SECTION_MARKER = "~~~~~~~~ slimx:"
  XML_EXTENSIONS = %w[.xml.slim .rss.slim .atom.slim].freeze
  LAYOUT_RULES = %w[Indentation Tab TrailingWhitespace EmptyLines TrailingBlankLines ControlStatementSpacing RedundantDiv].freeze

  class TiltScope
    include GoldenScope
  end

  class RailsView < ActionView::Base.with_empty_template_cache
    include GoldenScope

    # Rails helpers capture their block instead of letting it write into the page.
    def wrap(&) = "[#{capture(&)}]"
  end

  Case = Data.define(:path, :name, :source) do
    def corpus? = name.start_with?("corpus/")
    def tailwind_classes? = name.start_with?("tailwind/")
    def slim_comparable? = !tailwind_classes? && !name.start_with?("slimx_only/")
    def format = (XML_EXTENSIONS.any? { path.end_with?(_1) }) ? :xml : :html
    def snapshot_path = path.delete_suffix(".slim") + ".snap"
  end

  def self.cases
    Dir[File.join(GOLDEN_DIRECTORY, "**/*.slim")].sort.map do |path|
      Case.new(path:, name: path.delete_prefix("#{GOLDEN_DIRECTORY}/"), source: File.read(path))
    end
  end

  cases.each do |golden_case|
    define_method("test_#{golden_case.name.delete_suffix(".slim").gsub(/\W/, "_")}") { check(golden_case) }
  end

  private

  # Templates under tailwind/ run with SlimX.tailwind_classes on: compiler, formatter, linter and Rails alike.
  def check(golden_case)
    SlimX.tailwind_classes = golden_case.tailwind_classes?
    check_with_current_options(golden_case)
  ensure
    SlimX.tailwind_classes = nil
  end

  def check_with_current_options(golden_case)
    formatted = attempt { SlimX::Formatter.new.call(golden_case.source) }
    sections = {
      "tilt" => attempt { compile(golden_case, html_safe: false) },
      "rails" => attempt { compile(golden_case, rails: true, html_safe: true) },
      "fmt" => formatted,
      "lint" => lint(golden_case, golden_case.source)
    }
    unless golden_case.corpus?
      html = render_tilt(golden_case, golden_case.source, html_safe: true)
      sections = {"html" => html, **sections}
      assert_same_as_slim(golden_case) if golden_case.slim_comparable?
      assert_equal html, render_rails(golden_case), "#{golden_case.name}: Rails renders differently from Tilt"
    end
    assert_compiled_ruby_parses(golden_case, sections)
    assert_code_keeps_its_line(golden_case, sections["tilt"]) unless sections["tilt"].start_with?("error:")
    assert_formatting_holds(golden_case, formatted, sections["html"]) unless formatted.start_with?("error:")
    assert_snapshot(golden_case, sections)
  end

  def compile(golden_case, **options)
    SlimX.compile(golden_case.source, file: golden_case.name, format: golden_case.format, **options)
  end

  def attempt
    yield
  rescue StandardError, ::SyntaxError => exception
    "error: #{exception.class.name.split("::").last}: #{exception.message}"
  end

  def render_tilt(golden_case, source, html_safe:)
    attempt do
      SlimX::Template.new(golden_case.name, format: golden_case.format, html_safe:) { source }.render(TiltScope.new)
    end
  end

  def render_slim(golden_case, html_safe:)
    attempt do
      Slim::Template.new(golden_case.name, format: golden_case.format, sort_attrs: false, pretty: false, use_html_safe: html_safe) do
        golden_case.source
      end.render(TiltScope.new)
    end
  end

  def render_rails(golden_case)
    handler = SlimX::RailsHandler.new
    format = (golden_case.format == :xml) ? :xml : :html
    template = ActionView::Template.new(golden_case.source, golden_case.name, handler, locals: [], format:)
    attempt { template.render(RailsView.new(ActionView::LookupContext.new([]), {}, nil), {}).to_s }
  end

  # Error classes differ between the engines, their messages must not.
  def assert_same_as_slim(golden_case)
    [true, false].each do |html_safe|
      expected = render_slim(golden_case, html_safe:).sub(/\Aerror: \w+: /, "error: ")
      actual = render_tilt(golden_case, golden_case.source, html_safe:).sub(/\Aerror: \w+: /, "error: ")
      assert_equal expected, actual, "#{golden_case.name}: SlimX differs from Slim (html_safe: #{html_safe})"
    end
  end

  def assert_compiled_ruby_parses(golden_case, sections)
    sections.slice("tilt", "rails").each do |mode, code|
      next if code.start_with?("error:")

      errors = Prism.parse("def template(output_buffer = nil)\n#{code}\nend").errors
      assert_empty errors.map(&:message), "#{golden_case.name}: #{mode} code does not parse"
    end
  end

  # Backtraces point at the template line only if each `-` and `=` lands on its own line in the Ruby.
  def assert_code_keeps_its_line(golden_case, code)
    parser = SlimX::Parser.new(file: golden_case.name, outline: true)
    parser.call(golden_case.source)
    generated_lines = code.lines
    parser.line_by_node.each do |node, lineno|
      next unless node.is_a?(SlimX::AST::Control) || node.is_a?(SlimX::AST::Output)

      first_code_line = node.code.lines.first.to_s.strip
      next if first_code_line.empty?

      assert_includes generated_lines[lineno - 1].to_s, first_code_line,
        "#{golden_case.name}:#{lineno}: `#{first_code_line}` is not on line #{lineno} of the Ruby"
    end
  end

  def assert_formatting_holds(golden_case, formatted, html)
    assert_equal formatted, SlimX::Formatter.new.call(formatted), "#{golden_case.name}: formatting is not idempotent"
    assert_equal html, render_tilt(golden_case, formatted, html_safe: true), "#{golden_case.name}: formatting changes the HTML" if html
    layout_offenses = lint(golden_case, formatted).lines.select { |line| LAYOUT_RULES.any? { line.include?("[#{_1}]") } }
    assert_empty layout_offenses, "#{golden_case.name}: the formatted source breaks layout rules"
  end

  def lint(golden_case, source)
    linter = SlimX::Linter.new(ENABLE_EVERY_RULE)
    linter.call(golden_case.name, source).map { |offense| "#{offense.lineno}: [#{offense.rule}] #{offense.message}" }.join("\n")
  end

  ENABLE_EVERY_RULE = SlimX::Linter::Rules.constants.filter_map do |name|
    rule = SlimX::Linter::Rules.const_get(name)
    [name.name, {"enabled" => true}] if rule.is_a?(Class) && name != :Rule
  end.to_h.freeze

  def assert_snapshot(golden_case, sections)
    actual = sections.map { |name, content| "#{SECTION_MARKER} #{name}\n#{content.chomp}\n" }.join
    if UPDATE
      File.write(golden_case.snapshot_path, actual)
    elsif !File.exist?(golden_case.snapshot_path)
      flunk "#{golden_case.name}: no snapshot yet (UPDATE_GOLDEN=1 writes it, then review it)"
    else
      assert_equal File.read(golden_case.snapshot_path), actual, "#{golden_case.name}: snapshot changed (UPDATE_GOLDEN=1 rewrites it)"
    end
  end
end
