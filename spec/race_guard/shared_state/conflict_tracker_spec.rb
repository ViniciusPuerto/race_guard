# frozen_string_literal: true

require 'race_guard'

RSpec.describe RaceGuard::SharedState::ConflictTracker do
  let(:tracker) { described_class.new }
  let(:key) { 'gvar:spec:1' }
  let(:t1) { Object.new }
  let(:t2) { Object.new }

  around do |example|
    RaceGuard.reset_configuration!
    io = StringIO.new
    RaceGuard.configure do |c|
      c.enable(:shared_state_watcher)
      c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
    end
    example.run
    RaceGuard.reset_configuration!
  end

  def event(kind, key:, thread:)
    RaceGuard::SharedState::AccessEvent.new(kind: kind, key: key, thread: thread)
  end

  describe 'concurrent writes' do
    it 'reports when two different threads write the same key unprotected' do
      expect(RaceGuard).to receive(:report).once do |payload|
        expect(payload[:detector]).to eq('shared_state:conflict')
        expect(payload[:context]['pattern']).to eq('concurrent_write')
      end

      tracker.process!(event(:write, key: key, thread: t1), mutex_protected: false)
      tracker.process!(event(:write, key: key, thread: t2), mutex_protected: false)
    end

    it 'does not report a second concurrent write on the same key (debounced per key)' do
      allow(RaceGuard).to receive(:report).and_call_original
      expect(RaceGuard).to receive(:report).once

      tracker.process!(event(:write, key: key, thread: t1), mutex_protected: false)
      tracker.process!(event(:write, key: key, thread: t2), mutex_protected: false)
      tracker.process!(event(:write, key: key, thread: t1), mutex_protected: false)
    end

    it 'does not report when the second write is mutex-protected' do
      expect(RaceGuard).not_to receive(:report)

      tracker.process!(event(:write, key: key, thread: t1), mutex_protected: false)
      tracker.process!(event(:write, key: key, thread: t2), mutex_protected: true)
    end
  end

  describe 'read/write overlap' do
    it 'reports read then write from another thread' do
      expect(RaceGuard).to receive(:report).once do |payload|
        expect(payload[:context]['pattern']).to eq('read_write_overlap')
      end

      tracker.process!(event(:read, key: key, thread: t1), mutex_protected: false)
      tracker.process!(event(:write, key: key, thread: t2), mutex_protected: false)
    end

    it 'reports write then read from another thread' do
      expect(RaceGuard).to receive(:report).once do |payload|
        expect(payload[:context]['pattern']).to eq('read_write_overlap')
      end

      tracker.process!(event(:write, key: key, thread: t1), mutex_protected: false)
      tracker.process!(event(:read, key: key, thread: t2), mutex_protected: false)
    end

    it 'does not report read then write on the same thread' do
      expect(RaceGuard).not_to receive(:report)

      tracker.process!(event(:read, key: key, thread: t1), mutex_protected: false)
      tracker.process!(event(:write, key: key, thread: t1), mutex_protected: false)
    end
  end

  describe '#reset!' do
    it 'clears debounce so a new conflict can be reported' do
      allow(RaceGuard).to receive(:report)
      tracker.process!(event(:write, key: key, thread: t1), mutex_protected: false)
      tracker.process!(event(:write, key: key, thread: t2), mutex_protected: false)
      expect(RaceGuard).to have_received(:report).once

      tracker.reset!
      expect(RaceGuard).to receive(:report).once

      tracker.process!(event(:write, key: key, thread: t1), mutex_protected: false)
      tracker.process!(event(:write, key: key, thread: t2), mutex_protected: false)
    end
  end
end
