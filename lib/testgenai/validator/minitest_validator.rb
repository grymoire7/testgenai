require "shellwords"

module Testgenai
  module Validator
    class MinitestValidator < Base
      def validate(test_code, output_path)
        write_test_file(test_code, output_path)
        output, exit_status = run_minitest(output_path)
        parse_result(output, exit_status, output_path)
      end

      private

      def run_minitest(path)
        output = `bundle exec ruby -Ilib -Itest #{Shellwords.escape(path)} 2>&1`
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
        output.match?(/LoadError|SyntaxError|cannot load such file/)
      end

      def extract_load_errors(output)
        output.lines
              .select { |l| l.match?(/LoadError|SyntaxError|cannot load/) }
              .map(&:strip)
              .first(3)
      end

      def extract_failures(output)
        output.lines
              .select { |l| l.match?(/Failure:|Error:|\d+\) /) }
              .map(&:strip)
              .reject(&:empty?)
              .first(5)
      end
    end
  end
end
