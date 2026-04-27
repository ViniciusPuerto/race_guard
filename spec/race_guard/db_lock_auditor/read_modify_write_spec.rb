# frozen_string_literal: true

require 'active_record'
require 'json'
require 'sqlite3'
require 'stringio'
require 'race_guard'
require 'race_guard/active_record'

RSpec.describe 'RaceGuard DB read-modify-write (4.1 / 4.2)' do
  include EnvSpecHelpers

  before do
    ActiveRecord::Base.establish_connection(
      adapter: 'sqlite3',
      database: ':memory:'
    )
    ActiveRecord::Schema.define do
      create_table :rmw_wallets, force: true do |t|
        t.integer :balance, default: 0
        t.string :name
      end
      create_table :rmw_others, force: true do |t|
        t.integer :x, default: 0
      end
    end

    k = Object.const_set(:"RmwWallet#{object_id}", Class.new(ActiveRecord::Base) do
      self.table_name = 'rmw_wallets'
    end)
    o = Object.const_set(:"RmwOther#{object_id}", Class.new(ActiveRecord::Base) do
      self.table_name = 'rmw_others'
    end)
    @wallet_class = k
    @other_class = o

    RaceGuard::ActiveRecord.install_transaction_tracking!
    RaceGuard::DBLockAuditor::ReadModifyWrite.install!
    RaceGuard.context.reset!
  end

  after do
    RaceGuard.context.reset!
    RaceGuard.reset_configuration!
    ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?
  end

  let(:wallet_class) { @wallet_class }
  let(:other_class) { @other_class }

  it 'reports read-modify-write for a configured model' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      RaceGuard.configure do |c|
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
        c.severity(:'db_lock_auditor:read_modify_write', :warn)
        c.db_lock_read_modify_write_models(wallet_class)
      end
      w = wallet_class.create!(balance: 10, name: 'a')
      _v = w.balance
      w.update!(balance: w.balance - 1)

      lines = io.string.lines.map { |l| JSON.parse(l) }
      expect(lines.size).to eq(1)
      expect(lines[0]['detector']).to eq('db_lock_auditor:read_modify_write')
      expect(lines[0]['message']).to include('Rmw', 'balance')
      expect(lines[0]['context']['model']).to include('Rmw') # RmwWalletNNN
      expect(lines[0]['context']['attribute']).to eq('balance')
    end
  end

  it 'does not report when the attribute was not read first' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      RaceGuard.configure do |c|
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
        c.db_lock_read_modify_write_models(wallet_class)
      end
      w = wallet_class.create!(balance: 1)
      w.update!(balance: 0)

      expect(io.string).to be_empty
    end
  end

  it 'ignores non-configured models' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      RaceGuard.configure do |c|
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
        c.db_lock_read_modify_write_models(wallet_class)
      end
      o = other_class.create!(x: 1)
      _a = o.x
      o.update!(x: 2)

      expect(io.string).to be_empty
    end
  end

  it 'does not report when the read is older than the journal TTL' do
    with_isolated_env(rack: 'development') do
      stub_const('RaceGuard::Context::MutableStore::RMW_TTL_SEC', 0.05)
      io = StringIO.new
      RaceGuard.configure do |c|
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
        c.db_lock_read_modify_write_models(wallet_class)
      end
      w = wallet_class.create!(balance: 5)
      w.balance
      sleep 0.1
      w.update!(balance: 0)

      expect(io.string).to be_empty
    end
  end

  it 'does not use reads from another thread' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      RaceGuard.configure do |c|
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
        c.db_lock_read_modify_write_models(wallet_class)
      end
      w = wallet_class.create!(balance: 3)
      t = Thread.new { w.balance }
      t.join
      w.update!(balance: 0)

      expect(io.string).to be_empty
    end
  end

  describe 'lock awareness (4.2)' do
    it 'does not report RMW when read and save are inside with_lock' do
      with_isolated_env(rack: 'development') do
        io = StringIO.new
        RaceGuard.configure do |c|
          c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
          c.severity(:'db_lock_auditor:read_modify_write', :warn)
          c.db_lock_read_modify_write_models(wallet_class)
        end
        w = wallet_class.create!(balance: 10)
        w.with_lock do
          b = w.balance
          w.update!(balance: b - 1)
        end
        expect(io.string).to be_empty
      end
    end

    it 'does not report when read is outside and save uses a captured value inside with_lock' do
      with_isolated_env(rack: 'development') do
        io = StringIO.new
        RaceGuard.configure do |c|
          c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
          c.severity(:'db_lock_auditor:read_modify_write', :warn)
          c.db_lock_read_modify_write_models(wallet_class)
        end
        w = wallet_class.create!(balance: 7)
        v = w.balance
        w.with_lock { w.update!(balance: v - 1) }
        expect(io.string).to be_empty
      end
    end

    it 'does not report with nested with_lock on the same record' do
      with_isolated_env(rack: 'development') do
        io = StringIO.new
        RaceGuard.configure do |c|
          c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
          c.severity(:'db_lock_auditor:read_modify_write', :warn)
          c.db_lock_read_modify_write_models(wallet_class)
        end
        w = wallet_class.create!(balance: 3)
        w.with_lock do
          w.with_lock do
            b = w.balance
            w.update!(balance: b - 1)
          end
        end
        expect(io.string).to be_empty
      end
    end

    it 'does not report when lock! then read-modify-write inside AR transaction' do
      with_isolated_env(rack: 'development') do
        io = StringIO.new
        RaceGuard.configure do |c|
          c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
          c.severity(:'db_lock_auditor:read_modify_write', :warn)
          c.db_lock_read_modify_write_models(wallet_class)
        end
        w = wallet_class.create!(balance: 4)
        ActiveRecord::Base.transaction do
          w.lock!
          w.update!(balance: w.balance - 1)
        end
        expect(io.string).to be_empty
      end
    end

    it 'still reports RMW for another model when a tracked model was updated under with_lock' do
      with_isolated_env(rack: 'development') do
        io = StringIO.new
        RaceGuard.configure do |c|
          c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
          c.severity(:'db_lock_auditor:read_modify_write', :warn)
          c.db_lock_read_modify_write_models(wallet_class, other_class)
        end
        w = wallet_class.create!(balance: 1)
        o = other_class.create!(x: 1)
        w.with_lock { w.update!(balance: 2) }
        _a = o.x
        o.update!(x: 0)

        lines = io.string.lines.map { |l| JSON.parse(l) }
        expect(lines.size).to eq(1)
        expect(lines[0]['context']['model']).to include('RmwOther')
        expect(lines[0]['context']['attribute']).to eq('x')
      end
    end
  end
end
