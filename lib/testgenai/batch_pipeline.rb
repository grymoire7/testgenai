module Testgenai
  class BatchPipeline
    def initialize(config, context_builder, pipeline, reporter)
      @config = config
      @context_builder = context_builder
      @pipeline = pipeline
      @reporter = reporter
    end

    def run(untested_methods)
      results = {successful: [], failed: [], skipped: []}

      untested_methods.each_with_index do |method_info, i|
        sleep @config.pause if i > 0

        context = @context_builder.build(method_info)
        result = @pipeline.run(method_info, context)

        if result[:success]
          results[:successful] << result
          @reporter.success(method_info, result)
        else
          results[:failed] << result
          @reporter.failure(method_info, result)
        end
      rescue ConfigurationError => e
        @reporter.fatal_error(e)
        raise
      rescue => e
        results[:skipped] << {method_info: method_info, error: e.message}
        @reporter.skipped(method_info, e)
      end

      results
    end
  end
end
