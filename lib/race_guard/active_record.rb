# frozen_string_literal: true

require_relative '../race_guard'
require_relative 'db_lock_auditor/read_modify_write'

module RaceGuard
  # Optional integration: mirror +ActiveRecord::Base.transaction+ boundaries onto
  # {RaceGuard.context} (+begin_transaction+ / +end_transaction+).
  #
  # Require after ActiveRecord is loaded, or call {.install_transaction_tracking!}
  # again after +require "active_record"+.
  module ActiveRecord
    INSTALL_MUTEX = Mutex.new

    # Prepended onto +ActiveRecord::Base.singleton_class+.
    module TransactionPatch
      def transaction(*args, **kwargs, &block)
        return super(*args, **kwargs) unless block

        RaceGuard.context.begin_transaction
        success = false
        begin
          super(*args, **kwargs, &block) # rubocop:disable Style/SuperArguments -- bare super breaks nested AR
          success = true
        rescue StandardError
          success = false
          raise
        ensure
          RaceGuard.context.end_transaction(success: success)
        end
      end
    end

    class << self
      def install_transaction_tracking!
        return self unless defined?(::ActiveRecord::Base)

        INSTALL_MUTEX.synchronize do
          sc = ::ActiveRecord::Base.singleton_class
          return self if sc.ancestors.include?(TransactionPatch)

          sc.prepend(TransactionPatch)
        end
        self
      end
    end
  end
end

if defined?(ActiveRecord::Base)
  RaceGuard::ActiveRecord.install_transaction_tracking!
  RaceGuard::DBLockAuditor::ReadModifyWrite.install!
end
