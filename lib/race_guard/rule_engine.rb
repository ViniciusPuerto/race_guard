# frozen_string_literal: true

require_relative 'rule'

module RaceGuard
  # Registry + dispatch for user-defined rules (see {RaceGuard.define_rule}).
  module RuleEngine
    REGISTRY = {} # rubocop:disable Style/MutableConstant -- process-wide mutable registry
    REGISTRY_MUTEX = Mutex.new

    def self.define_rule(name, &)
      raise ArgumentError, 'RaceGuard.define_rule requires a block' unless block_given?

      sym = name.to_sym
      builder = Rule::Builder.new(sym)
      yield builder
      rule = builder.build

      REGISTRY_MUTEX.synchronize do
        raise ArgumentError, "rule #{sym.inspect} is already defined" if REGISTRY.key?(sym)

        REGISTRY[sym] = rule
      end
      RaceGuard
    end

    def self.dispatch(event, metadata = {})
      sym = event.to_sym
      meta = normalize_metadata(metadata).merge(event: sym)
      rules_snapshot = REGISTRY_MUTEX.synchronize { REGISTRY.dup }

      cfg = RaceGuard.configuration
      rules_snapshot.each do |rule_name, rule|
        next unless cfg.enabled_rule?(rule_name)

        run_rule_hooks(rule, meta)
        next unless rule.run_on?(sym)

        evaluate_and_report(rule_name, rule, meta)
      end
      nil
    end

    def self.evaluate(name, metadata: {})
      sym = name.to_sym
      rule = REGISTRY_MUTEX.synchronize { REGISTRY[sym] }
      return nil unless rule
      return nil unless RaceGuard.configuration.enabled_rule?(sym)

      meta = normalize_metadata(metadata).merge(event: :evaluate)
      evaluate_and_report(sym, rule, meta)
    end

    def self.rule_defined?(name)
      sym = name.to_sym
      REGISTRY_MUTEX.synchronize { REGISTRY.key?(sym) }
    end

    # Test helper: clears the rule registry (does not disable rules in config).
    def self.reset_registry!
      REGISTRY_MUTEX.synchronize { REGISTRY.clear }
      nil
    end

    def self.normalize_metadata(metadata)
      h = metadata || {}
      return h.transform_keys(&:to_sym) if h.respond_to?(:transform_keys)

      h.each_with_object({}) do |(k, v), o|
        sym = k.respond_to?(:to_sym) ? k.to_sym : k.to_s.to_sym
        o[sym] = v
      end
    end

    def self.run_rule_hooks(rule, meta)
      rule.hooks_for(meta[:event]).each do |blk|
        blk.call(RaceGuard.context.current, meta)
      rescue StandardError
        nil
      end
    end

    def self.evaluate_and_report(rule_name, rule, meta)
      ctx = RaceGuard.context.current
      return unless rule.detect_proc.call(ctx, meta)

      msg = rule.message_proc.call(ctx, meta).to_s
      sev = rule.severity_override || RaceGuard.configuration.severity_for(rule_name)
      RaceGuard.report(detector: rule_name.to_s, message: msg, severity: sev)
    rescue StandardError
      nil
    end
  end
end
