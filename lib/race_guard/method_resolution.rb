# frozen_string_literal: true

module RaceGuard
  # Shared rules for resolving +public_method_defined?(name, false)+ targets on a
  # class or module (used by {RaceGuard::MethodWatch} and commit-safety watchers).
  module MethodResolution
    module_function

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

    def resolve_auto_owner(klass, method_name, has_inst, has_single)
      return :instance if has_inst
      return :singleton if has_single

      raise ArgumentError, missing_method_message(klass, method_name)
    end

    def require_instance!(klass, method_name, has_inst)
      raise ArgumentError, missing_method_message(klass, method_name) unless has_inst

      :instance
    end

    def require_singleton!(klass, method_name, has_single)
      raise ArgumentError, missing_method_message(klass, method_name) unless has_single

      :singleton
    end

    def public_instance_method_own?(klass, name)
      klass.public_method_defined?(name, false)
    end

    def public_singleton_method_own?(klass, name)
      klass.singleton_class.public_method_defined?(name, false)
    end

    def missing_method_message(klass, name)
      label = klass.name || "Anonymous(#{klass.object_id})"
      "no public own method #{name.inspect} on #{label} for scope :auto " \
        '(define it on this class/module, or pass scope: :instance / :singleton)'
    end
  end
end
