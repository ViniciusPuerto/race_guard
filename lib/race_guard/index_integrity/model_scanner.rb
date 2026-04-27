# frozen_string_literal: true

require 'parser/current'
require_relative 'validation_ast'

module RaceGuard
  module IndexIntegrity
    # Static scan for ActiveRecord-style +validates+ macros with +uniqueness+ (Epic 5.1).
    #
    # Load explicitly for non-Rails use; in Rails apps +race_guard:index_integrity+ loads this.
    #   require "race_guard/index_integrity/model_scanner"
    UniquenessValidation = Struct.new(:fields, :scope, :filename, keyword_init: true)

    module ModelScanner
      class << self
        def scan_file(path)
          src = File.read(path, encoding: 'UTF-8')
          scan_source(src, filename: path)
        rescue Errno::ENOENT, ArgumentError
          []
        end

        def scan_source(source, filename: '(string)')
          ast = Parser::CurrentRuby.parse(source)
          return [] unless ast

          out = []
          walk(ast) { |node| maybe_record_validates_uniqueness!(node, out, filename) }
          out
        rescue Parser::SyntaxError
          []
        end

        private

        def walk(node, &block)
          return unless node.is_a?(Parser::AST::Node)

          yield node
          node.children.each do |child|
            walk(child, &block) if child.is_a?(Parser::AST::Node)
          end
        end

        def maybe_record_validates_uniqueness!(node, out, filename)
          return unless ValidationAst.validates_send?(node)

          args = node.children.drop(2)
          fields, hashes = ValidationAst.split_validates_arguments(args)
          return if fields.empty?

          uniq_node = ValidationAst.find_uniqueness_value(hashes)
          return if uniq_node.nil? || ValidationAst.uniqueness_disabled?(uniq_node)

          scope = ValidationAst.extract_uniqueness_scope(uniq_node)
          out << UniquenessValidation.new(fields: fields, scope: scope, filename: filename)
        end
      end
    end
  end
end
