# frozen_string_literal: true

require 'active_record'
require 'sqlite3'
require 'race_guard'
require 'race_guard/active_record'

RSpec.describe 'RaceGuard.after_commit' do
  include EnvSpecHelpers

  before do
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    RaceGuard::ActiveRecord.install_transaction_tracking!
  end

  after do
    RaceGuard.reset_configuration!
    RaceGuard.context.reset!
    ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?
  end

  it 'runs the block immediately when not in a transaction' do
    with_isolated_env(rack: 'development') do
      ran = []
      RaceGuard.after_commit { ran << :now }
      expect(ran).to eq([:now])
    end
  end

  it 'defers until AR transaction completes successfully' do
    with_isolated_env(rack: 'development') do
      ran = []
      ActiveRecord::Base.transaction do
        RaceGuard.after_commit { ran << :deferred }
        expect(ran).to be_empty
      end
      expect(ran).to eq([:deferred])
    end
  end

  it 'does not run deferred blocks when the transaction block raises' do
    with_isolated_env(rack: 'development') do
      ran = []
      expect do
        ActiveRecord::Base.transaction do
          RaceGuard.after_commit { ran << :bad }
          raise 'boom'
        end
      end.to raise_error('boom')
      expect(ran).to be_empty
    end
  end

  it 'runs inner then outer deferred callbacks for nested successful transactions' do
    with_isolated_env(rack: 'development') do
      ran = []
      ActiveRecord::Base.transaction do
        RaceGuard.after_commit { ran << :outer }
        ActiveRecord::Base.transaction(requires_new: true) do
          RaceGuard.after_commit { ran << :inner }
        end
        expect(ran).to eq([:inner])
      end
      expect(ran).to eq(%i[inner outer])
    end
  end

  it 'does not run inner deferred when inner transaction raises' do
    with_isolated_env(rack: 'development') do
      ran = []
      ActiveRecord::Base.transaction do
        RaceGuard.after_commit { ran << :outer }
        begin
          ActiveRecord::Base.transaction(requires_new: true) do
            RaceGuard.after_commit { ran << :inner }
            raise 'inner'
          end
        rescue StandardError
          nil
        end
        expect(ran).to be_empty
      end
      expect(ran).to eq([:outer])
    end
  end

  it 'rescues errors from immediate after_commit' do
    with_isolated_env(rack: 'development') do
      expect { RaceGuard.after_commit { raise 'x' } }.not_to raise_error
    end
  end
end
