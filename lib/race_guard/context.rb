# frozen_string_literal: true

module RaceGuard
  # Thread-local execution context (no global Thread => state map).
  module Context
    TLS_KEY = :__race_guard_context_mutable__

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

      def end_transaction
        mutable_store.end_transaction
        self
      end

      def reset!
        Thread.current[TLS_KEY] = nil
        self
      end

      private

      def mutable_store
        Thread.current[TLS_KEY] ||= MutableStore.new
      end
    end

    # Mutable per-thread store (never shared across threads).
    class MutableStore
      def initialize
        @transaction_depth = 0
        @protected_blocks = []
      end

      def push_protected(name)
        @protected_blocks << name.to_sym
      end

      def pop_protected
        @protected_blocks.pop
      end

      def begin_transaction
        @transaction_depth += 1
      end

      def end_transaction
        @transaction_depth -= 1 if @transaction_depth.positive?
      end

      attr_reader :transaction_depth, :protected_blocks
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
