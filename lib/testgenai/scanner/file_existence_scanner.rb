require "parser/current"

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

      def collect_methods(node, file, class_name:)
        return [] unless node.is_a?(Parser::AST::Node)

        case node.type
        when :class, :module
          current = [class_name, const_name(node.children[0])].compact.join("::")
          node.children.flat_map { |c| collect_methods(c, file, class_name: current) }
        when :def
          [method_descriptor(node, file, class_name, node.children[0].to_s)]
        when :defs
          [method_descriptor(node, file, class_name, "self.#{node.children[1]}")]
        else
          node.children.flat_map { |c| collect_methods(c, file, class_name: class_name) }
        end
      end

      def method_descriptor(node, file, class_name, method_name)
        {
          file: file,
          class: class_name,
          method: method_name,
          start_line: node.loc.line,
          end_line: node.loc.end.line
        }
      end

      def const_name(node)
        return nil unless node.is_a?(Parser::AST::Node) && node.type == :const
        parts = []
        current = node
        while current.is_a?(Parser::AST::Node) && current.type == :const
          parts.unshift(current.children[1].to_s)
          current = current.children[0]
        end
        parts.join("::")
      end
    end
  end
end
