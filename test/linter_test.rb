# frozen_string_literal: true

require "minitest/autorun"
require "slimx"
require "slimx/linter"

class LinterTest < Minitest::Test
  def test_layout_rules
    assert_offenses ["Indentation:2", "TrailingWhitespace:2", "ControlStatementSpacing:3", "RedundantDiv:4", "EmptyLines:6"],
      "ul\n   li \n-x = 1\ndiv.card\n\n\np\n"
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
    linter = SlimX::Linter.new
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
    linter = SlimX::Linter.new("LineLength" => {"max" => 10}, "ButtonType" => {"enabled" => true},
      "DeprecatedClasses" => {"classes" => {"text-muted" => "text-body-secondary"}})
    offenses = linter.call("x.slim", "button.text-muted Ok, long line\n")

    assert_equal %w[LineLength ButtonType DeprecatedClasses].sort, offenses.map(&:rule).sort
  end

  def test_offenses_of_one_line_come_in_rule_order
    offenses = SlimX::Linter.new.call("show.html.slim", "img src=\"/#{"a" * 120}.png\"\n")
    assert_equal %w[LineLength ImageAlt], offenses.map(&:rule)
    assert_equal %w[Indentation Tab TrailingWhitespace], SlimX::Linter::Rules.all.first(3).map(&:rule_name)
  end

  def test_syntax_errors_are_offenses
    assert_offenses ["Syntax:2"], "p\n  a(href='/'\n"
  end

  private

  def assert_offenses(expected, source, path: "app/views/show.html.slim")
    offenses = SlimX::Linter.new.call(path, source)
    assert_equal expected.sort, offenses.map { |offense| "#{offense.rule}:#{offense.lineno}" }.sort
  end
end
