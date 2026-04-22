# frozen_string_literal: true

require 'race_guard'

module EnvSpecHelpers
  def with_isolated_env(rack: nil, rails: nil)
    previous = {
      'RACK_ENV' => ENV.fetch('RACK_ENV', nil),
      'RAILS_ENV' => ENV.fetch('RAILS_ENV', nil)
    }
    set_env_pair(rack, rails)
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def set_env_pair(rack, rails)
    if rack
      ENV['RACK_ENV'] = rack
    else
      ENV.delete('RACK_ENV')
    end
    if rails
      ENV['RAILS_ENV'] = rails
    else
      ENV.delete('RAILS_ENV')
    end
  end
end

RSpec.configure do |config|
  config.include EnvSpecHelpers

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed
end
