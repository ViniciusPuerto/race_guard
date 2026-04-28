# frozen_string_literal: true

require 'monitor'

module RaceGuard
  module Distributed
    # In-process {LockStore} for tests and single-process simulations.
    # Uses monotonic clock for TTL expiry (no wall-clock sleep required for correctness).
    class MemoryLockStore
      include LockStore

      def initialize
        @mon = Monitor.new
        @entries = {} # key => { token:, expires_at: Float monotonic }
        @time_skew = 0.0
      end

      def claim(key:, token:, ttl:)
        raise ArgumentError, 'ttl must be positive' unless ttl.is_a?(Integer) && ttl.positive?

        now = monotonic
        @mon.synchronize do
          prune_expired_unlocked!(now)
          rec = @entries[key]
          if rec && rec[:expires_at] > now
            false
          else
            @entries[key] = { token: token.to_s, expires_at: now + ttl }
            true
          end
        end
      end

      def renew(key:, token:, ttl:)
        raise ArgumentError, 'ttl must be positive' unless ttl.is_a?(Integer) && ttl.positive?

        now = monotonic
        @mon.synchronize do
          prune_expired_unlocked!(now)
          rec = @entries[key]
          return false unless rec && rec[:expires_at] > now && rec[:token] == token.to_s

          rec[:expires_at] = now + ttl
          true
        end
      end

      def release(key:, token:)
        now = monotonic
        @mon.synchronize do
          prune_expired_unlocked!(now)
          rec = @entries[key]
          return false unless rec && rec[:expires_at] > now && rec[:token] == token.to_s

          @entries.delete(key)
          true
        end
      end

      # Test helper: advance logical time so TTLs expire without sleeping.
      def advance_time!(seconds)
        @mon.synchronize { @time_skew += seconds.to_f }
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC) + @time_skew
      end

      def prune_expired_unlocked!(now)
        @entries.delete_if { |_k, v| v[:expires_at] <= now }
      end
    end
  end
end
