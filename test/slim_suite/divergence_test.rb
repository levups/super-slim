# frozen_string_literal: true

require_relative "helper"

# Slim bugs SuperSlim fixes on purpose: Slim raises where SuperSlim renders.
class DivergenceTest < TestSlim
  # Without Rails, String alone may define html_safe?: Slim then asks a number or nil for it and raises.
  def test_values_without_html_safe_are_escaped
    with_html_safe do
      source = "p = 5\np = nil\np = :a\np title=5 *{data: {n: 1}}\n"
      assert_raises(NoMethodError) { render_with_slim(source, use_html_safe: true) }
      assert_equal %(<p>5</p><p></p><p>a</p><p title="5" data-n="1"></p>), render_with_super_slim(source, use_html_safe: true)
    end
  end
end
