# frozen_string_literal: true

require 'json'
require 'logger'
require 'tmpdir'

RSpec.describe 'RaceGuard reporters' do
  def event
    RaceGuard::Event.new(detector: 't', message: 'm', severity: :warn, location: 'f:1')
  end

  it 'log reporter writes a line' do
    io = StringIO.new
    logger = Logger.new(io)
    RaceGuard::Reporters::LogReporter.new(logger).report(event)
    expect(io.string).to include('WARN').and include('t').and include('m').and include('f:1')
  end

  it 'log reporter emits suggested_fix on a second line when present in context' do
    io = StringIO.new
    logger = Logger.new(io)
    e = RaceGuard::Event.new(
      detector: 't',
      message: 'm',
      severity: :warn,
      location: 'app/x.rb:10',
      context: { 'suggested_fix' => 'Use a mutex around shared state.' }
    )
    RaceGuard::Reporters::LogReporter.new(logger).report(e)
    lines = io.string.lines.map(&:chomp).reject(&:empty?)
    expect(lines[0]).to include('WARN').and include('t').and include('m').and include('app/x.rb:10')
    expect(lines[1]).to include('suggested_fix').and include('mutex')
  end

  it 'json reporter writes a JSON line' do
    io = StringIO.new
    RaceGuard::Reporters::JsonReporter.new(io).report(event)
    line = io.string.chomp
    h = JSON.parse(line)
    expect(h['detector']).to eq('t')
  end

  it 'file reporter appends' do
    path = File.join(Dir.mktmpdir, 'r.jsonl')
    RaceGuard::Reporters::FileReporter.new(path).report(event)
    line = File.read(path).chomp
    expect(JSON.parse(line)['message']).to eq('m')
  end

  it 'webhook uses injected http' do
    body_seen = nil
    uri_seen = nil
    http = lambda do |uri, body|
      uri_seen = uri
      body_seen = body
    end
    r = RaceGuard::Reporters::WebhookReporter.new('http://example.com/hook', http_request: http)
    r.report(event)
    expect(uri_seen.to_s).to include('example.com')
    expect(JSON.parse(body_seen)['detector']).to eq('t')
  end
end
