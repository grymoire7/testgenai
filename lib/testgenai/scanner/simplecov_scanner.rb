require "json"
require "parser/current"

module Testgenai
  module Scanner
    class SimplecovScanner < Base
      RESULTSET_PATH = "coverage/.resultset.json"

      def initialize(root: Dir.pwd)
        @root = root
      end

      def scan
        coverage = merged_coverage
        coverage.flat_map do |file, lines|
          next [] if test_file?(file)
          next [] unless File.exist?(file)
          extract_untested_methods(file, lines)
        end
      end

      private

      def merged_coverage
        resultset = JSON.parse(File.read(File.join(@root, RESULTSET_PATH)))
        result = {}
        resultset.each_value do |runner_data|
          (runner_data["coverage"] || {}).each do |file, data|
            lines = data["lines"]
            result[file] = merge_lines(result[file], lines)
          end
        end
        result
      end

      def merge_lines(existing, new_lines)
        return new_lines unless existing
        existing.zip(new_lines).map do |a, b|
          next nil if a.nil? && b.nil?
          (a || 0) + (b || 0)
        end
      end

      def test_file?(file)
        relative = file.sub("#{@root}/", "")
        relative.start_with?("spec/", "test/")
      end

      def extract_untested_methods(file, coverage_lines)
        source = File.read(file)
        ast = Parser::CurrentRuby.parse(source)
        return [] unless ast
        methods = collect_methods(ast, file, class_name: nil)
        methods.select { |m| untested?(coverage_lines, m[:start_line], m[:end_line]) }
      rescue Parser::SyntaxError, EncodingError => e
        warn "Warning: could not parse #{file}: #{e.message}"
        []
      end

      def untested?(coverage_lines, start_line, end_line)
        method_lines = coverage_lines[(start_line - 1)..(end_line - 1)] || []
        executable = method_lines.compact
        executable.any? && executable.all?(&:zero?)
      end

      def collect_methods(node, file, class_name:)
        return [] unless node.is_a?(Parser::AST::Node)
        case node.type
        when :class, :module
          current = [class_name, const_name(node.children[0])].compact.join("::")
          node.children.flat_map { |c| collect_methods(c, file, class_name: current) }
        when :def
          [{file: file, class: class_name, method: node.children[0].to_s,
            start_line: node.loc.line, end_line: node.loc.end.line}]
        when :defs
          [{file: file, class: class_name, method: "self.#{node.children[1]}",
            start_line: node.loc.line, end_line: node.loc.end.line}]
        else
          node.children.flat_map { |c| collect_methods(c, file, class_name: class_name) }
        end
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
