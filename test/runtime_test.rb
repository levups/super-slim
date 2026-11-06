# frozen_string_literal: true

require "minitest/autorun"
require "super_slim"

# Names known only at render time come from data: they must not open an attribute or a tag of their own.
class RuntimeTest < Minitest::Test
  def test_separators_in_a_data_key_cannot_add_an_attribute
    ["\t", "\n", "\f", "\r", " ", "\0"].each do |separator|
      exception = assert_raises(SuperSlim::InvalidAttributeNameError) { render("a data=meta", meta: {"x#{separator}onclick" => "alert(1)"}) }
      assert_includes exception.message, "data-x#{separator}onclick"
    end
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

  private

  def render(source, **locals)
    scope = binding
    locals.each { |name, value| scope.local_variable_set(name, value) }
    scope.eval(SuperSlim.compile(source))
  end
end
