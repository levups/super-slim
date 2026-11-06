# frozen_string_literal: true

require "minitest/autorun"
require "super_slim"
require "super_slim/formatter"
require "super_slim/linter"

# Templates in a pull request are written by anyone: the linter and the formatter must neither hang nor crash.
class HostileTemplatesTest < Minitest::Test
  # Each added brace doubled the time of the balanced-braces regexp: 24 took 2 seconds, 30 would take minutes.
  def test_nested_braces_in_an_interpolation_compile_in_linear_time
    assert_fast { SuperSlim.compile("p #{"\#{" + "{" * 30}\n") }
    assert_fast { SuperSlim.compile("p #{"\#{a" * 40_000}\n") }
    assert_equal "<p>#{"\#{" + "{" * 30}</p>", render("p #{"\#{" + "{" * 30}")
    assert_equal "<p>a {b} c</p>", render("p a \#{\"{b}\"} c")
  end

  # Each line after a bracket left open lexed the code read so far again: 4,000 lines took 21 seconds.
  def test_code_continued_over_many_lines_parses_in_linear_time
    assert_fast { SuperSlim::Linter.new.call("t.slim", "= foo(\n" + "  1 +\n" * 20_000 + "  1)\n") }
    assert_fast { SuperSlim.compile("= foo(\n" + "  [\n" * 2_000 + "  1" + "]" * 2_000 + ")\n") }
    assert_fast { SuperSlim.compile("= foo(\n  " + "\"\#{" * 5_000 + "1" + "}\"" * 5_000 + ")\n") }
  end

  # Outline columns counted each attribute from the start of the line, and rules scanned every ancestor.
  def test_long_lines_and_deep_nesting_lint_in_linear_time
    assert_fast { SuperSlim::Linter.new.call("t.slim", "p é #{"a=\"é\" " * 40_000}\n") }
    assert_fast { SuperSlim::Linter.new.call("t.slim", ("A: " * 200 + "b\n") * 200) }
  end

  def test_nesting_too_deep_for_the_stack_is_an_error
    exception = assert_raises(SuperSlim::SyntaxError) { SuperSlim.compile("#{"a: " * 5_000}b\n") }
    assert_equal "Tags nested more than 500 levels deep", exception.error
    assert_equal "<a>" * 499 + "<b></b>" + "</a>" * 499, render("#{"a: " * 499}b\n")

    # How deep Prism goes before it exhausts the stack depends on the machine.
    with_stack_overflow_in(:parse) { assert_raises(SuperSlim::UnsafeFormattingError) { SuperSlim::Formatter.new.call("p\n= 1  \n") } }
    assert_equal "p\n= #{"[" * 2_000}1#{"]" * 2_000}\n", SuperSlim::Formatter.new.call("p\n= #{"[" * 2_000}1#{"]" * 2_000}  \n")
  end

  def test_an_output_without_code_is_no_crash
    ["p =\n", "a=\n", %(a title="x\n  y" = n  \n)].each do |source|
      SuperSlim::Linter.new.call("t.slim", source)
      SuperSlim::Formatter.new.call(source)
    end
  end

  def test_invalid_utf8_is_a_syntax_error_on_its_line
    ["p ok\np \xFF bad\n", "p caf\xE9".b, "p café".encode("UTF-16LE")].each do |source|
      exception = assert_raises(SuperSlim::SyntaxError) { SuperSlim.compile(source) }
      assert_equal "Invalid UTF-8", exception.error
    end
    assert_equal [[2, "Syntax"]], SuperSlim::Linter.new.call("t.slim", "p ok\np \xFF\n").map { [_1.lineno, _1.rule] }
  end

  def test_an_error_on_a_line_of_nul_bytes_points_at_its_start
    assert_includes assert_raises(SuperSlim::SyntaxError) { SuperSlim.compile("\0") }.message, "Unknown line indicator"
  end

  def test_formatting_refuses_to_move_line_numbers
    assert_raises(SuperSlim::UnsafeFormattingError) { SuperSlim::Formatter.new.call("p\n\n\n\n= __LINE__\n") }
  end

  def test_offenses_without_a_line_sort_first
    linter = SuperSlim::Linter.new("UnescapedOutput" => {"enabled" => true})

    assert_equal [nil, 2], linter.call("t.slim", "/! \#{{x}}\n= raw y\n").map(&:lineno)
  end

  def test_a_data_hash_holding_itself_raises
    data = {}
    data[:self] = data

    assert_raises(SuperSlim::Error) { render("a data=data", data:) }
  end

  private

  def with_stack_overflow_in(method_name)
    original = Prism.method(method_name)
    Prism.define_singleton_method(method_name) { |*| raise SystemStackError }
    yield
  ensure
    Prism.define_singleton_method(method_name, original)
  end

  def assert_fast
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    assert_operator seconds, :<, 2, "took #{seconds.round(2)} seconds"
  end

  def render(source, **locals)
    scope = binding
    locals.each { |name, value| scope.local_variable_set(name, value) }
    scope.eval(SuperSlim.compile(source))
  end
end
