# frozen_string_literal: true

require_relative 'race_guard/version'
require_relative 'race_guard/constants'
require_relative 'race_guard/configuration'
require_relative 'race_guard/event'
require_relative 'race_guard/reporters/log_reporter'
require_relative 'race_guard/reporters/json_reporter'
require_relative 'race_guard/reporters/file_reporter'
require_relative 'race_guard/reporters/webhook_reporter'

module RaceGuard
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    alias config configuration

    def configure
      yield configuration
    end

    def reset_configuration!
      @configuration = nil
    end

    def report(payload)
      cfg = configuration
      return nil unless cfg.active?

      event = Event.from_payload(payload)
      cfg.reporters.each do |reporter|
        reporter.report(event)
      rescue StandardError
        # isolate reporter failure
      end
      nil
    end
  end
end
