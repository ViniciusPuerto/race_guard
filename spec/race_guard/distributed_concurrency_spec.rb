# frozen_string_literal: true

RSpec.describe 'RaceGuard distributed guard concurrency' do
  include EnvSpecHelpers

  after do
    RaceGuard.reset_configuration!
    RaceGuard.context.reset!
  end

  it 'runs the block exactly once while losers contend concurrently' do
    with_isolated_env(rack: 'development') do
      store = RaceGuard::Distributed::MemoryLockStore.new
      RaceGuard.configure do |c|
        c.enable(:distributed_guard)
        c.distributed_lock_store(store)
      end

      runs = 0
      mutex = Mutex.new
      ready = Queue.new
      gate = Queue.new

      losers = Array.new(19) do
        Thread.new do
          ready << true
          gate.pop
          RaceGuard.distributed_once('fleet_job', ttl: 30) { mutex.synchronize { runs += 1 } }
        end
      end

      19.times { ready.pop }

      RaceGuard.distributed_once('fleet_job', ttl: 300) do
        19.times { gate << :go }
        losers.each(&:join)
        mutex.synchronize { runs += 1 }
      end

      expect(runs).to eq(1)
    end
  end
end
