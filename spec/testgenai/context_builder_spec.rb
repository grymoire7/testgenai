RSpec.describe Testgenai::ContextBuilder do
  let(:root) { Dir.mktmpdir }
  after { FileUtils.rm_rf(root) }

  let(:builder) { described_class.new(root: root) }

  def write_file(rel_path, content)
    full = File.join(root, rel_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  let(:source_file) do
    write_file("lib/widget.rb", <<~RUBY)
      require_relative "widget_helper"
      require "json"

      class Widget
        def display
          puts "hello"
        end
      end
    RUBY
  end

  let(:method_info) do
    {file: source_file, class: "Widget", method: "display", start_line: 5, end_line: 7}
  end

  describe "#build" do
    it "returns a hash with the required keys" do
      result = builder.build(method_info)
      expect(result.keys).to contain_exactly(:target_file, :dependencies, :example_usage, :related_tests)
    end

    it "includes the full source of the target file" do
      result = builder.build(method_info)
      expect(result[:target_file]).to include("class Widget")
      expect(result[:target_file]).to include("def display")
    end

    it "includes require_relative dependencies that exist in the project" do
      write_file("lib/widget_helper.rb", "class WidgetHelper; end")
      result = builder.build(method_info)
      expect(result[:dependencies]).to include(end_with("widget_helper.rb"))
    end

    it "excludes gem requires (require 'json' is a gem, not a project file)" do
      result = builder.build(method_info)
      gem_dep = result[:dependencies].find { |d| d.include?("json") }
      expect(gem_dep).to be_nil
    end

    it "returns empty array when no project requires exist" do
      plain_file = write_file("lib/plain.rb", "class Plain; def foo; end; end")
      info = {file: plain_file, class: "Plain", method: "foo", start_line: 1, end_line: 1}
      result = builder.build(info)
      expect(result[:dependencies]).to eq([])
    end

    context "with example usages of the method" do
      before do
        write_file("lib/app.rb", <<~RUBY)
          widget = Widget.new
          widget.display
          widget.display("arg")
        RUBY
      end

      it "finds call sites" do
        result = builder.build(method_info)
        expect(result[:example_usage]).not_to be_empty
      end

      it "returns at most 3 examples" do
        3.times { |i| write_file("lib/caller#{i}.rb", "widget.display\n" * 5) }
        result = builder.build(method_info)
        expect(result[:example_usage].size).to be <= 3
      end
    end

    context "with no example usages" do
      it "returns an empty array" do
        result = builder.build(method_info)
        expect(result[:example_usage]).to eq([])
      end
    end

    context "when a spec file exists for the same class" do
      before do
        write_file("spec/widget_spec.rb", "RSpec.describe Widget do\n  it { }\nend")
      end

      it "includes the spec file contents" do
        result = builder.build(method_info)
        expect(result[:related_tests]).to include("RSpec.describe Widget")
      end
    end

    context "when no spec file exists" do
      it "returns nil for related_tests" do
        result = builder.build(method_info)
        expect(result[:related_tests]).to be_nil
      end
    end
  end
end
