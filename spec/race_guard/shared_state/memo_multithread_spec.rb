# frozen_string_literal: true

require 'json'
require 'race_guard'
require 'tmpdir'

RSpec.describe 'RaceGuard shared_state memoization (Epic 6.4)', :aggregate_failures do
  let(:feature) { RaceGuard::SharedState::TracePoint::FEATURE }

  def reset_trace_point_singleton_state!
    mod = RaceGuard::SharedState::TracePoint
    mod.instance_variable_set(:@warned_unsupported, false)
    mod.instance_variable_set(:@install_failed, false)
  end

  around do |example|
    RaceGuard::SharedState::TracePoint.uninstall!
    reset_trace_point_singleton_state!
    RaceGuard::SharedState::TracePoint.event_sink = nil
    RaceGuard.reset_configuration!
    example.run
    RaceGuard::SharedState::TracePoint.uninstall!
    reset_trace_point_singleton_state!
    RaceGuard::SharedState::TracePoint.event_sink = nil
    RaceGuard.reset_configuration!
  end

  it 'reports memo sites once after a non-main thread starts' do
    allow(Kernel).to receive(:warn)

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'memo.rb')
      File.write(path, <<~RUBY)
        class MemoHost
          def value
            @slow ||= 1
          end
        end
      RUBY

      io = StringIO.new
      RaceGuard.configure do |c|
        c.enable(feature)
        c.shared_state_memo_globs(File.join(dir, '*.rb'))
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
      end

      Thread.new { sleep 0.01 }.join

      lines = io.string.lines.map { |l| JSON.parse(l) }
      memo = lines.select { |j| j['detector'] == 'shared_state:memoization' }
      expect(memo.size).to eq(1)
      expect(memo.first['context']['ivar']).to eq('@slow')
      expect(memo.first['context']['path']).to eq(path)
    end
  end

  it 'does not report memo sites when only the main thread runs' do
    allow(Kernel).to receive(:warn)

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'single.rb')
      File.write(path, "@x ||= 1\n")

      io = StringIO.new
      RaceGuard.configure do |c|
        c.enable(feature)
        c.shared_state_memo_globs(File.join(dir, '*.rb'))
        c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
      end

      lines = io.string.lines.map { |l| JSON.parse(l) }
      memo = lines.select { |j| j['detector'] == 'shared_state:memoization' }
      expect(memo).to be_empty
    end
  end
end
