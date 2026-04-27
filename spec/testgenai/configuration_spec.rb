RSpec.describe Testgenai::Configuration do
  describe "framework" do
    it "defaults to rspec" do
      expect(described_class.new.framework).to eq("rspec")
    end

    it "reads from TESTGENAI_FRAMEWORK env var" do
      ENV["TESTGENAI_FRAMEWORK"] = "minitest"
      expect(described_class.new.framework).to eq("minitest")
    ensure
      ENV.delete("TESTGENAI_FRAMEWORK")
    end

    it "flag takes precedence over env var" do
      ENV["TESTGENAI_FRAMEWORK"] = "minitest"
      config = described_class.new(framework: "rspec")
      expect(config.framework).to eq("rspec")
    ensure
      ENV.delete("TESTGENAI_FRAMEWORK")
    end
  end

  describe "pause" do
    it "defaults to 1.0" do
      expect(described_class.new.pause).to eq(1.0)
    end

    it "reads from TESTGENAI_PAUSE env var" do
      ENV["TESTGENAI_PAUSE"] = "2.5"
      expect(described_class.new.pause).to eq(2.5)
    ensure
      ENV.delete("TESTGENAI_PAUSE")
    end

    it "flag takes precedence over env var" do
      ENV["TESTGENAI_PAUSE"] = "2.5"
      expect(described_class.new(pause: 0.5).pause).to eq(0.5)
    ensure
      ENV.delete("TESTGENAI_PAUSE")
    end
  end

  describe "provider, model, api_key, output_dir" do
    it "reads provider from TESTGENAI_PROVIDER" do
      ENV["TESTGENAI_PROVIDER"] = "openai"
      expect(described_class.new.provider).to eq("openai")
    ensure
      ENV.delete("TESTGENAI_PROVIDER")
    end

    it "reads model from TESTGENAI_MODEL" do
      ENV["TESTGENAI_MODEL"] = "gpt-4"
      expect(described_class.new.model).to eq("gpt-4")
    ensure
      ENV.delete("TESTGENAI_MODEL")
    end

    it "reads output_dir from TESTGENAI_OUTPUT_DIR" do
      ENV["TESTGENAI_OUTPUT_DIR"] = "/tmp/tests"
      expect(described_class.new.output_dir).to eq("/tmp/tests")
    ensure
      ENV.delete("TESTGENAI_OUTPUT_DIR")
    end

    it "flags override env vars" do
      ENV["TESTGENAI_MODEL"] = "gpt-4"
      config = described_class.new(model: "claude-sonnet-4-6")
      expect(config.model).to eq("claude-sonnet-4-6")
    ensure
      ENV.delete("TESTGENAI_MODEL")
    end
  end

  describe "#generator_class" do
    it "returns RspecGenerator for rspec framework" do
      config = described_class.new(framework: "rspec")
      expect(config.generator_class).to eq(Testgenai::Generator::RspecGenerator)
    end

    it "returns MinitestGenerator for minitest framework" do
      config = described_class.new(framework: "minitest")
      expect(config.generator_class).to eq(Testgenai::Generator::MinitestGenerator)
    end

    it "raises ConfigurationError for unknown framework" do
      config = described_class.new(framework: "jest")
      expect { config.generator_class }.to raise_error(Testgenai::ConfigurationError, /unknown framework/i)
    end
  end

  describe "#validator_class" do
    it "returns RspecValidator for rspec framework" do
      config = described_class.new(framework: "rspec")
      expect(config.validator_class).to eq(Testgenai::Validator::RspecValidator)
    end

    it "returns MinitestValidator for minitest framework" do
      config = described_class.new(framework: "minitest")
      expect(config.validator_class).to eq(Testgenai::Validator::MinitestValidator)
    end

    it "raises ConfigurationError for unknown framework" do
      config = described_class.new(framework: "jest")
      expect { config.validator_class }.to raise_error(Testgenai::ConfigurationError, /unknown framework/i)
    end
  end
end
