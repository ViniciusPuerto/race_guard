# frozen_string_literal: true

require_relative 'emitter'

module RaceGuard
  module Interceptors
    # Prepended onto +ActionMailer::MessageDelivery+.
    # Emits **after** +super+ because Rails forbids reading the mail before enqueue
    # (+deliver_later+ / +MailDeliveryJob+ contract).
    module ActionMailerDeliverLater
      def deliver_later(...)
        r = super
        Emitter.emit(
          :action_mailer,
          'ActionMailer deliver_later (message enqueued)',
          {}
        )
        r
      end
    end
  end
end
