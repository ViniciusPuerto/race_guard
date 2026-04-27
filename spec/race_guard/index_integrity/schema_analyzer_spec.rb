# frozen_string_literal: true

require 'active_record'
require 'race_guard/index_integrity/schema_analyzer'

RSpec.describe RaceGuard::IndexIntegrity::SchemaAnalyzer do
  let(:fixture_path) do
    File.expand_path('../../fixtures/index_integrity/schema_sample.rb', __dir__)
  end

  describe '.parse_file' do
    it 'extracts unique add_index and t.index entries; skips non-unique indexes' do
      idx = described_class.parse_file(fixture_path)
      expect(idx.size).to eq(2)
      expect(idx.map(&:table).sort).to eq(%i[accounts users])

      email_ix = idx.find { |i| i.table == :users }
      expect(email_ix.columns).to eq([:email])
      expect(email_ix.unique).to be true

      composite = idx.find { |i| i.table == :accounts && i.columns.size == 2 }
      expect(composite.columns).to eq(%i[slug tenant_id])
    end

    it 'skips partial indexes (where: in options hash)' do
      src = <<~RUBY
        ActiveRecord::Schema[7.1].define(version: 1) do
          add_index "posts", ["author_id"], unique: true, where: "deleted_at IS NULL"
        end
      RUBY
      expect(described_class.parse_source(src)).to be_empty
    end

    it 'returns empty array for missing file' do
      expect(described_class.parse_file('/nonexistent/schema.rb')).to eq([])
    end

    it 'returns empty array on syntax error' do
      expect(described_class.parse_source('def oops')).to eq([])
    end
  end

  describe '.parse_source' do
    it 'handles change-wrapped add_index' do
      src = <<~RUBY
        ActiveRecord::Schema[7.1].define(version: 1) do
          change do
            add_index "widgets", ["token"], unique: true
          end
        end
      RUBY
      idx = described_class.parse_source(src)
      expect(idx.size).to eq(1)
      expect(idx.first.table).to eq(:widgets)
      expect(idx.first.columns).to eq([:token])
    end
  end

  describe '.from_connection' do
    around do |example|
      ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
      example.run
      ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?
    end

    it 'matches parse_file output for the same logical indexes' do
      ActiveRecord::Schema.define(version: 20_240_101_000_000) do
        create_table :users, force: true do |t|
          t.string :email
          t.index %i[email], name: 'index_users_on_email', unique: true
        end
        create_table :accounts, force: true do |t|
          t.string :slug
          t.string :tenant_id
        end
        add_index :accounts, %i[slug tenant_id], unique: true,
                                                 name: 'index_accounts_on_slug_and_tenant_id'
        add_index :accounts, [:slug], unique: false, name: 'index_accounts_on_slug_nonunique'
      end

      conn = ActiveRecord::Base.connection
      from_db = described_class.from_connection(conn)
      from_file = described_class.parse_file(fixture_path)

      normalize = lambda do |list|
        list.map { |i| [i.table, i.columns.sort, i.unique] }.sort
      end

      expect(normalize.call(from_db)).to eq(normalize.call(from_file))
    end
  end
end
