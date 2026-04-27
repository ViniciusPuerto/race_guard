# frozen_string_literal: true

require 'race_guard'
require 'race_guard/shared_state/trace_point'

RSpec.describe RaceGuard::SharedState::TracePoint do
  let(:feature) { described_class::FEATURE }

  def cvasgn_tracepoint_available?
    t = TracePoint.new(:cvasgn, :gvasgn) { |_tp| nil }
    t.disable
    true
  rescue ArgumentError
    false
  end

  def reset_trace_point_singleton_state!
    # Class methods use `class << self`; ivars like @warned_unsupported live on the module object,
    # not on its singleton_class (see Ruby ivar rules for module eigenmethods).
    mod = described_class
    mod.instance_variable_set(:@warned_unsupported, false)
    mod.instance_variable_set(:@install_failed, false)
  end

  around do |example|
    described_class.uninstall!
    reset_trace_point_singleton_state!
    described_class.event_sink = nil
    RaceGuard.reset_configuration!
    example.run
    described_class.uninstall!
    reset_trace_point_singleton_state!
    described_class.event_sink = nil
    RaceGuard.reset_configuration!
  end

  describe '.sync_with_configuration!' do
    it 'does not install when the feature is off' do
      RaceGuard.configure { |c| expect(c).to be_a(RaceGuard::Configuration) }
      expect(described_class).not_to be_installed
    end

    it 'warns once and stays uninstalled when :cvasgn/:gvasgn are unavailable' do
      skip 'MRI exposes :cvasgn/:gvasgn' if cvasgn_tracepoint_available?

      allow(Kernel).to receive(:warn)
      expect(Kernel).to receive(:warn).once.with(a_string_matching(/shared_state_watcher/))

      RaceGuard.configure { |c| c.enable(feature) }
      RaceGuard.configure { |c| c.enable(feature) }

      expect(described_class).not_to be_installed
    end

    it 'installs and delivers TracePoint events when :cvasgn/:gvasgn exist' do
      skip 'MRI does not expose :cvasgn/:gvasgn' unless cvasgn_tracepoint_available?
      events = []
      described_class.event_sink = proc { |tp| events << tp.event }

      RaceGuard.configure { |c| c.enable(feature) }

      expect(described_class).to be_installed
      # rubocop:disable Style/ClassVars -- intentional cvasgn under TracePoint-supported MRI
      Class.new.class_eval { @@race_guard_epic6_cvar = 1 }
      # rubocop:enable Style/ClassVars
      expect(events).to include(:cvasgn)

      TOPLEVEL_BINDING.eval('$race_guard_epic6_gvar_test = 1')
      expect(events).to include(:gvasgn)
    ensure
      TOPLEVEL_BINDING.eval('$race_guard_epic6_gvar_test = nil')
    end

    it 'uninstalls when the feature is disabled after being enabled' do
      allow(Kernel).to receive(:warn)
      RaceGuard.configure { |c| c.enable(feature) }

      RaceGuard.configure { |c| c.disable(feature) }
      expect(described_class).not_to be_installed
    end

    it 'uninstalls on reset_configuration!' do
      allow(Kernel).to receive(:warn)
      RaceGuard.configure { |c| c.enable(feature) }

      RaceGuard.reset_configuration!
      expect(described_class).not_to be_installed
    end
  end
end
