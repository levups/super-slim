# frozen_string_literal: true

require "minitest/autorun"
require "active_support/core_ext/string/output_safety"
require "super_slim"

# Names known only at render time come from data: they must not open an attribute or a tag of their own.
class RuntimeTest < Minitest::Test
  def test_separators_in_a_data_key_cannot_add_an_attribute
    ["\t", "\n", "\f", "\r", " ", "\0"].each do |separator|
      exception = assert_raises(SuperSlim::InvalidAttributeNameError) { render("a data=meta", meta: {"x#{separator}onclick" => "alert(1)"}) }
      assert_includes exception.message, "data-x#{separator}onclick"
    end
  end

  def test_a_template_name_with_a_control_character_next_to_a_splat_raises
    assert_raises(SuperSlim::InvalidAttributeNameError) { render(%(a*attributes x\u0001y="1"), attributes: {}) }
  end

  def test_separators_in_a_splat_key_cannot_add_an_attribute
    assert_raises(SuperSlim::InvalidAttributeNameError) { render("a*attributes", attributes: {"title\nonclick" => "alert(1)"}) }
    assert_raises(SuperSlim::InvalidAttributeNameError) { render("a*attributes", attributes: {"" => "x"}) }
  end

  def test_a_dynamic_tag_name_cannot_carry_attributes_or_markup
    ["img src=x onerror=alert(1)", "img/src=x/onerror=alert(1)", "<script>", "a\thref=x", "1a"].each do |tag|
      assert_raises(SuperSlim::InvalidTagNameError) { render("*attributes Hello", attributes: {tag:}) }
    end
  end

  def test_valid_dynamic_tag_names_still_render
    assert_equal "<my-card>Hello</my-card>", render("*attributes Hello", attributes: {tag: "my-card"})
    assert_equal %(<svg:rect aria-label="Close"></svg:rect>), render("*attributes", attributes: {:tag => "svg:rect", "aria-label" => "Close"})
    assert_equal "<div>Hello</div>", render("*attributes Hello", attributes: {tag: ""})
  end

  def test_a_falsy_html_safe_option_renders_dynamic_classes_and_splats
    [nil, false].each do |html_safe|
      assert_equal %(<p class="a b"></p><a href="/"></a>), render(%(p class=klass\na*{href: "/"}), html_safe:, klass: %w[a b])
    end
  end

  # Slim calls html_safe? on the value itself, which only Rails defines on every object.
  def test_an_output_without_html_safe_of_its_own_is_escaped
    count = Class.new do
      undef_method :html_safe? if method_defined?(:html_safe?)

      def to_s
        "<5>"
      end
    end.new

    assert_equal "<p>&lt;5&gt;</p>", render("p = count", html_safe: true, count:)
  end

  def test_an_error_inside_html_safe_still_raises
    other = Class.new { undef_method :html_safe? if method_defined?(:html_safe?) }.new
    [
      Class.new { define_method(:html_safe?) { self.missing_helper } }.new, # rubocop:disable Style/RedundantSelf -- a NoMethodError, not a NameError
      Class.new { define_method(:html_safe?) { other.html_safe? } }.new,
      Class.new { define_method(:html_safe?) { raise NoMethodError.new("gone", :html_safe?) } }.new,
      Class.new do
        undef_method :html_safe? if method_defined?(:html_safe?)
        define_method(:to_s) { html_safe?.to_s }
      end.new
    ].each do |broken|
      assert_raises(NoMethodError) { render("p = broken", html_safe: true, broken:) }
    end
  end

  private

  def render(source, html_safe: String.method_defined?(:html_safe?), **locals)
    scope = binding
    locals.each { |name, value| scope.local_variable_set(name, value) }
    scope.eval(SuperSlim.compile(source, html_safe:))
  end
end
