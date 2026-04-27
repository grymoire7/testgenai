require "parser/current"

module Testgenai
  module Scanner
    class Base
      def scan
        raise NotImplementedError, "#{self.class} must implement #scan"
      end

      private

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
