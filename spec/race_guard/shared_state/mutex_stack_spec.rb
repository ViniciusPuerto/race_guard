# frozen_string_literal: true

require 'race_guard'

RSpec.describe RaceGuard::SharedState::MutexStack do
  describe '.mutex_protected?' do
    it 'is true when called from inside Mutex#synchronize' do
      m = Mutex.new
      m.synchronize do
        expect(described_class.mutex_protected?).to be(true)
      end
    end

    it 'is false outside Mutex#synchronize' do
      expect(described_class.mutex_protected?).to be(false)
    end
  end
end
