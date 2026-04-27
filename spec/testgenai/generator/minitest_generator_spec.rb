RSpec.describe Testgenai::Generator::MinitestGenerator do
  let(:config) { Testgenai::Configuration.new(framework: "minitest") }
  let(:generator) { described_class.new(config) }

  let(:method_info) { {file: "/app/lib/widget.rb", class: "Widget", method: "display", start_line: 5, end_line: 7} }
  let(:context) do
    {target_file: "class Widget; end", dependencies: [], example_usage: [], related_tests: nil}
  end

  let(:llm_response) { "```ruby\nclass WidgetTest < Minitest::Test\n  def test_display\n  end\nend\n```" }

  before { allow(generator).to receive(:call_llm).and_return(llm_response) }

  describe "#generate" do
    it "returns Minitest test code without fences" do
      result = generator.generate(method_info, context)
      expect(result).to include("WidgetTest")
      expect(result).not_to include("```")
    end

    it "includes Minitest-specific language in the prompt" do
      expect(generator).to receive(:call_llm) do |prompt|
        expect(prompt).to match(/minitest/i)
        llm_response
      end
      generator.generate(method_info, context)
    end

    it "includes the method name in the prompt" do
      expect(generator).to receive(:call_llm) do |prompt|
        expect(prompt).to include("display")
        llm_response
      end
      generator.generate(method_info, context)
    end

    it "includes feedback in the prompt when provided" do
      expect(generator).to receive(:call_llm) do |prompt|
        expect(prompt).to include("failed")
        llm_response
      end
      generator.generate(method_info, context, feedback: "assertion error")
    end
  end

  describe "#output_path_for" do
    it "maps lib/widget.rb to test/widget_test.rb" do
      info = method_info.merge(file: "/app/lib/widget.rb")
      allow(Dir).to receive(:pwd).and_return("/app")
      expect(generator.output_path_for(info)).to eq("/app/test/widget_test.rb")
    end

    it "maps lib/myapp/services/widget.rb to test/myapp/services/widget_test.rb" do
      info = method_info.merge(file: "/app/lib/myapp/services/widget.rb")
      allow(Dir).to receive(:pwd).and_return("/app")
      expect(generator.output_path_for(info)).to eq("/app/test/myapp/services/widget_test.rb")
    end

    it "maps app/models/user.rb to test/models/user_test.rb" do
      info = method_info.merge(file: "/app/app/models/user.rb")
      allow(Dir).to receive(:pwd).and_return("/app")
      expect(generator.output_path_for(info)).to eq("/app/test/models/user_test.rb")
    end

    it "uses output_dir when configured" do
      cfg = Testgenai::Configuration.new(framework: "minitest", output_dir: "/custom/out")
      gen = described_class.new(cfg)
      result = gen.output_path_for(method_info)
      expect(result).to start_with("/custom/out/")
    end
  end
end
