# frozen_string_literal: true

RSpec.describe RaceGuard::Distributed::KeyBuilder do
  describe '.build' do
    it 'builds a default-prefixed key without resource' do
      k = described_class.build(name: 'cron_daily')
      expect(k).to eq('race_guard:distributed:v1:cron_daily')
    end

    it 'includes a stable resource digest when resource is present' do
      k1 = described_class.build(name: 'job', resource: 'tenant_42')
      k2 = described_class.build(name: 'job', resource: 'tenant_42')
      k3 = described_class.build(name: 'job', resource: 'tenant_43')
      d = described_class.resource_digest('tenant_42')
      expect(k1).to eq("race_guard:distributed:v1:job:#{d}")
      expect(k1).to eq(k2)
      expect(k1).not_to eq(k3)
    end

    it 'uses a custom prefix when given' do
      k = described_class.build(name: 'x', prefix: 'app:locks:')
      expect(k).to eq('app:locks:v1:x')
    end

    it 'sanitizes unsafe characters in the name segment' do
      k = described_class.build(name: 'a b:c')
      expect(k).to eq('race_guard:distributed:v1:a_b_c')
    end

    it 'raises on empty name' do
      expect { described_class.build(name: '') }.to raise_error(ArgumentError, /non-empty/)
    end
  end
end
