# frozen_string_literal: true

module Slipway
  # Runs one block per item on at most +workers+ threads; results come back in input order,
  # whatever order the items finish in.
  #
  # However a call ends early (an exception from an item, an interrupt, a consumer that raises),
  # the workers are killed and waited for before the exception leaves it: killing a thread runs
  # its ensure blocks, which is how Git::Runner sends TERM to a git still running. An exception
  # from an item is re-raised on the calling thread as soon as it is seen, without waiting for
  # the other items, because callers turn the failures they expect into results and anything
  # else is a bug or a fatal condition.
  class Pool
    attr_reader :workers

    def initialize(workers:)
      raise ArgumentError, "workers must be a positive Integer, not #{workers.inspect}" unless positive?(workers)

      @workers = workers
    end

    def map(items, &work)
      results = []
      each_ordered(items, work) { results << it }
      results
    end

    # Yields each result on the calling thread as soon as every earlier item is done, so a
    # caller that prints one line per item streams them in input order.
    def each_ordered(items, work, &)
      threads = []
      begin
        jobs = Queue.new
        items.each_with_index { |item, index| jobs << [index, item] }
        jobs.close
        done = Queue.new
        # An interrupt between Thread.new and the append would leave a worker that stop never sees.
        Thread.handle_interrupt(Exception => :never) do
          [@workers, items.size].min.times { threads << worker(jobs, done, work) }
        end
        deliver(items.size, done, &)
      ensure
        stop(threads)
      end
    end

    private

    def positive?(workers) = workers.is_a?(Integer) && workers.positive?

    # A worker pushes itself when it ends, so the caller joins one that died of an exception,
    # which re-raises it once, instead of waiting for a result that never comes.
    def worker(jobs, done, work)
      Thread.new do
        Thread.current.report_on_exception = false
        # A thread inherits its creator's interrupt mask; without lifting it, an exception sent
        # with Thread#raise would wait until the worker ends.
        Thread.handle_interrupt(Exception => :immediate) do
          while (job = jobs.pop)
            index, item = job
            done << [index, work.call(item)]
          end
        end
      ensure
        done << Thread.current
      end
    end

    def deliver(count, done)
      pending = {}
      delivered = 0
      while delivered < count
        message = done.pop
        if message.is_a?(Thread)
          message.join
        else
          pending.store(*message)
        end
        while pending.key?(delivered)
          yield pending.delete(delivered)
          delivered += 1
        end
      end
    end

    # A worker that died of an exception has nothing left to wait for, and joining it would
    # raise that exception again over the one already leaving the call. An interrupt between
    # two kills would leave the rest running, so the kills are masked.
    def stop(threads)
      Thread.handle_interrupt(Exception => :never) { threads.each(&:kill) }
      threads.each { it.join unless it.status.nil? }
    end
  end
end
