RSpec.describe Testgenai::Generator::RspecGenerator do
  let(:config) do
    Testgenai::Configuration.new(
      framework: "rspec",
      model: "claude-sonnet-4-6"
    )
  end
  let(:generator) { described_class.new(config) }

  let(:method_info) { {file: "/app/lib/widget.rb", class: "Widget", method: "display", start_line: 5, end_line: 7} }
  let(:context) do
    {
      target_file: "class Widget\n  def display\n    puts 'hi'\n  end\nend",
      dependencies: [],
      example_usage: [],
      related_tests: nil
    }
  end

  let(:llm_response) { "```ruby\nRSpec.describe Widget do\n  it 'displays' do\n  end\nend\n```" }

  before do
    allow(generator).to receive(:call_llm).and_return(llm_response)
  end

  describe "#generate" do
    it "returns extracted Ruby code without fences" do
      result = generator.generate(method_info, context)
      expect(result).to include("RSpec.describe Widget")
      expect(result).not_to include("```")
    end

    it "passes feedback in the prompt when provided" do
      expect(generator).to receive(:call_llm) do |prompt|
        expect(prompt).to include("failed")
        llm_response
      end
      generator.generate(method_info, context, feedback: "expected 1 got 2")
    end

    it "includes the method class and name in the prompt" do
      expect(generator).to receive(:call_llm) do |prompt|
        expect(prompt).to include("Widget")
        expect(prompt).to include("display")
        llm_response
      end
      generator.generate(method_info, context)
    end

    it "includes related tests in the prompt when present" do
      ctx_with_tests = context.merge(related_tests: "RSpec.describe Widget do; end")
      expect(generator).to receive(:call_llm) do |prompt|
        expect(prompt).to include("RSpec.describe Widget")
        llm_response
      end
      generator.generate(method_info, ctx_with_tests)
    end
  end

  describe "#output_path_for" do
    it "maps lib/widget.rb to spec/widget_spec.rb" do
      info = method_info.merge(file: "/app/lib/widget.rb")
      allow(Dir).to receive(:pwd).and_return("/app")
      expect(generator.output_path_for(info)).to eq("/app/spec/widget_spec.rb")
    end

    it "maps lib/myapp/services/widget.rb to spec/myapp/services/widget_spec.rb" do
      info = method_info.merge(file: "/app/lib/myapp/services/widget.rb")
      allow(Dir).to receive(:pwd).and_return("/app")
      expect(generator.output_path_for(info)).to eq("/app/spec/myapp/services/widget_spec.rb")
    end

    it "uses output_dir when configured" do
      cfg = Testgenai::Configuration.new(framework: "rspec", output_dir: "/custom/out")
      gen = described_class.new(cfg)
      result = gen.output_path_for(method_info)
      expect(result).to start_with("/custom/out/")
    end
  end
end
