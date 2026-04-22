# frozen_string_literal: true

require 'logger'

module RaceGuard
  module Reporters
    # Writes a single human-readable line per event to a stdlib Logger.
    class LogReporter
      def initialize(logger = nil)
        @logger = logger || Logger.new($stderr)
      end

      def report(event)
        h = event.to_h
        parts = [h['severity']&.upcase, h['detector'], h['message']]
        parts << "at #{h['location']}" if h['location']
        line = parts.join(' | ')
        @logger.info(line)
      end
    end
  end
end
