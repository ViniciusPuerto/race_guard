# frozen_string_literal: true

require 'active_record'
require 'sqlite3'
require 'race_guard'
require 'race_guard/active_record'

RSpec.describe 'RaceGuard ActiveRecord transaction tracking' do
  before do
    ActiveRecord::Base.establish_connection(
      adapter: 'sqlite3',
      database: ':memory:'
    )
    RaceGuard::ActiveRecord.install_transaction_tracking!
    RaceGuard.context.reset!
  end

  after do
    RaceGuard.context.reset!
    ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?
  end

  it 'increments context depth inside a transaction block' do
    ActiveRecord::Base.transaction do
      expect(RaceGuard.context.current).to be_in_transaction
    end
    expect(RaceGuard.context.current).not_to be_in_transaction
  end

  it 'handles nested transactions' do
    ActiveRecord::Base.transaction do
      expect(RaceGuard.context.current).to be_in_transaction
      ActiveRecord::Base.transaction do
        expect(RaceGuard.context.current).to be_in_transaction
      end
      expect(RaceGuard.context.current).to be_in_transaction
    end
    expect(RaceGuard.context.current).not_to be_in_transaction
  end

  it 'handles requires_new: true inner transaction' do
    ActiveRecord::Base.transaction do
      expect(RaceGuard.context.current).to be_in_transaction
      ActiveRecord::Base.transaction(requires_new: true) do
        expect(RaceGuard.context.current).to be_in_transaction
      end
      expect(RaceGuard.context.current).to be_in_transaction
    end
    expect(RaceGuard.context.current).not_to be_in_transaction
  end

  it 'restores depth when inner block raises' do
    expect do
      ActiveRecord::Base.transaction do
        expect(RaceGuard.context.current).to be_in_transaction
        ActiveRecord::Base.transaction do
          raise 'inner boom'
        end
      end
    end.to raise_error('inner boom')

    expect(RaceGuard.context.current).not_to be_in_transaction
  end

  it 'keeps outer depth when inner raises and outer rescues' do
    ActiveRecord::Base.transaction do
      expect(RaceGuard.context.current).to be_in_transaction
      begin
        ActiveRecord::Base.transaction do
          raise 'inner'
        end
      rescue StandardError
        # swallow
      end
      expect(RaceGuard.context.current).to be_in_transaction
    end
    expect(RaceGuard.context.current).not_to be_in_transaction
  end

  it 'does not change context when no block is passed (delegates to AR)' do
    expect { ActiveRecord::Base.transaction }.to raise_error(LocalJumpError)
    expect(RaceGuard.context.current).not_to be_in_transaction
  end

  it 'install_transaction_tracking! is idempotent' do
    2.times { RaceGuard::ActiveRecord.install_transaction_tracking! }
    ActiveRecord::Base.transaction { expect(RaceGuard.context.current).to be_in_transaction }
  end
end
