# frozen_string_literal: true

# LockStore protocol uses +claim+ / +renew+ / +release+ (not predicate names) for adapter symmetry.
# rubocop:disable Naming/PredicateMethod
module RaceGuard
  module Distributed
    # Redis-backed {LockStore} using +SET key token NX EX ttl+ and Lua scripts for
    # compare-and-extend and compare-and-delete.
    #
    # +redis+ must support +set(..., nx: true, ex: seconds)+ and +eval(script, keys:, argv:)+
    # (the +redis+ gem satisfies this).
    class RedisLockStore
      include LockStore

      RENEW_SCRIPT = <<~LUA
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("expire", KEYS[1], tonumber(ARGV[2]))
        else
          return 0
        end
      LUA

      RELEASE_SCRIPT = <<~LUA
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("del", KEYS[1])
        else
          return 0
        end
      LUA

      def initialize(redis)
        @redis = redis
      end

      def claim(key:, token:, ttl:)
        raise ArgumentError, 'ttl must be positive' unless ttl.is_a?(Integer) && ttl.positive?

        !!@redis.set(key.to_s, token.to_s, nx: true, ex: ttl)
      end

      def renew(key:, token:, ttl:)
        raise ArgumentError, 'ttl must be positive' unless ttl.is_a?(Integer) && ttl.positive?

        n = @redis.eval(RENEW_SCRIPT, keys: [key.to_s], argv: [token.to_s, ttl.to_s])
        n.to_i == 1
      end

      def release(key:, token:)
        n = @redis.eval(RELEASE_SCRIPT, keys: [key.to_s], argv: [token.to_s])
        n.to_i == 1
      end
    end
  end
end
# rubocop:enable Naming/PredicateMethod
