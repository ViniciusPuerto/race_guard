# frozen_string_literal: true

require 'digest/sha2'

module RaceGuard
  module Distributed
    # Builds bounded, stable lock keys from a namespace + optional resource segment.
    #
    # Raw +resource+ values are never embedded verbatim (cardinality / key length);
    # they are hashed with SHA-256 (hex prefix).
    class KeyBuilder
      MAX_NAME_BYTES = 128
      RESOURCE_HASH_HEX_CHARS = 16

      class << self
        def build(name:, resource: nil, prefix: nil)
          pfx =
            if prefix.nil? || (prefix.respond_to?(:empty?) && prefix.empty?)
              'race_guard:distributed:'
            else
              prefix.to_s
            end
          seg = sanitize_name_segment(name)
          r = resource_segment(resource)
          r ? "#{pfx}v1:#{seg}:#{r}" : "#{pfx}v1:#{seg}"
        end

        def resource_digest(resource)
          return nil if resource.nil?

          s = resource.to_s
          return nil if s.empty?

          Digest::SHA256.hexdigest(s)[0, RESOURCE_HASH_HEX_CHARS]
        end

        private

        def sanitize_name_segment(name)
          raw = name.to_s.encode('UTF-8')
          raw = raw.gsub(/[^a-zA-Z0-9._-]/, '_')
          raw = raw[0, MAX_NAME_BYTES] if raw.bytesize > MAX_NAME_BYTES
          raise ArgumentError, 'lock name must be non-empty' if raw.empty?

          raw
        end

        def resource_segment(resource)
          resource_digest(resource)
        end
      end
    end
  end
end
