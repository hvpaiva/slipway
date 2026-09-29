# frozen_string_literal: true

require 'test_helper'

# Items block on queues the test releases, so every ordering below is forced rather than hoped for.
class PoolTest < Minitest::Test
  def test_map_returns_the_results_in_input_order_whatever_order_the_items_finish_in
    gates = Array.new(4) { Queue.new }
    finished = Queue.new
    mapping = Thread.new { Slipway::Pool.new(workers: 4).map([0, 1, 2, 3], &gated(gates, finished)) }

    finishing = [3, 2, 1, 0].map { release(gates[it], finished) }

    assert_equal [3, 2, 1, 0], finishing
    assert_equal [0, 10, 20, 30], mapping.value
  end

  def test_each_ordered_yields_each_result_as_soon_as_every_earlier_item_is_done
    gates = Array.new(3) { Queue.new }
    finished = Queue.new
    yielded = Queue.new
    work = gated(gates, finished)
    streaming = Thread.new { Slipway::Pool.new(workers: 3).each_ordered([0, 1, 2], work) { yielded << it } }
    release(gates[1], finished)

    assert_empty yielded, 'the second result came before the first'

    release(gates[0], finished)
    early = [yielded.pop, yielded.pop]
    release(gates[2], finished)
    streaming.join

    assert_equal [0, 10], early
    assert_equal 20, yielded.pop
  end

  def test_each_ordered_yields_on_the_thread_that_called_it
    calling = []

    Slipway::Pool.new(workers: 2).each_ordered([1, 2, 3], ->(item) { item }) { calling << Thread.current }

    assert_equal [Thread.current] * 3, calling
  end

  def test_the_items_share_no_more_threads_than_there_are_workers
    started = Queue.new
    gate = Queue.new
    work = lambda do |item|
      started << Thread.current
      gate.pop
      item
    end
    mapping = Thread.new { Slipway::Pool.new(workers: 2).map((1..6).to_a, &work) }
    threads = Array.new(2) { started.pop }
    6.times { gate << :go }
    threads.concat(Array.new(4) { started.pop })

    assert_equal (1..6).to_a, mapping.value
    assert_equal 2, threads.uniq.size
  end

  def test_an_exception_from_an_item_reaches_the_caller_after_the_other_workers_are_stopped
    ended = Queue.new

    error = assert_raises(ArgumentError) { Slipway::Pool.new(workers: 2).map([0, 1], &failing_beside_a_hold(ended)) }

    assert_equal 'item 1 is broken', error.message
    assert_includes error.backtrace.first, __FILE__
    assert_equal [0, 1], Array.new(ended.size) { ended.pop }.sort
  end

  def test_an_exception_that_is_not_a_standard_error_reaches_the_caller_too
    work = ->(item) { item == 2 ? raise(NotImplementedError, 'no such thing') : item }

    error = assert_raises(NotImplementedError) { Slipway::Pool.new(workers: 2).map([1, 2, 3], &work) }

    assert_equal 'no such thing', error.message
  end

  def test_an_interrupt_kills_the_workers_and_runs_their_ensure_blocks_before_it_leaves
    started = Queue.new
    ended = Queue.new
    mapping = Thread.new { Slipway::Pool.new(workers: 2).map([1, 2, 3], &holding(started, ended)) }
    mapping.report_on_exception = false
    workers = Array.new(2) { started.pop }
    Thread.pass until mapping.stop?

    mapping.raise(Interrupt)

    assert_raises(Interrupt) { mapping.join }
    assert_empty workers.select(&:alive?)
    assert_equal [1, 2], Array.new(ended.size) { ended.pop }.sort
  end

  def test_an_interrupt_as_a_worker_starts_still_stops_every_worker
    workers = []
    pool = Slipway::Pool.new(workers: 2)

    assert_raises(Interrupt) do
      interrupting_after(:new, workers).enable { pool.map([1, 2], &holding(Queue.new, Queue.new)) }
    end
    assert_equal 2, workers.size
    assert_empty workers.select(&:alive?)
  end

  def test_a_second_interrupt_while_the_workers_are_killed_still_kills_every_worker
    started = Queue.new
    killed = []
    pool = Slipway::Pool.new(workers: 2)
    mapping = Thread.new do
      interrupting_after(:kill, killed).enable { pool.map([1, 2], &holding(started, Queue.new)) }
    end
    mapping.report_on_exception = false
    2.times { started.pop }
    Thread.pass until mapping.stop?

    mapping.raise(Interrupt)

    assert_raises(Interrupt) { mapping.join }
    assert_equal 2, killed.size
  end

  # Timeout.timeout works this way: another thread raises into the one running the block.
  def test_an_exception_raised_into_an_item_by_another_thread_reaches_the_caller
    work = lambda do |_|
      item = Thread.current
      Thread.new { item.raise(ArgumentError, 'raised into the item') }.join
    end

    error = assert_raises(ArgumentError) { Slipway::Pool.new(workers: 1).map([1], &work) }

    assert_equal 'raised into the item', error.message
  end

  def test_nothing_to_do_runs_nothing
    pool = Slipway::Pool.new(workers: 2)
    yielded = []

    pool.each_ordered([], ->(_) { flunk 'ran without an item' }) { yielded << it }

    assert_empty yielded
    assert_empty pool.map([]) { flunk 'ran without an item' }
  end

  def test_workers_must_be_a_positive_integer
    error = assert_raises(ArgumentError) { Slipway::Pool.new(workers: 0) }

    assert_equal 'workers must be a positive Integer, not 0', error.message
    [-1, 1.5, nil, '2'].each { |workers| assert_raises(ArgumentError) { Slipway::Pool.new(workers:) } }
    assert_equal 3, Slipway::Pool.new(workers: 3).workers
  end

  private

  def gated(gates, finished)
    lambda do |item|
      gates[item].pop
      finished << item
      item * 10
    end
  end

  def release(gate, finished)
    gate << :go
    finished.pop
  end

  def holding(started, ended)
    lambda do |item|
      started << Thread.current
      Queue.new.pop
    ensure
      ended << item
    end
  end

  # A Ctrl-C is raised at the next interrupt check of the thread it lands on, and the return from
  # a C method such as Thread.new or Thread#kill is one, so this puts one exactly there.
  def interrupting_after(method, threads)
    TracePoint.new(:c_return) do |call|
      next unless call.method_id == method && call.return_value.is_a?(Thread)

      threads << call.return_value
      Thread.current.raise(Interrupt) if threads.one?
    end
  end

  # Item 1 raises only once item 0 is running, so the pool has a busy worker to stop.
  def failing_beside_a_hold(ended)
    holding = Queue.new
    lambda do |item|
      if item.zero?
        holding << item
        Queue.new.pop
      else
        holding.pop
        raise ArgumentError, "item #{item} is broken"
      end
    ensure
      ended << item
    end
  end
end
