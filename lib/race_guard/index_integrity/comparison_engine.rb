# frozen_string_literal: true

require 'set'

require_relative 'table_inference'

module RaceGuard
  module IndexIntegrity
    # Match +UniquenessValidation+ rows to unique indexes (Epic 5.3).
    #
    #   require "race_guard/index_integrity/comparison_engine"
    MissingIndexViolation = Struct.new(:validation, :table, :required_columns, :suggested_migration,
                                       keyword_init: true) do
      def message
        cols = required_columns.sort.map(&:inspect).join(', ')
        <<~MSG.strip
          Missing unique index for #{validation.filename} (table :#{table}) columns [#{cols}]
            Suggested: #{suggested_migration}
        MSG
      end
    end

    module ComparisonEngine
      class << self
        def missing_indexes(validations:, indexes:)
          unique_indexes = indexes.select(&:unique)

          validations.filter_map do |validation|
            violation_for(validation, unique_indexes)
          end
        end

        def table_for_model_path(filename)
          TableInference.table_for_model_path(filename)
        end

        private

        def violation_for(validation, unique_indexes)
          table = TableInference.table_for_model_path(validation.filename)
          return if table.nil?

          required = required_column_set(validation)
          return if required.empty?
          return if covered?(unique_indexes, table, required)

          MissingIndexViolation.new(
            validation: validation,
            table: table,
            required_columns: required.to_a,
            suggested_migration: format_add_index(table, required)
          )
        end

        def required_column_set(validation)
          scope_cols =
            case validation.scope
            when nil then []
            when Array then validation.scope
            else [validation.scope]
            end
          (scope_cols + validation.fields).to_set
        end

        def covered?(unique_indexes, table, required_set)
          unique_indexes.any? do |ix|
            ix.table == table && ix.columns.to_set == required_set
          end
        end

        def format_add_index(table, column_set)
          cols = column_set.sort.map { |c| ":#{c}" }.join(', ')
          "add_index :#{table}, [#{cols}], unique: true"
        end
      end
    end
  end
end
