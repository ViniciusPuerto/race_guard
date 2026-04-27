# frozen_string_literal: true

begin
  require 'rails/railtie'
rescue LoadError
  # Non-Rails apps: no Railtie (railties gem not present).
else
  require_relative 'active_record'

  module RaceGuard
    # Rails integration: rake tasks, ActiveRecord hooks after AR loads, install generator.
    class Railtie < ::Rails::Railtie
      rake_tasks do
        load File.expand_path('../tasks/race_guard/index_integrity.rake', __dir__)
      end

      ActiveSupport.on_load(:active_record) do
        RaceGuard::ActiveRecord.install_transaction_tracking!
        RaceGuard::DBLockAuditor::ReadModifyWrite.install!
      end
    end
  end
end
