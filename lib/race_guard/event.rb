# frozen_string_literal: true

require_relative 'constants'

module RaceGuard
  # Structured event payload for reporting and JSON serialization.
  class Event
    SCHEMA = {
      'context' => 'Hash (JSON-serializable values)',
      'detector' => 'String',
      'location' => 'String, optional',
      'message' => 'String',
      'severity' => 'String (one of info, warn, error, raise)',
      'thread_id' => 'String, optional',
      'timestamp' => 'String (ISO 8601)'
    }.freeze

    attr_reader :detector, :message, :severity, :location, :thread_id, :context, :timestamp

    def initialize(
      detector:,
      message:,
      severity:,
      location: nil,
      thread_id: nil,
      context: {},
      timestamp: Time.now
    )
      @detector = detector.to_s
      @message = message.to_s
      @severity = validate_severity(severity)
      @location = location&.to_s
      @thread_id = thread_id&.to_s
      @context = context.is_a?(Hash) ? context : {}
      @timestamp = timestamp
    end

    def self.from_payload(payload)
      case payload
      when Event
        payload
      when Hash
        kwargs = symbolize_keys_for_new(payload)
        new(**kwargs)
      else
        message = "report payload must be a RaceGuard::Event or a Hash (got #{payload.class})"
        raise ArgumentError, message
      end
    end

    def self.symbolize_keys_for_new(raw_hash)
      allowed = %i[detector message severity location thread_id context timestamp]
      out = {}
      raw_hash.each do |k, v|
        sym = k.respond_to?(:to_sym) ? k.to_sym : k.to_s.to_sym
        out[sym] = v if allowed.include?(sym)
      end
      missing = %i[detector message severity] - out.keys
      raise ArgumentError, "missing keys: #{missing.join(', ')}" unless missing.empty?

      out
    end
    private_class_method :symbolize_keys_for_new

    def to_h
      base = {
        'context' => stringify_hash_keys(context),
        'detector' => detector,
        'message' => message,
        'severity' => severity.to_s,
        'timestamp' => timestamp.utc.iso8601(3)
      }
      base.merge(optional_to_h)
    end

    private

    def optional_to_h
      out = {}
      out['location'] = location if location && !location.empty?
      out['thread_id'] = thread_id if thread_id && !thread_id.empty?
      out
    end

    def stringify_hash_keys(value)
      return value unless value.is_a?(Hash)

      value.to_h { |k, v| [k.to_s, v] }
    end

    def validate_severity(value)
      sym = value.to_sym
      return sym if ::RaceGuard::SEVERITY_LEVELS.include?(sym)

      list = ::RaceGuard::SEVERITY_LEVELS.join(', ')
      raise ArgumentError, "invalid severity: #{value.inspect} (expected one of: #{list})"
    end
  end
end
