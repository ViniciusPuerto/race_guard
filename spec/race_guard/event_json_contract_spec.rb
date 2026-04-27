# frozen_string_literal: true

require 'json'
require 'stringio'

RSpec.describe 'RaceGuard Event JSON contract' do
  let(:schema_path) do
    File.expand_path('../../docs/schemas/race_guard_report_event.json', __dir__)
  end

  let(:required_keys) do
    JSON.parse(File.read(schema_path))['required']
  end

  let(:event_min) do
    RaceGuard::Event.new(detector: 'd', message: 'msg', severity: :info)
  end

  it 'Event#to_h includes all schema-required keys' do
    h = event_min.to_h
    expect(required_keys - h.keys).to eq([])
  end

  it 'Event#to_h uses expected types for core fields' do
    h = event_min.to_h
    expect(h['detector']).to be_a(String)
    expect(h['message']).to be_a(String)
    expect(h['severity']).to be_a(String).and match(/\A(info|warn|error|raise)\z/)
    expect(h['timestamp']).to be_a(String).and start_with('20')
    expect(h['context']).to be_a(Hash)
  end

  it 'JsonReporter writes one parseable object per line with the same contract' do
    io = StringIO.new
    e = RaceGuard::Event.new(
      detector: 'x',
      message: 'y',
      severity: :warn,
      location: 'f.rb:1',
      thread_id: '99',
      context: { 'suggested_fix' => 'do z' }
    )
    RaceGuard::Reporters::JsonReporter.new(io).report(e)
    h = JSON.parse(io.string.chomp)
    expect(required_keys - h.keys).to eq([])
    expect(h['location']).to eq('f.rb:1')
    expect(h['thread_id']).to eq('99')
    expect(h['context']['suggested_fix']).to eq('do z')
  end
end
