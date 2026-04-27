# frozen_string_literal: true

require_relative 'schema_ast'
require_relative 'schema_index_send'

module RaceGuard
  module IndexIntegrity
    # Internal: AST walk for {SchemaAnalyzer} (Epic 5.2).
    class SchemaWalker
      def initialize(acc)
        @acc = acc
      end

      def walk(node, table_ctx)
        return unless node.is_a?(Parser::AST::Node)

        case node.type
        when :begin, :kwbegin
          walk_children(node, table_ctx)
        when :block
          walk_block(node, table_ctx)
        else
          record_send_indexes(node, table_ctx)
          walk_children(node, table_ctx)
        end
      end

      private

      def walk_children(node, table_ctx)
        node.children.each { |c| walk(c, table_ctx) if c.is_a?(Parser::AST::Node) }
      end

      def walk_block(node, table_ctx)
        call, _, body = node.children
        unless call.is_a?(Parser::AST::Node) && call.type == :send
          walk_children(node, table_ctx)
          return
        end

        dispatch_block(call, body, table_ctx)
      end

      def dispatch_block(call, body, table_ctx)
        mid = SchemaAst.send_method(call)
        case mid
        when :create_table
          walk_create_table(body, call, table_ctx)
        when :change
          walk(body, table_ctx) if body.is_a?(Parser::AST::Node)
        else
          walk_call_and_body(call, body, table_ctx)
        end
      end

      def walk_create_table(body, call, table_ctx)
        tname = SchemaAst.create_table_name(call)
        if tname && body.is_a?(Parser::AST::Node)
          walk(body, tname)
        else
          walk_call_and_body(call, body, table_ctx)
        end
      end

      def walk_call_and_body(call, body, table_ctx)
        walk(call, table_ctx)
        walk(body, table_ctx) if body.is_a?(Parser::AST::Node)
      end

      def record_send_indexes(node, table_ctx)
        return unless node.type == :send

        record_add_index(node)
        record_t_index(node, table_ctx)
      end

      def record_add_index(node)
        return unless SchemaAst.add_index_send?(node)

        idx = SchemaIndexSend.try_unique_index(node, forced_table: nil)
        @acc << idx if idx
      end

      def record_t_index(node, table_ctx)
        return unless SchemaAst.t_index_send?(node, table_ctx)

        idx = SchemaIndexSend.try_unique_index(node, forced_table: table_ctx)
        @acc << idx if idx
      end
    end
  end
end
