# frozen_string_literal: true

require "etc"

module SuperSlim
  # Maps items in forked processes, one per core, and returns the results in item order. Below
  # minimum_per_process items per process, forking costs more than it saves, and the map stays in this process.
  module Parallel
    module_function

    def map(items, minimum_per_process: 100, &block)
      process_count = [Etc.nprocessors, items.size / minimum_per_process].min
      return items.map(&block) if process_count < 2 || !Process.respond_to?(:fork)

      workers = items.each_slice((items.size.to_f / process_count).ceil).map do |slice|
        reader, writer = IO.pipe
        pid = fork do
          reader.close
          writer.binmode.write(dump { slice.map(&block) })
          exit!(0)
        end
        writer.close
        [pid, reader]
      end
      results_by_process = workers.map { |pid, reader| receive(pid, reader) }
      results_by_process.each { |results| raise results if results.is_a?(Exception) }
      results_by_process.flatten(1)
    ensure
      workers&.each do |pid, reader|
        reader.close unless reader.closed?
        Process.wait(pid)
      rescue Errno::ECHILD # already reaped by receive
      end
    end

    # A result or an exception Marshal cannot dump (a Proc, an IO) is sent as a RuntimeError naming it.
    def dump
      Marshal.dump(yield)
    rescue Exception => exception # rubocop:disable Lint/RescueException -- re-raised by the parent
      begin
        Marshal.dump(exception)
      rescue TypeError
        Marshal.dump(RuntimeError.new("#{exception.class}: #{exception.message}"))
      end
    end

    def receive(pid, reader)
      payload = reader.binmode.read
      reader.close
      Process.wait(pid)
      raise Error, "Worker #{pid} died: #{$?}" unless $?.success? && !payload.empty?

      Marshal.load(payload) # rubocop:disable Security/MarshalLoad -- written by our own child
    end
  end
end
