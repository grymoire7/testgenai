module Testgenai
  class Configuration
    attr_reader :provider, :model, :api_key, :framework, :output_dir, :pause

    def initialize(options = {})
      @provider = options[:provider] || ENV["TESTGENAI_PROVIDER"]
      @model = options[:model] || ENV["TESTGENAI_MODEL"]
      @api_key = options[:api_key]
      @framework = options[:framework] || ENV["TESTGENAI_FRAMEWORK"] || "rspec"
      @output_dir = options[:output_dir] || ENV["TESTGENAI_OUTPUT_DIR"]
      @pause = (options[:pause] || ENV["TESTGENAI_PAUSE"] || 1).to_f
    end

    def generator_class
      case framework
      when "rspec" then Generator::RspecGenerator
      when "minitest" then Generator::MinitestGenerator
      else raise ConfigurationError, "Unknown framework: #{framework}"
      end
    end

    def validator_class
      case framework
      when "rspec" then Validator::RspecValidator
      when "minitest" then Validator::MinitestValidator
      else raise ConfigurationError, "Unknown framework: #{framework}"
      end
    end
  end
end
