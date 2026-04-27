# frozen_string_literal: true

namespace :race_guard do
  desc 'Check validates uniqueness has backing unique database indexes (Epic 5)'
  task index_integrity: :environment do
    require 'race_guard/index_integrity/runner'
    code = RaceGuard::IndexIntegrity::Runner.exit_code_for(Rails.root)
    exit(code) if code != 0
  end
end
