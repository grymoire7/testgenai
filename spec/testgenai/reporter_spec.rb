RSpec.describe Testgenai::Reporter do
  let(:reporter) { described_class.new }
  let(:method_info) { {file: "lib/widget.rb", class: "Widget", method: "display", start_line: 5, end_line: 7} }

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end

  describe "#scan_results" do
    it "reports each untested method" do
      output = capture_stdout { reporter.scan_results([method_info]) }
      expect(output).to include("Widget#display")
      expect(output).to include("lib/widget.rb")
    end

    it "reports a count of methods found" do
      output = capture_stdout { reporter.scan_results([method_info, method_info]) }
      expect(output).to include("2")
    end

    it "reports nothing found when empty" do
      output = capture_stdout { reporter.scan_results([]) }
      expect(output).to include("No untested")
    end
  end

  describe "#context_result" do
    let(:context) do
      {
        target_file: "class Widget; end",
        dependencies: ["lib/widget_helper.rb"],
        example_usage: ["widget.display"],
        related_tests: nil
      }
    end

    it "outputs context details for the method" do
      output = capture_stdout { reporter.context_result(method_info, context) }
      expect(output).to include("Widget#display")
      expect(output).to include("widget_helper.rb")
    end
  end

  describe "#success" do
    it "reports the generated file path and attempt count" do
      result = {output_path: "spec/widget_spec.rb", attempts: 1}
      output = capture_stdout { reporter.success(method_info, result) }
      expect(output).to include("spec/widget_spec.rb")
      expect(output).to include("Widget#display")
    end
  end

  describe "#failure" do
    it "reports failure with attempt count" do
      result = {output_path: "spec/widget_spec.rb", attempts: 3, errors: ["expected 1 got 2"]}
      output = capture_stdout { reporter.failure(method_info, result) }
      expect(output).to include("Widget#display")
      expect(output).to include("3")
    end
  end

  describe "#skipped" do
    it "reports the skip reason" do
      error = StandardError.new("parse error")
      output = capture_stdout { reporter.skipped(method_info, error) }
      expect(output).to include("Widget#display")
      expect(output).to include("parse error")
    end
  end

  describe "#summary" do
    it "reports counts of successful, failed, skipped" do
      results = {successful: [{}, {}], failed: [{}], skipped: []}
      output = capture_stdout { reporter.summary(results) }
      expect(output).to include("2")
      expect(output).to include("1")
    end
  end

  describe "#fatal_error" do
    it "reports a fatal error message" do
      output = capture_stdout { reporter.fatal_error(StandardError.new("auth failed")) }
      expect(output).to include("auth failed")
    end
  end
end
