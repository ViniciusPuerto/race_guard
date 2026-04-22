# frozen_string_literal: true

require_relative 'race_guard/version'
require_relative 'race_guard/configuration'

module RaceGuard
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end
  end
end
