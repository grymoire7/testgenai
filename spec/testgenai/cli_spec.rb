RSpec.describe Testgenai::CLI do
  let(:root) { Dir.mktmpdir }
  after { FileUtils.rm_rf(root) }

  describe "version flag" do
    it "outputs the version" do
      expect { described_class.start(["--version"]) }.to output(/#{Testgenai::VERSION}/o).to_stdout
    end
  end

  describe "scanner startup sequence" do
    let(:config) { Testgenai::Configuration.new }
    let(:cli) { described_class.new }

    context "when resultset.json exists" do
      before do
        cov = File.join(root, "coverage")
        FileUtils.mkdir_p(cov)
        File.write(File.join(cov, ".resultset.json"), '{"RSpec":{"coverage":{}}}')
        allow(Dir).to receive(:pwd).and_return(root)
      end

      it "returns a SimplecovScanner" do
        scanner = cli.send(:build_scanner, config)
        expect(scanner).to be_a(Testgenai::Scanner::SimplecovScanner)
      end
    end

    context "when resultset.json does not exist and simplecov is not in Gemfile" do
      before do
        File.write(File.join(root, "Gemfile"), "source 'https://rubygems.org'")
        allow(Dir).to receive(:pwd).and_return(root)
      end

      it "returns a FileExistenceScanner" do
        scanner = cli.send(:build_scanner, config)
        expect(scanner).to be_a(Testgenai::Scanner::FileExistenceScanner)
      end
    end

    context "when simplecov is in Gemfile but coverage run fails" do
      before do
        File.write(File.join(root, "Gemfile"), "gem 'simplecov'")
        allow(Dir).to receive(:pwd).and_return(root)
        allow(cli).to receive(:system).and_return(false)
      end

      it "falls back to FileExistenceScanner" do
        scanner = cli.send(:build_scanner, config)
        expect(scanner).to be_a(Testgenai::Scanner::FileExistenceScanner)
      end
    end

    context "when simplecov is in Gemfile and coverage run succeeds" do
      before do
        File.write(File.join(root, "Gemfile"), "gem 'simplecov'")
        allow(Dir).to receive(:pwd).and_return(root)
        allow(cli).to receive(:system) do
          cov = File.join(root, "coverage")
          FileUtils.mkdir_p(cov)
          File.write(File.join(cov, ".resultset.json"), '{"RSpec":{"coverage":{}}}')
          true
        end
      end

      it "returns a SimplecovScanner" do
        scanner = cli.send(:build_scanner, config)
        expect(scanner).to be_a(Testgenai::Scanner::SimplecovScanner)
      end
    end

    context "when run in the testgenai repo itself" do
      it "finds simplecov in the project Gemfile" do
        cli_instance = described_class.new
        expect(cli_instance.send(:simplecov_in_gemfile?)).to be true
      end
    end
  end

  describe "scan command" do
    before { allow(Dir).to receive(:pwd).and_return(root) }

    it "calls reporter.scan_results with untested methods" do
      scanner = instance_double(Testgenai::Scanner::FileExistenceScanner, scan: [])
      reporter = instance_double(Testgenai::Reporter, scan_results: nil)
      allow(Testgenai::Scanner::FileExistenceScanner).to receive(:new).and_return(scanner)
      allow(Testgenai::Reporter).to receive(:new).and_return(reporter)

      described_class.start(["scan"])
      expect(reporter).to have_received(:scan_results).with([])
    end
  end
end
