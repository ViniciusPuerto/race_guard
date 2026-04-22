# frozen_string_literal: true

require 'json'

module RaceGuard
  module Reporters
    # Appends one JSON line per event to a file.
    class FileReporter
      def initialize(path, append: true)
        @path = path
        @append = append
        @mutex = Mutex.new
      end

      def report(event)
        line = JSON.generate(event.to_h)
        mode = @append ? 'a' : 'w'
        @mutex.synchronize do
          File.open(@path, mode) { |f| f.puts(line) }
        end
      end
    end
  end
end
