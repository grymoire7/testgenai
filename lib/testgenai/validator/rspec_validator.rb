module Testgenai
  module Validator
    class RspecValidator < Base
      def validate(test_code, output_path)
        write_test_file(test_code, output_path)
        output, exit_status = run_rspec(output_path)
        parse_result(output, exit_status, output_path)
      end

      private

      def run_rspec(path)
        output = `bundle exec rspec #{path} --format documentation 2>&1`
        [output, $?.exitstatus]
      end

      def parse_result(output, exit_status, output_path)
        if load_error?(output)
          errors = extract_load_errors(output)
          cleanup(output_path)
          {valid: false, runs: false, passes: false, errors: errors}
        elsif exit_status == 0
          {valid: true, runs: true, passes: true, errors: []}
        else
          errors = extract_failures(output)
          {valid: true, runs: true, passes: false, errors: errors}
        end
      end

      def load_error?(output)
        output.match?(/LoadError|SyntaxError|NameError.*uninitialized constant|An error occurred while loading/)
      end

      def extract_load_errors(output)
        lines = output.lines
        lines.select { |l| l.match?(/LoadError|SyntaxError|NameError|cannot load/) }
             .map(&:strip)
             .first(3)
      end

      def extract_failures(output)
        failures = []
        in_failure = false
        output.each_line do |line|
          if line.match?(/^\s+\d+\)/)
            in_failure = true
            failures << line.strip
          elsif in_failure && line.match?(/^\s+(Failure|Error):/)
            failures.last << " #{line.strip}"
          elsif in_failure && line.strip.empty?
            in_failure = false
          end
        end
        failures.first(5)
      end
    end
  end
end
