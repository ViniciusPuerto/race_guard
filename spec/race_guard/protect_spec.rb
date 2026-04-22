# frozen_string_literal: true

require 'json'
require 'stringio'

RSpec.describe 'RaceGuard.protect' do
  include EnvSpecHelpers

  after do
    RaceGuard.reset_configuration!
    RaceGuard.context.reset!
  end

  it 'raises without a block' do
    expect { RaceGuard.protect(:x) }.to raise_error(ArgumentError, /block/)
  end

  it 'supports nested blocks and restores the stack' do
    RaceGuard.protect(:outer) do
      expect(RaceGuard.context.current.protected_blocks).to eq(%i[outer])
      RaceGuard.protect(:inner) do
        expect(RaceGuard.context.current.protected_blocks).to eq(%i[outer inner])
      end
      expect(RaceGuard.context.current.protected_blocks).to eq(%i[outer])
    end
    expect(RaceGuard.context.current.protected_blocks).to eq([])
  end

  it 'pops the stack when the block raises' do
    expect do
      RaceGuard.protect(:bad) { raise 'boom' }
    end.to raise_error('boom')
    expect(RaceGuard.context.current.protected_blocks).to eq([])
  end

  it 'merges protect into report context when active' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      RaceGuard.configure { |c| c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io)) }
      RaceGuard.protect(:payment_flow) do
        RaceGuard.report(detector: 't', message: 'm', severity: :info)
      end
      ctx = JSON.parse(io.string)['context']
      expect(ctx['protect']).to eq('payment_flow')
      expect(ctx['protect_stack']).to eq(['payment_flow'])
    end
  end

  it 'reports innermost protect name when nested' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      RaceGuard.configure { |c| c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io)) }
      RaceGuard.protect(:outer) do
        RaceGuard.protect(:inner) do
          RaceGuard.report(detector: 't', message: 'm', severity: :warn)
        end
      end
      ctx = JSON.parse(io.string)['context']
      expect(ctx['protect']).to eq('inner')
      expect(ctx['protect_stack']).to eq(%w[outer inner])
    end
  end

  it 'notifies protect detectors on enter and exit' do
    log = []
    detector = Object.new
    detector.define_singleton_method(:on_protect_enter) { |name| log << [:enter, name] }
    detector.define_singleton_method(:on_protect_exit) { |name| log << [:exit, name] }

    RaceGuard.configure { |c| c.add_protect_detector(detector) }
    RaceGuard.protect(:a) { log << :yield }
    expect(log).to eq([%i[enter a], :yield, %i[exit a]])
  end
end
