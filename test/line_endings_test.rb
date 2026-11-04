# frozen_string_literal: true

require "minitest/autorun"
require "slim"
require "slimx"

class LineEndingsTest < Minitest::Test
  TEMPLATE = "ul\n  - %w[alice bob].each do |name|\n    li = name\n\np\n  | Hello\n    world\n"

  def test_crlf_templates_render_like_lf_templates
    assert_equal render(TEMPLATE), render(TEMPLATE.gsub("\n", "\r\n"))
  end

  def test_a_carriage_return_inside_a_line_stays_like_in_slim
    source = "p a\rb\r\n\r\nspan c\r"
    assert_equal Slim::Template.new { source }.render, render(source)
  end

  private

  def render(source)
    eval(SlimX.compile(source)) # rubocop:disable Security/Eval -- the template is the test's own
  end
end
