# frozen_string_literal: true

require_relative 'detector_runtime'

module RaceGuard
  def self.protect(name, &block)
    raise ArgumentError, 'RaceGuard.protect requires a block' unless block

    sym = name.to_sym
    context.push_protected(sym)
    DetectorRuntime.enter(sym)
    yield
  ensure
    safe_protect_exit(sym)
    context.pop_protected
  end

  def self.safe_protect_exit(sym)
    DetectorRuntime.exit(sym)
  rescue StandardError
    nil
  end
  private_class_method :safe_protect_exit
end
