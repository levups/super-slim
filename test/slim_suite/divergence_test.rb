# frozen_string_literal: true

require_relative "helper"

# Slim bugs SuperSlim fixes on purpose: Slim raises where SuperSlim renders. This process has no Rails, so Object
# has no html_safe?.
class DivergenceTest < TestSlim
  # Where String alone defines html_safe?, Slim asks a number or nil for it and raises.
  def test_values_without_html_safe_are_escaped
    with_html_safe do
      source = "p = 5\np = nil\np = :a\np = value\np title=5 *{data: {n: 1}}\n"
      locals = {value: Class.new(BasicObject) { define_method(:to_s) { "<b>" } }.new}
      assert_raises(NoMethodError) { render_with_slim(source, use_html_safe: true, locals:) }
      assert_equal %(<p>5</p><p></p><p>a</p><p>&lt;b&gt;</p><p title="5" data-n="1"></p>),
        render_with_super_slim(source, use_html_safe: true, locals:)
    end
  end

  def test_errors_that_are_not_a_missing_html_safe_still_raise
    with_html_safe do
      gone = Class.new { define_method(:html_safe?) { raise NoMethodError.new("gone", :html_safe?) } }.new
      exception = assert_raises(NoMethodError) { render_with_super_slim("p = gone", use_html_safe: true, locals: {gone:}) }
      assert_equal "gone", exception.message
    end
    # html_safe: true while String has no html_safe? is a configuration error, not a value to escape.
    exception = assert_raises(NoMethodError) { render_with_super_slim("p = 'a'", use_html_safe: true) }
    assert_equal :html_safe?, exception.name
  end
end
