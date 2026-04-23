# frozen_string_literal: true

require 'json'
require 'stringio'

RSpec.describe 'RaceGuard watch_commit_safety' do
  include EnvSpecHelpers

  let(:client_class) do
    Class.new do
      def call
        :call_ok
      end

      def ping
        :ping_ok
      end
    end
  end

  after do
    RaceGuard::CommitSafety::Watcher.reset_registry!
    RaceGuard::MethodWatch.reset_registry!
    RaceGuard.reset_configuration!
    RaceGuard.context.reset!
  end

  it 'installs multiple intercepts and emits commit_safety events' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      RaceGuard.configure do |c|
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
        c.watch_commit_safety :custom do |w|
          w.intercept(client_class, :call)
          w.intercept(client_class, :ping)
        end
      end

      inst = client_class.new
      expect(inst.call).to eq(:call_ok)
      expect(inst.ping).to eq(:ping_ok)

      lines = io.string.lines.map { |l| JSON.parse(l) }
      detectors = lines.map { |h| h['detector'] }
      expect(detectors).to all(start_with('commit_safety:'))
      expect(detectors.count('commit_safety:custom')).to eq(2)
    end
  end

  it 'allows different watch names for the same method on different classes' do
    with_isolated_env(rack: 'development') do
      io = StringIO.new
      other = Class.new do
        def m
          1
        end
      end

      RaceGuard.configure do |c|
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
        c.watch_commit_safety :alpha do |w|
          w.intercept(client_class, :call)
        end
        c.watch_commit_safety :beta do |w|
          w.intercept(other, :m)
        end
      end

      client_class.new.call
      other.new.m

      lines = io.string.lines.map { |l| JSON.parse(l) }
      detectors = lines.map { |h| h['detector'] }
      expect(detectors).to contain_exactly('commit_safety:alpha', 'commit_safety:beta')
    end
  end
end
