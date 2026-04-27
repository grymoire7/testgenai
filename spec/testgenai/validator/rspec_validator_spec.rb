RSpec.describe Testgenai::Validator::RspecValidator do
  let(:validator) { described_class.new }
  let(:root) { Dir.mktmpdir }
  let(:output_path) { File.join(root, "spec", "widget_spec.rb") }

  after { FileUtils.rm_rf(root) }

  let(:passing_code) do
    <<~RUBY
      RSpec.describe "Widget" do
        it "passes" do
          expect(1 + 1).to eq(2)
        end
      end
    RUBY
  end

  let(:failing_code) do
    <<~RUBY
      RSpec.describe "Widget" do
        it "fails" do
          expect(1).to eq(2)
        end
      end
    RUBY
  end

  let(:load_error_code) do
    <<~RUBY
      require "totally_missing_gem_xyz_abc"
      RSpec.describe "Widget" do
        it "something" do; end
      end
    RUBY
  end

  describe "#validate" do
    it "returns valid: true, runs: true, passes: true for a passing test" do
      result = validator.validate(passing_code, output_path)
      expect(result[:valid]).to be true
      expect(result[:runs]).to be true
      expect(result[:passes]).to be true
      expect(result[:errors]).to be_empty
    end

    it "returns runs: true, passes: false for a failing test" do
      result = validator.validate(failing_code, output_path)
      expect(result[:valid]).to be true
      expect(result[:runs]).to be true
      expect(result[:passes]).to be false
      expect(result[:errors]).not_to be_empty
    end

    it "returns runs: false for a load error" do
      result = validator.validate(load_error_code, output_path)
      expect(result[:runs]).to be false
      expect(result[:errors]).not_to be_empty
    end

    it "writes the test file before running" do
      validator.validate(passing_code, output_path)
      expect(File.exist?(output_path)).to be true
    end

    it "removes the file when tests fail to load" do
      validator.validate(load_error_code, output_path)
      expect(File.exist?(output_path)).to be false
    end

    it "keeps the file when tests pass" do
      validator.validate(passing_code, output_path)
      expect(File.exist?(output_path)).to be true
    end

    it "keeps the file when tests fail (assertion failures, not load errors)" do
      validator.validate(failing_code, output_path)
      expect(File.exist?(output_path)).to be true
    end
  end
end
