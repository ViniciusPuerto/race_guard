# frozen_string_literal: true

# Avoid client/server mode when the cache dir is unavailable (e.g. CI, sandboxes).
ENV['RUBOCOP_DISABLE_SERVER'] = '1'

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

task default: %i[spec rubocop]
