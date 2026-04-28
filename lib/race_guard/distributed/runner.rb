# frozen_string_literal: true

require 'digest/sha2'
require 'securerandom'

module RaceGuard
  module Distributed
    # Raised when +on_skip: :raise+ and the lock was not acquired.
    class LockNotAcquiredError < StandardError; end

    # Returned when skip behavior is +:sentinel+.
    SKIPPED = Object.new.freeze

    # Yields to a long-running block so it can extend TTL while still holding the owner token.
    class LockControl
      def initialize(opts)
        @store = opts.fetch(:store)
        @lock_key = opts.fetch(:lock_key)
        @token = opts.fetch(:token)
        @ttl = opts.fetch(:ttl)
        @lock_name = opts.fetch(:lock_name)
        @resource_digest = opts.fetch(:resource_digest)
        @caller_line = opts.fetch(:caller_line)
        @store_class = opts.fetch(:store_class)
      end

      # @param extra_ttl [Integer, nil] seconds; defaults to the lock's original +ttl+
      # rubocop:disable Metrics/MethodLength -- emit + store call
      def renew(extra_ttl = nil)
        t = (extra_ttl || @ttl).to_i
        return false unless t.positive?

        ok = @store.renew(key: @lock_key, token: @token, ttl: t)
        if ok
          Runner.emit_lifecycle(
            event: 'renewed',
            lock_name: @lock_name,
            lock_key: @lock_key,
            resource_digest: @resource_digest,
            token: @token,
            ttl: t,
            caller_line: @caller_line,
            store_class: @store_class
          )
        end
        ok
      end
      # rubocop:enable Metrics/MethodLength
    end

    # Orchestrates claim / yield / release and reporting.
    # rubocop:disable Metrics/ModuleLength, Metrics/ClassLength -- Epic 10 runner
    # rubocop:disable Layout/LineLength, Metrics/ParameterLists, Metrics/MethodLength -- Epic 10 runner
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- Epic 10 runner
    module Runner
      HELD_STACK_KEY = :__race_guard_distributed_held_stack__

      class << self
        def run(name:, ttl:, resource:, on_skip:, &block)
          raise ArgumentError, 'RaceGuard.distributed_once requires a block' unless block

          cfg = RaceGuard.configuration
          lock_name = name.to_s
          caller_line = safe_caller

          return yield_simple(block, nil) if !cfg.enabled?(:distributed_guard) || !cfg.active?

          unless ttl.is_a?(Integer) && ttl.positive?
            raise ArgumentError, 'ttl must be a positive Integer (seconds)'
          end

          prefix = cfg.distributed_key_prefix
          lock_key = KeyBuilder.build(name: lock_name, resource: resource, prefix: prefix)
          resource_digest = KeyBuilder.resource_digest(resource)

          stack = Thread.current[HELD_STACK_KEY] ||= []
          if cfg.distributed_reentrancy == :skip && stack.include?(lock_key)
            emit_skipped_reentrant(
              lock_name, lock_key, resource_digest, ttl, caller_line, on_skip, cfg
            )
            return handle_skip(block, on_skip, cfg.distributed_skip_behavior)
          end

          store = effective_store(cfg)
          if store.nil?
            return run_misconfigured_store(cfg, block, on_skip, lock_name, lock_key, resource_digest, ttl,
                                           caller_line)
          end

          store_class = store.class.name
          token = SecureRandom.hex(16)
          res, payload = try_claim(store, lock_key, token, ttl.to_i)
          if res == :err
            return run_store_error(
              cfg, block, on_skip, lock_name, lock_key, resource_digest, ttl, caller_line, store_class, payload
            )
          end

          claimed = payload
          unless claimed
            emit_skipped_lost_race(
              lock_name, lock_key, resource_digest, token, ttl, caller_line, store_class, on_skip, cfg
            )
            return handle_skip(block, on_skip, cfg.distributed_skip_behavior)
          end

          emit_claimed(lock_name, lock_key, resource_digest, token, ttl, caller_line, store_class)
          stack << lock_key
          control = LockControl.new(
            {
              store: store,
              lock_key: lock_key,
              token: token,
              ttl: ttl.to_i,
              lock_name: lock_name,
              resource_digest: resource_digest,
              caller_line: caller_line,
              store_class: store_class
            }
          )
          begin
            yield_simple(block, control)
          ensure
            stack.pop if stack.last == lock_key
            finalize_release(
              store, lock_key, token, lock_name, resource_digest, ttl, caller_line, store_class
            )
          end
        end

        def try_claim(store, lock_key, token, ttl)
          [:ok, store.claim(key: lock_key, token: token, ttl: ttl)]
        rescue StandardError => e
          [:err, e]
        end

        def emit_skipped_reentrant(lock_name, lock_key, resource_digest, ttl, caller_line, on_skip, cfg)
          skip_behavior = effective_skip_behavior(on_skip, cfg)
          emit_lifecycle(
            event: 'skipped',
            lock_name: lock_name,
            lock_key: lock_key,
            resource_digest: resource_digest,
            token: nil,
            ttl: ttl,
            caller_line: caller_line,
            store_class: nil,
            extra: { 'skip_reason' => 'reentrant', 'skip_behavior' => skip_behavior.to_s }
          )
        end

        def emit_skipped_lost_race(lock_name, lock_key, resource_digest, token, ttl, caller_line, store_class,
                                   on_skip, cfg)
          skip_behavior = effective_skip_behavior(on_skip, cfg)
          emit_lifecycle(
            event: 'skipped',
            lock_name: lock_name,
            lock_key: lock_key,
            resource_digest: resource_digest,
            token: token,
            ttl: ttl,
            caller_line: caller_line,
            store_class: store_class,
            extra: { 'skip_reason' => 'lost_race', 'skip_behavior' => skip_behavior.to_s }
          )
        end

        def emit_claimed(lock_name, lock_key, resource_digest, token, ttl, caller_line, store_class)
          emit_lifecycle(
            event: 'claimed',
            lock_name: lock_name,
            lock_key: lock_key,
            resource_digest: resource_digest,
            token: token,
            ttl: ttl,
            caller_line: caller_line,
            store_class: store_class
          )
        end

        def finalize_release(store, lock_key, token, lock_name, resource_digest, ttl, caller_line, store_class)
          release_error = nil
          released =
            begin
              store.release(key: lock_key, token: token)
            rescue StandardError => e
              release_error = e
              false
            end
          if release_error
            emit_error(
              event: 'release_failed',
              lock_name: lock_name,
              lock_key: lock_key,
              resource_digest: resource_digest,
              token: token,
              ttl: ttl,
              caller_line: caller_line,
              store_class: store_class,
              error: release_error
            )
          elsif released
            emit_lifecycle(
              event: 'released',
              lock_name: lock_name,
              lock_key: lock_key,
              resource_digest: resource_digest,
              token: token,
              ttl: ttl,
              caller_line: caller_line,
              store_class: store_class
            )
          else
            emit_lifecycle(
              event: 'release_failed',
              lock_name: lock_name,
              lock_key: lock_key,
              resource_digest: resource_digest,
              token: token,
              ttl: ttl,
              caller_line: caller_line,
              store_class: store_class,
              extra: { 'note' => 'compare-and-delete did not remove key (expired or stolen)' },
              severity: :warn
            )
          end
        end

        def emit_lifecycle(event:, lock_name:, lock_key:, resource_digest:, token:, ttl:, caller_line:,
                           store_class: nil, extra: {}, severity: :info)
          return unless RaceGuard.configuration.active?

          ctx = base_context(
            event: event,
            lock_name: lock_name,
            lock_key: lock_key,
            resource_digest: resource_digest,
            token: token,
            ttl: ttl,
            caller_line: caller_line,
            store_class: store_class
          )
          ctx.merge!(stringify_keys(extra))
          RaceGuard.report(
            detector: 'distributed_guard',
            message: "distributed_guard:#{event}",
            severity: severity,
            context: ctx
          )
        end

        def emit_error(event:, lock_name:, lock_key:, resource_digest:, token:, ttl:, caller_line:, store_class:,
                       error:, extra: {})
          return unless RaceGuard.configuration.active?

          ctx = base_context(
            event: event,
            lock_name: lock_name,
            lock_key: lock_key,
            resource_digest: resource_digest,
            token: token,
            ttl: ttl,
            caller_line: caller_line,
            store_class: store_class
          )
          ctx.merge!(stringify_keys(extra))
          ctx['error_class'] = error.class.name if error
          ctx['error_message'] = error.message.to_s[0, 500] if error
          sev = RaceGuard.configuration.severity_for(:distributed_guard)
          RaceGuard.report(
            detector: 'distributed_guard',
            message: "distributed_guard:#{event}",
            severity: sev,
            context: ctx
          )
        end

        def token_hash(token)
          return nil unless token

          Digest::SHA256.hexdigest(token.to_s)[0, 32]
        end

        def base_context(event:, lock_name:, lock_key:, resource_digest:, token:, ttl:, caller_line:, store_class:)
          {
            'event' => event,
            'lock_name' => lock_name,
            'lock_key' => lock_key,
            'resource_hash' => resource_digest,
            'owner_token_hash' => token_hash(token),
            'ttl' => ttl,
            'caller' => caller_line,
            'store_class' => store_class
          }.compact
        end

        def effective_store(cfg)
          cfg.distributed_lock_store ||
            (cfg.distributed_redis_client && RedisLockStore.new(cfg.distributed_redis_client))
        end

        def yield_simple(block, control)
          if block.arity.zero?
            block.call
          else
            block.call(control)
          end
        end

        def effective_skip_behavior(on_skip, cfg)
          (on_skip.nil? ? cfg.distributed_skip_behavior : on_skip).to_sym
        end

        def handle_skip(_block, on_skip, default_behavior)
          behavior = (on_skip.nil? ? default_behavior : on_skip).to_sym
          case behavior
          when :nil
            nil
          when :sentinel
            SKIPPED
          when :raise
            raise LockNotAcquiredError, 'distributed lock not acquired'
          else
            raise ArgumentError,
                  "invalid on_skip / distributed_skip_behavior: #{behavior.inspect} " \
                  '(expected :nil, :sentinel, or :raise)'
          end
        end

        def run_misconfigured_store(cfg, block, on_skip, lock_name, lock_key, resource_digest, ttl, caller_line)
          return yield_simple(block, nil) if cfg.distributed_degrade_silently

          emit_error(
            event: 'configuration_error',
            lock_name: lock_name,
            lock_key: lock_key,
            resource_digest: resource_digest,
            token: nil,
            ttl: ttl,
            caller_line: caller_line,
            store_class: nil,
            error: nil,
            extra: {
              'reason' => 'missing_lock_store',
              'hint' => 'set distributed_lock_store or distributed_redis_client'
            }
          )
          handle_skip(block, on_skip, cfg.distributed_skip_behavior)
        end

        def run_store_error(cfg, block, on_skip, lock_name, lock_key, resource_digest, ttl, caller_line,
                            store_class, error)
          return yield_simple(block, nil) if cfg.distributed_degrade_silently

          emit_error(
            event: 'redis_error',
            lock_name: lock_name,
            lock_key: lock_key,
            resource_digest: resource_digest,
            token: nil,
            ttl: ttl,
            caller_line: caller_line,
            store_class: store_class,
            error: error
          )
          handle_skip(block, on_skip, cfg.distributed_skip_behavior)
        end

        def safe_caller
          loc = caller_locations(2, 1)&.first
          loc ? "#{loc.path}:#{loc.lineno}:in `#{loc.label}'" : ''
        end

        def stringify_keys(hash)
          hash.to_h { |k, v| [k.to_s, v] }
        end
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    # rubocop:enable Layout/LineLength, Metrics/ParameterLists, Metrics/MethodLength
    # rubocop:enable Metrics/ModuleLength, Metrics/ClassLength
  end
end
