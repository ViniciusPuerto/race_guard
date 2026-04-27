# frozen_string_literal: true

require 'json'
require 'stringio'

RSpec.describe 'RaceGuard.report' do
  after do
    RaceGuard.reset_configuration!
  end

  it 'is a no-op when the environment is inactive' do
    with_isolated_env(rack: 'production') do
      io = StringIO.new
      RaceGuard.configure { |c| c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io)) }
      RaceGuard.report(detector: 'x', message: 'y', severity: :info)
      expect(io.string).to be_empty
    end
  end

  it 'fans out to every registered reporter' do
    with_isolated_env(rack: 'development') do
      a = StringIO.new
      b = StringIO.new
      ra = RaceGuard::Reporters::JsonReporter.new(a)
      rb = RaceGuard::Reporters::JsonReporter.new(b)
      RaceGuard.configure do |c|
        c.add_reporter(ra)
        c.add_reporter(rb)
      end
      RaceGuard.report('detector' => 'a', 'message' => 'b', 'severity' => 'warn')
      [a, b].each { |io| expect(io.string).to include('a').and include('warn') }
    end
  end

  it 'keeps other reporters when one raises' do
    with_isolated_env(rack: 'development') do
      ok = StringIO.new
      bad = Class.new do
        def report(_event)
          raise 'boom'
        end
      end
      RaceGuard.configure do |c|
        c.add_reporter(bad.new)
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(ok))
      end
      expect { RaceGuard.report(detector: 'x', message: 'y', severity: :info) }.not_to raise_error
      expect(ok.string).to include('x')
    end
  end

  it 'raises ReportRaisedError after reporters when severity is :raise' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      RaceGuard.configure { |c| c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io)) }
      report_raise = proc do
        RaceGuard.report(detector: 'd', message: 'boom', severity: :raise, location: 't.rb:3')
      end
      expect(&report_raise).to raise_error(RaceGuard::ReportRaisedError) do |err|
        expect(err.event).to be_a(RaceGuard::Event)
        expect(err.event.detector).to eq('d')
        expect(err.message).to include('d').and include('boom').and include('t.rb:3')
      end
      h = JSON.parse(io.string.chomp)
      expect(h['severity']).to eq('raise')
      expect(h['detector']).to eq('d')
    end
  end

  it 'does not raise when inactive even if severity is :raise' do
    with_isolated_env(rack: 'production') do
      io = StringIO.new
      RaceGuard.configure { |c| c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io)) }
      expect { RaceGuard.report(detector: 'x', message: 'y', severity: :raise) }.not_to raise_error
      expect(io.string).to be_empty
    end
  end
end
