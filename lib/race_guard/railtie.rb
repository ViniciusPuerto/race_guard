# frozen_string_literal: true

module RaceGuard
  # Loads rake tasks when the host application uses Rails (Epic 5.4).
  class Railtie < ::Rails::Railtie
    rake_tasks do
      load File.expand_path('../tasks/race_guard/index_integrity.rake', __dir__)
    end
  end
end
