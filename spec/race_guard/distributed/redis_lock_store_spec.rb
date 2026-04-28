# frozen_string_literal: true

# Fake Redis client for command-shape contract (not a real server).
# rubocop:disable Metrics/MethodLength, Naming/PredicateMethod, Naming/MethodParameterName
RSpec.describe RaceGuard::Distributed::RedisLockStore do
  let(:commands) { [] }
  let(:storage) { {} }

  let(:fake_redis) do
    log = commands
    st = storage
    Class.new do
      def initialize(log, storage)
        @log = log
        @h = storage
      end

      def set(key, value, nx:, ex:)
        @log << [:set, key, value, nx, ex]
        if nx && @h[key]
          false
        else
          @h[key] = { value: value, ex: ex }
          true
        end
      end

      def eval(script, keys:, argv:)
        @log << [:eval, script, keys, argv]
        key = keys.first
        token = argv[0]
        rec = @h[key]
        return 0 unless rec && rec[:value] == token

        if script.include?('expire')
          ttl = argv[1].to_i
          rec[:ex] = ttl
          1
        elsif script.include?('del')
          @h.delete(key)
          1
        else
          0
        end
      end
    end.new(log, st)
  end

  let(:store) { described_class.new(fake_redis) }

  it 'claims with SET NX EX shape' do
    expect(store.claim(key: 'k', token: 'tok', ttl: 30)).to be true
    expect(commands.first).to eq([:set, 'k', 'tok', true, 30])
  end

  it 'returns false when SET NX loses' do
    store.claim(key: 'k', token: 'a', ttl: 10)
    commands.clear
    expect(store.claim(key: 'k', token: 'b', ttl: 10)).to be false
    expect(commands.first).to eq([:set, 'k', 'b', true, 10])
  end

  it 'renews via Lua using keys/argv' do
    store.claim(key: 'k', token: 'tok', ttl: 10)
    commands.clear
    expect(store.renew(key: 'k', token: 'tok', ttl: 60)).to be true
    expect(commands.size).to eq(1)
    _cmd, script, keys, argv = commands.first
    expect(keys).to eq(['k'])
    expect(argv).to eq(%w[tok 60])
    expect(script).to include('get').and include('expire')
  end

  it 'releases via Lua compare-and-delete' do
    store.claim(key: 'k', token: 'tok', ttl: 10)
    commands.clear
    expect(store.release(key: 'k', token: 'tok')).to be true
    _cmd, script, keys, argv = commands.first
    expect(keys).to eq(['k'])
    expect(argv).to eq(['tok'])
    expect(script).to include('get').and include('del')
  end
end
# rubocop:enable Metrics/MethodLength, Naming/PredicateMethod, Naming/MethodParameterName
