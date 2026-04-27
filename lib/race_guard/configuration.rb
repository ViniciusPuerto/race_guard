# frozen_string_literal: true

require 'set'

require_relative 'constants'
require_relative 'commit_safety/watcher'

module RaceGuard
  # Per-process configuration. Mutations are protected by a Mutex.
  class Configuration
    DEFAULT_ENVIRONMENTS = %i[development test].freeze
    DEFAULT_SEVERITY = :info

    def initialize
      @mutex = Mutex.new
      @enabled = Set.new
      @enabled_rules = Set.new
      @default_severity = DEFAULT_SEVERITY
      @severities = {}
      @environments = DEFAULT_ENVIRONMENTS.dup
      @reporters = []
      @protect_detectors = []
      @db_lock_read_modify_write_classes = Set.new
      @shared_state_memo_globs = []
    end

    def enable(name)
      sym = name.to_sym
      @mutex.synchronize { @enabled.add(sym) }
      self
    end

    def disable(name)
      sym = name.to_sym
      @mutex.synchronize { @enabled.delete(sym) }
      self
    end

    def enabled?(name)
      sym = name.to_sym
      @mutex.synchronize do
        return false unless @environments.include?(current_environment)

        @enabled.include?(sym)
      end
    end

    def enable_rule(name)
      sym = name.to_sym
      @mutex.synchronize { @enabled_rules.add(sym) }
      self
    end

    def disable_rule(name)
      sym = name.to_sym
      @mutex.synchronize { @enabled_rules.delete(sym) }
      self
    end

    def enabled_rule?(name)
      sym = name.to_sym
      @mutex.synchronize do
        return false unless @environments.include?(current_environment)

        @enabled_rules.include?(sym)
      end
    end

    def severity(*args)
      @mutex.synchronize { apply_severity_args(args) }
      self
    end

    def severity_for(name)
      sym = name.to_sym
      @mutex.synchronize { @severities[sym] || @default_severity }
    end

    def environments(*names)
      return @mutex.synchronize { @environments.dup } if names.empty?

      @mutex.synchronize { @environments = names.map(&:to_sym).freeze }
      self
    end

    def active?
      @mutex.synchronize { @environments.include?(current_environment) }
    end

    def add_reporter(reporter)
      @mutex.synchronize { @reporters << reporter }
      self
    end

    def remove_reporter(reporter)
      @mutex.synchronize { @reporters.delete(reporter) }
      self
    end

    def clear_reporters
      @mutex.synchronize { @reporters.clear }
      self
    end

    def reporters
      @mutex.synchronize { @reporters.dup }
    end

    def add_protect_detector(detector)
      @mutex.synchronize { @protect_detectors << detector }
      self
    end

    def remove_protect_detector(detector)
      @mutex.synchronize { @protect_detectors.delete(detector) }
      self
    end

    def clear_protect_detectors
      @mutex.synchronize { @protect_detectors.clear }
      self
    end

    def protect_detectors
      @mutex.synchronize { @protect_detectors.dup }
    end

    def watch_commit_safety(name, &block)
      raise ArgumentError, 'watch_commit_safety requires a block' unless block

      sym = name.to_sym
      @mutex.synchronize do
        dsl = CommitSafety::WatcherDSL.new(sym)
        block.call(dsl)
      end
      self
    end

    # Classes (e.g. ActiveRecord models) to audit for read-modify-write patterns
    # (Epic 4.1). Empty by default: no read tracking / write correlation.
    def db_lock_read_modify_write_models(*klasses)
      if klasses.compact.empty?
        return @mutex.synchronize do
          @db_lock_read_modify_write_classes.to_a
        end
      end

      flat = klasses.length == 1 && klasses.first.is_a?(Array) ? klasses.first : klasses
      @mutex.synchronize { @db_lock_read_modify_write_classes = Set.new(flat.compact) }
      self
    end

    def db_lock_read_modify_write_tracks?(klass)
      k = klass
      return false unless k.is_a?(Class)

      @mutex.synchronize { @db_lock_read_modify_write_classes.include?(k) }
    end

    # Glob patterns (e.g. +lib/**/*.rb+) scanned for +@ivar ||=+ memoization (Epic 6.4).
    # Empty by default: memo reports are disabled until patterns are set.
    def shared_state_memo_globs(*patterns)
      return @mutex.synchronize { @shared_state_memo_globs.dup } if patterns.empty?

      flat = patterns.length == 1 && patterns.first.is_a?(Array) ? patterns.first : patterns
      @mutex.synchronize { @shared_state_memo_globs = flat.compact.map(&:to_s).freeze }
      self
    end

    def to_h
      @mutex.synchronize { to_h_unsafe }
    end

    def current_environment
      raw = ENV['RACK_ENV'] || ENV['RAILS_ENV'] || 'development'
      raw.downcase.to_sym
    end

    private

    # rubocop:disable Metrics/MethodLength -- one stable snapshot hash; keep field list explicit
    def to_h_unsafe
      h = {
        active: @environments.include?(current_environment),
        current_environment: current_environment,
        default_severity: @default_severity,
        enabled_features: @enabled.to_a,
        enabled_rules: @enabled_rules.to_a,
        environments: @environments.dup,
        protect_detector_count: @protect_detectors.size,
        reporter_classes: @reporters.map { |r| r.class.name },
        reporter_count: @reporters.size,
        severities: @severities.dup
      }
      h[:db_lock_read_modify_write_class_count] = @db_lock_read_modify_write_classes.size
      h[:shared_state_memo_glob_count] = @shared_state_memo_globs.size
      h
    end
    # rubocop:enable Metrics/MethodLength

    def apply_severity_args(args)
      case args.length
      when 1
        @default_severity = validate_severity(args[0])
      when 2
        detector = args[0].to_sym
        @severities[detector] = validate_severity(args[1])
      else
        raise ArgumentError, "expected 1 or 2 arguments (got #{args.length})"
      end
    end

    def validate_severity(level)
      sym = level.to_sym
      return sym if ::RaceGuard::SEVERITY_LEVELS.include?(sym)

      list = ::RaceGuard::SEVERITY_LEVELS.join(', ')
      msg = "invalid severity: #{level.inspect} (expected one of: #{list})"
      raise ArgumentError, msg
    end
  end
end
