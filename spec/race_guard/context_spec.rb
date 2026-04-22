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
  end

  describe '#reset!' do
    it 'clears state for the current thread only' do
      RaceGuard.context.push_protected(:x).begin_transaction
      RaceGuard.context.reset!
      cur = RaceGuard.context.current
      expect(cur.protected_blocks).to eq([])
      expect(cur).not_to be_in_transaction
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
end
