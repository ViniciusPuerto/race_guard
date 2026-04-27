# frozen_string_literal: true

module RaceGuard
  module SharedState
    # Adapts TracePoint payloads and dispatches to +ConflictTracker+ (Epic 6.2–6.3).
    module Watcher
      class << self
        def tracker
          @tracker ||= ConflictTracker.new
        end

        def reset!
          tracker.reset!
        end

        def handle_tracepoint(trace)
          ev = event_from_tracepoint(trace)
          return unless ev

          cfg = RaceGuard.configuration
          return unless cfg.active? && cfg.enabled?(TracePoint::FEATURE)

          tracker.process!(ev, mutex_protected: MutexStack.mutex_protected?)
        end

        # For tests and future instrumentation (+:read+ events).
        def handle_event(event, mutex_skip: nil)
          ev = coerce_event(event)
          return unless ev

          cfg = RaceGuard.configuration
          return unless cfg.active? && cfg.enabled?(TracePoint::FEATURE)

          guarded = if mutex_skip
                      MutexStack.mutex_protected?(skip_frames: mutex_skip)
                    else
                      MutexStack.mutex_protected?
                    end
          tracker.process!(ev, mutex_protected: guarded)
        end

        private

        def coerce_event(event)
          return event if event.is_a?(AccessEvent)
          return nil unless event.is_a?(Hash)

          access_from_hash(event)
        end

        def access_from_hash(hash)
          kind = hash[:kind] || hash['kind']
          key = hash[:key] || hash['key']
          return nil if kind.nil? || key.nil?

          kind = kind.to_sym if kind.respond_to?(:to_sym)
          AccessEvent.new(
            kind: kind,
            key: key,
            path: hash_val(hash, :path, 'path'),
            lineno: hash_val(hash, :lineno, 'lineno'),
            thread: hash_val(hash, :thread, 'thread') || Thread.current
          )
        end

        def hash_val(hash, sym, str)
          hash[sym] || hash[str]
        end

        def event_from_tracepoint(trace)
          case trace.event
          when :cvasgn
            cvar_write_event(trace)
          when :gvasgn
            gvar_write_event(trace)
          end
        end

        def cvar_write_event(trace)
          owner = trace.self
          owner = owner.class unless owner.is_a?(Module)
          name = owner.name || owner.inspect
          key = "cvar:#{name}:#{trace.path}:#{trace.lineno}"
          write_access(trace, key)
        end

        def gvar_write_event(trace)
          key = "gvar:#{trace.path}:#{trace.lineno}"
          write_access(trace, key)
        end

        def write_access(trace, key)
          AccessEvent.new(
            kind: :write,
            key: key,
            path: trace.path,
            lineno: trace.lineno,
            thread: Thread.current
          )
        end
      end
    end
  end
end
