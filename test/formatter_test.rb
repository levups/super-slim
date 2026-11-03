# frozen_string_literal: true

require "minitest/autorun"
require "slimx"

class FormatterTest < Minitest::Test
  def test_indents_two_spaces_per_level
    assert_formats "ul\n  li\n    a href=\"/\" Home\n", "ul\n    li\n       a href=\"/\" Home\n"
  end

  def test_shifts_text_blocks_whole_to_keep_the_whitespace_they_render
    assert_formats "div\n  |\n    one\n      two\n", "div\n    |\n      one\n        two\n"
  end

  def test_spaces_control_and_output_markers
    assert_formats "- x = 1\n= x\n=> x\np = x\np == x\n", "-x = 1\n=x\n=>x\np=x\np==x\n"
  end

  def test_drops_redundant_div
    assert_formats ".card\n#main\n", "div.card\ndiv#main\n"
  end

  def test_collapses_blank_lines_and_ends_with_one_newline
    assert_formats "p\n\np\n", "\n\np\n\n\n\np\n\n\n"
  end

  def test_keeps_blank_lines_and_trailing_whitespace_that_render
    source = "javascript:\n  one()\n\n\n  two()\np Hello \n"

    assert_equal source, SlimX::Formatter.call(source)
  end

  def test_is_idempotent
    formatted = SlimX::Formatter.call("div\n   - if x\n      p=y\n   - else\n      |  a\n          b\n")

    assert_equal formatted, SlimX::Formatter.call(formatted)
  end

  def test_strict_mode_refuses_an_unformatted_template
    error = assert_raises(SlimX::SyntaxError) { SlimX.compile("ul\n   li\n", strict: true) }

    assert_equal 2, error.lineno
    assert_includes error.message, %(`slimx fmt` writes: "  li")
    assert SlimX.compile("ul\n  li\n", strict: true)
  end

  private

  def assert_formats(expected, source)
    assert_equal expected, SlimX::Formatter.call(source)
  end
end
