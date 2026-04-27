# frozen_string_literal: true

module RaceGuard
  module SharedState
    # TracePoint listener for class- and global-variable assignments (Epic 6.1).
    #
    # CRuby 3.x public +TracePoint+ does not expose +:cvasgn+ / +:gvasgn+
    # (+ArgumentError+ on +new+).
    # This module still performs **setup**: when those events exist in a future MRI, they are used;
    # otherwise a one-time +Kernel.warn+ explains the limitation and nothing is installed (no
    # blanket +:c_call+ trace, which would be prohibitively expensive).
    #
    # Opt in with +RaceGuard.configure+ { |c| c.enable(:shared_state_watcher) }.
    module TracePoint
      FEATURE = :shared_state_watcher
      INSTALL_MUTEX = Mutex.new

      class << self
        attr_accessor :event_sink

        def sync_with_configuration!
          INSTALL_MUTEX.synchronize do
            cfg = RaceGuard.configuration
            if cfg.active? && cfg.enabled?(FEATURE)
              install_unlocked!
            else
              uninstall_unlocked!
            end
          end
        end

        def installed?
          INSTALL_MUTEX.synchronize { !@trace.nil? || !@thread_trace.nil? }
        end

        def install!
          INSTALL_MUTEX.synchronize do
            cfg = RaceGuard.configuration
            install_unlocked! if cfg.active? && cfg.enabled?(FEATURE)
          end
        end

        def uninstall!
          INSTALL_MUTEX.synchronize { uninstall_unlocked! }
        end

        private

        def install_unlocked!
          install_cvar_trace_unlocked!
          reinstall_thread_trace_unlocked!
        end

        def reinstall_thread_trace_unlocked!
          if @thread_trace
            @thread_trace.disable
            @thread_trace = nil
          end
          install_thread_begin_unlocked!
        end

        def install_cvar_trace_unlocked!
          return if @trace || @install_failed

          @trace = ::TracePoint.new(:cvasgn, :gvasgn) { |trace| dispatch(trace) }
          @trace.enable
        rescue ArgumentError
          @install_failed = true
          warn_unsupported_once
          @trace = nil
        end

        def install_thread_begin_unlocked!
          return if @thread_trace

          cfg = RaceGuard.configuration
          return unless thread_begin_memo_watch?(cfg)

          @thread_trace = ::TracePoint.new(:thread_begin) do
            SharedState.mark_multi_threaded! if Thread.current != Thread.main
            MemoRegistry.flush_pending!
          end
          @thread_trace.enable
        rescue ArgumentError, RuntimeError
          @thread_trace = nil
        end

        def thread_begin_memo_watch?(cfg)
          cfg.active? && cfg.enabled?(FEATURE) && Array(cfg.shared_state_memo_globs).any?
        end

        def uninstall_unlocked!
          if @trace
            @trace.disable
            @trace = nil
          end
          if @thread_trace
            @thread_trace.disable
            @thread_trace = nil
          end
          @install_failed = false
          SharedState.reset!
        end

        def dispatch(trace)
          cfg = RaceGuard.configuration
          return unless cfg.active? && cfg.enabled?(FEATURE)

          Watcher.handle_tracepoint(trace)
          event_sink&.call(trace)
        end

        def warn_unsupported_once
          return if @warned_unsupported

          @warned_unsupported = true
          Kernel.warn(
            '[race_guard] shared_state_watcher: TracePoint :cvasgn/:gvasgn are not available on ' \
            'this Ruby; Epic 6.1 listener not installed. See docs/specs.md (Epic 6, Task 6.1).'
          )
        end
      end
    end
  end
end
