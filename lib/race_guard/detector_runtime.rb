# frozen_string_literal: true

require_relative 'rule_engine'

module RaceGuard
  # Hooks invoked around {RaceGuard.protect} blocks. Register detectors on
  # {RaceGuard::Configuration} via {#add_protect_detector}; default list is empty.
  module DetectorRuntime
    module_function

    def enter(name)
      RaceGuard.configuration.protect_detectors.each do |detector|
        detector.on_protect_enter(name) if detector.respond_to?(:on_protect_enter)
      end
      RuleEngine.dispatch(:protect_enter, protect: name)
    end

    def exit(name)
      RaceGuard.configuration.protect_detectors.each do |detector|
        detector.on_protect_exit(name) if detector.respond_to?(:on_protect_exit)
      end
      RuleEngine.dispatch(:protect_exit, protect: name)
    end
  end
end
