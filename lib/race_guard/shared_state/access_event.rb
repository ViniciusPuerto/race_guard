# frozen_string_literal: true

module RaceGuard
  module SharedState
    # Normalized access for Epic 6.2–6.3 (tests and TracePoint adapters).
    AccessEvent = Struct.new(:kind, :key, :path, :lineno, :thread, keyword_init: true)
  end
end
