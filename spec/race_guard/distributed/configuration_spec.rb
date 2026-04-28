# frozen_string_literal: true

RSpec.describe RaceGuard::Configuration, 'distributed guard (Epic 10)' do
  subject(:config) { described_class.new }

  it 'defaults distributed settings' do
    with_isolated_env(rack: 'development') do
      h = config.to_h
      expect(h[:distributed_skip_behavior]).to eq(:nil)
      expect(h[:distributed_reentrancy]).to eq(:skip)
      expect(h[:distributed_degrade_silently]).to be false
      expect(h[:distributed_lock_store_configured]).to be false
      expect(h[:distributed_redis_client_configured]).to be false
    end
  end

  it 'stores lock store and redis client' do
    store = Object.new
    client = Object.new
    config.distributed_lock_store(store)
    config.distributed_redis_client(client)
    expect(config.distributed_lock_store).to be(store)
    expect(config.distributed_redis_client).to be(client)
    h = config.to_h
    expect(h[:distributed_lock_store_configured]).to be true
    expect(h[:distributed_redis_client_configured]).to be true
  end

  it 'validates skip behavior' do
    expect { config.distributed_skip_behavior(:nope) }.to raise_error(ArgumentError, /invalid/)
    config.distributed_skip_behavior(:sentinel)
    expect(config.distributed_skip_behavior).to eq(:sentinel)
  end

  it 'validates reentrancy mode' do
    expect { config.distributed_reentrancy(:refcount) }.to raise_error(ArgumentError, /invalid/)
  end

  it 'toggles degrade silently' do
    expect(config.distributed_degrade_silently).to be false
    config.distributed_degrade_silently(true)
    expect(config.distributed_degrade_silently).to be true
  end
end
