# frozen_string_literal: true

require 'set'

require_relative '../interceptors/emitter'
require_relative '../method_resolution'

module RaceGuard
  module CommitSafety
    # DSL yielded by {RaceGuard::Configuration#watch_commit_safety}.
    class WatcherDSL
      def initialize(watch_name)
        @watch_name = watch_name.to_sym
      end

      def intercept(klass, method_name, scope: :auto)
        Watcher.install!(@watch_name, klass, method_name, scope: scope)
      end
    end

    # Prepends emit-and-super wrappers for commit-safety custom intercepts.
    module Watcher
      REGISTRY_MUTEX = Mutex.new
      REGISTRY = Set.new

      class << self
        def install!(watch_name, klass, method_name, scope:)
          raise TypeError, 'klass must be a Class or Module' unless klass.is_a?(Module)

          m = method_name.to_sym
          sym = watch_name.to_sym
          REGISTRY_MUTEX.synchronize do
            owner = MethodResolution.resolve_owner!(klass, m, scope)
            key = [klass.__id__, m, owner, sym]
            return if REGISTRY.include?(key)

            prepend_emit_wrapper!(klass, m, owner, sym)
            REGISTRY.add(key)
          end
        end

        def reset_registry!
          REGISTRY_MUTEX.synchronize { REGISTRY.clear }
        end

        # Called from prepended wrappers; kept public so +define_method+ bodies can invoke it.
        def emit_intercept_event(watch_name, label, method_name, owner)
          ::RaceGuard::Interceptors::Emitter.emit(
            watch_name,
            "#{label}##{method_name}",
            'watch' => watch_name.to_s,
            'class' => label,
            'method' => method_name.to_s,
            'owner' => owner.to_s
          )
        end

        private

        def prepend_emit_wrapper!(klass, method_name, owner, watch_name)
          target = owner == :instance ? klass : klass.singleton_class
          label = klass.name || "Anonymous#{klass.object_id}"
          wrapper = Module.new
          wrapper.define_method(method_name) do |*args, **kwargs, &block|
            ::RaceGuard::CommitSafety::Watcher.emit_intercept_event(
              watch_name, label, method_name, owner
            )
            super(*args, **kwargs, &block)
          end
          target.prepend(wrapper)
        end
      end
    end
  end
end
