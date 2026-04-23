# frozen_string_literal: true

require 'set'

module RaceGuard
  # Immutable rule definition built by {RaceGuard.define_rule}.
  class Rule
    KNOWN_EVENTS = %i[protect_enter protect_exit].freeze
    EMPTY_HOOKS = [].freeze

    attr_reader :name, :detect_proc, :message_proc, :hooks, :run_on, :severity_override

    # rubocop:disable Metrics/ParameterLists -- explicit fields keep Rule immutable and clear
    def initialize(name:, detect_proc:, message_proc:, hooks:, run_on:, severity_override:)
      @name = name.to_sym
      @detect_proc = detect_proc
      @message_proc = message_proc
      @hooks = hooks.freeze
      @run_on = run_on.freeze
      @severity_override = severity_override
      freeze
    end
    # rubocop:enable Metrics/ParameterLists

    def hooks_for(event)
      hooks[event.to_sym] || EMPTY_HOOKS
    end

    def run_on?(event)
      run_on.include?(event.to_sym)
    end

    # DSL used inside +define_rule+ blocks.
    class Builder
      def initialize(name)
        @name = name.to_sym
        @detect = nil
        @message = nil
        @hooks = {}
        @run_on = Set.new
        @severity = nil
      end

      def detect(&block)
        @detect = block
      end

      def message(&block)
        @message = block
      end

      def hook(event, &block)
        sym = self.class.validate_event!(event)
        (@hooks[sym] ||= []) << block
      end

      def run_on(*events)
        events.flatten.compact.each { |e| @run_on.add(self.class.validate_event!(e)) }
      end

      def severity(level)
        @severity = level&.to_sym
      end

      def build
        raise ArgumentError, "rule #{@name.inspect} requires detect { ... }" unless @detect
        raise ArgumentError, "rule #{@name.inspect} requires message { ... }" unless @message

        hooks_frozen = @hooks.transform_values { |list| list.dup.freeze }.freeze
        Rule.new(
          name: @name,
          detect_proc: @detect,
          message_proc: @message,
          hooks: hooks_frozen.freeze,
          run_on: @run_on.dup.freeze,
          severity_override: @severity
        )
      end

      def self.validate_event!(event)
        sym = event.to_sym
        return sym if Rule::KNOWN_EVENTS.include?(sym)

        list = Rule::KNOWN_EVENTS.join(', ')
        raise ArgumentError, "unknown rule event #{event.inspect} (expected one of: #{list})"
      end
    end
  end
end
