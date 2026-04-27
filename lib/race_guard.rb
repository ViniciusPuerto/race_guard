# frozen_string_literal: true

require_relative 'race_guard/version'
require_relative 'race_guard/constants'
require_relative 'race_guard/configuration'
require_relative 'race_guard/context'
require_relative 'race_guard/event'
require_relative 'race_guard/report_raised_error'
require_relative 'race_guard/rule'
require_relative 'race_guard/rule_engine'
require_relative 'race_guard/protection'
require_relative 'race_guard/method_watch'
require_relative 'race_guard/reporters/log_reporter'
require_relative 'race_guard/reporters/json_reporter'
require_relative 'race_guard/reporters/file_reporter'
require_relative 'race_guard/reporters/webhook_reporter'
require_relative 'race_guard/db_lock_auditor/read_modify_write'
require_relative 'race_guard/shared_state'

module RaceGuard
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    alias config configuration

    def configure
      yield configuration
      SharedState::MemoRegistry.sync_from_configuration!
      SharedState::TracePoint.sync_with_configuration!
    end

    def reset_configuration!
      SharedState::TracePoint.uninstall!
      @configuration = nil
    end

    def context
      @context ||= Context::Facade.new
    end

    def watch(klass, method_name, scope: :auto)
      MethodWatch.watch(klass, method_name, scope: scope)
    end

    def define_rule(name, &)
      RuleEngine.define_rule(name, &)
    end

    def after_commit(&block)
      raise ArgumentError, 'RaceGuard.after_commit requires a block' unless block

      if context.current.in_transaction?
        context.defer_after_commit(&block)
      else
        run_after_commit_immediate(block)
      end
      self
    end

    def report(payload)
      cfg = configuration
      return nil unless cfg.active?

      event = Event.from_payload(payload)
      event = merge_protect_context(event)
      cfg.reporters.each do |reporter|
        reporter.report(event)
      rescue StandardError
        # isolate reporter failure
      end

      raise ReportRaisedError, event if event.severity == :raise

      nil
    end

    private

    def run_after_commit_immediate(block)
      block.call
    rescue StandardError
      nil
    end

    def merge_protect_context(event)
      blocks = context.current.protected_blocks
      return event if blocks.empty?

      inner = blocks.last.to_s
      stack = blocks.map(&:to_s)
      event.with_merged_context('protect' => inner, 'protect_stack' => stack)
    end
  end
end

RaceGuard::DBLockAuditor::ReadModifyWrite.install! if defined?(ActiveRecord::Base)

require_relative 'race_guard/railtie'
