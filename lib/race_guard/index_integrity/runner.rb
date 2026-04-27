# frozen_string_literal: true

require 'pathname'

require_relative 'model_scanner'
require_relative 'schema_analyzer'
require_relative 'comparison_engine'

module RaceGuard
  module IndexIntegrity
    # Orchestrates model scan, schema indexes, and comparison (Epic 5.4 core).
    module Runner
      class << self
        # @return [Integer] 0 if no violations, 1 otherwise
        def exit_code_for(root, stdout: $stdout, stderr: $stderr)
          root = Pathname.new(root)
          validations = scan_models(root)
          indexes = load_indexes(root, stderr: stderr)
          return 1 if indexes.nil?

          violations = ComparisonEngine.missing_indexes(validations: validations, indexes: indexes)
          if violations.empty?
            stdout.puts 'Index integrity: OK (no missing unique indexes for validations).'
            0
          else
            violations.each { |v| stdout.puts(v.message) }
            1
          end
        end

        private

        def scan_models(root)
          pattern = root.join('app', 'models', '**', '*.rb').to_s
          Dir.glob(pattern).each_with_object([]) do |path, acc|
            next if path.include?("#{File::SEPARATOR}concerns#{File::SEPARATOR}")

            acc.concat(ModelScanner.scan_file(path))
          end
        end

        def load_indexes(root, stderr:)
          schema_path = root.join('db', 'schema.rb')
          if schema_path.file?
            SchemaAnalyzer.parse_file(schema_path.to_s)
          elsif defined?(ActiveRecord::Base)
            SchemaAnalyzer.from_connection(ActiveRecord::Base.connection)
          else
            stderr.puts 'Index integrity: db/schema.rb not found and ActiveRecord is not available.'
            nil
          end
        end
      end
    end
  end
end
