# frozen_string_literal: true

begin
  require 'active_support/inflector'
rescue LoadError
  # Optional: table inference uses a simple plural fallback without ActiveSupport.
  nil
end

module RaceGuard
  module IndexIntegrity
    # Internal: infer AR table name from +app/models+ path (Epic 5.3).
    module TableInference
      class << self
        def table_for_model_path(filename)
          path = filename.to_s.tr('\\', '/')
          return nil if path.include?('/concerns/')

          rel = path.sub(%r{.*?app/models/}i, '')
          return nil if rel.empty?

          rel = rel.sub(/\.rb\z/i, '')
          segments = rel.split('/').compact.reject(&:empty?)
          return nil if segments.empty?

          infer_from_segments(segments)
        end

        private

        def infer_from_segments(segments)
          if defined?(ActiveSupport::Inflector)
            const_name = segments.map { |seg| ActiveSupport::Inflector.camelize(seg) }.join('::')
            ActiveSupport::Inflector.tableize(const_name).tr('/', '_').to_sym
          else
            last = segments.pop
            (segments + [simple_plural(last)]).join('_').to_sym
          end
        end

        def simple_plural(segment)
          w = segment.downcase
          "#{w}s"
        end
      end
    end
  end
end
