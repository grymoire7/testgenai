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
        return unless @config.api_key
        provider = @config.provider || "anthropic"
        RubyLLM.configure do |c|
          c.public_send(:"#{provider}_api_key=", @config.api_key)
        end
      end

      def call_llm(prompt)
        model = @config.model || default_model
        chat = RubyLLM.chat(model: model)
        chat.ask(prompt).content
      end

      def default_model
        "claude-sonnet-4-6"
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
