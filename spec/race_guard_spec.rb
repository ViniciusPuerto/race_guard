# frozen_string_literal: true

RSpec.describe RaceGuard do
  describe '.configure' do
    it 'yields a configuration object' do
      yielded = nil
      described_class.configure { |c| yielded = c }
      expect(yielded).to be_a(RaceGuard::Configuration)
    end
  end
end
