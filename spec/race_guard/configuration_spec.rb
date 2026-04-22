# frozen_string_literal: true

RSpec.describe RaceGuard::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'defaults severity, environments, and no enabled features' do
      with_isolated_env(rack: 'development') do
        h = config.to_h
        expect(h[:default_severity]).to eq(:info)
        expect(h[:environments]).to eq(%i[development test])
        expect(h[:enabled_features]).to be_empty
      end
    end
  end

  describe '#enable, #disable, #enabled?' do
    it 'toggles a feature in an active environment' do
      with_isolated_env(rack: 'development') do
        config.enable(:db_lock_auditor)
        expect(config).to be_enabled(:db_lock_auditor)
      end
    end

    it 'returns false for disabled features' do
      with_isolated_env(rack: 'development') do
        expect(config).not_to be_enabled(:db_lock_auditor)
        config.enable(:x)
        config.disable(:x)
        expect(config).not_to be_enabled(:x)
      end
    end

    it 'does not count features as enabled in production with default environments' do
      with_isolated_env(rack: 'production') do
        config.environments :development, :test
        config.enable(:db_lock_auditor)
        expect(config).not_to be_enabled(:db_lock_auditor)
      end
    end

    it 'allows production when environments include it' do
      with_isolated_env(rack: 'production', rails: 'production') do
        config.environments :development, :test, :production
        config.enable(:db_lock_auditor)
        expect(config).to be_enabled(:db_lock_auditor)
      end
    end
  end

  describe '#severity and #severity_for' do
    it 'sets default with one arg' do
      with_isolated_env(rack: 'development') do
        config.severity(:warn)
        expect(config.severity_for(:anything)).to eq(:warn)
      end
    end

    it 'overrides per detector with two args' do
      with_isolated_env(rack: 'development') do
        config.severity(:info)
        config.severity(:db_lock_auditor, :error)
        expect(config.severity_for(:other)).to eq(:info)
        expect(config.severity_for(:db_lock_auditor)).to eq(:error)
      end
    end

    it 'rejects invalid severities' do
      with_isolated_env(rack: 'development') do
        expect { config.severity(:loud) }.to raise_error(ArgumentError, /invalid severity/)
        expect { config.severity(:x, :nope) }.to raise_error(ArgumentError, /invalid severity/)
      end
    end

    it 'raises for wrong arity' do
      with_isolated_env(rack: 'development') do
        expect { config.severity }.to raise_error(ArgumentError, /expected 1 or 2 arguments/)
        err = /expected 1 or 2 arguments/
        expect { config.severity(1, 2, 3) }.to raise_error(ArgumentError, err)
      end
    end
  end

  describe '#environments' do
    it 'returns a copy with no args' do
      with_isolated_env(rack: 'development') do
        a = config.environments
        a << :production
        expect(config.environments).not_to include(:production)
      end
    end
  end

  describe '#active?' do
    it 'is true in development with defaults' do
      with_isolated_env(rack: 'development') do
        expect(config).to be_active
      end
    end

    it 'is false in production with default allowlist' do
      with_isolated_env(rack: 'production') do
        expect(config).not_to be_active
      end
    end

    it 'uses RAILS_ENV when RACK_ENV is unset' do
      with_isolated_env(rack: nil, rails: 'test') do
        expect(config).to be_active
      end
    end
  end
end

RSpec.describe 'RaceGuard singleton' do
  after do
    RaceGuard.reset_configuration!
  end

  it 'exposes the same object via .configuration and .config' do
    a = RaceGuard.configuration
    b = RaceGuard.config
    expect(b).to be(a)
  end

  it 'yields a configured instance from .configure' do
    with_isolated_env(rack: 'development') do
      RaceGuard.configure do |c|
        c.severity :warn
        c.enable :db_lock_auditor
      end
      expect(RaceGuard.config.severity_for(:x)).to eq(:warn)
      expect(RaceGuard.config).to be_enabled(:db_lock_auditor)
    end
  end

  it 'resets the singleton' do
    with_isolated_env(rack: 'development') do
      RaceGuard.configuration.enable(:a)
      RaceGuard.reset_configuration!
      expect(RaceGuard.configuration.enabled?(:a)).to be false
    end
  end
end
