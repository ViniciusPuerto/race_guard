# frozen_string_literal: true

RSpec.describe 'RaceGuard.watch' do
  after do
    RaceGuard::MethodWatch.reset_registry!
    RaceGuard.context.reset!
    Thread.current[:rg_watch_seen] = nil
  end

  let(:service_class) do
    Class.new do
      def call
        Thread.current[:rg_watch_seen] = RaceGuard.context.current.protected_blocks.dup
        :instance_ok
      end

      def self.foo
        Thread.current[:rg_watch_seen] = RaceGuard.context.current.protected_blocks.dup
        :class_ok
      end
    end
  end

  it 'wraps an instance method and preserves return value' do
    RaceGuard.watch(service_class, :call)
    expect(service_class.new.call).to eq(:instance_ok)
    expect(Thread.current[:rg_watch_seen].last.to_s).to start_with('watch_')
  end

  it 'wraps a class method and preserves return value' do
    RaceGuard.watch(service_class, :foo, scope: :singleton)
    expect(service_class.foo).to eq(:class_ok)
    expect(Thread.current[:rg_watch_seen].last.to_s).to include('foo')
  end

  it 'is idempotent (no double wrap)' do
    anc1 = service_class.ancestors.take(5)
    RaceGuard.watch(service_class, :call)
    anc2 = service_class.ancestors.take(5)
    RaceGuard.watch(service_class, :call)
    anc3 = service_class.ancestors.take(5)
    expect(anc2).to eq(anc3)
    expect(anc2.first).not_to eq(anc1.first)
  end

  it 'raises TypeError for non-Module' do
    expect { RaceGuard.watch('nope', :x) }.to raise_error(TypeError, /Class or Module/)
  end

  it 'raises when no matching own public method' do
    empty = Class.new
    expect { RaceGuard.watch(empty, :missing) }.to raise_error(
      ArgumentError,
      /no public own method/
    )
  end

  it 'raises on invalid scope keyword' do
    expect { RaceGuard.watch(service_class, :call, scope: :nope) }.to raise_error(
      ArgumentError,
      /invalid scope/
    )
  end

  it 'allows concurrent watch on the same method (second is no-op)' do
    errors = []
    threads = Array.new(4) do
      Thread.new do
        RaceGuard.watch(service_class, :call)
      rescue StandardError => e
        errors << e
      end
    end
    threads.each(&:join)
    expect(errors).to be_empty
    expect(service_class.new.call).to eq(:instance_ok)
  end
end
