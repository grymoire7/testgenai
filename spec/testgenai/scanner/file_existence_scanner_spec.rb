RSpec.describe Testgenai::Scanner::FileExistenceScanner do
  let(:root) { Dir.mktmpdir }
  after { FileUtils.rm_rf(root) }

  let(:scanner) { described_class.new(root: root) }

  def write_file(rel_path, content)
    full = File.join(root, rel_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  describe "#scan" do
    context "when a lib file has no corresponding spec" do
      before do
        write_file("lib/widget.rb", <<~RUBY)
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

      it "returns method descriptors for all methods in the file" do
        results = scanner.scan
        expect(results.size).to eq(2)
        expect(results.map { |r| r[:method] }).to contain_exactly("initialize", "display")
      end

      it "includes file, class, method, start_line, end_line in each descriptor" do
        result = scanner.scan.find { |r| r[:method] == "display" }
        expect(result[:file]).to end_with("lib/widget.rb")
        expect(result[:class]).to eq("Widget")
        expect(result[:start_line]).to be_a(Integer)
        expect(result[:end_line]).to be >= result[:start_line]
      end
    end

    context "when a lib file has a corresponding spec" do
      before do
        write_file("lib/widget.rb", "class Widget; def foo; end; end")
        write_file("spec/widget_spec.rb", "RSpec.describe Widget do; end")
      end

      it "excludes that file" do
        expect(scanner.scan).to be_empty
      end
    end

    context "when a lib file has a corresponding test" do
      before do
        write_file("lib/widget.rb", "class Widget; def foo; end; end")
        write_file("test/widget_test.rb", "class WidgetTest; end")
      end

      it "excludes that file" do
        expect(scanner.scan).to be_empty
      end
    end

    context "with nested lib paths" do
      before do
        write_file("lib/myapp/services/widget.rb", <<~RUBY)
          module Myapp
            module Services
              class Widget
                def call
                  "ok"
                end
              end
            end
          end
        RUBY
      end

      it "matches against spec/myapp/services/widget_spec.rb" do
        write_file("spec/myapp/services/widget_spec.rb", "RSpec.describe Widget do; end")
        expect(scanner.scan).to be_empty
      end

      it "returns methods when no spec exists" do
        results = scanner.scan
        expect(results.size).to eq(1)
        expect(results.first[:class]).to eq("Myapp::Services::Widget")
        expect(results.first[:method]).to eq("call")
      end
    end

    context "with app/ directory" do
      before do
        write_file("app/models/user.rb", "class User; def name; end; end")
      end

      it "scans app/ as well as lib/" do
        results = scanner.scan
        expect(results.size).to eq(1)
        expect(results.first[:method]).to eq("name")
      end
    end

    context "with a file that has parse errors" do
      before do
        write_file("lib/broken.rb", "def this is not valid ruby {{{{")
      end

      it "skips the file and does not raise" do
        expect { scanner.scan }.not_to raise_error
        expect(scanner.scan).to be_empty
      end
    end
  end
end
