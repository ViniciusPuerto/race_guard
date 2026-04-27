# frozen_string_literal: true

module RaceGuard
  module IndexIntegrity
    # Internal: Parser AST helpers for {SchemaAnalyzer} (Epic 5.2).
    module SchemaAst
      class << self
        def send_method(node)
          return nil unless node.is_a?(Parser::AST::Node) && node.type == :send

          node.children[1]
        end

        def hash_pairs(hash_node)
          return [] unless hash_node.is_a?(Parser::AST::Node) && hash_node.type == :hash

          hash_node.children.select { |c| c.is_a?(Parser::AST::Node) && c.type == :pair }
        end

        def literal_table_sym(node)
          case node&.type
          when :sym then node.children[0]
          when :str then node.children[0].to_sym
          end
        end

        def literal_string_or_sym(node)
          case node&.type
          when :sym then node.children[0].to_s
          when :str then node.children[0]
          end
        end

        def column_array_to_syms(array_node)
          return nil unless array_node.is_a?(Parser::AST::Node) && array_node.type == :array

          cols = array_node.children.grep(Parser::AST::Node).filter_map do |el|
            literal_table_sym(el)
          end
          return nil if cols.size != array_node.children.grep(Parser::AST::Node).size

          cols
        end

        def hash_option_true?(hash_node, key_sym)
          val = pair_value_for_key(hash_node, key_sym)
          return false unless val.is_a?(Parser::AST::Node)

          val.type == :true # rubocop:disable Lint/BooleanSymbol
        end

        def hash_has_key?(hash_node, key_sym)
          hash_pairs(hash_node).any? do |pair|
            k, = pair.children
            k.is_a?(Parser::AST::Node) && k.type == :sym && k.children[0] == key_sym
          end
        end

        def hash_name(hash_node)
          hash_pairs(hash_node).each do |pair|
            k, v = pair.children
            next unless k.is_a?(Parser::AST::Node) && k.type == :sym
            next unless k.children[0] == :name

            return literal_string_or_sym(v) if v
          end
          nil
        end

        def create_table_name(send_node)
          return nil unless send_node.is_a?(Parser::AST::Node) && send_node.type == :send
          return nil unless send_method(send_node) == :create_table

          args = send_node.children.drop(2)
          return nil if args.empty?

          first = args[0]
          sym = literal_table_sym(first)
          return sym if sym

          nil
        end

        def t_index_send?(node, table_ctx)
          return false unless table_ctx && node.is_a?(Parser::AST::Node) && node.type == :send

          recv, mid, = node.children
          mid == :index && lvar_named?(recv, :t)
        end

        def add_index_send?(node)
          return false unless node.is_a?(Parser::AST::Node) && node.type == :send

          recv, mid, = node.children
          recv.nil? && mid == :add_index
        end

        private

        def pair_value_for_key(hash_node, key_sym)
          hash_pairs(hash_node).each do |pair|
            k, v = pair.children
            next unless k.is_a?(Parser::AST::Node) && k.type == :sym
            next unless k.children[0] == key_sym

            return v
          end
          nil
        end

        def lvar_named?(recv, name)
          recv.is_a?(Parser::AST::Node) && recv.type == :lvar && recv.children[0] == name
        end
      end
    end
  end
end
