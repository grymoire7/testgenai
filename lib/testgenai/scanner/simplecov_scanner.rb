require "json"

module Testgenai
  module Scanner
    class SimplecovScanner < Base
      RESULTSET_PATH = "coverage/.resultset.json"

      def initialize(root: Dir.pwd)
        @root = root
      end

      def scan
        resultset_path = File.join(@root, RESULTSET_PATH)
        unless File.exist?(resultset_path)
          warn "Warning: #{RESULTSET_PATH} not found"
          return []
        end
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
    end
  end
end
