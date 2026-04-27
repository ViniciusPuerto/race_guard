# frozen_string_literal: true

require 'pathname'
require 'tmpdir'
require 'race_guard/index_integrity/runner'

RSpec.describe RaceGuard::IndexIntegrity::Runner do
  describe '.exit_code_for' do
    it 'returns 0 when unique index backs the validation' do
      Dir.mktmpdir do |dir|
        root = Pathname(dir)
        root.join('app/models').mkpath
        root.join('db').mkpath
        File.write(root.join('app/models/user.rb'), "validates :email, uniqueness: true\n")
        File.write(root.join('db/schema.rb'), <<~RUBY)
          ActiveRecord::Schema[7.1].define(version: 1) do
            create_table :users, force: true do |t|
              t.string :email
              t.index [:email], unique: true
            end
          end
        RUBY

        expect(described_class.exit_code_for(root, stdout: StringIO.new)).to eq(0)
      end
    end

    it 'returns 1 when no matching unique index exists' do
      Dir.mktmpdir do |dir|
        root = Pathname(dir)
        root.join('app/models').mkpath
        root.join('db').mkpath
        File.write(root.join('app/models/user.rb'), "validates :email, uniqueness: true\n")
        File.write(root.join('db/schema.rb'), <<~RUBY)
          ActiveRecord::Schema[7.1].define(version: 1) do
            create_table :users, force: true do |t|
              t.string :email
            end
          end
        RUBY

        out = StringIO.new
        expect(described_class.exit_code_for(root, stdout: out)).to eq(1)
        expect(out.string).to include('Missing unique index')
      end
    end
  end
end
