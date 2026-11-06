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
