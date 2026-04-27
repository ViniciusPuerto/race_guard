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

        fix = suggested_fix_from_event_hash(h)
        @logger.info("race_guard suggested_fix: #{fix}") if fix
      end

      private

      def suggested_fix_from_event_hash(event_hash)
        ctx = event_hash['context']
        return nil unless ctx.is_a?(Hash)

        raw = ctx['suggested_fix']
        s = raw.nil? ? '' : raw.to_s.strip
        s.empty? ? nil : s
      end
    end
  end
end
