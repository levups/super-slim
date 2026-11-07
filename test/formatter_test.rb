# frozen_string_literal: true

require "minitest/autorun"
require "slim"
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

  # Both render their trailing whitespace: stripped, the formatter refused the whole template.
  def test_keeps_trailing_whitespace_of_inline_html_and_of_a_quoted_value_that_goes_on
    assert_formats "p\n  <em>Posts</em>  \n", "p\n    <em>Posts</em>  \n"
    assert_formats %(p title="Posts  \n  and comments"\n), %(p title="Posts  \n  and comments"\n)
    assert_formats %(p(id="post"\n  title="Posts  \n  and comments")\n), %(p(id="post"\n  title="Posts  \n  and comments")  \n)
    assert_formats %(p title="Posts\n  and\n  comments"\n), %(p title="Posts\n  and  \n  comments"\n)
  end

  def test_leaves_the_lines_between_format_off_and_on_as_written_shifted_with_their_block
    source = "table\n    / super-slim:format off\n    tr: td  =  t(\".empty\")\n\n\n    tr: td  x\n    / super-slim:format on\n    tr: td  =  1\n"
    expected = "table\n  / super-slim:format off\n  tr: td  =  t(\".empty\")\n\n\n  tr: td  x\n  / super-slim:format on\n  tr: td = 1\n"

    assert_equal expected, SuperSlim::Formatter.call(source)
    assert_equal expected, SuperSlim::Formatter.new(max_line_length: 20).call(source)
  end

  def test_format_off_without_on_leaves_the_rest_of_its_block_as_written
    assert_formats "p = 1\n/ super-slim:format off\np  =  2\ndiv(a=\"1\"   b=\"2\")\n", "p  =  1\n/ super-slim:format off\np  =  2\ndiv(a=\"1\"   b=\"2\")\n"
    assert_formats "div\n  div\n    / super-slim:format off\n    p    a\n  span\n    b = 1\n",
      "div\n    div\n        / super-slim:format off\n        p    a\n    span\n        b  =  1\n"
  end

  def test_format_directives_deeper_than_the_off_are_left_as_written
    assert_formats "div\n  / super-slim:format off\n  ul\n       li\n         / super-slim:format on\n         a x\n", "div\n    / super-slim:format off\n    ul\n         li\n           / super-slim:format on\n           a x\n"
    assert_formats "/ super-slim:format off\ndiv\n  / super-slim:format off\n  p  =  1\nspan  =  2\n", "/ super-slim:format off\ndiv\n  / super-slim:format off\n  p  =  1\nspan  =  2\n"
  end

  def test_blank_lines_closing_a_format_off_block_are_formatted
    assert_formats "div\n  / super-slim:format  off\n  p  a\n\nspan = 1\n", "div\n  / super-slim:format  off\n  p  a\n\n\n\nspan  =  1\n"
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

  def test_spreads_the_arguments_of_a_call_one_per_line_after_commas
    assert_wraps %(= link_to "Edit, now",\n  edit_post_path(post, x: 1),\n  class: "btn"\n), %(= link_to "Edit, now", edit_post_path(post, x: 1), class: "btn"\n),
      max_line_length: 31
    assert_wraps %(- links = [\\\n  root_path,\n  posts_path]\n), %(- links = [root_path, posts_path]\n), max_line_length: 20
  end

  def test_spreads_code_in_a_layout_slim_reads
    assert_wraps %(= link_to "Read the whole post",\n  post_path(post),\n  class: "btn btn-primary"\n),
      %(= link_to "Read the whole post", post_path(post), class: "btn btn-primary"\n), max_line_length: 40
  end

  def test_puts_a_first_argument_that_passes_the_limit_on_a_line_of_its_own
    assert_wraps %(= some_long_helper_name \\\n  "first argument",\n  second\n), %(= some_long_helper_name "first argument", second\n), max_line_length: 40
  end

  def test_spreads_the_only_argument_when_it_is_a_call_or_a_hash
    assert_wraps %(= render Card.new(\\\n  title: post.title,\n  body: post.body)\n), %(= render Card.new(title: post.title, body: post.body)\n)
    assert_wraps %(= render({\\\n  partial: "a/partial",\n  locals: {post: post}})\n), %(= render({partial: "a/partial", locals: {post: post}})\n), max_line_length: 20
  end

  def test_spreads_a_block_argument_last
    assert_wraps %(= link_to post.title,\n  post_path(post),\n  &block\n), %(= link_to post.title, post_path(post), &block\n)
    assert_wraps %(= link_to post.title,\n  data: post_data(&block)\n), %(= link_to post.title, data: post_data(&block)\n)
  end

  def test_leaves_alone_the_lines_it_cannot_spread_and_wraps_the_others
    untouched = %(- words = %w[alpha bravo charlie delta]\n- list[first_key, second_key] = value\n= form.radio label: post.title, hint: -> do\n  p Hint\n)

    assert_wraps %(#{untouched}= link_to post.title,\n  post_path(post)\n), %(#{untouched}= link_to post.title, post_path(post)\n)
  end

  def test_starts_a_block_right_after_the_line_that_opens_it
    assert_formats "= nicely_centered_content do\n  h1 = t(\".title\")\n\np\n", "= nicely_centered_content do\n\n  h1 = t(\".title\")\n\np\n"
    assert_formats "p\n  | text\n\n    more\n", "p\n  | text\n\n    more\n"
  end

  def test_sets_a_partial_signature_apart_from_its_body
    assert_formats "/# locals: (product:)\n\n- if product\n  p = product.name\n", "/# locals: (product:)\n- if product\n  p = product.name\n"
    assert_formats "/# locals: (a:)\n\np = a\n", "\n/# locals: (a:)\np = a\n"
  end

  def test_writes_the_do_that_slim_adds_to_ruby_code_with_children
    assert_formats "= link_to root_path do\n  = fa_icon \"bell\"\n- posts.each do\n  p\n", "= link_to root_path\n  = fa_icon \"bell\"\n- posts.each\n\n  p\n"
    assert_wraps "= foo(a, b) do\n  p\n", "= foo(a,\n  b)\n  p\n"
    untouched = "= f.label :name\n  / a comment opens no block\n- if x\n  p\n- while false\n  p\n= render Card.new # card\n  p\n= form_with(model: x) { |form|\n  = form.text\n"
    assert_formats untouched, untouched
  end

  def test_sets_apart_the_arguments_of_a_call_that_opens_a_block
    assert_wraps %(= form_with model: post,\n    url: posts_path do |form, options|\n  = form.text_field :title\n),
      %(= form_with model: post, url: posts_path do |form, options|\n  = form.text_field :title\n)
    assert_wraps %(= render layout: "card",\n    locals: {post:}\n  p Hello\n), %(= render layout: "card", locals: {post:}\n  p Hello\n)
  end

  def test_wraps_the_output_of_a_tag_after_its_attributes
    assert_wraps %(p(\n  class=classes\n  title="A long title"\n) = format_date \\\n  post.created_at,\n  :long\n),
      %(p class=classes title="A long title" = format_date post.created_at, :long\n)
  end

  def test_joins_code_spread_over_lines_when_it_fits
    assert_wraps %(= link_to post.title, post_path(post)\n), %(= link_to post.title,\n      post_path(post)\n), max_line_length: 40
    assert_wraps %(= link_to(post.title, post_path(post))\n), %(= link_to(\n    post.title,\n    post_path(post),\n  )\n), max_line_length: 40
    assert_wraps %(= link_to post.title, post_path(post)\n), %(= link_to post.title, \\\n  post_path(post)\n), max_line_length: 40
  end

  def test_respreads_code_spread_by_hand
    assert_wraps %(= render Card.new(title: post.title,\n  data: {controller: "a-long-controller",\n    action: "click->a-long-controller#open"})\n),
      %(= render Card.new(\n    title: post.title,\n    data: {\n      controller: "a-long-controller",\n      action: "click->a-long-controller#open",\n    },\n  )\n), max_line_length: 60
    assert_wraps %(= link_to post.title,\n  post_path(post)\n), %(= link_to post.title,\n        post_path(post)\n)
  end

  def test_keeps_code_spread_by_hand_when_the_layout_would_pass_the_limit
    source = %(= render layout: "card",\n  locals: {post: "Alice wrote a long post"}\n  p Hello\n)

    assert_wraps source, source, max_line_length: 50
  end

  def test_respreads_code_spread_by_hand_in_a_layout_slim_cannot_read
    assert_wraps %(= render Card.new(\\\n  title: "Alice wrote a post about Bob",\n  body: post.body)\n),
      %(= render Card.new(\n    title: "Alice wrote a post about Bob",\n    body: post.body,\n  )\n), max_line_length: 50
  end

  def test_keeps_code_spread_by_hand_when_every_layout_passes_the_limit
    source = %(= render "posts/card", post:, title: "Alice",\n  hint: "Alice wrote this post. " \\\n    "Bob read it and wrote a long reply."\n)

    assert_wraps source, source, max_line_length: 40
  end

  def test_spreads_an_argument_that_passes_the_limit_one_element_per_line
    expected = %(= render "posts/card",\n  hint: ["Alice wrote this post.",\n    "Bob read it and replied."].join(" ")\n)

    assert_wraps expected, %(= render "posts/card", hint: ["Alice wrote this post.", "Bob read it and replied."].join(" ")\n), max_line_length: 40
    assert_wraps expected, %(= render "posts/card", hint: ["Alice wrote this post.",\n  "Bob read it and replied."].join(" ")\n), max_line_length: 40
  end

  def test_spreads_a_nested_array_spread_by_hand_one_element_per_line
    expected = %(= form.select :state,\n  collection: [["New", "new"],\n    ["Used", "used"],\n    ["Demo", "demo"]],\n  class: "x"\n)

    assert_wraps expected, %(= form.select :state, collection: [["New", "new"], ["Used", "used"], ["Demo", "demo"]], class: "x"\n), max_line_length: 30
    assert_wraps expected, %(= form.select :state, collection: [["New", "new"], ["Used", "used"],\n    ["Demo", "demo"]], class: "x"\n), max_line_length: 30
  end

  def test_puts_the_arguments_of_new_in_parentheses
    assert_wraps %(= render Card.new(title: post.title)\n), %(= render Card.new title: post.title\n)
    assert_wraps %(= render Card.new(title: post.title) do\n  p Hello\n), %(= render Card.new title: post.title do\n  p Hello\n)
    assert_wraps %(= render Card.new(post, &block)\n), %(= render Card.new post, &block\n), max_line_length: 50
    assert_wraps %(= render Card.new(post, body: body(&block))\n), %(= render Card.new post, body: body(&block)\n), max_line_length: 50
  end

  def test_leaves_alone_what_wrapping_would_change
    [
      %(- first, second = values_of_a_long_list, and_another_one\n),
      %(- first, second = values_of_a_long_list,\n  and_another_one\n),
      %(p.card title="A long title here" Some text\n  continued on the next line\n),
      %(*{tag: tag_name, class: "card", id: "dynamic-identifier"} Dynamic\n),
      %(= link_to post.title, post_path(post) # the post\n),
      %(- if post.published? && post.commentable? && current_user\n  p Hello\n)
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

  def test_turns_a_literal_id_or_class_into_shortcuts
    assert_wraps %(form#search action="/search"\n), %(form id="search" action="/search"\n), max_line_length: 120
    assert_wraps %(li.card.shadow id=dom_id(post)\n), %(li id=dom_id(post) class="card shadow"\n), max_line_length: 120
    assert_wraps %(.card.shadow\n), %(div class="card shadow"\n), max_line_length: 120
    assert_wraps %(a.link#home> href="/" Home\n), %(a.link> id="home" href="/" Home\n), max_line_length: 120
    assert_wraps %(p id="post-\#{post.id}" class=classes\n), %(p id="post-\#{post.id}" class=classes\n), max_line_length: 120
  end

  def test_drops_a_class_named_twice
    assert_wraps %(.p-3.border\n  p Hello\n), %(.p-3.border.p-3\n  p Hello\n), max_line_length: 120
  end

  def test_orders_attributes_by_what_they_say
    assert_wraps %(input.form-control type="number" name="quantity" data-action="change->cart#update" aria-label=label\n),
      %(input aria-label=label data-action="change->cart#update" type="number" name="quantity" class="form-control"\n), max_line_length: 120
  end

  def test_writes_attributes_without_delimiters_when_they_fit
    assert_wraps %(fieldset data-flow="accessories"\n  legend Title\n), %(fieldset{data-flow="accessories"}\n  legend Title\n), max_line_length: 120
    assert_wraps %(button.btn type="button" data-action="modal#close"\n), %(button.btn {\n  type="button"\n  data-action="modal#close"\n}\n), max_line_length: 120
  end

  def test_leaves_attributes_alone_when_their_order_or_delimiters_matter
    [
      %(input(type="checkbox" checked)\n),
      %(div *attributes class="card" id="main"\n),
      %(*{tag: tag_name, class: "card"} Dynamic\n),
      %(p(title="A") role=main\n),
      %(p class=classes class="card"\n),
      %(p class=" " Hello\n),
      %(.card class="card shadow"\n)
    ].each { assert_wraps "#{_1}.p-3\n", "#{_1}.p-3.p-3\n", max_line_length: 120 }
  end

  def test_joins_back_only_the_attributes_of_a_tag
    [%(/ Disabled until (\n  the API ships\n  )\n), %(| Call us (\n  9am to 5pm\n  )\n)].each do
      assert_wraps "#{_1}.p-3\n", "#{_1}.p-3.p-3\n", max_line_length: 120
    end
  end

  def test_spreads_attributes_whose_opening_line_fits_the_limit
    assert_wraps %(abcdefgh(\n  title="aaaaaaaaaaaaaa"\n)\n), %(abcdefgh title="aaaaaaaaaaaaaa"\n), max_line_length: 10
  end

  def test_reads_tailwind_shortcuts_whole
    formatter = SuperSlim::Formatter.new(max_line_length: 120, tailwind_classes: true)

    assert_equal ".py-1.5.py-1\n.w-1/2.w-1\n.p-3\n", formatter.call(".py-1.5.py-1\n.w-1/2.w-1\n.p-3.p-3\n")
  end

  def test_refuses_a_wrap_that_changes_the_order_of_classes
    source = "div class=\"b a\" Hello\n"

    assert_equal source, formatter_wrapping_into(".a.b Hello\n").call(source)
  end

  private

  def assert_formats(expected, source)
    assert_equal expected, SuperSlim::Formatter.call(source)
    assert_equal expected, SuperSlim::Formatter.call(expected)
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
    # Brakeman reads templates with Slim: it must read the same code, not a continuation line as a tag.
    assert_equal code_of(SuperSlim::Parser.new.call(expected)), slim_code_of(Slim::Parser.new.call(expected)), "Slim reads otherwise:\n#{expected}"
  end

  def code_of(nodes)
    Array(nodes).flat_map do |node|
      case node
      when SuperSlim::AST::Output, SuperSlim::AST::Control then [node.code, *code_of(node.children)]
      when SuperSlim::AST::Tag then code_of(node.content)
      when Struct then node.members.flat_map { code_of(node[_1]) if node[_1].is_a?(Array) }.compact
      else []
      end
    end
  end

  def slim_code_of(sexp)
    return [] unless sexp.is_a?(Array)
    return [sexp[3], *slim_code_of(sexp[4])] if sexp[0..1] == [:slim, :output]
    return [sexp[2], *slim_code_of(sexp[3])] if sexp[0..1] == [:slim, :control]

    sexp.flat_map { slim_code_of(_1) }
  end
end
