# frozen_string_literal: true

require 'parser/current'
require_relative 'schema_ast'

module RaceGuard
  module IndexIntegrity
    # Static scan for unique indexes in +schema.rb+ or from an AR connection (Epic 5.2).
    #
    #   require "race_guard/index_integrity/schema_analyzer"
    IndexDefinition = Struct.new(:table, :columns, :unique, :name, keyword_init: true)

    require_relative 'schema_connection_indexes'
    require_relative 'schema_index_send'
    require_relative 'schema_walker'

    module SchemaAnalyzer
      class << self
        def parse_file(path)
          src = File.read(path, encoding: 'UTF-8')
          parse_source(src)
        rescue Errno::ENOENT, ArgumentError, Parser::SyntaxError
          []
        end

        def parse_source(source)
          ast = Parser::CurrentRuby.parse(source)
          return [] unless ast

          out = []
          SchemaWalker.new(out).walk(ast, nil)
          out
        rescue Parser::SyntaxError
          []
        end

        def from_connection(connection, tables: nil)
          SchemaConnectionIndexes.fetch(connection, tables: tables)
        end
      end
    end
  end
end
