# frozen_string_literal: true

require_relative 'emitter'

module RaceGuard
  module Interceptors
    # Prepended onto +ActiveJob::Base.singleton_class+.
    module ActiveJobPerformLater
      def perform_later(*args, **kwargs, &)
        job_name = name
        Emitter.emit(
          :active_job,
          "ActiveJob perform_later (#{job_name})",
          'job_class' => job_name,
          'args_preview' => args.inspect.byteslice(0, 240).to_s
        )
        super
      end
    end
  end
end
