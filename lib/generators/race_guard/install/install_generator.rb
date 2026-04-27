# frozen_string_literal: true

require 'rails/generators'

module RaceGuard
  module Generators
    # Copies `config/initializers/race_guard.rb` for app-level configuration.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      def copy_initializer
        template 'race_guard.rb', 'config/initializers/race_guard.rb'
      end
    end
  end
end
