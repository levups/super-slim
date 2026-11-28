# frozen_string_literal: true

require "minitest/autorun"
require "super_slim"
require "super_slim/linter"

# A comment after code is dropped where it would swallow what the compiler writes after it, and only there: a `#`
# that Ruby reads as part of a literal stays. The golden templates hold the rest; these need a local variable,
# which the golden test reads each line without.
class TrailingCommentTest < Minitest::Test
  def test_a_comment_after_a_local_divided_or_questioned_is_dropped
    assert_equal "3", render("- count = 9\n= (count /3).round # thirds, see /docs#round\n")
    assert_equal "a", render("- count = 9\n= count ?'a':'b' # it's #1\n")
    assert_equal "-2", render("- count = 7\n= count %-3 # remainder\n")
    assert_equal "5", render("- count = 10\n= (1..count /2).count # half, see #12\n")
    assert_equal "2", render("- @in = 4\n= @in /2 # c\n")
    assert_equal "a", render("- state = :ok?\n= state == :ok? ?'a':'b' # c\n")
  end

  def test_slim_syntax_reports_the_comment_after_a_regexp
    messages = SuperSlim::Linter.new.call("show.html.slim", "p = \"a#b\".split /#/ # c\n").map(&:rule)

    assert_equal ["SlimSyntax"], messages
  end

  private

  def render(source)
    scope = binding
    scope.eval(SuperSlim.compile(source))
  end
end
