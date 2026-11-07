# frozen_string_literal: true

require "minitest/autorun"
require "super_slim"
require "super_slim/linter"

class LinterTest < Minitest::Test
  def test_layout_rules
    assert_offenses ["Indentation:2", "TrailingWhitespace:2", "ControlStatementSpacing:3", "RedundantDiv:4", "EmptyLines:6"],
      "ul\n   li \n-x = 1\ndiv.card\n\n\np\n"
  end

  def test_trailing_whitespace_that_renders_is_not_to_be_removed
    source = %(p Posts \n<em>Posts</em> \np title="Posts \n  and comments" \nli \n)
    messages = SuperSlim::Linter.new.call("show.html.slim", source).map { |offense| "#{offense.lineno}: #{offense.message}" }

    renders = "Trailing whitespace renders: write it with `'` or `>` instead"
    assert_equal ["1: #{renders}", "2: #{renders}", "3: #{renders}", "4: Remove trailing whitespace", "5: Remove trailing whitespace"], messages
  end

  def test_final_newline
    assert_offenses ["TrailingBlankLines:1"], "p"
    assert_offenses ["TrailingBlankLines:2"], "p\n\n"
  end

  def test_slim_lint_rules
    assert_offenses ["CommentControlStatement:1", "EmptyControlStatement:2", "TagCase:3"], "- # note\n-\nDIV\n"
    assert_offenses ["ConsecutiveControlStatements:1"], "- a = 1\n- b = 2\n- c = 3\n"
    assert_offenses [], "- # rubocop:disable Style/Foo\n"
  end

  def test_html_and_accessibility_rules
    source = <<~SLIM
      img src="/a.webp"
      img src="/b.webp" alt=""
      iframe src="/map"
      a.nav Home
      a href="/"
        a href="/x" Nested
      div tabindex="2"
      input disabled="disabled"
      div role="buton" aria-labeledby="x"
      p#main
      p#main
    SLIM
    assert_offenses ["ImageAlt:1", "IframeTitle:3", "AnchorHref:4", "NestedLinks:6", "PositiveTabindex:7",
      "BooleanAttributeValue:8", "AriaRole:9", "AriaAttribute:9", "DuplicateId:11"], source
  end

  def test_string_output_inline_after_a_tag
    linter = SuperSlim::Linter.new
    messages = linter.call("show.html.slim", %(span.note = "(estimate)"\nspan = "Hello"\np\n  = "(alone)"\n)).map(&:message)
    assert_equal ["Write the text `| (estimate)` on its own line, under the tag: inline, it would read as attributes",
      "Write the text `| Hello` instead of outputting a string",
      "Write the text `| (alone)` instead of outputting a string"], messages
  end

  def test_zero_width_characters
    assert_offenses ["Zwsp:1", "Zwsp:2"], "p Hello\u200Bworld\np Join\u200Ded\n"
    assert_offenses [], "\uFEFFp Byte order mark\np Black cat 🐈\u200D⬛, coder 👩🏻\u200D💻, flag 🏳\uFE0F\u200D🌈\n"
    assert_offenses ["Zwsp:1", "Zwsp:2", "Zwsp:3"], "p Cat 🐈\u200C⬛\np Joiner after 😀\u200D\np Space 😀\u200B😀\n"
  end

  def test_same_id_in_two_branches_is_not_a_duplicate
    assert_offenses [], "- if x\n  p#main\n- else\n  p#main\n"
  end

  def test_unnecessary_ruby
    assert_offenses ["UnnecessaryInterpolation:1", "UnnecessaryStringOutput:2", "UnnecessaryInterpolation:4"], "| \#{title}\n= \"Hello\"\n= \" \"\nh1 \#{title}\n"
  end

  def test_instance_variables_in_partials_only
    assert_offenses ["InstanceVariables:1"], "p = @user.name\n", path: "app/views/_card.html.slim"
    assert_offenses [], "p = @user.name\n", path: "app/views/show.html.slim"
  end

  def test_case_sensitive_xml_and_svg_tags
    assert_offenses [], "pubDate = date\n", path: "feed.rss.slim"
    assert_offenses [], "svg\n  linearGradient\n"
  end

  def test_configuration
    linter = SuperSlim::Linter.new("LineLength" => {"max" => 10}, "ButtonType" => {"enabled" => true},
      "DeprecatedClasses" => {"classes" => {"text-muted" => "text-body-secondary"}})
    offenses = linter.call("x.slim", "button.text-muted Ok, long line\n")

    assert_equal %w[LineLength ButtonType DeprecatedClasses].sort, offenses.map(&:rule).sort
  end

  def test_deprecated_classes_by_prefix_and_attributes
    linter = SuperSlim::Linter.new("DeprecatedClasses" => {"classes" => {"ml-*" => "ms-*", "badge-*" => "text-bg-*", "close" => "btn-close"}},
      "DeprecatedAttributes" => {"attributes" => {"data-toggle" => "data-bs-toggle"}})
    source = "span.ml-2.ml.badge-info.close\nbutton{\n  type=\"button\"\n  data-toggle=\"modal\"\n} Open\n"

    assert_equal ["`ml-2` is deprecated: use `ms-2`", "`badge-info` is deprecated: use `text-bg-info`",
      "`close` is deprecated: use `btn-close`", "`data-toggle` is deprecated: use `data-bs-toggle`"],
      linter.call("show.html.slim", source).map(&:message)
  end

  def test_bootstrap5_preset_under_the_entries_of_the_configuration
    linter = SuperSlim::Linter.new("DeprecatedClasses" => {"preset" => "bootstrap5",
                                                           "classes" => {"media" => nil, "text-muted" => "text-secondary", "badge-promo-*" => "promo-*"}},
      "DeprecatedAttributes" => {"preset" => "bootstrap5", "attributes" => nil})
    source = "span.ml-2.media.text-muted.badge-pill.badge-info.badge-promo-red.text-md-right\nbutton{\n  type=\"button\"\n  data-toggle=\"modal\"\n} Open\n"

    assert_equal ["`ml-2` is deprecated: use `ms-2`", "`text-muted` is deprecated: use `text-secondary`",
      "`badge-pill` is deprecated: use `rounded-pill`", "`badge-info` is deprecated: use `text-bg-info`",
      "`badge-promo-red` is deprecated: use `promo-red`", "`text-md-right` is deprecated: use `text-md-end`",
      "`data-toggle` is deprecated: use `data-bs-toggle`"],
      linter.call("show.html.slim", source).map(&:message)
  end

  def test_unknown_preset
    error = assert_raises(SuperSlim::Error) { SuperSlim::Linter.new("DeprecatedClasses" => {"preset" => "bootstrap4"}) }

    assert_equal "DeprecatedClasses: unknown preset `bootstrap4`, use one of: bootstrap5", error.message
  end

  def test_unescaped_output
    linter = SuperSlim::Linter.new("UnescapedOutput" => {"enabled" => true})
    source = <<~'SLIM'
      == post.body
      p = raw(post.body)
      a href==url = title
      p = t(".intro").html_safe
      p Hello #{{name}}
      ruby:
        intro = post.intro.html_safe
      p = form.raw_value
      p = t(".intro_html")
    SLIM
    offenses = linter.call("show.html.slim", source)

    assert_equal ["UnescapedOutput:1", "UnescapedOutput:2", "UnescapedOutput:3", "UnescapedOutput:4", "UnescapedOutput:5",
      "UnescapedOutput:6"], offenses.map { "#{_1.rule}:#{_1.lineno}" }
    assert_equal "`raw` skips HTML escaping: output with `=`, or render HTML from a translation key ending in `_html`", offenses[1].message
  end

  def test_slim_syntax
    linter = SuperSlim::Linter.new("SlimSyntax" => {"enabled" => true})
    source = <<~SLIM
      = link_to(
          post.title,
          post_path(post),
        )
      = render Card.new(post:) # rubocop:disable Some/Cop
      p = post.title # the title
      - if post.published? # only then
        p Published
      = link_to post.title,
        post_path(post)
      = "Post #1"
    SLIM
    offenses = linter.call("show.html.slim", source)

    assert_equal ["SlimSyntax:1", "SlimSyntax:5", "SlimSyntax:6", "SlimSyntax:7"], offenses.map { "#{_1.rule}:#{_1.lineno}" }
    assert_equal "Slim, and so Brakeman, cannot read a comment after code: move it to a line of its own", offenses[1].message
  end

  def test_embedded_engines
    linter = SuperSlim::Linter.new("EmbeddedEngines" => {"enabled" => true, "forbidden_engines" => %w[javascript css]})

    assert_equal ["EmbeddedEngines:2"], linter.call("show.html.slim", "p Hello\njavascript:\n  alert(1)\nruby:\n  x = 1\n")
      .map { "#{_1.rule}:#{_1.lineno}" }
  end

  def test_hardcoded_text
    linter = SuperSlim::Linter.new("HardcodedText" => {"enabled" => true})
    source = <<~'SLIM'
      h1 Welcome
      p
        | Read the
          full story
      p = t(".title")
      p #{count} &mdash; 12
      ' &nbsp;
      / Comment
      p #{{name}}
      description
        | <![CDATA[
        = post.body
        | ]]>
    SLIM
    offenses = linter.call("show.html.slim", source)

    assert_equal ["HardcodedText:1", "HardcodedText:3"], offenses.map { "#{_1.rule}:#{_1.lineno}" }
    assert_equal "Translate `Read the full story` instead of writing it in the template", offenses.last.message
  end

  def test_include_and_exclude_globs
    linter = SuperSlim::Linter.new({"InlineStyles" => {"enabled" => true, "include" => ["app/**/*.slim"], "exclude" => ["app/views/*_mailer/**/*"]}},
      "/project")
    source = "p style=\"color: red\" Hello\n"

    assert_equal ["InlineStyles"], linter.call("/project/app/views/posts/show.html.slim", source).map(&:rule)
    assert_empty linter.call("/project/app/views/user_mailer/welcome.html.slim", source)
    assert_empty linter.call("/project/lib/templates/show.html.slim", source)
  end

  def test_offenses_of_one_line_come_in_rule_order
    offenses = SuperSlim::Linter.new.call("show.html.slim", "img src=\"/#{"a" * 120}.png\"\n")
    assert_equal %w[LineLength ImageAlt], offenses.map(&:rule)
    assert_equal %w[Indentation Tab TrailingWhitespace], SuperSlim::Linter::Rules.all.first(3).map(&:rule_name)
  end

  def test_aria_true_and_false_render_no_value
    offenses = SuperSlim::Linter.new.call("show.html.slim", ".toast aria-atomic=true aria-hidden=false aria-live=\"polite\" aria-busy=busy\n")

    assert_equal ["Write `aria-atomic=\"true\"`: Slim renders `aria-atomic=true` without a value",
      "Write `aria-hidden=\"false\"`: Slim renders `aria-hidden=false` as no attribute at all"], offenses.map(&:message)
  end

  def test_disable_directive_silences_its_rules_on_the_next_line_and_reports_unknown_ones
    source = "﻿/ super-slim:disable ImageAlt, IframeTitle, Typo\n\nimg src=\"/a.webp\"\nimg src=\"/b.webp\"\n"
    assert_offenses ["Directive:1", "ImageAlt:4"], source
  end

  def test_disable_directive_covers_the_lines_its_line_goes_on_over
    source = "/ super-slim:disable ,LineLength\ndiv(\n  data-x=\"#{"x" * 130}\")\np\n  | #{"y" * 130}\n"
    assert_offenses ["LineLength:5"], source
  end

  def test_disable_directive_skips_comments
    assert_offenses [], "/ super-slim:disable ImageAlt\n/ Hero\nimg src=\"/a.webp\"\n"
    assert_offenses [], "/ super-slim:disable ImageAlt\n/ super-slim:disable ButtonType\nimg src=\"/a.webp\"\nbutton Save\n"
  end

  def test_disable_directive_with_no_line_after_it_is_reported
    assert_offenses ["Directive:2"], "p\n/ super-slim:disable ImageAlt\n"
  end

  def test_layout_rules_stay_quiet_where_format_is_off
    assert_offenses ["Indentation:6"], "div\n  / super-slim:format off\n  p\n       span    a\nspan\n   em\n"
  end

  def test_syntax_errors_are_offenses
    assert_offenses ["Syntax:2"], "p\n  a(href='/'\n"
  end

  private

  def assert_offenses(expected, source, path: "app/views/show.html.slim")
    offenses = SuperSlim::Linter.new.call(path, source)
    assert_equal expected.sort, offenses.map { |offense| "#{offense.rule}:#{offense.lineno}" }.sort
  end
end
