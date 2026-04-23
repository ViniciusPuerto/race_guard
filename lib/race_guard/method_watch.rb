# frozen_string_literal: true

require 'set'

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
        owner = resolve_owner!(klass, m, scope)
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

    def resolve_owner!(klass, method_name, scope)
      has_inst = public_instance_method_own?(klass, method_name)
      has_single = public_singleton_method_own?(klass, method_name)

      case scope
      when :auto
        resolve_auto_owner(klass, method_name, has_inst, has_single)
      when :instance
        require_instance!(klass, method_name, has_inst)
      when :singleton
        require_singleton!(klass, method_name, has_single)
      else
        raise ArgumentError, "invalid scope: #{scope.inspect} (use :auto, :instance, or :singleton)"
      end
    end
    private_class_method :resolve_owner!

    def resolve_auto_owner(klass, method_name, has_inst, has_single)
      return :instance if has_inst
      return :singleton if has_single

      raise ArgumentError, missing_method_message(klass, method_name)
    end
    private_class_method :resolve_auto_owner

    def require_instance!(klass, method_name, has_inst)
      raise ArgumentError, missing_method_message(klass, method_name) unless has_inst

      :instance
    end
    private_class_method :require_instance!

    def require_singleton!(klass, method_name, has_single)
      raise ArgumentError, missing_method_message(klass, method_name) unless has_single

      :singleton
    end
    private_class_method :require_singleton!

    def public_instance_method_own?(klass, name)
      klass.public_method_defined?(name, false)
    end
    private_class_method :public_instance_method_own?

    def public_singleton_method_own?(klass, name)
      klass.singleton_class.public_method_defined?(name, false)
    end
    private_class_method :public_singleton_method_own?

    def missing_method_message(klass, name)
      label = klass.name || "Anonymous(#{klass.object_id})"
      "no public own method #{name.inspect} on #{label} for scope :auto " \
        '(define it on this class/module, or pass scope: :instance / :singleton)'
    end
    private_class_method :missing_method_message

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
