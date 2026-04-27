# frozen_string_literal: true

RSpec.describe RaceGuard::Context do
  after do
    RaceGuard.context.reset!
  end

  describe 'RaceGuard.context.current' do
    it 'returns thread id, transaction flag, and protected stack' do
      c = RaceGuard.context.current
      expect(c.thread_id).to eq(Thread.current.object_id)
      expect(c).not_to be_in_transaction
      expect(c.protected_blocks).to eq([])
      expect(c.current_rule).to be_nil
    end

    it 'orders protected_blocks outermost-first (first push at index 0)' do
      RaceGuard.context.push_protected(:a).push_protected(:b)
      blocks = RaceGuard.context.current.protected_blocks
      expect(blocks).to eq(%i[a b])
    end

    it 'no-ops pop when stack is empty' do
      expect { RaceGuard.context.pop_protected }.not_to raise_error
      expect(RaceGuard.context.current.protected_blocks).to eq([])
    end

    it 'pops innermost last' do
      RaceGuard.context.push_protected(:a).push_protected(:b)
      RaceGuard.context.pop_protected
      expect(RaceGuard.context.current.protected_blocks).to eq(%i[a])
      RaceGuard.context.pop_protected
      expect(RaceGuard.context.current.protected_blocks).to eq([])
    end
  end

  describe 'transaction nesting' do
    it 'tracks depth with begin/end' do
      RaceGuard.context.begin_transaction.begin_transaction
      expect(RaceGuard.context.current).to be_in_transaction
      RaceGuard.context.end_transaction
      expect(RaceGuard.context.current).to be_in_transaction
      RaceGuard.context.end_transaction
      expect(RaceGuard.context.current).not_to be_in_transaction
    end

    it 'no-ops end when depth is already zero' do
      3.times { RaceGuard.context.end_transaction }
      expect(RaceGuard.context.current).not_to be_in_transaction
    end

    it 'runs deferred after_commit when end_transaction succeeds' do
      ran = []
      RaceGuard.context.begin_transaction
      RaceGuard.context.defer_after_commit { ran << :done }
      RaceGuard.context.end_transaction(success: true)
      expect(ran).to eq([:done])
    end

    it 'discards deferred after_commit when end_transaction reports failure' do
      ran = []
      RaceGuard.context.begin_transaction
      RaceGuard.context.defer_after_commit { ran << :done }
      RaceGuard.context.end_transaction(success: false)
      expect(ran).to be_empty
    end
  end

  describe '#reset!' do
    it 'clears state for the current thread only' do
      RaceGuard.context.push_protected(:x).begin_transaction
      RaceGuard.context.reset!
      cur = RaceGuard.context.current
      expect(cur.protected_blocks).to eq([])
      expect(cur).not_to be_in_transaction
    end

    it 'clears RMW read-modify-write thread flags (in-save depth, read re-entrancy hook)' do
      depth = :__race_guard_rmw_in_save_depth
      hook = :__race_guard_rmw_in_read_hook
      Thread.current[depth] = 1
      Thread.current[hook] = true
      RaceGuard.context.reset!
      expect(Thread.current[depth]).to be_nil
      expect(Thread.current[hook]).to be_nil
    end

    it 'clears RMW with_lock per-row depth when resetting context' do
      wl = :__race_guard_rmw_with_lock_by_row
      Thread.current[wl] = { [0, 1] => 1 }
      RaceGuard.context.reset!
      expect(Thread.current[wl]).to be_nil
    end
  end

  describe 'thread isolation' do
    it 'keeps separate stacks per thread' do
      q = Queue.new
      t = Thread.new do
        RaceGuard.context.push_protected(:thread_b)
        q.push(RaceGuard.context.current.protected_blocks)
      end
      RaceGuard.context.push_protected(:thread_a)
      expect(RaceGuard.context.current.protected_blocks).to eq(%i[thread_a])
      expect(q.pop).to eq(%i[thread_b])
      t.join
    end
  end

  describe 'RaceGuard::Context::Snapshot#to_h' do
    it 'returns string-keyed hash' do
      RaceGuard.context.push_protected(:z)
      h = RaceGuard.context.current.to_h
      expect(h['protected_blocks']).to eq(['z'])
      expect(h).to have_key('thread_id')
    end
  end

  describe 'RMW pessimistic lock (4.2)' do
    it 'clears transaction-scoped row locks when the outermost transaction frame ends' do
      RaceGuard.context.begin_transaction
      RaceGuard.context.rmw_pessimistic_lock_register!(String, 42)
      expect(RaceGuard.context.rmw_pessimistic_lock_active?(String, 42)).to be true
      RaceGuard.context.end_transaction(success: true)
      expect(RaceGuard.context.rmw_pessimistic_lock_active?(String, 42)).to be false
    end
  end

  describe 'read-modify-write journal' do
    it 'returns age in ms for a prior read, then nil after forget' do
      model = String
      RaceGuard.context.rmw_read_record!(model, 42, 'balance')
      expect(RaceGuard.context.rmw_read_age_ms_for(model, 42, 'balance')).to be > 0
      RaceGuard.context.rmw_read_forget!(model, 42, 'balance')
      expect(RaceGuard.context.rmw_read_age_ms_for(model, 42, 'balance')).to be_nil
    end
  end
end
