# frozen_string_literal: true

require_relative 'emitter'

module RaceGuard
  module Interceptors
    # Prepended onto +Net::HTTP+.
    module NetHttpRequest
      module RequestEmit
        module_function

        def call(http, req)
          host = http.instance_variable_get(:@address) if http.instance_variable_defined?(:@address)
          port = http.instance_variable_get(:@port) if http.instance_variable_defined?(:@port)
          method = req.respond_to?(:method) ? req.method : 'UNKNOWN'
          path = req.respond_to?(:path) ? req.path : req.class.name
          Emitter.emit(
            :net_http,
            "Net::HTTP #{method} #{host}:#{port}#{path}",
            'http_method' => method.to_s,
            'host' => host.to_s,
            'port' => port.to_s,
            'path' => path.to_s
          )
        end
      end

      def request(req, body = nil, &)
        RequestEmit.call(self, req)
        super
      end
    end
  end
end
