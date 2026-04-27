# frozen_string_literal: true

require_relative 'schema_ast'

module RaceGuard
  module IndexIntegrity
    # Internal: extract +IndexDefinition+ from +add_index+ / +t.index+ send nodes (Epic 5.2).
    module SchemaIndexSend
      class << self
        # @param forced_table [Symbol, nil] nil for +add_index+, set for +t.index+
        def try_unique_index(send_node, forced_table:)
          args = send_node.children.drop(2)
          table, cols_node, opts = extract_parts(args, forced_table: forced_table)
          return nil unless table && cols_node

          cols = SchemaAst.column_array_to_syms(cols_node)
          return nil unless cols && !cols.empty?
          return nil if hash_skipped?(opts)

          unique = hash_true?(opts, :unique)
          return nil unless unique

          name = hash_name(opts)
          IndexDefinition.new(table: table, columns: cols, unique: true, name: name)
        end

        private

        def extract_parts(args, forced_table:)
          if forced_table
            return [forced_table, args[0], args[1]] if args[0]

            return [nil, nil, nil]
          end

          return [nil, nil, nil] if args.size < 2

          table = SchemaAst.literal_table_sym(args[0])
          [table, args[1], args[2]]
        end

        def hash_skipped?(opts)
          hash_node?(opts) && SchemaAst.hash_has_key?(opts, :where)
        end

        def hash_true?(opts, key_sym)
          hash_node?(opts) && SchemaAst.hash_option_true?(opts, key_sym)
        end

        def hash_node?(opts)
          opts.is_a?(Parser::AST::Node) && opts.type == :hash
        end

        def hash_name(opts)
          return nil unless opts.is_a?(Parser::AST::Node) && opts.type == :hash

          SchemaAst.hash_name(opts)
        end
      end
    end
  end
end
