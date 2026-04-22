# frozen_string_literal: true

require_relative 'lib/race_guard/version'

Gem::Specification.new do |spec|
  spec.name = 'race_guard'
  spec.version = RaceGuard::VERSION
  spec.authors = ['race_guard contributors']
  spec.email = ['race_guard@users.noreply.github.com']
  spec.summary = 'Runtime and static analysis for race conditions in Ruby applications.'
  spec.description = 'Detects race conditions in Ruby/Rails apps via static and ' \
                     'runtime analysis, with an extensible API.'
  spec.homepage = 'https://github.com/race_guard/race_guard'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = [__FILE__, 'README.md', 'LICENSE.txt'] + Dir['lib/**/*.rb']
  spec.bindir = 'exe'
  spec.executables = []
  spec.require_paths = ['lib']

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
end
