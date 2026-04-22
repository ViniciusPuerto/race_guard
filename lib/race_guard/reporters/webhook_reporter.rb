# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module RaceGuard
  module Reporters
    # POSTs one JSON event per call to a URL. Network errors are swallowed.
    # Pass +http_request:+ for tests: +->(request_uri, body) { ... }+.
    class WebhookReporter
      def initialize(url, open_timeout: 2, read_timeout: 2, http_request: nil)
        @url = url
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @http_request = http_request
      end

      def report(event)
        body = JSON.generate(event.to_h)
        uri = URI(@url)
        if @http_request
          @http_request.call(uri, body)
        else
          post_json(uri, body)
        end
      rescue StandardError
        nil
      end

      private

      def post_json(uri, body)
        req = Net::HTTP::Post.new(uri.request_uri)
        req['Content-Type'] = 'application/json; charset=utf-8'
        req.body = body
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout
        http.use_ssl = (uri.scheme == 'https')
        http.start { |h| h.request(req) }
      end
    end
  end
end
