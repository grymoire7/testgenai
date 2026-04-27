require "json"

RSpec.describe Testgenai::Scanner::SimplecovScanner do
  let(:root) { Dir.mktmpdir }
  after { FileUtils.rm_rf(root) }

  let(:scanner) { described_class.new(root: root) }

  def write_source(rel_path, content)
    full = File.join(root, rel_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  def write_coverage(lines_by_file)
    coverage_data = {
      "RSpec" => {
        "coverage" => lines_by_file.transform_values { |lines| {"lines" => lines} }
      }
    }
    cov_dir = File.join(root, "coverage")
    FileUtils.mkdir_p(cov_dir)
    File.write(File.join(cov_dir, ".resultset.json"), JSON.generate(coverage_data))
  end

  describe "#scan" do
    context "when a method has zero coverage on all executable lines" do
      let(:source_file) do
        write_source("lib/widget.rb", <<~RUBY)
          class Widget
            def initialize(name)
              @name = name
            end

            def display
              puts @name
            end
          end
        RUBY
      end

      before do
        # Line 1: class (nil), 2: def init (0), 3: @name=name (0), 4: end (nil),
        # 5: blank (nil), 6: def display (0), 7: puts (0), 8: end (nil), 9: end (nil)
        write_coverage(source_file => [nil, 0, 0, nil, nil, 0, 0, nil, nil])
      end

      it "returns both methods as untested" do
        results = scanner.scan
        expect(results.size).to eq(2)
        expect(results.map { |r| r[:method] }).to contain_exactly("initialize", "display")
      end

      it "includes file, class, method, start_line, end_line" do
        result = scanner.scan.find { |r| r[:method] == "display" }
        expect(result[:file]).to end_with("lib/widget.rb")
        expect(result[:class]).to eq("Widget")
        expect(result[:start_line]).to be_a(Integer)
        expect(result[:end_line]).to be >= result[:start_line]
      end
    end

    context "when a method has some coverage" do
      let(:source_file) do
        write_source("lib/widget.rb", <<~RUBY)
          class Widget
            def display
              puts "hello"
            end
          end
        RUBY
      end

      before do
        write_coverage(source_file => [nil, 1, 1, nil, nil])
      end

      it "does not return that method" do
        expect(scanner.scan).to be_empty
      end
    end

    context "when a method has partial coverage" do
      let(:source_file) do
        write_source("lib/widget.rb", <<~RUBY)
          class Widget
            def branch(x)
              if x
                "yes"
              else
                "no"
              end
            end
          end
        RUBY
      end

      before do
        # def line covered, else branch not — method is still considered tested
        # because at least one executable line has coverage > 0
        write_coverage(source_file => [nil, 1, 1, 1, nil, 0, nil, nil, nil])
      end

      it "does not return the method (partial coverage counts as tested)" do
        expect(scanner.scan).to be_empty
      end
    end

    context "with spec/ files in coverage data" do
      let(:spec_file) do
        write_source("spec/widget_spec.rb", "RSpec.describe Widget do; end")
      end

      before do
        write_coverage(spec_file => [nil])
      end

      it "skips spec files" do
        expect(scanner.scan).to be_empty
      end
    end

    context "with test/ files in coverage data" do
      let(:test_file) do
        write_source("test/widget_test.rb", "class WidgetTest; end")
      end

      before do
        write_coverage(test_file => [nil])
      end

      it "skips test files" do
        expect(scanner.scan).to be_empty
      end
    end

    context "when the resultset has multiple runners" do
      let(:source_file) do
        write_source("lib/widget.rb", <<~RUBY)
          class Widget
            def call; end
          end
        RUBY
      end

      before do
        coverage_data = {
          "RSpec" => {"coverage" => {source_file => {"lines" => [nil, 0, nil]}}},
          "Minitest" => {"coverage" => {source_file => {"lines" => [nil, 0, nil]}}}
        }
        cov_dir = File.join(root, "coverage")
        FileUtils.mkdir_p(cov_dir)
        File.write(File.join(cov_dir, ".resultset.json"), JSON.generate(coverage_data))
      end

      it "merges coverage across all runners and still detects the untested method" do
        results = scanner.scan
        expect(results.size).to eq(1)
        expect(results.first[:method]).to eq("call")
      end
    end
  end
end
