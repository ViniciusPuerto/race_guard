# frozen_string_literal: true

module RaceGuard
  module Interceptors
    # Emits a {RaceGuard.report} for built-in interceptors; never raises to callers.
    module Emitter
      module_function

      def emit(kind, message, extra_context = {})
        merged = build_merged_context(kind, extra_context)
        RaceGuard.report(
          detector: "commit_safety:#{kind}",
          message: message.to_s,
          severity: :info,
          context: merged
        )
      rescue StandardError
        nil
      end

      def build_merged_context(kind, extra_context)
        ctx = RaceGuard.context.current
        {
          'in_transaction' => ctx.in_transaction?,
          'interceptor_kind' => kind.to_s
        }.merge(stringify_keys(extra_context || {}))
      end
      private_class_method :build_merged_context

      def stringify_keys(hash)
        hash.to_h.transform_keys { |k| k.respond_to?(:to_s) ? k.to_s : k.inspect }
      end
    end
  end
end
