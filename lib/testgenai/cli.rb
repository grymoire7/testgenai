require "thor"

module Testgenai
  class CLI < Thor
    package_name "testgenai"

    class_option :output_dir, aliases: "-o", desc: "Output directory for generated tests"
    class_option :test_framework, aliases: "-t", default: "rspec", desc: "Test framework: rspec or minitest"
    class_option :provider, desc: "LLM provider (e.g. anthropic, openai)"
    class_option :model, desc: "LLM model name"
    class_option :api_key, desc: "API key (overrides env var)"
    class_option :pause, aliases: "-p", type: :numeric, default: 1, desc: "Pause between API calls in seconds"

    def self.exit_on_failure?
      true
    end

    map "--version" => :version

    desc "version", "Show version"
    def version
      puts Testgenai::VERSION
    end

    desc "scan", "Scan for untested code and report it"
    def scan
      config = build_config
      scanner = build_scanner(config)
      methods = scanner.scan
      reporter.scan_results(methods)
    end

    desc "context", "Scan, build LLM context, and report it (diagnostic)"
    def context
      config = build_config
      scanner = build_scanner(config)
      methods = scanner.scan
      ctx_builder = ContextBuilder.new
      methods.each do |method_info|
        ctx = ctx_builder.build(method_info)
        reporter.context_result(method_info, ctx)
      end
    end

    desc "generate", "Full pipeline: scan → context → generate → validate"
    def generate
      config = build_config
      scanner = build_scanner(config)
      methods = scanner.scan

      if methods.empty?
        reporter.scan_results(methods)
        exit 0
      end

      generator = config.generator_class.new(config)
      validator = config.validator_class.new
      single_pipeline = Pipeline.new(generator, validator)
      ctx_builder = ContextBuilder.new
      batch = BatchPipeline.new(config, ctx_builder, single_pipeline, reporter)

      results = batch.run(methods)
      reporter.summary(results)
      exit(results[:successful].empty? ? 1 : 0)
    rescue ConfigurationError => e
      warn "Error: #{e.message}"
      exit 2
    end

    private

    def build_config
      Configuration.new(
        provider: options[:provider],
        model: options[:model],
        api_key: options[:api_key],
        framework: options[:test_framework],
        output_dir: options[:output_dir],
        pause: options[:pause]
      )
    rescue ConfigurationError => e
      warn "Configuration error: #{e.message}"
      exit 2
    end

    def build_scanner(config)
      resultset = File.join(Dir.pwd, "coverage", ".resultset.json")

      if File.exist?(resultset)
        return Scanner::SimplecovScanner.new
      end

      unless simplecov_in_gemfile?
        warn "Warning: SimpleCov not found in Gemfile or gemspec. Using file-existence scanner."
        warn "Note: file-existence scanner cannot detect untested methods in partially-tested files."
        return Scanner::FileExistenceScanner.new
      end

      warn "Running test suite to generate coverage data..."
      cmd = config.framework == "minitest" ? "bundle exec ruby -Itest test/**/*_test.rb" : "bundle exec rspec"
      system({"COVERAGE" => "true"}, cmd, out: File::NULL, err: File::NULL)

      if File.exist?(resultset)
        Scanner::SimplecovScanner.new
      else
        warn "Warning: Coverage generation failed. Using file-existence scanner."
        Scanner::FileExistenceScanner.new
      end
    end

    def simplecov_in_gemfile?
      gemfiles = Dir.glob(File.join(Dir.pwd, "{Gemfile,*.gemspec}"))
      gemfiles.any? { |f| File.read(f).include?("simplecov") }
    end

    def reporter
      @reporter ||= Reporter.new
    end
  end
end
