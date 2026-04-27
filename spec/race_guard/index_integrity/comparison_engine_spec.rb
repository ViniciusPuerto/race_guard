# frozen_string_literal: true

require 'active_support/inflector'
require 'race_guard/index_integrity/model_scanner'
require 'race_guard/index_integrity/schema_analyzer'
require 'race_guard/index_integrity/comparison_engine'

RSpec.describe RaceGuard::IndexIntegrity::ComparisonEngine do
  let(:index) do
    lambda do |table, *cols|
      RaceGuard::IndexIntegrity::IndexDefinition.new(
        table: table,
        columns: cols.flatten,
        unique: true,
        name: nil
      )
    end
  end

  describe '.table_for_model_path' do
    it 'maps app/models/user.rb to :users' do
      expect(described_class.table_for_model_path('/app/models/user.rb')).to eq(:users)
    end

    it 'maps nested admin user to :admin_users' do
      expect(described_class.table_for_model_path('/app/models/admin/user.rb')).to eq(:admin_users)
    end

    it 'returns nil for concerns paths' do
      expect(described_class.table_for_model_path('/app/models/concerns/taggable.rb')).to be_nil
    end
  end

  describe '.missing_indexes' do
    let(:user_model_path) { '/rails/app/models/user.rb' }

    it 'returns empty when a unique index covers scope + field' do
      v = RaceGuard::IndexIntegrity::UniquenessValidation.new(
        fields: [:slug],
        scope: :account_id,
        filename: user_model_path
      )
      idx = [
        index.call(:users, :account_id, :slug)
      ]
      expect(described_class.missing_indexes(validations: [v], indexes: idx)).to be_empty
    end

    it 'treats column order on the index as irrelevant' do
      v = RaceGuard::IndexIntegrity::UniquenessValidation.new(
        fields: [:slug],
        scope: :account_id,
        filename: user_model_path
      )
      idx = [index.call(:users, :slug, :account_id)]
      expect(described_class.missing_indexes(validations: [v], indexes: idx)).to be_empty
    end

    it 'detects missing unique index and suggests add_index' do
      v = RaceGuard::IndexIntegrity::UniquenessValidation.new(
        fields: [:email],
        scope: nil,
        filename: user_model_path
      )
      nonunique = RaceGuard::IndexIntegrity::IndexDefinition.new(
        table: :users,
        columns: [:email],
        unique: false,
        name: 'nope'
      )
      violations = described_class.missing_indexes(validations: [v], indexes: [nonunique])
      expect(violations.size).to eq(1)
      expect(violations.first.suggested_migration).to eq('add_index :users, [:email], unique: true')
      expect(violations.first.message).to include('Missing unique index')
    end

    it 'requires composite columns for multi-field validates' do
      src = 'validates :a, :b, uniqueness: { scope: :shop_id }'
      v = RaceGuard::IndexIntegrity::ModelScanner.scan_source(src, filename: user_model_path).first
      idx = [index.call(:users, :shop_id, :a)] # missing :b
      violations = described_class.missing_indexes(validations: [v], indexes: idx)
      expect(violations.size).to eq(1)
    end
  end
end
