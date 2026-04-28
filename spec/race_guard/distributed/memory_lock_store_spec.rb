# frozen_string_literal: true

RSpec.describe RaceGuard::Distributed::MemoryLockStore do
  let(:store) { described_class.new }
  let(:key) { 'race_guard:distributed:v1:test' }
  let(:token) { 'owner-1' }

  it 'claims when key is free' do
    expect(store.claim(key: key, token: token, ttl: 10)).to be true
  end

  it 'does not claim when key is held' do
    expect(store.claim(key: key, token: token, ttl: 10)).to be true
    expect(store.claim(key: key, token: 'other', ttl: 10)).to be false
  end

  it 'releases only for matching token' do
    store.claim(key: key, token: token, ttl: 10)
    expect(store.release(key: key, token: 'nope')).to be false
    expect(store.release(key: key, token: token)).to be true
    expect(store.claim(key: key, token: 'new', ttl: 5)).to be true
  end

  it 'renews only for matching token' do
    store.claim(key: key, token: token, ttl: 1)
    expect(store.renew(key: key, token: 'nope', ttl: 10)).to be false
    expect(store.renew(key: key, token: token, ttl: 10)).to be true
    store.advance_time!(0.5)
    expect(store.claim(key: key, token: 'other', ttl: 1)).to be false
    store.advance_time!(11)
    expect(store.claim(key: key, token: 'other', ttl: 1)).to be true
  end

  it 'expires entries without wall-clock sleep' do
    store.claim(key: key, token: token, ttl: 2)
    store.advance_time!(3)
    expect(store.claim(key: key, token: 'next', ttl: 2)).to be true
  end
end
