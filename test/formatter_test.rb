# frozen_string_literal: true

require "minitest/autorun"
require "super_slim"
require "slim"

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
    assert_wraps %(= link_to post.title,\n    (post_path(post) if post.published?)\n), %(= link_to post.title, (post_path(post) if post.published?)\n)
  end

  def test_spreads_the_arguments_of_a_call_one_per_line_after_a_comma
    assert_wraps %(= link_to "Edit, now",\n    edit_post_path(post, x: 1),\n    class: "btn"\n), %(= link_to "Edit, now", edit_post_path(post, x: 1), class: "btn"\n),
      max_line_length: 31
    assert_wraps %(= link_to(post.title,\n    post_path(post))\n), %(= link_to(post.title, post_path(post))\n), max_line_length: 25
    assert_wraps %(- links = [root_path,\n    posts_path]\n), %(- links = [root_path, posts_path]\n), max_line_length: 22
  end

  def test_moves_a_first_argument_too_long_for_its_line_after_a_backslash
    assert_wraps %(= link_to \\\n    post.author.profile_page_path,\n    class: "btn"\n), %(= link_to post.author.profile_page_path, class: "btn"\n), max_line_length: 36
  end

  def test_spreads_the_only_argument_when_it_is_a_call_or_a_hash
    assert_wraps %(= render Card.new(title: post.title,\n    body: post.body)\n), %(= render Card.new(title: post.title, body: post.body)\n), max_line_length: 40
    assert_wraps %(= render({partial: "a/partial",\n    locals: {post: post}})\n), %(= render({partial: "a/partial", locals: {post: post}})\n), max_line_length: 35
  end

  def test_spreads_a_block_argument_last
    assert_wraps %(= link_to post.title,\n    post_path(post),\n    &block\n), %(= link_to post.title, post_path(post), &block\n)
    assert_wraps %(= link_to post.title,\n    data: post_data(&block)\n), %(= link_to post.title, data: post_data(&block)\n)
  end

  def test_leaves_alone_the_lines_it_cannot_spread_and_wraps_the_others
    untouched = %(- words = %w[alpha bravo charlie delta]\n- list[first_key, second_key] = value\n= form.radio label: post.title, hint: -> do\n  p Hint\n)

    assert_wraps %(#{untouched}= link_to post.title,\n    post_path(post)\n), %(#{untouched}= link_to post.title, post_path(post)\n)
  end

  def test_spreads_the_arguments_of_a_call_that_opens_a_block
    assert_wraps %(= form_with model: post,\n    url: posts_path do |form, options|\n  = form.text_field :title\n),
      %(= form_with model: post, url: posts_path do |form, options|\n  = form.text_field :title\n), max_line_length: 40
    assert_wraps %(= render layout: "card",\n    locals: {post:}\n  p Hello\n), %(= render layout: "card", locals: {post:}\n  p Hello\n)
  end

  def test_wraps_the_output_of_a_tag_after_its_attributes
    assert_wraps %(p(\n  class=classes\n  title="A long title"\n) = format_date post.created_at,\n    :long\n),
      %(p class=classes title="A long title" = format_date post.created_at, :long\n), max_line_length: 32
    assert_wraps %(p(\n  class=classes\n  title="A long title"\n) = format_date(post.created_at,\n    :long)\n),
      %(p(\n  class=classes\n  title="A long title"\n) = format_date(\n    post.created_at,\n    :long,\n  )\n), max_line_length: 32
  end

  def test_joins_code_spread_over_lines_when_it_fits
    assert_wraps %(= link_to post.title, post_path(post)\n), %(= link_to post.title,\n      post_path(post)\n), max_line_length: 40
    assert_wraps %(= link_to(post.title, post_path(post))\n), %(= link_to(\n    post.title,\n    post_path(post),\n  )\n), max_line_length: 40
    assert_wraps %(= link_to post.title, post_path(post)\n), %(= link_to post.title, \\\n  post_path(post)\n), max_line_length: 40
    assert_wraps %(p class=classes title="A long title" = format_date post.created_at, :long\n),
      %(p(\n  class=classes\n  title="A long title"\n) = format_date post.created_at,\n    :long\n), max_line_length: 100
  end

  def test_spreads_a_call_whose_first_argument_cannot_fit
    assert_wraps %(- f(very_long_argument_name_xxxxxxxxxxxxxx,\n    b,\n    c)\n), %(- f(very_long_argument_name_xxxxxxxxxxxxxx, b, c)\n)
    assert_wraps %(= [some_long_element_name_xxxxxxxxxxxxxxxx,\n    b,\n    c].join(", ")\n), %(= [some_long_element_name_xxxxxxxxxxxxxxxx, b, c].join(", ")\n)
    assert_wraps %(= post.comments_by(author).sorted_by( \\\n    created_at,\n    title)\n), %(= post.comments_by(author).sorted_by(created_at, title)\n), max_line_length: 40
  end

  def test_moves_a_block_that_would_pass_the_limit_after_a_backslash
    assert_wraps %(= form_with model: post,\n    url: posts_path \\\n    do |form_builder, options|\n  = form_builder.text_field :title\n),
      %(= form_with model: post, url: posts_path do |form_builder, options|\n  = form_builder.text_field :title\n)
  end

  def test_keeps_code_spread_by_hand_when_joining_it_would_comment_out_the_rest
    source = %(= link_to(\n    post.title, # the title\n    post_path(post),\n  )\n= link_to post.title, post_path(post), class: "btn"\n)
    expected = %(= link_to(\n    post.title, # the title\n    post_path(post),\n  )\n= link_to post.title,\n    post_path(post),\n    class: "btn"\n)

    assert_equal expected, SuperSlim::Formatter.new(max_line_length: 30).call(source)
  end

  def test_respreads_code_spread_by_hand
    assert_wraps %(= link_to post.title,\n    post_path(post)\n), %(= link_to post.title,\n        post_path(post)\n)
  end

  def test_respreads_code_that_slim_cannot_read
    assert_wraps %(= link_to(post.title,\n    post_path(post))\n), %(= link_to(\n    post.title,\n    post_path(post),\n  )\n), max_line_length: 25
    assert_wraps %(= render Card.new(title: post.title,\n    data: {controller: "a-long-controller",\n      action: "click->a-long-controller#open"})\n),
      %(= render Card.new(\n    title: post.title,\n    data: {\n      controller: "a-long-controller",\n      action: "click->a-long-controller#open",\n    },\n  )\n), max_line_length: 50
  end

  def test_keeps_code_spread_by_hand_when_every_layout_passes_the_limit
    source = %(= render "posts/card", post:, title: "Alice",\n  hint: "Alice wrote this post. " \\\n    "Bob read it and wrote a long reply."\n)

    assert_wraps source, source, max_line_length: 40
  end

  def test_spreads_an_argument_that_passes_the_limit_one_element_per_line
    expected = %(= render "posts/card",\n    hint: ["Alice wrote this post.",\n      "Bob read it and replied."].join(" ")\n)

    assert_wraps expected, %(= render "posts/card", hint: ["Alice wrote this post.", "Bob read it and replied."].join(" ")\n), max_line_length: 44
    assert_wraps expected, %(= render "posts/card", hint: ["Alice wrote this post.",\n  "Bob read it and replied."].join(" ")\n), max_line_length: 44
  end

  def test_spreads_a_nested_array_spread_by_hand_one_element_per_line
    expected = %(= form.select :state,\n    collection: [["New", "new"],\n      ["Used", "used"],\n      ["Demo", "demo"]],\n    class: "x"\n)

    assert_wraps expected, %(= form.select :state, collection: [["New", "new"], ["Used", "used"], ["Demo", "demo"]], class: "x"\n), max_line_length: 32
    assert_wraps expected, %(= form.select :state, collection: [["New", "new"], ["Used", "used"],\n    ["Demo", "demo"]], class: "x"\n), max_line_length: 32
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
    assert_wraps %(= render "card",\n    body: yield(post)\n), %(= render "card", body: yield(post)\n)
  end

  def test_wraps_an_argument_that_is_an_if_expression
    assert_wraps %(= submit_button :save,\n    if post.persisted? then "Save" else "Add" end\n),
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
    assert_slim_reads_the_same_code expected
  end

  # Tools built on Slim, such as Brakeman, read what the formatter writes.
  def assert_slim_reads_the_same_code(template)
    assert_equal ruby_code_of(SuperSlim::Parser.new.call(template)), ruby_code_of(Slim::Parser.new.call(template))
  end

  # The code of each control and output, line breaks aside, from SuperSlim's tree or Slim's.
  def ruby_code_of(tree)
    case tree
    in SuperSlim::AST::Control | SuperSlim::AST::Output
      [on_one_line(tree.code), *ruby_code_of(tree.children)]
    in [:slim, :control, code, children]
      [on_one_line(code), *ruby_code_of(children)]
    in [:slim, :output, _escape, code, children]
      [on_one_line(code), *ruby_code_of(children)]
    in Array | Struct
      tree.to_a.flat_map { ruby_code_of(_1) }
    else
      []
    end
  end

  def on_one_line(code)
    code.gsub(/\s*\\?\n\s*/, " ")
  end
end
