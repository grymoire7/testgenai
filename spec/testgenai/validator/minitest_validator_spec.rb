RSpec.describe Testgenai::Validator::MinitestValidator do
  let(:validator) { described_class.new }
  let(:root) { Dir.mktmpdir }
  let(:output_path) { File.join(root, "test", "widget_test.rb") }

  after { FileUtils.rm_rf(root) }

  let(:passing_code) do
    <<~RUBY
      require "minitest/autorun"
      class WidgetTest < Minitest::Test
        def test_addition
          assert_equal 2, 1 + 1
        end
      end
    RUBY
  end

  let(:failing_code) do
    <<~RUBY
      require "minitest/autorun"
      class WidgetTest < Minitest::Test
        def test_fail
          assert_equal 2, 1
        end
      end
    RUBY
  end

  let(:load_error_code) do
    <<~RUBY
      require "totally_missing_gem_xyz_abc"
      require "minitest/autorun"
      class WidgetTest < Minitest::Test
        def test_something; end
      end
    RUBY
  end

  describe "#validate" do
    it "returns passes: true for a passing test" do
      result = validator.validate(passing_code, output_path)
      expect(result[:passes]).to be true
      expect(result[:runs]).to be true
      expect(result[:valid]).to be true
    end

    it "returns passes: false for a failing test" do
      result = validator.validate(failing_code, output_path)
      expect(result[:passes]).to be false
      expect(result[:runs]).to be true
      expect(result[:errors]).not_to be_empty
    end

    it "returns runs: false for a load error" do
      result = validator.validate(load_error_code, output_path)
      expect(result[:runs]).to be false
      expect(result[:errors]).not_to be_empty
    end

    it "removes the file when tests fail to load" do
      validator.validate(load_error_code, output_path)
      expect(File.exist?(output_path)).to be false
    end

    it "keeps the file when tests pass" do
      validator.validate(passing_code, output_path)
      expect(File.exist?(output_path)).to be true
    end

    it "keeps the file when tests fail (assertion failures)" do
      validator.validate(failing_code, output_path)
      expect(File.exist?(output_path)).to be true
    end
  end
end
