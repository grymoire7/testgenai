require "parser/current"

module Testgenai
  class ContextBuilder
    def initialize(root: Dir.pwd)
      @root = root
    end

    def build(method_info)
      {
        target_file: File.read(method_info[:file]),
        dependencies: extract_dependencies(method_info[:file]),
        example_usage: find_usages(method_info[:method]),
        related_tests: find_related_tests(method_info[:file])
      }
    rescue => e
      raise Error, "Could not build context for #{method_info[:file]}: #{e.message}"
    end

    private

    def extract_dependencies(file)
      source = File.read(file)
      ast = Parser::CurrentRuby.parse(source)
      return [] unless ast
      find_requires(ast, File.dirname(file))
    rescue Parser::SyntaxError
      []
    end

    def find_requires(node, dir, results = [])
      return results unless node.is_a?(Parser::AST::Node)

      if node.type == :send && node.children[0].nil? && node.children[2]&.type == :str
        path = node.children[2].children[0]
        case node.children[1]
        when :require_relative
          resolved = File.expand_path("#{path}.rb", dir)
          results << resolved if File.exist?(resolved)
        when :require
          resolved = File.join(@root, "lib", "#{path}.rb")
          results << resolved if File.exist?(resolved)
        end
      end

      node.children.each { |c| find_requires(c, dir, results) }
      results
    end

    def find_usages(method_name)
      name = method_name.to_s.sub(/\Aself\./, "")
      pattern = /\.#{Regexp.escape(name)}[\s(]/
      usages = []

      source_files.each do |file|
        lines = File.readlines(file)
        lines.each_with_index do |line, i|
          next unless line.match?(pattern)
          start = [0, i - 2].max
          finish = [lines.size - 1, i + 2].min
          usages << lines[start..finish].join
          break if usages.size >= 3
        end
        break if usages.size >= 3
      end

      usages
    end

    def find_related_tests(source_file)
      rel = source_file.sub("#{@root}/", "")
      base = rel.sub(/\A(?:lib|app)\//, "").sub(/\.rb\z/, "")

      spec_path = File.join(@root, "spec", "#{base}_spec.rb")
      test_path = File.join(@root, "test", "#{base}_test.rb")

      if File.exist?(spec_path)
        File.read(spec_path)
      elsif File.exist?(test_path)
        File.read(test_path)
      end
    end

    def source_files
      %w[lib app].flat_map do |dir|
        full = File.join(@root, dir)
        Dir.exist?(full) ? Dir.glob(File.join(full, "**", "*.rb")) : []
      end
    end
  end
end
