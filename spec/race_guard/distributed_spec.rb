# frozen_string_literal: true

require 'json'
require 'stringio'

RSpec.describe 'RaceGuard.distributed_once' do
  include EnvSpecHelpers

  after do
    RaceGuard.reset_configuration!
    RaceGuard.context.reset!
  end

  it 'raises without a block' do
    expect { RaceGuard.distributed_once('x', ttl: 1) }.to raise_error(ArgumentError, /block/)
  end

  it 'runs the block when the feature is disabled (pass-through)' do
    with_isolated_env(rack: 'development') do
      RaceGuard.configure { |c| c.distributed_lock_store(RaceGuard::Distributed::MemoryLockStore.new) }
      ran = false
      RaceGuard.distributed_once('job', ttl: 10) { ran = true }
      expect(ran).to be true
    end
  end

  it 'runs the block when enabled but environment inactive' do
    with_isolated_env(rack: 'production') do
      RaceGuard.configure do |c|
        c.enable(:distributed_guard)
        c.distributed_lock_store(RaceGuard::Distributed::MemoryLockStore.new)
      end
      ran = false
      RaceGuard.distributed_once('job', ttl: 10) { ran = true }
      expect(ran).to be true
    end
  end

  it 'claims, runs, and releases with reporting' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      store = RaceGuard::Distributed::MemoryLockStore.new
      RaceGuard.configure do |c|
        c.enable(:distributed_guard)
        c.distributed_lock_store(store)
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
      end
      out = RaceGuard.distributed_once('cron', ttl: 60, resource: 'a') { :ok }
      expect(out).to eq(:ok)
      lines = io.string.lines.map { |l| JSON.parse(l) }
      types = lines.map { |j| j['context']['event'] }
      expect(types).to include('claimed', 'released')
    end
  end

  it 'returns nil on lost race by default' do
    with_isolated_env(rack: 'development') do
      store = RaceGuard::Distributed::MemoryLockStore.new
      RaceGuard.configure do |c|
        c.enable(:distributed_guard)
        c.distributed_lock_store(store)
      end
      lk = RaceGuard::Distributed::KeyBuilder.build(name: 'k')
      store.claim(key: lk, token: 'foreign', ttl: 120)
      v = RaceGuard.distributed_once('k', ttl: 60) { :second }
      expect(v).to be_nil
    end
  end

  it 'supports on_skip sentinel' do
    with_isolated_env(rack: 'development') do
      store = RaceGuard::Distributed::MemoryLockStore.new
      RaceGuard.configure do |c|
        c.enable(:distributed_guard)
        c.distributed_lock_store(store)
      end
      lk = RaceGuard::Distributed::KeyBuilder.build(name: 'k')
      store.claim(key: lk, token: 'foreign', ttl: 120)
      v = RaceGuard.distributed_once('k', ttl: 60, on_skip: :sentinel) { :second }
      expect(v).to be(RaceGuard::Distributed::SKIPPED)
    end
  end

  it 'raises LockNotAcquiredError when on_skip is raise' do
    with_isolated_env(rack: 'development') do
      store = RaceGuard::Distributed::MemoryLockStore.new
      RaceGuard.configure do |c|
        c.enable(:distributed_guard)
        c.distributed_lock_store(store)
      end
      lk = RaceGuard::Distributed::KeyBuilder.build(name: 'k')
      store.claim(key: lk, token: 'foreign', ttl: 120)
      expect do
        RaceGuard.distributed_once('k', ttl: 60, on_skip: :raise) { :second }
      end.to raise_error(RaceGuard::Distributed::LockNotAcquiredError)
    end
  end

  it 'releases after the block raises' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      store = RaceGuard::Distributed::MemoryLockStore.new
      RaceGuard.configure do |c|
        c.enable(:distributed_guard)
        c.distributed_lock_store(store)
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
      end
      expect do
        RaceGuard.distributed_once('k', ttl: 60) { raise 'boom' }
      end.to raise_error('boom')
      lines = io.string.lines.map { |l| JSON.parse(l) }
      expect(lines.map { |j| j['context']['event'] }).to include('released')
    end
  end

  it 'skips nested same-key calls when reentrancy is skip' do
    with_isolated_env(rack: 'development') do
      store = RaceGuard::Distributed::MemoryLockStore.new
      RaceGuard.configure do |c|
        c.enable(:distributed_guard)
        c.distributed_lock_store(store)
      end
      inner = nil
      RaceGuard.distributed_once('k', ttl: 60) do
        inner = RaceGuard.distributed_once('k', ttl: 60) { :inner }
      end
      expect(inner).to be_nil
    end
  end

  it 'yields LockControl for renew' do
    with_isolated_env(rack: 'development') do
      store = RaceGuard::Distributed::MemoryLockStore.new
      RaceGuard.configure do |c|
        c.enable(:distributed_guard)
        c.distributed_lock_store(store)
      end
      RaceGuard.distributed_once('k', ttl: 2) do |ctl|
        expect(ctl.renew(10)).to be true
      end
    end
  end

  it 'reports configuration_error when enabled without store and raises via severity' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      RaceGuard.configure do |c|
        c.enable(:distributed_guard)
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
        c.severity(:distributed_guard, :raise)
      end
      expect do
        RaceGuard.distributed_once('k', ttl: 10) { :nope }
      end.to raise_error(RaceGuard::ReportRaisedError)
      h = JSON.parse(io.string.lines.first)
      expect(h['context']['event']).to eq('configuration_error')
    end
  end

  it 'distributed_protect is an alias' do
    with_isolated_env(rack: 'development') do
      RaceGuard.configure do |c|
        c.enable(:distributed_guard)
        c.distributed_lock_store(RaceGuard::Distributed::MemoryLockStore.new)
      end
      v = RaceGuard.distributed_protect('x', ttl: 5) { 42 }
      expect(v).to eq(42)
    end
  end
end
