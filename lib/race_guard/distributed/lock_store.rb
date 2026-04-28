# frozen_string_literal: true

module RaceGuard
  module Distributed
    # Pluggable mutual-exclusion backend for {RaceGuard.distributed_once}.
    #
    # Implementations must be thread-safe for concurrent +claim+ calls on the same key.
    #
    # @!method claim(key:, token:, ttl:)
    #   @param key [String] full Redis key or logical lock key
    #   @param token [String] opaque owner token written on success
    #   @param ttl [Integer] seconds until the lock expires if not released
    #   @return [Boolean] true if this caller now owns the lock
    #
    # @!method renew(key:, token:, ttl:)
    #   @return [Boolean] true if TTL was extended for the same owner token
    #
    # @!method release(key:, token:)
    #   @return [Boolean] true if the key was deleted and matched +token+
    module LockStore
    end
  end
end
