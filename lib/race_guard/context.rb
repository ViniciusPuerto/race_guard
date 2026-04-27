# frozen_string_literal: true

require 'set'

module RaceGuard
  # Thread-local execution context (no global Thread => state map).
  module Context
    TLS_KEY = :__race_guard_context_mutable__
    # Must match {RaceGuard::DBLockAuditor::ReadModifyWrite::Patches} / {ReadModWriteImpl}:
    # thread-local flags not stored on {MutableStore}; clear them in {#reset!}.
    RMW_THREAD_FLAGS = %i[
      __race_guard_rmw_in_save_depth
      __race_guard_rmw_in_read_hook
      __race_guard_rmw_with_lock_by_row
    ].freeze

    # Per-thread depth for nested +with_lock+ user blocks (4.2). Key: +[model_class.object_id, id]+.
    module RmwWithLockBlockDepth
      module_function

      KEY = :__race_guard_rmw_with_lock_by_row

      def enter!(model_class, record_id)
        h = (Thread.current[KEY] ||= {})
        k = [model_class.object_id, record_id]
        h[k] = h[k].to_i + 1
      end

      def leave!(model_class, record_id)
        h = Thread.current[KEY]
        return unless h

        k = [model_class.object_id, record_id]
        d = h[k].to_i - 1
        if d <= 0
          h.delete(k)
        else
          h[k] = d
        end
        nil
      end

      def depth_for(model_class, record_id)
        h = Thread.current[KEY]
        return 0 unless h

        h[[model_class.object_id, record_id]].to_i
      end
    end

    # Process-singleton facade; all mutations apply only to {Thread.current}.
    class Facade
      def current
        Snapshot.build(mutable_store)
      end

      def push_protected(name)
        mutable_store.push_protected(name)
        self
      end

      def pop_protected
        mutable_store.pop_protected
        self
      end

      def begin_transaction
        mutable_store.begin_transaction
        self
      end

      def end_transaction(success: true)
        mutable_store.end_transaction(success: success)
        self
      end

      def defer_after_commit(&block)
        mutable_store.defer_after_commit(block)
        self
      end

      def reset!
        Thread.current[TLS_KEY] = nil
        RMW_THREAD_FLAGS.each { |f| Thread.current[f] = nil }
        self
      end

      def rmw_read_record!(model_class, record_id, attr_name)
        mutable_store.rmw_read_record!(model_class, record_id, attr_name)
        self
      end

      # @return [Integer, nil] age of matching read in milliseconds, or +nil+ if none within TTL
      def rmw_read_age_ms_for(model_class, record_id, attr_name)
        mutable_store.rmw_read_age_ms_for(model_class, record_id, attr_name)
      end

      def rmw_read_forget!(model_class, record_id, attr_name)
        mutable_store.rmw_read_forget!(model_class, record_id, attr_name)
        self
      end

      def rmw_read_forget_record!(model_class, record_id)
        mutable_store.rmw_read_forget_record!(model_class, record_id)
        self
      end

      def rmw_pessimistic_lock_register!(model_class, record_id)
        mutable_store.rmw_pessimistic_lock_register!(model_class, record_id)
        self
      end

      def rmw_pessimistic_lock_active?(model_class, record_id)
        mutable_store.rmw_pessimistic_lock_active?(model_class, record_id)
      end

      def rmw_with_lock_block_depth_for(model_class, record_id)
        RmwWithLockBlockDepth.depth_for(model_class, record_id)
      end

      def rmw_with_lock_block_enter!(model_class, record_id)
        RmwWithLockBlockDepth.enter!(model_class, record_id)
        self
      end

      def rmw_with_lock_block_leave!(model_class, record_id)
        RmwWithLockBlockDepth.leave!(model_class, record_id)
        self
      end

      private

      def mutable_store
        Thread.current[TLS_KEY] ||= MutableStore.new
      end
    end

    # Mutable per-thread store (never shared across threads).
    class MutableStore
      # {RaceGuard::DBLockAuditor::ReadModifyWrite} (Epic 4.1) — bounded RMW read journal
      RMW_TTL_SEC = 2.0
      RMW_MAX_ENTRIES = 500

      def initialize
        @transaction_depth = 0
        @protected_blocks = []
        @after_commit_stack = []
        @rmw_last_read_at = {}
        @rmw_pessimistic_lock_rows = Set.new
      end

      def push_protected(name)
        @protected_blocks << name.to_sym
      end

      def pop_protected
        @protected_blocks.pop
      end

      def begin_transaction
        @transaction_depth += 1
        @after_commit_stack << []
      end

      def end_transaction(success: true)
        return unless @transaction_depth.positive?

        callbacks = @after_commit_stack.pop
        @transaction_depth -= 1
        flush_after_commit_callbacks(callbacks, success)
        @rmw_pessimistic_lock_rows.clear if @transaction_depth.zero?
      end

      def defer_after_commit(proc)
        if @after_commit_stack.empty?
          run_after_commit_proc(proc)
        else
          @after_commit_stack.last << proc
        end
      end

      attr_reader :transaction_depth, :protected_blocks

      def rmw_read_record!(model_class, record_id, attr_name)
        name = attr_name.to_s
        now = monotonic_time_ms
        key = rmw_key(model_class, record_id, name)
        prune_stale_rmw_map!(now)
        @rmw_last_read_at[key] = now
        evict_oldest_rmw_reads_if_needed!
      end

      def rmw_read_age_ms_for(model_class, record_id, attr_name)
        name = attr_name.to_s
        now = monotonic_time_ms
        key = rmw_key(model_class, record_id, name)
        prune_stale_rmw_map!(now)
        t = @rmw_last_read_at[key]
        return nil unless t
        return nil if (now - t) > (RMW_TTL_SEC * 1000.0)

        (now - t)
      end

      def rmw_read_forget!(model_class, record_id, attr_name)
        key = rmw_key(model_class, record_id, attr_name.to_s)
        @rmw_last_read_at.delete(key)
        self
      end

      def rmw_read_forget_record!(model_class, record_id)
        oid = model_class.object_id
        @rmw_last_read_at.delete_if { |k, _| k[0] == oid && k[1] == record_id }
        self
      end

      def rmw_pessimistic_lock_register!(model_class, record_id)
        @rmw_pessimistic_lock_rows << [model_class.object_id, record_id]
        self
      end

      def rmw_pessimistic_lock_active?(model_class, record_id)
        @rmw_pessimistic_lock_rows.include?([model_class.object_id, record_id])
      end

      private

      def flush_after_commit_callbacks(callbacks, success)
        return unless success && callbacks&.any?

        callbacks.each { |p| run_after_commit_proc(p) }
      end

      def run_after_commit_proc(proc)
        proc.call
      rescue StandardError
        nil
      end

      def monotonic_time_ms
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
      end

      def rmw_key(model_class, record_id, attr_name)
        [model_class.object_id, record_id, attr_name.to_s]
      end

      def prune_stale_rmw_map!(now_ms)
        ttl = RMW_TTL_SEC * 1000.0
        @rmw_last_read_at.delete_if { |_, t| (now_ms - t) > ttl }
      end

      def evict_oldest_rmw_reads_if_needed!
        return if @rmw_last_read_at.size <= RMW_MAX_ENTRIES

        overflow = @rmw_last_read_at.size - RMW_MAX_ENTRIES
        to_drop = @rmw_last_read_at.sort_by { |_, t| t }.first(overflow)
        to_drop.map(&:first).each { |k| @rmw_last_read_at.delete(k) }
      end
    end

    # Immutable snapshot of {#current} state for the calling thread.
    # +protected_blocks+ is ordered outermost-first (first +push_protected+ is index +0+;
    # innermost / most recent is last). Reserved for {RaceGuard.protect} (Task 2.1).
    class Snapshot
      attr_reader :thread_id, :in_transaction, :protected_blocks, :current_rule

      alias in_transaction? in_transaction

      def self.build(store)
        new(
          thread_id: Thread.current.object_id,
          in_transaction: store.transaction_depth.positive?,
          protected_blocks: store.protected_blocks.dup.freeze,
          current_rule: nil
        )
      end

      def initialize(thread_id:, in_transaction:, protected_blocks:, current_rule:)
        @thread_id = thread_id
        @in_transaction = in_transaction
        @protected_blocks = protected_blocks
        @current_rule = current_rule
        freeze
      end

      def to_h
        {
          'current_rule' => current_rule,
          'in_transaction' => in_transaction,
          'protected_blocks' => protected_blocks.map(&:to_s),
          'thread_id' => thread_id
        }
      end
    end
  end
end
