# frozen_string_literal: true

module RaceGuard
  SEVERITY_LEVELS = %i[info warn error raise].freeze

  # Epic 10 — enable with +RaceGuard.configure { |c| c.enable(:distributed_guard) }+.
  DISTRIBUTED_GUARD_FEATURE = :distributed_guard
end
