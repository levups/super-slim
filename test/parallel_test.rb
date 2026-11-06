# frozen_string_literal: true

require "minitest/autorun"
require "super_slim"
require "super_slim/parallel"

class ParallelTest < Minitest::Test
  ITEMS = (1..400).to_a

  def test_results_come_back_in_item_order
    assert_equal ITEMS.map { _1 * 2 }, SuperSlim::Parallel.map(ITEMS) { _1 * 2 }
  end

  def test_an_exception_in_a_worker_is_raised_by_the_parent
    exception = assert_raises(IOError) { SuperSlim::Parallel.map(ITEMS) { |item| raise IOError, "closed" if item == 400 } }
    assert_equal "closed", exception.message
  end

  def test_what_marshal_cannot_dump_comes_back_named
    exception = assert_raises(TypeError) { SuperSlim::Parallel.map(ITEMS) { |item| (item == 400) ? -> {} : item } }
    assert_equal "no _dump_data is defined for class Proc", exception.message

    exception = assert_raises(RuntimeError) do
      SuperSlim::Parallel.map(ITEMS) { |item| raise ArgumentError.new("bad").tap { _1.instance_variable_set(:@callback, -> {}) } if item == 400 }
    end
    assert_equal "ArgumentError: bad", exception.message
  end

  def test_a_worker_that_dies_is_reported_and_every_worker_is_reaped
    exception = assert_raises(SuperSlim::Error) { SuperSlim::Parallel.map(ITEMS) { |item| Process.kill(:KILL, Process.pid) if item == 400 } }
    assert_match(/\AWorker \d+ died: .*SIGKILL/, exception.message)
    assert_raises(Errno::ECHILD) { Process.wait }
  end
end
