# frozen_string_literal: true

require "minitest/autorun"
require "slim"
require "super_slim"

# An error raised while rendering points at its template line, where Slim drifts.
class RuntimeLinesTest < Minitest::Test
  FILE = "show.html.slim"

  class Scope
    def foo(*)
      "alice"
    end
  end

  # A line break inside an interpolation of a quoted attribute is one line of the compiled code (#122).
  def test_a_line_break_in_a_quoted_attribute_counts_once
    [
      %(p title="\#{foo(\n1)}"\n= raise "boom"\n),
      %(p title="\#{foo(\n1,\n2)}" lang="\#{foo(\n)}"\n= raise "boom"\n),
      %(p class="\#{foo(\n1)}" class="b"\n= raise "boom"\n)
    ].each do |source|
      assert_equal [source.lines.size, source.lines.size], [slim_line(source), super_slim_line(source)], source
    end
  end

  # Slim loses the other breaks, one line each: a static part of the value, an escaped interpolation, a backslash
  # that joins two lines of an interpolation.
  def test_the_other_breaks_count_too
    assert_equal 3, super_slim_line(%(p title="{a\n b}"\n= raise "boom"\n))
    assert_equal 3, super_slim_line(%(p title="\\\#{a\n b}"\n= raise "boom"\n))
    assert_equal 3, super_slim_line(%(p title="\#{foo(1,\\\n2)}"\n= raise "boom"\n))
    assert_equal 5, super_slim_line(%(p title="a\nb \#{foo(\n1)} c\nd"\n= raise "boom"\n))
  end

  # `ruby:` and `markdown:` drop their attributes, but not the lines those take.
  def test_the_attributes_of_a_ruby_or_markdown_block_keep_their_lines
    assert_equal 4, super_slim_line(%(ruby title="\#{foo(:\n 1)}":\n  x = 1\n= raise "boom"\n))
    assert_equal 4, super_slim_line(%(markdown title="\#{foo(:\n 1)}":\n  alice\n= raise "boom"\n))
  end

  private

  def slim_line(source)
    line_of { Slim::Template.new(FILE) { source }.render(Scope.new) }
  end

  def super_slim_line(source)
    line_of { Scope.new.instance_eval(SuperSlim.compile(source), FILE, 1) }
  end

  def line_of
    yield
    flunk "Rendered without raising"
  rescue RuntimeError => exception
    frame = exception.backtrace.find { _1.start_with?("#{FILE}:") } or flunk "No #{FILE} frame in:\n#{exception.backtrace.join("\n")}"
    frame[/:(\d+)/, 1].to_i
  end
end
