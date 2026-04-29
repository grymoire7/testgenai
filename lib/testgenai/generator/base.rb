require "ruby_llm"

module Testgenai
  module Generator
    class Base
      def initialize(config)
        @config = config
        configure_llm
      end

      def generate(method_info, context, feedback: nil)
        prompt = build_prompt(method_info, context, feedback: feedback)
        response = call_llm(prompt)
        CodeExtractor.extract(response)
      end

      def output_path_for(method_info)
        raise NotImplementedError, "#{self.class} must implement #output_path_for"
      end

      private

      def configure_llm
        return unless @config.api_key && @config.provider
        RubyLLM.configure do |c|
          c.public_send(:"#{@config.provider}_api_key=", @config.api_key)
        end
      end

      def call_llm(prompt)
        if @config.provider.nil? && @config.model.nil?
          raise ConfigurationError,
            "provider and model must be configured. " \
            "Set TESTGENAI_PROVIDER and TESTGENAI_MODEL, or use --provider and --model flags."
        end
        if @config.provider.nil?
          raise ConfigurationError,
            "provider must be configured. Set TESTGENAI_PROVIDER or use --provider flag."
        end
        if @config.model.nil?
          raise ConfigurationError,
            "model must be configured. Set TESTGENAI_MODEL or use --model flag."
        end
        chat = RubyLLM.chat(model: @config.model)
        chat.ask(prompt).content
      end

      def build_prompt(method_info, context, feedback: nil)
        raise NotImplementedError, "#{self.class} must implement #build_prompt"
      end

      def custom_output_path(method_info, suffix)
        class_part = method_info[:class]&.downcase&.gsub("::", "/") || "unknown"
        method_part = method_info[:method].to_s.gsub(/\Aself\./, "").tr(".", "_")
        File.join(@config.output_dir, "#{class_part}_#{method_part}#{suffix}")
      end
    end
  end
end
