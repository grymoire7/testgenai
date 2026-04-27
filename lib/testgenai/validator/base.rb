require "fileutils"

module Testgenai
  module Validator
    class Base
      def validate(test_code, output_path)
        raise NotImplementedError, "#{self.class} must implement #validate"
      end

      private

      def write_test_file(test_code, output_path)
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, test_code)
      end

      def cleanup(output_path)
        File.delete(output_path) if File.exist?(output_path)
      end
    end
  end
end
