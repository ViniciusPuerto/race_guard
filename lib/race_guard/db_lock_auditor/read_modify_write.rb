# frozen_string_literal: true

module RaceGuard
  module DBLockAuditor
    module ReadModifyWrite
      DETECTOR = 'db_lock_auditor:read_modify_write'

      INSTALL_MUTEX = Mutex.new
      @installed = false

      # Prepended to +ActiveRecord::Base+.
      module Patches
        RMW_IN_READ_HOOK = :__race_guard_rmw_in_read_hook

        # Generated readers (e.g. +#balance+) call +_read_attribute+, not +read_attribute+.
        # Re-entrant +_read_attribute+ (e.g. +id+ while resolving a journal key) must skip
        # instrumentation to avoid infinite recursion.
        def _read_attribute(*args, **kwargs, &)
          return super if Thread.current[RMW_IN_READ_HOOK]

          Thread.current[RMW_IN_READ_HOOK] = true
          val = super
          ReadModWriteImpl.note_read_from__read_attribute(self, args[0], val)
          val
        ensure
          Thread.current[RMW_IN_READ_HOOK] = false
        end

        def read_attribute(*args, **kwargs, &)
          return super if Thread.current[RMW_IN_READ_HOOK]

          Thread.current[RMW_IN_READ_HOOK] = true
          val = super
          ReadModWriteImpl.note_read_from_read_attribute(self, args[0], val)
          val
        ensure
          Thread.current[RMW_IN_READ_HOOK] = false
        end

        def save(*args, **kwargs)
          ReadModWriteImpl.enter_persisted_write!
          result = super
          ReadModWriteImpl.after_save(self, result, 'save')
          result
        ensure
          ReadModWriteImpl.leave_persisted_write!
        end

        def save!(*args, **kwargs)
          ReadModWriteImpl.enter_persisted_write!
          result = super
          ReadModWriteImpl.after_save(self, true, 'save!')
          result
        ensure
          ReadModWriteImpl.leave_persisted_write!
        end

        def with_lock(*args, &block)
          return super unless block

          super do
            ReadModWriteImpl.around_with_lock_user_block(self) { block.call }
          end
        end

        # Match {ActiveRecord::Locking::Pessimistic#lock!}; default +true+ matches upstream.
        def lock!(lock = true) # rubocop:disable Style/OptionalBooleanParameter
          result = super
          ReadModWriteImpl.record_pessimistic_lock_for_record!(self)
          result
        end
      end

      # Internal: keeps Patches and singleton API small (RuboCop).
      # rubocop:disable Metrics/ModuleLength -- one cohesive implementation unit for 4.1
      module ReadModWriteImpl
        WRITE_DEPTH_KEY = :__race_guard_rmw_in_save_depth

        module_function

        def enter_persisted_write!
          d = Thread.current[WRITE_DEPTH_KEY].to_i + 1
          Thread.current[WRITE_DEPTH_KEY] = d
        end

        def leave_persisted_write!
          d = Thread.current[WRITE_DEPTH_KEY].to_i - 1
          Thread.current[WRITE_DEPTH_KEY] = d <= 0 ? nil : d
        end

        def inside_persisted_write?
          Thread.current[WRITE_DEPTH_KEY].to_i.positive?
        end

        def primary_key_value_for_rmw(record)
          return nil unless record.is_a?(::ActiveRecord::Base)
          return nil if record.new_record?

          pk = record.class.primary_key
          name = (pk.is_a?(Array) ? pk.first : pk).to_s
          set = record.instance_variable_get(:@attributes)
          return nil unless set

          set.fetch_value(name)
        rescue StandardError
          nil
        end

        def normalize_attr_name_for_read(record, attr)
          s = attr.to_s
          return s unless record.class.respond_to?(:attribute_aliases)

          record.class.attribute_aliases[s] || s
        end

        def note_read_from__read_attribute(record, raw_attr, _val)
          return if raw_attr.nil? || inside_persisted_write?

          n = normalize_attr_name_for_read(record, raw_attr)
          capture_read!(record, n)
        rescue StandardError
          nil
        end

        def note_read_from_read_attribute(record, raw_attr, _val)
          return if raw_attr.nil? || inside_persisted_write?

          n = raw_attr.to_s
          n = record.class.attribute_aliases[n] || n if record.class.respond_to?(:attribute_aliases)
          capture_read!(record, n)
        rescue StandardError
          nil
        end

        def capture_read!(record, attr)
          return if inside_persisted_write?
          return unless should_track_read?(record)

          pk = primary_key_value_for_rmw(record)
          return unless pk

          RaceGuard.context.rmw_read_record!(record.class, pk, attr)
        end

        def after_save(record, success, write_label)
          return unless success

          check_after_persisted_save!(record, write_label)
        end

        def check_after_persisted_save!(record, write_label)
          return unless should_track_write?(record)
          return unless record.persisted?

          pk = primary_key_value_for_rmw(record)
          return if pk.nil?

          changes = record.saved_changes
          return if changes.nil? || changes.empty?

          each_rmw_matching_change(record, changes, write_label, pk)
        end

        def each_rmw_matching_change(record, changes, write_label, record_pk)
          changes.each_key do |attr_name|
            age_ms = RaceGuard.context.rmw_read_age_ms_for(record.class, record_pk, attr_name)
            next unless age_ms

            if skip_rmw_due_to_pessimistic_lock?(record, record_pk)
              RaceGuard.context.rmw_read_forget!(record.class, record_pk, attr_name)
              next
            end

            report_read_modify_write!(record, attr_name, age_ms, write_label, record_pk)
            RaceGuard.context.rmw_read_forget!(record.class, record_pk, attr_name)
          end
        end

        def skip_rmw_due_to_pessimistic_lock?(record, record_pk)
          return true if RaceGuard.context.rmw_pessimistic_lock_active?(record.class, record_pk)

          depth = RaceGuard.context.rmw_with_lock_block_depth_for(record.class, record_pk)
          return true if depth.positive?

          false
        end

        def around_with_lock_user_block(record)
          pk = primary_key_value_for_rmw(record)
          begin
            RaceGuard.context.rmw_with_lock_block_enter!(record.class, pk) if pk
            yield
          ensure
            RaceGuard.context.rmw_with_lock_block_leave!(record.class, pk) if pk
          end
        end

        def record_pessimistic_lock_for_record!(record)
          return unless should_track_write?(record)
          return unless record.is_a?(::ActiveRecord::Base)
          return if record.new_record?

          pk = primary_key_value_for_rmw(record)
          return if pk.nil?

          RaceGuard.context.rmw_pessimistic_lock_register!(record.class, pk)
          RaceGuard.context.rmw_read_forget_record!(record.class, pk)
        rescue StandardError
          nil
        end

        def should_track_read?(record)
          cfg = RaceGuard.configuration
          return false unless cfg.active?
          return false unless record.is_a?(::ActiveRecord::Base)
          return false if record.new_record?
          return false if primary_key_value_for_rmw(record).nil?
          return false if cfg.db_lock_read_modify_write_models.empty?

          cfg.db_lock_read_modify_write_tracks?(record.class)
        end

        def should_track_write?(record)
          cfg = RaceGuard.configuration
          return false unless cfg.active?
          return false if cfg.db_lock_read_modify_write_models.empty?

          cfg.db_lock_read_modify_write_tracks?(record.class)
        end

        # rubocop:disable Metrics/MethodLength -- one linear report; keeps context fields explicit
        def report_read_modify_write!(record, attr_name, read_age_ms, write_label, record_pk = nil)
          cfg = RaceGuard.configuration
          msg = "Read-modify-write on #{record.class.name}##{attr_name} " \
                '(read then persisted save; consider atomic SQL, locking, or idempotency)'
          snapshot = RaceGuard.context.current
          sev = cfg.severity_for(:'db_lock_auditor:read_modify_write')
          rid = record_pk || primary_key_value_for_rmw(record)
          ctx = {
            'model' => record.class.name,
            'record_id' => rid,
            'attribute' => attr_name.to_s,
            'write_method' => write_label,
            'in_transaction' => snapshot.in_transaction?,
            'read_age_ms' => read_age_ms.round
          }
          RaceGuard.report(
            detector: ReadModifyWrite::DETECTOR,
            message: msg,
            severity: sev,
            context: ctx
          )
        end
        # rubocop:enable Metrics/MethodLength
      end
      # rubocop:enable Metrics/ModuleLength

      class << self
        def install!
          return unless defined?(::ActiveRecord::Base)

          INSTALL_MUTEX.synchronize do
            return if @installed
            return if ::ActiveRecord::Base.ancestors.include?(Patches)

            ::ActiveRecord::Base.prepend(Patches)
            @installed = true
          end
          self
        end
      end
    end
  end
end
