# frozen_string_literal: true

require "etc"

module SlimX
  # Maps items in forked processes, one per core, and returns the results in item order. Below
  # minimum_per_process items per process, forking costs more than it saves, and the map stays in this process.
  module Parallel
    module_function

    def map(items, minimum_per_process: 100, &block)
      process_count = [Etc.nprocessors, items.size / minimum_per_process].min
      return items.map(&block) if process_count < 2 || !Process.respond_to?(:fork)

      readers = items.each_slice((items.size.to_f / process_count).ceil).map do |slice|
        reader, writer = IO.pipe
        fork do
          reader.close
          results = begin
            slice.map(&block)
          rescue Exception => exception # rubocop:disable Lint/RescueException -- re-raised by the parent
            exception
          end
          writer.binmode.write(Marshal.dump(results))
          exit!(0)
        end
        writer.close
        reader
      end
      results_by_process = readers.map { Marshal.load(it.binmode.read) }
      Process.waitall
      results_by_process.each { raise it if it.is_a?(Exception) }
      results_by_process.flatten(1)
    end
  end
end
