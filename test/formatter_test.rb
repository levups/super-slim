# frozen_string_literal: true

require "minitest/autorun"
require "super_slim"

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

    assert_equal source, SuperSlim::Formatter.call(source)
  end

  def test_is_idempotent
    formatted = SuperSlim::Formatter.call("div\n   - if x\n      p=y\n   - else\n      |  a\n          b\n")

    assert_equal formatted, SuperSlim::Formatter.call(formatted)
  end

  def test_wraps_attributes_one_per_line_inside_delimiters
    assert_wraps %(a.btn(\n  href="/posts/1"\n  data-turbo="false"\n) Edit\n), %(a.btn href="/posts/1" data-turbo="false" Edit\n)
    assert_wraps %(li: a(\n  href=url\n  disabled\n) = title\n), %(li: a{href=url disabled} = title\n), max_line_length: 20
  end

  def test_wraps_attributes_inside_the_configured_delimiters
    expected = %(a.btn {\n  href="/posts/1"\n  data-turbo="false"\n} Edit\n)

    assert_wraps expected, %(a.btn href="/posts/1" data-turbo="false" Edit\n), attribute_delimiters: "{}"
    assert_wraps expected, %(a.btn(href="/posts/1" data-turbo="false") Edit\n), attribute_delimiters: "{}"
    assert_wraps %(p[\n  class=classes\n  title="A long title"\n]\n), %(p class=classes title="A long title"\n), attribute_delimiters: "[]"
  end

  def test_refuses_unknown_attribute_delimiters
    assert_raises(ArgumentError) { SuperSlim::Formatter.new(max_line_length: 80, attribute_delimiters: "<>") }
  end

  def test_keeps_a_line_that_ends_with_a_modifier_whole
    source = %(td = link_to post.title, post_path(post) if post.published?\n)

    assert_equal source, SuperSlim::Formatter.new(max_line_length: 30).call(source)
    assert_wraps %(= link_to post.title,\n  (post_path(post) if post.published?)\n), %(= link_to post.title, (post_path(post) if post.published?)\n)
  end

  def test_wraps_arguments_after_each_comma_up_to_the_block
    assert_wraps %(= link_to "Edit, now",\n  edit_post_path(post, x: 1),\n  class: "btn"\n), %(= link_to "Edit, now", edit_post_path(post, x: 1), class: "btn"\n)
    assert_wraps %(= form_with model: post,\n    url: posts_path do |form, options|\n  = form.text_field :title\n),
      %(= form_with model: post, url: posts_path do |form, options|\n  = form.text_field :title\n)
    assert_wraps %(= render layout: "card",\n    locals: {post:}\n  p Hello\n), %(= render layout: "card", locals: {post:}\n  p Hello\n)
  end

  def test_wraps_the_output_of_a_tag_after_its_attributes
    assert_wraps %(p(\n  class=classes\n  title="A long title"\n) = format_date post.created_at,\n  :long\n),
      %(p class=classes title="A long title" = format_date post.created_at, :long\n)
  end

  def test_leaves_alone_what_wrapping_would_change
    [
      %(- first, second = values_of_a_long_list, and_another_one\n),
      %(p.card title="A long title here" Some text\n  continued on the next line\n),
      %(*{tag: tag_name, class: "card", id: "dynamic-identifier"} Dynamic\n),
      %(= render({partial: "a/partial", locals: {post: post}})\n)
    ].each { assert_wraps _1, _1, max_line_length: 20 }
  end

  def test_keeps_the_layout_when_a_wrap_would_change_the_ruby
    assert_equal "p Hello, world\n", formatter_wrapping_into("p Hello,\n  world\n").call("p Hello, world\n")
  end

  def test_keeps_a_wrap_that_only_adds_a_trailing_comma_and_parentheses
    wrapped = "= link_to(\n    post.title,\n    post_path(post),\n  )\n"

    assert_equal wrapped, formatter_wrapping_into(wrapped).call("= link_to post.title, post_path(post)\n")
  end

  def test_refuses_a_wrap_that_moves_an_argument
    source = "= link_to(post.title) + suffix\n"

    assert_equal source, formatter_wrapping_into("= link_to (post.title) + suffix\n").call(source)
    assert_equal source, formatter_wrapping_into("= link_to(\n    post.title + suffix,\n  )\n").call(source)
  end

  def test_refuses_a_wrap_that_changes_a_number
    source = "= limit 1, 2.5\n"

    assert_equal source, formatter_wrapping_into("= limit(\n    2,\n    1.5,\n  )\n").call(source)
  end

  def test_refuses_a_wrap_that_renames_a_variable
    source = "- @title = post.title\n"

    assert_equal source, formatter_wrapping_into("- @name = post.title\n").call(source)
  end

  def test_refuses_a_wrap_of_a_template_that_does_not_compile
    source = %(p id="a" id="b" Hello, world\n)

    assert_equal source, formatter_wrapping_into(%(p id="a" id="b" Hello,\n  world\n)).call(source)
  end

  def test_wraps_a_template_that_yields
    assert_wraps %(= render "card",\n  body: yield(post)\n), %(= render "card", body: yield(post)\n)
  end

  def test_wraps_an_argument_that_is_an_if_expression
    assert_wraps %(= submit_button :save,\n  if post.persisted? then "Save" else "Add" end\n),
      %(= submit_button :save, if post.persisted? then "Save" else "Add" end\n)
  end

  private

  def assert_formats(expected, source)
    assert_equal expected, SuperSlim::Formatter.call(source)
  end

  def formatter_wrapping_into(wrapped)
    formatter = SuperSlim::Formatter.new(max_line_length: 10)
    formatter.instance_variable_set(:@line_wrapper, ->(_source) { wrapped })
    formatter
  end

  def assert_wraps(expected, source, max_line_length: 30, attribute_delimiters: "()")
    formatter = SuperSlim::Formatter.new(max_line_length:, attribute_delimiters:)

    assert_equal expected, formatter.call(source)
    assert_equal expected, formatter.call(expected)
  end
end
