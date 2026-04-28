module Testgenai
  class Pipeline
    MAX_ATTEMPTS = 3

    def initialize(generator, validator)
      @generator = generator
      @validator = validator
    end

    def run(method_info, context)
      output_path = @generator.output_path_for(method_info)
      feedback = nil

      MAX_ATTEMPTS.times do |i|
        test_code = @generator.generate(method_info, context, feedback: feedback)
        result = @validator.validate(test_code, output_path)

        if result[:runs] && result[:passes]
          return {success: true, output_path: output_path, attempts: i + 1, errors: []}
        end

        feedback = build_feedback(result)
      end

      {success: false, output_path: output_path, attempts: MAX_ATTEMPTS, errors: [feedback]}
    end

    private

    def build_feedback(result)
      if result[:runs]
        "The following tests failed: #{result[:errors].join(", ")}"
      else
        "The following errors prevented the tests from running: #{result[:errors].join(", ")}"
      end
    end
  end
end
