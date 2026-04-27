module Testgenai
  module Generator
    class MinitestGenerator < Base
      def output_path_for(method_info)
        return custom_output_path(method_info, "_test.rb") if @config.output_dir

        rel = method_info[:file].sub("#{Dir.pwd}/", "")
        base = rel.sub(/\A(?:lib|app)\//, "").sub(/\.rb\z/, "")
        File.join(Dir.pwd, "test", "#{base}_test.rb")
      end

      private

      def build_prompt(method_info, context, feedback: nil)
        prompt = <<~PROMPT
          You are an expert Ruby developer. Write Minitest tests for the following method.

          ## Method to test
          Class: #{method_info[:class]}
          Method: #{method_info[:method]}
          Location: #{method_info[:file]}:#{method_info[:start_line]}-#{method_info[:end_line]}

          ## Source file
          ```ruby
          #{context[:target_file]}
          ```
        PROMPT

        unless context[:dependencies].to_a.empty?
          prompt += "\n## Dependencies\n"
          prompt += context[:dependencies].map { |d| "- #{d}" }.join("\n")
          prompt += "\n"
        end

        context[:example_usage].to_a.each_with_index do |usage, i|
          prompt += "\n## Example usage #{i + 1}\n```ruby\n#{usage}\n```\n"
        end

        if context[:related_tests]
          prompt += "\n## Existing tests (match this style)\n```ruby\n#{context[:related_tests]}\n```\n"
        end

        if feedback
          prompt += "\n## Previous attempt failed — fix these issues\n#{feedback}\n"
        end

        prompt + "\nWrite comprehensive Minitest tests using test/setup methods and Minitest assertions. " \
                 "Subclass Minitest::Test. Return ONLY the test code in a ```ruby code block."
      end
    end
  end
end
