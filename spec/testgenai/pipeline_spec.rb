RSpec.describe Testgenai::Pipeline do
  let(:generator) { instance_double(Testgenai::Generator::RspecGenerator) }
  let(:validator) { instance_double(Testgenai::Validator::RspecValidator) }
  let(:pipeline) { described_class.new(generator, validator) }

  let(:method_info) { {file: "lib/widget.rb", class: "Widget", method: "display", start_line: 2, end_line: 4} }
  let(:context) { {target_file: "class Widget; end", dependencies: [], example_usage: [], related_tests: nil} }
  let(:output_path) { "spec/widget_spec.rb" }
  let(:generated_code) { "RSpec.describe Widget do; end" }

  before do
    allow(generator).to receive(:output_path_for).with(method_info).and_return(output_path)
  end

  describe "#run" do
    context "when validation passes on first attempt" do
      before do
        allow(generator).to receive(:generate).with(method_info, context, feedback: nil)
          .and_return(generated_code)
        allow(validator).to receive(:validate).with(generated_code, output_path)
          .and_return({valid: true, runs: true, passes: true, errors: []})
      end

      it "returns success: true with 1 attempt" do
        result = pipeline.run(method_info, context)
        expect(result[:success]).to be true
        expect(result[:attempts]).to eq(1)
        expect(result[:output_path]).to eq(output_path)
        expect(result[:errors]).to be_empty
      end
    end

    context "when first attempt has assertion failures, second succeeds" do
      let(:fail_result) { {valid: true, runs: true, passes: false, errors: ["expected 1 got 2"]} }
      let(:pass_result) { {valid: true, runs: true, passes: true, errors: []} }

      before do
        allow(generator).to receive(:generate).with(method_info, context, feedback: nil)
          .and_return("attempt 1")
        allow(generator).to receive(:generate)
          .with(method_info, context, feedback: "The following tests failed: expected 1 got 2")
          .and_return("attempt 2")
        allow(validator).to receive(:validate).with("attempt 1", output_path).and_return(fail_result)
        allow(validator).to receive(:validate).with("attempt 2", output_path).and_return(pass_result)
      end

      it "returns success: true with 2 attempts" do
        result = pipeline.run(method_info, context)
        expect(result[:success]).to be true
        expect(result[:attempts]).to eq(2)
      end
    end

    context "when tests fail to load, passes load error feedback on retry" do
      let(:load_fail) { {valid: false, runs: false, passes: false, errors: ["cannot load missing"]} }
      let(:pass_result) { {valid: true, runs: true, passes: true, errors: []} }

      before do
        allow(generator).to receive(:generate).with(method_info, context, feedback: nil)
          .and_return("attempt 1")
        allow(generator).to receive(:generate)
          .with(method_info, context, feedback: "The following errors prevented the tests from running: cannot load missing")
          .and_return("attempt 2")
        allow(validator).to receive(:validate).with("attempt 1", output_path).and_return(load_fail)
        allow(validator).to receive(:validate).with("attempt 2", output_path).and_return(pass_result)
      end

      it "uses load error feedback phrasing and succeeds" do
        result = pipeline.run(method_info, context)
        expect(result[:success]).to be true
      end
    end

    context "when all 3 attempts fail" do
      before do
        allow(generator).to receive(:generate).and_return(generated_code)
        allow(validator).to receive(:validate)
          .and_return({valid: true, runs: true, passes: false, errors: ["always fails"]})
      end

      it "returns success: false after exactly 3 attempts" do
        result = pipeline.run(method_info, context)
        expect(result[:success]).to be false
        expect(result[:attempts]).to eq(3)
        expect(generator).to have_received(:generate).exactly(3).times
      end

      it "includes the last error in result" do
        result = pipeline.run(method_info, context)
        expect(result[:errors]).not_to be_empty
      end
    end
  end
end
