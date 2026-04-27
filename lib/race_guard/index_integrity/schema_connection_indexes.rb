# frozen_string_literal: true

module RaceGuard
  module IndexIntegrity
    # Internal: AR connection.indexes → {IndexDefinition} (Epic 5.2).
    module SchemaConnectionIndexes
      class << self
        def fetch(connection, tables: nil)
          return [] unless connection.respond_to?(:indexes)

          names = tables ? tables.map(&:to_s) : connection_table_names(connection)
          names.flat_map { |table| indexes_for_table(connection, table) }
        end

        private

        def connection_table_names(connection)
          if connection.respond_to?(:tables)
            connection.tables
          else
            connection.data_sources
          end
        end

        def indexes_for_table(connection, table)
          connection.indexes(table).filter_map do |idx|
            next unless idx.unique

            IndexDefinition.new(
              table: table.to_sym,
              columns: idx.columns.map(&:to_sym),
              unique: true,
              name: idx.name
            )
          end
        end
      end
    end
  end
end
