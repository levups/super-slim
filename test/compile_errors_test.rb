# frozen_string_literal: true

require "minitest/autorun"
require "action_dispatch"
require "action_view"
require "super_slim"
require "super_slim/rails_handler"

# Errors found while compiling, after parsing, point at their template line like the parser's own.
class CompileErrorsTest < Minitest::Test
  FILE = "app/views/posts/show.html.slim"

  class View < ActionView::Base.with_empty_template_cache; end

  def test_an_explicit_end_points_at_its_line
    assert_compile_error "Explicit end statements are forbidden", "p one\np two\n- end\np four\n", 3, "- end"
  end

  def test_a_duplicate_attribute_points_at_its_line
    assert_compile_error "Multiple id attributes specified", %(p one\np two\np id="a" id="b"\np four\n), 3, %(p id="a" id="b")
  end

  def test_an_xml_directive_in_html_points_at_its_line
    assert_compile_error "Invalid xml directive in html mode", "p one\np two\ndoctype xml\np four\n", 3, "doctype xml"
  end

  def test_an_unknown_doctype_points_at_its_line
    assert_compile_error "Invalid doctype mobile", "p one\np two\ndoctype mobile\np four\n", 3, "doctype mobile"
  end

  def test_the_line_counts_every_template_line_before_it
    assert_compile_error "Explicit end statements are forbidden", "- end\n", 1, "- end"
    assert_compile_error "Explicit end statements are forbidden", "div\n  - if x\n    p one\n  - end\n", 4, "  - end"
    assert_compile_error "Multiple id attributes specified", %(div\n  p one\n  div: p id="a" id="b"\n), 3, %(  div: p id="a" id="b")
    assert_compile_error "Multiple id attributes specified", %(ruby:\n  a = 1\n\n  b = 2\np id="a" id="b"\n), 5, %(p id="a" id="b")
    assert_compile_error "Multiple id attributes specified", %(ruby:\n  a = 1\np id="a" id="b"\n), 3, %(p id="a" id="b")
    assert_compile_error "Multiple id attributes specified", %(p\n  | one\n    two\np id="a" id="b"\n), 4, %(p id="a" id="b")
    assert_compile_error "Explicit end statements are forbidden", "- x = [1,\n  2]\n- end\n", 3, "- end"
    assert_compile_error "Explicit end statements are forbidden", "div\r\n\t- end\r\n", 2, "\t- end"
  end

  # Its compiled code sits on the last line of its attributes.
  def test_a_tag_over_several_lines_points_at_its_last_line
    assert_compile_error "Multiple id attributes specified", "p\np(id=\"a\"\n  title=\"c\"\n  id=\"b\")\n", 4, "  id=\"b\")"
  end

  def test_it_stays_a_superslim_error
    assert_raises(SuperSlim::Error) { SuperSlim.compile("- end\n") }
    assert_includes assert_raises(SuperSlim::SyntaxError) { SuperSlim.compile("- end\n") }.message, "(__TEMPLATE__), Line 1"
  end

  def test_rails_reports_the_template_line
    [false, true].each do |annotate|
      ActionView::Base.annotate_rendered_view_with_filenames = annotate
      template = ActionView::Template.new("p one\np two\n- end\n", FILE, SuperSlim::RailsHandler.new, locals: [], format: :html)
      exception = assert_raises(ActionView::Template::Error) { template.render(View.new(ActionView::LookupContext.new([]), {}, nil), {}) }

      assert_equal "3", exception.line_number.to_s
      assert_kind_of SuperSlim::SyntaxError, exception.cause
    end
  ensure
    ActionView::Base.annotate_rendered_view_with_filenames = false
  end

  private

  def assert_compile_error(message, source, lineno, line)
    exception = assert_raises(SuperSlim::SyntaxError) { SuperSlim.compile(source, file: FILE) }

    assert_equal message, exception.error
    assert_equal [FILE, lineno, line], [exception.file, exception.lineno, exception.line]
    assert_equal "#{FILE}:#{lineno}", exception.backtrace.first
    assert_equal message, exception.message.lines.first.chomp
  end
end
