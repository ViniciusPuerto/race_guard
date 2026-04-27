# frozen_string_literal: true

require_relative 'shared_state/access_event'
require_relative 'shared_state/mutex_stack'
require_relative 'shared_state/conflict_tracker'
require_relative 'shared_state/memo_scanner'
require_relative 'shared_state/memo_registry'
require_relative 'shared_state/watcher'
require_relative 'shared_state/trace_point'

module RaceGuard
  module SharedState
    @multi_mutex = Mutex.new
    @multi_threaded = false

    def self.reset!
      @multi_mutex ||= Mutex.new
      @multi_mutex.synchronize { @multi_threaded = false }
      Watcher.reset!
      MemoRegistry.reset!
    end

    def self.mark_multi_threaded!
      @multi_mutex ||= Mutex.new
      @multi_mutex.synchronize { @multi_threaded = true }
    end

    def self.multi_threaded?
      @multi_mutex ||= Mutex.new
      @multi_mutex.synchronize { @multi_threaded }
    end
  end
end
