# frozen_string_literal: true

require 'active_record'
require 'sqlite3'
require 'race_guard'

RSpec.describe RaceGuard::Railtie do
  after do
    next unless defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?

    ActiveRecord::Base.connection_pool.disconnect!
  end

  it 'inherits Rails::Railtie' do
    expect(described_class.superclass).to eq(Rails::Railtie)
  end

  it 'installs ActiveRecord transaction tracking when ActiveRecord loads' do
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    expect(ActiveRecord::Base.singleton_class.ancestors).to include(RaceGuard::ActiveRecord::TransactionPatch)
    expect(ActiveRecord::Base.ancestors).to include(RaceGuard::DBLockAuditor::ReadModifyWrite::Patches)
  end
end
