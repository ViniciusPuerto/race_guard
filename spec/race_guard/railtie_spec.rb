# frozen_string_literal: true

require 'rails/railtie'
require 'race_guard/railtie'

RSpec.describe RaceGuard::Railtie do
  it 'inherits Rails::Railtie' do
    expect(described_class.superclass).to eq(Rails::Railtie)
  end
end
