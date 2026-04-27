# frozen_string_literal: true

require 'tmpdir'
require 'race_guard/index_integrity/model_scanner'

RSpec.describe RaceGuard::IndexIntegrity::ModelScanner do
  describe '.scan_source' do
    it 'extracts field and nil scope for uniqueness: true' do
      src = 'validates :email, uniqueness: true'
      hits = described_class.scan_source(src)
      expect(hits.size).to eq(1)
      expect(hits.first.fields).to eq([:email])
      expect(hits.first.scope).to be_nil
    end

    it 'extracts field and symbol scope' do
      src = 'validates :slug, uniqueness: { scope: :account_id }'
      hits = described_class.scan_source(src)
      expect(hits.first.fields).to eq([:slug])
      expect(hits.first.scope).to eq(:account_id)
    end

    it 'extracts multiple fields and array scope' do
      src = 'validates :a, :b, uniqueness: { scope: [:shop_id, :kind] }'
      hits = described_class.scan_source(src)
      expect(hits.first.fields).to eq(%i[a b])
      expect(hits.first.scope).to eq(%i[shop_id kind])
    end

    it 'returns no hits when uniqueness is absent' do
      src = 'validates :email, presence: true'
      expect(described_class.scan_source(src)).to be_empty
    end

    it 'returns no hits when uniqueness is false' do
      src = 'validates :email, uniqueness: false'
      expect(described_class.scan_source(src)).to be_empty
    end

    it 'parses multi-line validates with uniqueness' do
      src = <<~RUBY
        class User < ApplicationRecord
          validates :email,
                    uniqueness: { scope: :tenant_id },
                    presence: true
        end
      RUBY
      hits = described_class.scan_source(src, filename: 'user.rb')
      expect(hits.size).to eq(1)
      expect(hits.first.fields).to eq([:email])
      expect(hits.first.scope).to eq(:tenant_id)
      expect(hits.first.filename).to eq('user.rb')
    end

    it 'recognizes self.validates' do
      src = 'self.validates :name, uniqueness: true'
      hits = described_class.scan_source(src)
      expect(hits.first.fields).to eq([:name])
    end

    it 'returns empty array on syntax error' do
      expect(described_class.scan_source('def oops')).to eq([])
    end
  end

  describe '.scan_file' do
    it 'reads a UTF-8 file and scans' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'account.rb')
        File.write(path, "validates :external_id, uniqueness: { scope: :provider }\n")
        hits = described_class.scan_file(path)
        expect(hits.size).to eq(1)
        expect(hits.first.fields).to eq([:external_id])
        expect(hits.first.scope).to eq(:provider)
        expect(hits.first.filename).to eq(path)
      end
    end

    it 'returns empty array for missing file' do
      expect(described_class.scan_file('/nonexistent/path/model.rb')).to eq([])
    end
  end
end
