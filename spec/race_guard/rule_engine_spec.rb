# frozen_string_literal: true

require 'json'
require 'stringio'

RSpec.describe 'RaceGuard rule engine' do
  include EnvSpecHelpers

  after do
    RaceGuard::RuleEngine.reset_registry!
    RaceGuard.reset_configuration!
    RaceGuard.context.reset!
  end

  it 'defines a rule with detect and message' do
    RaceGuard.define_rule(:r1) do |r|
      r.detect { |_ctx, _meta| false }
      r.message { |_ctx, _meta| 'nope' }
    end
    expect(RaceGuard::RuleEngine.rule_defined?(:r1)).to be true
  end

  it 'raises when detect is missing' do
    expect do
      RaceGuard.define_rule(:bad) do |r|
        r.message { 'x' }
      end
    end.to raise_error(ArgumentError, /detect/)
  end

  it 'raises when message is missing' do
    expect do
      RaceGuard.define_rule(:bad) do |r|
        r.detect { false }
      end
    end.to raise_error(ArgumentError, /message/)
  end

  it 'raises on duplicate rule name' do
    RaceGuard.define_rule(:dup) do |r|
      r.detect { false }
      r.message { 'm' }
    end
    expect do
      RaceGuard.define_rule(:dup) do |r|
        r.detect { false }
        r.message { 'm' }
      end
    end.to raise_error(ArgumentError, /already defined/)
  end

  it 'rejects unknown hook event' do
    expect do
      RaceGuard.define_rule(:bad) do |r|
        r.hook(:nope) { |_c, _m| nil }
        r.detect { false }
        r.message { 'm' }
      end
    end.to raise_error(ArgumentError, /unknown rule event/)
  end

  it 'allows enable_rule and enabled_rule? in active environment' do
    with_isolated_env(rack: 'development') do
      cfg = RaceGuard.configuration
      expect(cfg).not_to be_enabled_rule(:my_rule)
      cfg.enable_rule(:my_rule)
      expect(cfg).to be_enabled_rule(:my_rule)
      cfg.disable_rule(:my_rule)
      expect(cfg).not_to be_enabled_rule(:my_rule)
    end
  end

  it 'treats rules as disabled when environment is inactive' do
    with_isolated_env(rack: 'production') do
      cfg = RaceGuard.configuration
      cfg.environments(:development, :test)
      cfg.enable_rule(:x)
      expect(cfg).not_to be_enabled_rule(:x)
    end
  end

  it 'evaluate runs detect/message when rule is enabled' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      RaceGuard.configure do |c|
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
        c.enable_rule(:flagged)
      end

      RaceGuard.define_rule(:flagged) do |r|
        r.detect { |_ctx, meta| meta[:force] }
        r.message { |_ctx, _meta| 'violation' }
      end

      RaceGuard::RuleEngine.evaluate(:flagged, metadata: { force: false })
      expect(io.string).to eq('')

      RaceGuard::RuleEngine.evaluate(:flagged, metadata: { force: true })
      line = JSON.parse(io.string.lines.last)
      expect(line['detector']).to eq('flagged')
      expect(line['message']).to eq('violation')
    end
  end

  it 'evaluate is a no-op when rule is disabled' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      RaceGuard.configure { |c| c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io)) }

      RaceGuard.define_rule(:silent) do |r|
        r.detect { true }
        r.message { 'x' }
      end

      RaceGuard::RuleEngine.evaluate(:silent)
      expect(io.string).to eq('')
    end
  end

  it 'fires hooks from RaceGuard.protect with context and metadata' do
    with_isolated_env(rack: 'development') do
      seen = []
      RaceGuard.configure { |c| c.enable_rule(:hooked) }

      RaceGuard.define_rule(:hooked) do |r|
        r.hook(:protect_enter) do |ctx, meta|
          seen << [:enter, ctx.protected_blocks.last, meta[:protect], meta[:event]]
        end
        r.hook(:protect_exit) do |ctx, meta|
          seen << [:exit, ctx.protected_blocks.last, meta[:protect], meta[:event]]
        end
        r.detect { false }
        r.message { 'n' }
        r.run_on :protect_enter
      end

      RaceGuard.protect(:demo) { seen << :body }
      expect(seen[0][0]).to eq(:enter)
      expect(seen[0][1]).to eq(:demo)
      expect(seen[0][2]).to eq(:demo)
      expect(seen[0][3]).to eq(:protect_enter)
      expect(seen[1]).to eq(:body)
      expect(seen[2][0]).to eq(:exit)
      expect(seen[2][3]).to eq(:protect_exit)
    end
  end

  it 'runs detect on run_on events and reports' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      RaceGuard.configure do |c|
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
        c.enable_rule(:on_enter)
      end

      RaceGuard.define_rule(:on_enter) do |r|
        r.run_on :protect_enter
        r.detect { |_ctx, meta| meta[:event] == :protect_enter }
        r.message { 'bad' }
      end

      RaceGuard.protect(:x) { nil }
      line = JSON.parse(io.string.lines.last)
      expect(line['detector']).to eq('on_enter')
      expect(line['message']).to eq('bad')
    end
  end

  it 'rescues hook errors so protect still completes' do
    with_isolated_env(rack: 'development') do
      RaceGuard.configure { |c| c.enable_rule(:boom) }

      RaceGuard.define_rule(:boom) do |r|
        r.hook(:protect_enter) { raise 'hook error' }
        r.detect { false }
        r.message { 'm' }
      end

      expect { RaceGuard.protect(:safe) { :ok } }.not_to raise_error
    end
  end

  it 'define_rule without block raises' do
    expect { RaceGuard.define_rule(:x) }.to raise_error(ArgumentError, /block/)
  end
end
