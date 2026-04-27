# frozen_string_literal: true

require 'race_guard'

RSpec.describe RaceGuard::SharedState::Watcher do
  let(:feature) { RaceGuard::SharedState::TracePoint::FEATURE }
  let(:key) { 'gvar:watcher:1' }
  let(:t1) { Object.new }
  let(:t2) { Object.new }

  around do |example|
    RaceGuard.reset_configuration!
    io = StringIO.new
    RaceGuard.configure do |c|
      c.enable(feature)
      c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
    end
    example.run
    RaceGuard.reset_configuration!
  end

  describe '.handle_event' do
    it 'suppresses concurrent write reports when Mutex#synchronize protects the access' do
      expect(RaceGuard).not_to receive(:report)

      m = Mutex.new
      m.synchronize do
        described_class.handle_event({ kind: :write, key: key, thread: t1 })
        described_class.handle_event({ kind: :write, key: key, thread: t2 })
      end
    end

    it 'reports concurrent writes when the same pattern runs outside Mutex' do
      expect(RaceGuard).to receive(:report).once

      described_class.handle_event({ kind: :write, key: key, thread: t1 })
      described_class.handle_event({ kind: :write, key: key, thread: t2 })
    end
  end
end
