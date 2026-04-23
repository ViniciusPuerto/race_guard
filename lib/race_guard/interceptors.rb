# frozen_string_literal: true

require 'set'

require_relative '../race_guard'
require_relative 'interceptors/emitter'
require_relative 'interceptors/active_job'
require_relative 'interceptors/action_mailer'
require_relative 'interceptors/net_http'
require_relative 'interceptors/faraday'

module RaceGuard
  # Optional Epic 3 hooks: emit +RaceGuard.report+ events when common async /
  # side-effect APIs run (see Task 3.2). Install is explicit and idempotent.
  module Interceptors
    INSTALL_MUTEX = Mutex.new
    @installed = Set.new

    class << self
      def install_all!
        install_active_job!
        install_action_mailer!
        install_net_http!
        install_faraday!
        self
      end

      def install_active_job!
        INSTALL_MUTEX.synchronize do
          return self if @installed.include?(:active_job)

          if defined?(::ActiveJob::Base)
            sc = ::ActiveJob::Base.singleton_class
            sc.prepend(ActiveJobPerformLater) unless sc.ancestors.include?(ActiveJobPerformLater)
            @installed.add(:active_job)
          end
        end
        self
      end

      def install_action_mailer!
        INSTALL_MUTEX.synchronize do
          return self if @installed.include?(:action_mailer)

          if defined?(::ActionMailer::MessageDelivery)
            mod = ActionMailerDeliverLater
            delivery = ::ActionMailer::MessageDelivery
            delivery.prepend(mod) unless delivery.ancestors.include?(mod)
            @installed.add(:action_mailer)
          end
        end
        self
      end

      def install_net_http!
        require 'net/http' unless defined?(::Net::HTTP)
        INSTALL_MUTEX.synchronize do
          return self if @installed.include?(:net_http)

          if defined?(::Net::HTTP)
            mod = NetHttpRequest
            ::Net::HTTP.prepend(mod) unless ::Net::HTTP.ancestors.include?(mod)
            @installed.add(:net_http)
          end
        end
        self
      end

      def install_faraday!
        INSTALL_MUTEX.synchronize do
          return self if @installed.include?(:faraday)

          if defined?(::Faraday::Connection)
            mod = FaradayRunRequest
            ::Faraday::Connection.prepend(mod) unless ::Faraday::Connection.ancestors.include?(mod)
            @installed.add(:faraday)
          end
        end
        self
      end

      def reset_install_registry_for_tests!
        INSTALL_MUTEX.synchronize { @installed.clear }
        nil
      end
    end
  end
end
