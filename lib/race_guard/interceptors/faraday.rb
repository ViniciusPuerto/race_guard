# frozen_string_literal: true

require_relative 'emitter'

module RaceGuard
  module Interceptors
    # Prepended onto +Faraday::Connection+.
    module FaradayRunRequest
      def run_request(method, url, body = nil, headers = nil, &)
        Emitter.emit(
          :faraday,
          "Faraday #{method} #{url}",
          'http_method' => method.to_s,
          'url' => url.to_s
        )
        super
      end
    end
  end
end
