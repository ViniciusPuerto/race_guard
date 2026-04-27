# frozen_string_literal: true

require_relative 'lib/race_guard/version'

Gem::Specification.new do |spec| # rubocop:disable Metrics/BlockLength -- gemspec DSL
  spec.name = 'race_guard'
  spec.version = RaceGuard::VERSION
  spec.authors = ['Vinicius Porto']
  spec.email = ['vinicius.alves.porto@gmail.com']
  spec.summary = 'Runtime and static analysis for race conditions in Ruby applications.'
  spec.description = 'Detects race conditions in Ruby/Rails apps via static and ' \
                     'runtime analysis, with an extensible API.'
  spec.homepage = 'https://github.com/ViniciusPuerto/race_guard'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['documentation_uri'] = "#{spec.homepage}#readme"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files =
    [__FILE__, 'README.md', 'LICENSE.txt', 'docs/assets/race-guard-logo.png'] +
    Dir['lib/**/*.rb'] + Dir['lib/**/*.rake'] + Dir['lib/**/*.tt']
  spec.bindir = 'exe'
  spec.executables = []
  spec.require_paths = ['lib']

  spec.add_dependency 'logger', '>= 1.0'
  spec.add_dependency 'parser', '>= 3.3', '< 4'

  spec.add_development_dependency 'actionmailer', '>= 7.0', '< 8'
  spec.add_development_dependency 'activejob', '>= 7.0', '< 8'
  spec.add_development_dependency 'activerecord', '>= 7.0', '< 8'
  spec.add_development_dependency 'faraday', '>= 1.0'
  spec.add_development_dependency 'railties', '>= 7.0', '< 8'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
  spec.add_development_dependency 'sqlite3', '>= 1.6'
end # rubocop:enable Metrics/BlockLength
