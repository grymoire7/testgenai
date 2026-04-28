module Testgenai
  module Scanner
    class FileExistenceScanner < Base
      def initialize(root: Dir.pwd)
        @root = root
      end

      def scan
        source_files.reject { |f| test_exists?(f) }.flat_map { |f| extract_methods(f) }
      end

      private

      def source_files
        %w[lib app].flat_map do |dir|
          full = File.join(@root, dir)
          Dir.exist?(full) ? Dir.glob(File.join(full, "**", "*.rb")) : []
        end
      end

      def test_exists?(source_file)
        rel = relative(source_file)
        base = rel.sub(/\A(?:lib|app)\//, "").sub(/\.rb\z/, "")
        File.exist?(File.join(@root, "spec", "#{base}_spec.rb")) ||
          File.exist?(File.join(@root, "test", "#{base}_test.rb"))
      end

      def relative(file)
        file.sub("#{@root}/", "")
      end

      def extract_methods(file)
        source = File.read(file)
        ast = Parser::CurrentRuby.parse(source)
        return [] unless ast
        collect_methods(ast, file, class_name: nil)
      rescue Parser::SyntaxError, EncodingError => e
        warn "Warning: could not parse #{file}: #{e.message}"
        []
      end
    end
  end
end
