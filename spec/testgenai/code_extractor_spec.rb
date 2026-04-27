RSpec.describe Testgenai::CodeExtractor do
  describe ".extract" do
    it "extracts content from a ruby fence" do
      response = "Here is the test:\n```ruby\nRSpec.describe Widget do\nend\n```\nDone."
      expect(described_class.extract(response)).to eq("RSpec.describe Widget do\nend\n")
    end

    it "extracts content from a generic fence" do
      response = "```\nsome code\n```"
      expect(described_class.extract(response)).to eq("some code\n")
    end

    it "returns raw response when no fences are present" do
      response = "RSpec.describe Widget do\nend"
      expect(described_class.extract(response)).to eq("RSpec.describe Widget do\nend")
    end

    it "prefers ruby fence over generic fence" do
      response = "```ruby\npreferred\n```\n```\nfallback\n```"
      expect(described_class.extract(response)).to eq("preferred\n")
    end
  end

  describe ".valid_ruby?" do
    it "returns true for valid Ruby" do
      expect(described_class.valid_ruby?("def foo; 42; end")).to be true
    end

    it "returns false for invalid Ruby" do
      expect(described_class.valid_ruby?("def foo end end")).to be false
    end
  end
end
