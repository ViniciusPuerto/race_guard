# frozen_string_literal: true

require 'set'

module RaceGuard
  module SharedState
    # Static memo sites + one-shot reports when multi-threaded (Epic 6.4).
    module MemoRegistry
      DETECTOR = 'shared_state:memoization'
      MODULE_MUTEX = Mutex.new

      class << self
        def reset!
          MODULE_MUTEX.synchronize do
            @sites = []
            @reported_keys = Set.new
          end
        end

        def sites
          MODULE_MUTEX.synchronize { @sites.dup }
        end

        def sync_from_configuration!
          cfg = RaceGuard.configuration
          globs = cfg.shared_state_memo_globs
          MODULE_MUTEX.synchronize do
            @sites = []
            Array(globs).each do |pattern|
              Dir.glob(pattern).each do |path|
                next unless File.file?(path)

                @sites.concat(MemoScanner.scan_file(path))
              end
            end
            flush_pending_unlocked! if SharedState.multi_threaded?
          end
        end

        def flush_pending!
          MODULE_MUTEX.synchronize { flush_pending_unlocked! }
        end

        private

        def flush_pending_unlocked!
          return unless SharedState.multi_threaded?

          cfg = RaceGuard.configuration
          return unless cfg.active?
          return unless cfg.enabled?(:shared_state_watcher)

          @sites.each { |site| report_site_once_unlocked!(site) }
        end

        def report_site_once_unlocked!(site)
          key = site_key(site)
          return if @reported_keys.include?(key)

          @reported_keys << key
          emit_memo_report!(site)
        end

        # rubocop:disable Metrics/MethodLength -- single report payload
        def emit_memo_report!(site)
          configuration = RaceGuard.configuration
          sev = configuration.severity_for(:'shared_state:memoization')
          loc = "#{site.path}:#{site.line}"
          msg = "Possible unsafe instance-variable memoization #{site.ivar} at #{loc}"
          ctx = { 'path' => site.path, 'line' => site.line, 'ivar' => site.ivar }
          RaceGuard.report(
            detector: DETECTOR,
            message: msg,
            severity: sev,
            location: loc,
            thread_id: Thread.current.object_id.to_s,
            context: ctx
          )
        end
        # rubocop:enable Metrics/MethodLength

        def site_key(site)
          "#{site.path}:#{site.line}:#{site.ivar}"
        end
      end
    end
  end
end

RaceGuard::SharedState::MemoRegistry.reset!
