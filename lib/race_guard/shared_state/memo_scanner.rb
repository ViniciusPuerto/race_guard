# frozen_string_literal: true

require 'parser/current'

module RaceGuard
  module SharedState
    # Finds +@ivar ||= rhs+ (Parser +:or_asgn+ with +:ivasgn+ LHS) for Epic 6.4.
    module MemoScanner
      MemoSite = Struct.new(:path, :line, :ivar, keyword_init: true)

      class << self
        def scan_source(source, path: '(eval)')
          ast = Parser::CurrentRuby.parse(source)
          sites = []
          walk(ast, path, sites)
          sites
        rescue Parser::SyntaxError
          []
        end

        def scan_file(path)
          scan_source(File.read(path, encoding: 'UTF-8'), path: path.to_s)
        rescue Errno::ENOENT, ArgumentError
          []
        end

        private

        def walk(node, path, sites)
          return unless node.is_a?(Parser::AST::Node)

          append_ivar_memo_site(node, path, sites)
          node.children.each { |c| walk(c, path, sites) if c.is_a?(Parser::AST::Node) }
        end

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        def append_ivar_memo_site(node, path, sites)
          return unless node.type == :or_asgn

          recv, = *node.children
          return unless recv.is_a?(Parser::AST::Node) && recv.type == :ivasgn

          ivar_sym = recv.children[0]
          line = node.loc&.expression&.line || recv.loc&.name&.line
          sites << MemoSite.new(path: path, line: line, ivar: ivar_sym.to_s) if line
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      end
    end
  end
end
