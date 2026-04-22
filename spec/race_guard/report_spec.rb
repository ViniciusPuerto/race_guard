# frozen_string_literal: true

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
end
