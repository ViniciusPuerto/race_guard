# frozen_string_literal: true

require 'set'

module RaceGuard
  module SharedState
    # Tracks variable keys and threads for Epic 6.2 (concurrent writes, read/write overlap).
    #
    # Pass +mutex_protected:+ from the caller (+Watcher+) using the stack at the access site.
    class ConflictTracker
      DETECTOR = 'shared_state:conflict'

      def initialize
        @mutex = Mutex.new
        @unprotected_writers = {} # key => Set<Thread>
        @last_unprotected = {} # key => { thread: Thread, kind: Symbol }
        @reported_concurrent_write = Set.new
        @reported_rw = Set.new
      end

      def reset!
        @mutex.synchronize do
          @unprotected_writers.clear
          @last_unprotected.clear
          @reported_concurrent_write.clear
          @reported_rw.clear
        end
      end

      def process!(event, mutex_protected:)
        return unless event.is_a?(AccessEvent)

        @mutex.synchronize { process_unlocked!(event, mutex_protected: mutex_protected) }
      end

      private

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- single linear state machine
      def process_unlocked!(event, mutex_protected:)
        key = event.key.to_s
        return if key.empty?

        if mutex_protected
          @last_unprotected.delete(key)
          return
        end

        th = event.thread || Thread.current
        kind = event.kind.to_sym

        case kind
        when :write
          check_concurrent_write!(key, th)
          check_rw_after_read!(key, th, :write)
          (@unprotected_writers[key] ||= Set.new) << th
        when :read
          check_rw_after_write!(key, th, :read)
        end

        @last_unprotected[key] = { thread: th, kind: kind }
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def check_concurrent_write!(key, thread)
        writers = @unprotected_writers[key]
        return if writers.nil? || writers.empty?

        return if writers.include?(thread)

        return if @reported_concurrent_write.include?(key)

        @reported_concurrent_write << key
        report!(
          message: "Concurrent unprotected writes on shared state key #{key.inspect}",
          context: { 'key' => key, 'pattern' => 'concurrent_write' }
        )
      end

      def check_rw_after_read!(key, thread, kind)
        last = @last_unprotected[key]
        return unless last
        return if last[:thread] == thread
        return unless last[:kind] == :read && kind == :write

        rw_key = "#{key}:rw:#{last[:thread].object_id}:#{thread.object_id}"
        return if @reported_rw.include?(rw_key)

        @reported_rw << rw_key
        report!(
          message: "Read/write overlap on shared state key #{key.inspect} (unprotected)",
          context: { 'key' => key, 'pattern' => 'read_write_overlap' }
        )
      end

      def check_rw_after_write!(key, thread, kind)
        last = @last_unprotected[key]
        return unless last
        return if last[:thread] == thread
        return unless last[:kind] == :write && kind == :read

        rw_key = "#{key}:wr:#{last[:thread].object_id}:#{thread.object_id}"
        return if @reported_rw.include?(rw_key)

        @reported_rw << rw_key
        report!(
          message: "Read/write overlap on shared state key #{key.inspect} (unprotected)",
          context: { 'key' => key, 'pattern' => 'read_write_overlap' }
        )
      end

      def report!(message:, context:)
        cfg = RaceGuard.configuration
        return unless cfg.active?
        return unless cfg.enabled?(:shared_state_watcher)

        sev = cfg.severity_for(:'shared_state:conflict')
        RaceGuard.report(
          detector: DETECTOR,
          message: message,
          severity: sev,
          thread_id: Thread.current.object_id.to_s,
          context: context
        )
      end
    end
  end
end
