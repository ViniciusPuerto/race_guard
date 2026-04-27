# frozen_string_literal: true

module RaceGuard
  # Raised from +RaceGuard.report+ when the event severity is +:raise+ (after reporters run).
  class ReportRaisedError < StandardError
    attr_reader :event

    def initialize(event)
      @event = event
      super(self.class.format_message(event))
    end

    def self.format_message(event)
      parts = ["[#{event.detector}] #{event.message}"]
      parts << "(#{event.location})" if event.location && !event.location.empty?
      parts.join(' ')
    end
  end
end
