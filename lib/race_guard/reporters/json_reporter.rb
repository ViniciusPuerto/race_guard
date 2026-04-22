# frozen_string_literal: true

require 'json'

module RaceGuard
  module Reporters
    # One JSON object per line (newline-delimited JSON) to the given IO.
    class JsonReporter
      def initialize(io = $stderr)
        @io = io
        @io_mutex = Mutex.new
      end

      def report(event)
        line = JSON.generate(event.to_h)
        @io_mutex.synchronize { @io.puts(line) }
      end
    end
  end
end
