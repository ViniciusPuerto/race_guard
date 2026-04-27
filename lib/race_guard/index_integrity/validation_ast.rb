# frozen_string_literal: true

module RaceGuard
  module IndexIntegrity
    # Internal: Parser AST helpers for {ModelScanner} (Epic 5.1).
    module ValidationAst
      class << self
        def validates_send?(node)
          return false unless node.is_a?(Parser::AST::Node) && node.type == :send

          recv, mid, = node.children
          return false unless mid == :validates

          recv.nil? || (recv.is_a?(Parser::AST::Node) && recv.type == :self)
        end

        def split_validates_arguments(args)
          fields = []
          hashes = []
          args.each { |arg| break unless consume_validates_argument!(arg, fields, hashes) }
          [fields.compact, hashes]
        end

        def find_uniqueness_value(hashes)
          hashes.each do |h|
            hash_pairs(h).each do |pair|
              key, val = pair.children
              next unless key.is_a?(Parser::AST::Node) && key.type == :sym
              next unless key.children[0] == :uniqueness

              return val
            end
          end
          nil
        end

        def uniqueness_disabled?(uniq_node)
          uniq_node.is_a?(Parser::AST::Node) && uniq_node.type == :false # rubocop:disable Lint/BooleanSymbol
        end

        def extract_uniqueness_scope(uniq_node)
          return nil unless uniq_node.is_a?(Parser::AST::Node)
          return nil if uniq_node.type == :true # rubocop:disable Lint/BooleanSymbol
          return nil unless uniq_node.type == :hash

          scope_from_uniqueness_options(uniq_node)
        end

        def hash_pairs(hash_node)
          return [] unless hash_node.is_a?(Parser::AST::Node) && hash_node.type == :hash

          hash_node.children.select { |c| c.is_a?(Parser::AST::Node) && c.type == :pair }
        end

        def literal_to_field_sym(node)
          case node&.type
          when :sym then node.children[0]
          when :str then node.children[0].to_sym
          end
        end

        private

        # Returns whether scanning should continue to the next argument.
        # rubocop:disable Naming/PredicateMethod -- name reflects continuation, not a pure predicate
        def consume_validates_argument!(arg, fields, hashes)
          return false unless arg.is_a?(Parser::AST::Node)

          case arg.type
          when :sym, :str
            n = literal_to_field_sym(arg)
            fields << n if n
          when :hash
            hashes << arg
          else
            return false
          end
          true
        end
        # rubocop:enable Naming/PredicateMethod

        def scope_from_uniqueness_options(hash_node)
          hash_pairs(hash_node).each do |pair|
            k, v = pair.children
            next unless k.is_a?(Parser::AST::Node) && k.type == :sym
            next unless k.children[0] == :scope

            return scope_literal(v)
          end
          nil
        end

        def scope_literal(node)
          case node&.type
          when :sym
            node.children[0]
          when :str
            node.children[0].to_sym
          when :array
            node.children.grep(Parser::AST::Node).filter_map { |el| scope_literal(el) }
          end
        end
      end
    end
  end
end
