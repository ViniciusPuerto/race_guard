# frozen_string_literal: true

RSpec.describe RaceGuard::Event do
  it 'exposes a frozen SCHEMA' do
    expect(described_class::SCHEMA).to be_frozen
    expect(described_class::SCHEMA['detector']).to include('String')
  end

  it 'coerces to_h with string keys and ISO timestamp' do
    t = Time.utc(2020, 1, 2, 3, 4, 5)
    e = described_class.new(detector: 'd', message: 'm', severity: :info, timestamp: t)
    h = e.to_h
    expect(h['detector']).to eq('d')
    expect(h['message']).to eq('m')
    expect(h['severity']).to eq('info')
    expect(h['timestamp']).to match(/2020-01-02T03:04:05/)
  end

  it 'rejects invalid severity' do
    expect { described_class.new(detector: 'a', message: 'b', severity: :noop) }
      .to raise_error(ArgumentError, /invalid severity/)
  end

  describe '.from_payload' do
    it 'builds from a Hash' do
      e = described_class.from_payload(
        'detector' => 'x', 'message' => 'y', 'severity' => 'warn', 'context' => { a: 1 }
      )
      expect(e).to be_a(described_class)
      expect(e.severity).to eq(:warn)
      expect(e.to_h['context']).to eq('a' => 1)
    end

    it 'accepts the same class instance' do
      e1 = described_class.new(detector: 'a', message: 'b', severity: :error)
      e2 = described_class.from_payload(e1)
      expect(e2).to be(e1)
    end
  end
end
