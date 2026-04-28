RSpec.describe Testgenai::BatchPipeline do
  let(:config) { Testgenai::Configuration.new(pause: 0) }
  let(:context_builder) { instance_double(Testgenai::ContextBuilder) }
  let(:pipeline) { instance_double(Testgenai::Pipeline) }
  let(:reporter) do
    instance_double(Testgenai::Reporter,
      success: nil, failure: nil, skipped: nil,
      fatal_error: nil, summary: nil)
  end

  let(:batch) { described_class.new(config, context_builder, pipeline, reporter) }

  let(:method_info) { {file: "lib/widget.rb", class: "Widget", method: "display", start_line: 2, end_line: 4} }
  let(:context) { {target_file: "class Widget; end", dependencies: [], example_usage: [], related_tests: nil} }

  before do
    allow(context_builder).to receive(:build).with(method_info).and_return(context)
  end

  describe "#run" do
    context "when pipeline succeeds" do
      let(:success_result) { {success: true, output_path: "spec/widget_spec.rb", attempts: 1, errors: []} }

      before do
        allow(pipeline).to receive(:run).with(method_info, context).and_return(success_result)
      end

      it "includes the result in successful" do
        results = batch.run([method_info])
        expect(results[:successful]).to include(success_result)
        expect(results[:failed]).to be_empty
        expect(results[:skipped]).to be_empty
      end

      it "calls reporter.success" do
        batch.run([method_info])
        expect(reporter).to have_received(:success).with(method_info, success_result)
      end
    end

    context "when pipeline fails" do
      let(:fail_result) { {success: false, output_path: "spec/widget_spec.rb", attempts: 3, errors: ["still wrong"]} }

      before do
        allow(pipeline).to receive(:run).and_return(fail_result)
      end

      it "includes the result in failed" do
        results = batch.run([method_info])
        expect(results[:failed]).to include(fail_result)
      end

      it "calls reporter.failure" do
        batch.run([method_info])
        expect(reporter).to have_received(:failure).with(method_info, fail_result)
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow(pipeline).to receive(:run).and_raise(StandardError, "parse error")
      end

      it "counts as skipped" do
        results = batch.run([method_info])
        expect(results[:skipped].size).to eq(1)
        expect(results[:skipped].first[:error]).to eq("parse error")
      end

      it "calls reporter.skipped" do
        batch.run([method_info])
        expect(reporter).to have_received(:skipped)
      end
    end

    context "when a ConfigurationError occurs (auth failure)" do
      before do
        allow(pipeline).to receive(:run).and_raise(Testgenai::ConfigurationError, "auth failed")
      end

      it "re-raises to abort the run" do
        expect { batch.run([method_info]) }.to raise_error(Testgenai::ConfigurationError)
      end

      it "calls reporter.fatal_error before aborting" do
        begin
          batch.run([method_info])
        rescue
          nil
        end
        expect(reporter).to have_received(:fatal_error)
      end
    end

    context "with multiple methods and pause: 0" do
      let(:method2) { method_info.merge(method: "initialize") }

      before do
        allow(context_builder).to receive(:build).and_return(context)
        allow(pipeline).to receive(:run).and_return({success: true, output_path: "x", attempts: 1, errors: []})
      end

      it "processes all methods" do
        results = batch.run([method_info, method2])
        expect(results[:successful].size).to eq(2)
      end
    end
  end
end
