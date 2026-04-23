# frozen_string_literal: true

require 'set'

require_relative 'method_resolution'

module RaceGuard
  # Prepends a thin wrapper around public methods so calls run inside
  # {RaceGuard.protect}. Idempotent per class/method/owner (see registry).
  module MethodWatch
    REGISTRY_MUTEX = Mutex.new
    REGISTRY = Set.new

    module_function

    def watch(klass, method_name, scope: :auto)
      raise TypeError, 'klass must be a Class or Module' unless klass.is_a?(Module)

      m = method_name.to_sym
      REGISTRY_MUTEX.synchronize do
        owner = MethodResolution.resolve_owner!(klass, m, scope)
        key = [klass.__id__, m, owner]
        return RaceGuard if REGISTRY.include?(key)

        install!(klass, m, owner)
        REGISTRY.add(key)
      end
      RaceGuard
    end

    # Test helper: clears idempotency keys only (does not remove prepended modules).
    def self.reset_registry!
      REGISTRY_MUTEX.synchronize { REGISTRY.clear }
    end

    def install!(klass, method_name, owner)
      target = owner == :instance ? klass : klass.singleton_class
      label = protect_label(klass, method_name, owner)
      wrapper = Module.new
      wrapper.define_method(method_name) do |*args, **kwargs, &block|
        RaceGuard.protect(label) do
          super(*args, **kwargs, &block)
        end
      end
      target.prepend(wrapper)
    end
    private_class_method :install!

    def protect_label(klass, method_name, owner)
      base = klass.name&.gsub('::', '__') || "Anonymous#{klass.object_id}"
      suffix = owner == :singleton ? '_class' : '_instance'
      :"watch_#{base}__#{method_name}#{suffix}"
    end
    private_class_method :protect_label
  end
end
