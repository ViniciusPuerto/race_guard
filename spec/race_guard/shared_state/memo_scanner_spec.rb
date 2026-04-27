# frozen_string_literal: true

require 'race_guard'

RSpec.describe RaceGuard::SharedState::MemoScanner do
  describe '.scan_source' do
    it 'finds @ivar ||= rhs' do
      sites = described_class.scan_source(<<~RUBY, path: 'a.rb')
        class X
          def m
            @cache ||= expensive
          end
        end
      RUBY
      expect(sites.size).to eq(1)
      expect(sites.first).to have_attributes(path: 'a.rb', ivar: '@cache')
      expect(sites.first.line).to be_a(Integer)
    end

    it 'does not match @@cvar ||=' do
      sites = described_class.scan_source('@@cv ||= 1', path: 'b.rb')
      expect(sites).to be_empty
    end

    it 'does not match local ||= ' do
      sites = described_class.scan_source('a ||= 1', path: 'c.rb')
      expect(sites).to be_empty
    end

    it 'does not match plain ivar assignment' do
      sites = described_class.scan_source('@x = 1', path: 'd.rb')
      expect(sites).to be_empty
    end

    it 'returns empty on syntax error' do
      expect(described_class.scan_source('def oops', path: 'e.rb')).to eq([])
    end
  end
end
