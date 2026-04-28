# TestGenAI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Ruby CLI gem that scans for untested methods and generates RSpec/Minitest tests using an LLM, with a retry loop that feeds validation errors back to the generator.

**Architecture:** Staged pipeline with strategy injection — Scanner → ContextBuilder → Generator → Validator, each an independent class. Framework-specific behavior (RSpec vs Minitest) lives in strategy classes selected at startup via `Configuration`. The CLI composes only the stages each command needs.

**Tech Stack:** Ruby 3.4.5, Thor (CLI), RubyLLM (LLM API), Parser gem (AST analysis), RSpec (gem's own tests), StandardRB (linting via pre-commit hook)

---

## Scope Note

This spec covers one cohesive pipeline — all components are required for `generate` to work end-to-end. The `scan` command works with just Scanner + Reporter + CLI, and `context` adds ContextBuilder, but we build them all in one plan because integration between stages is the key risk.

---

## File Map

```
testgenai/
├── testgenai.gemspec                        # gem metadata + runtime deps
├── Gemfile                                  # dev/test deps via gemspec
├── exe/testgenai                            # CLI entry point
├── lib/
│   ├── testgenai.rb                         # requires everything; defines Error, ConfigurationError
│   └── testgenai/
│       ├── version.rb                       # VERSION constant
│       ├── configuration.rb                 # flag/env merging; returns strategy classes
│       ├── code_extractor.rb                # strips fences from LLM output
│       ├── context_builder.rb               # builds {target_file, dependencies, example_usage, related_tests}
│       ├── reporter.rb                      # all puts; nothing else calls puts
│       ├── pipeline.rb                      # single-method generate→validate→retry loop
│       ├── batch_pipeline.rb                # iterates methods; rate limiting; error categorization
│       ├── cli.rb                           # Thor commands; scanner startup sequence
│       ├── scanner/
│       │   ├── base.rb                      # abstract; defines #scan interface
│       │   ├── simplecov_scanner.rb         # parses coverage/.resultset.json + AST
│       │   └── file_existence_scanner.rb    # walks lib/app; reports methods in untested files
│       ├── generator/
│       │   ├── base.rb                      # abstract; defines #generate + #output_path_for
│       │   ├── rspec_generator.rb           # RSpec-specific prompt + output path
│       │   └── minitest_generator.rb        # Minitest-specific prompt + output path
│       └── validator/
│           ├── base.rb                      # abstract; write/run/cleanup helpers
│           ├── rspec_validator.rb           # runs bundle exec rspec; parses output
│           └── minitest_validator.rb        # runs bundle exec ruby -Itest; parses output
└── spec/
    └── testgenai/
        ├── configuration_spec.rb
        ├── code_extractor_spec.rb
        ├── context_builder_spec.rb
        ├── reporter_spec.rb
        ├── pipeline_spec.rb
        ├── batch_pipeline_spec.rb
        ├── cli_spec.rb
        ├── scanner/
        │   ├── file_existence_scanner_spec.rb
        │   └── simplecov_scanner_spec.rb
        ├── generator/
        │   ├── rspec_generator_spec.rb
        │   └── minitest_generator_spec.rb
        └── validator/
            ├── rspec_validator_spec.rb
            └── minitest_validator_spec.rb
```

---

## Task 1: Gem Skeleton

**Files:**
- Create: `testgenai.gemspec`
- Create: `Gemfile`
- Create: `lib/testgenai/version.rb`
- Create: `lib/testgenai.rb`
- Create: `exe/testgenai`
- Create: `spec/spec_helper.rb`
- Create: `.rspec`

- [ ] **Step 1: Create `lib/testgenai/version.rb`**

```ruby
module Testgenai
  VERSION = "0.1.0"
end
```

- [ ] **Step 2: Create `lib/testgenai.rb`**

```ruby
require "testgenai/version"
require "testgenai/configuration"
require "testgenai/code_extractor"
require "testgenai/context_builder"
require "testgenai/reporter"
require "testgenai/pipeline"
require "testgenai/batch_pipeline"
require "testgenai/scanner/base"
require "testgenai/scanner/simplecov_scanner"
require "testgenai/scanner/file_existence_scanner"
require "testgenai/generator/base"
require "testgenai/generator/rspec_generator"
require "testgenai/generator/minitest_generator"
require "testgenai/validator/base"
require "testgenai/validator/rspec_validator"
require "testgenai/validator/minitest_validator"
require "testgenai/cli"

module Testgenai
  class Error < StandardError; end
  class ConfigurationError < Error; end
end
```

- [ ] **Step 3: Create `testgenai.gemspec`**

```ruby
require_relative "lib/testgenai/version"

Gem::Specification.new do |spec|
  spec.name = "testgenai"
  spec.version = Testgenai::VERSION
  spec.authors = ["Tracy Atteberry"]
  spec.email = ["tracy@magicbydesign.com"]
  spec.summary = "Find untested Ruby code and generate tests with AI"
  spec.homepage = "https://github.com/tracyatteberry/testgenai"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.files = Dir["lib/**/*.rb", "exe/**/*", "*.md", "*.gemspec", "Gemfile"]
  spec.bindir = "exe"
  spec.executables = ["testgenai"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "ruby_llm", "~> 1.3"
  spec.add_dependency "parser", "~> 3.3"
end
```

- [ ] **Step 4: Create `Gemfile`**

```ruby
source "https://rubygems.org"

gemspec

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "standard", "~> 1.40"
end
```

- [ ] **Step 5: Create `exe/testgenai`**

```ruby
#!/usr/bin/env ruby

require "testgenai"

Testgenai::CLI.start(ARGV)
```

Make it executable:
```bash
chmod +x exe/testgenai
```

- [ ] **Step 6: Create `spec/spec_helper.rb`**

```ruby
require "bundler/setup"
require "testgenai"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.order = :random
end
```

- [ ] **Step 7: Create `.rspec`**

```
--require spec_helper
--format documentation
--color
```

- [ ] **Step 8: Create stub files so `require "testgenai"` loads**

These will be replaced with real implementations in later tasks. Create each file with just the module/class skeleton:

```bash
mkdir -p lib/testgenai/scanner lib/testgenai/generator lib/testgenai/validator
mkdir -p spec/testgenai/scanner spec/testgenai/generator spec/testgenai/validator
```

Create `lib/testgenai/configuration.rb`:
```ruby
module Testgenai
  class Configuration
  end
end
```

Create `lib/testgenai/code_extractor.rb`:
```ruby
module Testgenai
  class CodeExtractor
  end
end
```

Create `lib/testgenai/context_builder.rb`:
```ruby
module Testgenai
  class ContextBuilder
  end
end
```

Create `lib/testgenai/reporter.rb`:
```ruby
module Testgenai
  class Reporter
  end
end
```

Create `lib/testgenai/pipeline.rb`:
```ruby
module Testgenai
  class Pipeline
  end
end
```

Create `lib/testgenai/batch_pipeline.rb`:
```ruby
module Testgenai
  class BatchPipeline
  end
end
```

Create `lib/testgenai/scanner/base.rb`:
```ruby
module Testgenai
  module Scanner
    class Base
    end
  end
end
```

Create `lib/testgenai/scanner/simplecov_scanner.rb`:
```ruby
module Testgenai
  module Scanner
    class SimplecovScanner < Base
    end
  end
end
```

Create `lib/testgenai/scanner/file_existence_scanner.rb`:
```ruby
module Testgenai
  module Scanner
    class FileExistenceScanner < Base
    end
  end
end
```

Create `lib/testgenai/generator/base.rb`:
```ruby
module Testgenai
  module Generator
    class Base
    end
  end
end
```

Create `lib/testgenai/generator/rspec_generator.rb`:
```ruby
module Testgenai
  module Generator
    class RspecGenerator < Base
    end
  end
end
```

Create `lib/testgenai/generator/minitest_generator.rb`:
```ruby
module Testgenai
  module Generator
    class MinitestGenerator < Base
    end
  end
end
```

Create `lib/testgenai/validator/base.rb`:
```ruby
module Testgenai
  module Validator
    class Base
    end
  end
end
```

Create `lib/testgenai/validator/rspec_validator.rb`:
```ruby
module Testgenai
  module Validator
    class RspecValidator < Base
    end
  end
end
```

Create `lib/testgenai/validator/minitest_validator.rb`:
```ruby
module Testgenai
  module Validator
    class MinitestValidator < Base
    end
  end
end
```

Create `lib/testgenai/cli.rb`:
```ruby
require "thor"

module Testgenai
  class CLI < Thor
  end
end
```

- [ ] **Step 9: Install dependencies**

```bash
bundle install
```

Expected: bundler resolves and installs thor, ruby_llm, parser, rspec, standard.

- [ ] **Step 10: Run the test suite to verify the skeleton loads**

```bash
bundle exec rspec
```

Expected: `0 examples, 0 failures` — no tests yet but the load succeeds.

- [ ] **Step 11: Commit**

```bash
git add testgenai.gemspec Gemfile lib/ exe/ spec/ .rspec
git commit -m "feat: add gem skeleton with stub classes"
```

---

## Task 2: Configuration

**Files:**
- Modify: `lib/testgenai/configuration.rb`
- Create: `spec/testgenai/configuration_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/configuration_spec.rb`:

```ruby
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
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/configuration_spec.rb
```

Expected: failures like `NoMethodError: undefined method 'framework'`

- [ ] **Step 3: Implement `Configuration`**

Replace `lib/testgenai/configuration.rb`:

```ruby
module Testgenai
  class Configuration
    attr_reader :provider, :model, :api_key, :framework, :output_dir, :pause

    def initialize(options = {})
      @provider = options[:provider] || ENV["TESTGENAI_PROVIDER"]
      @model = options[:model] || ENV["TESTGENAI_MODEL"]
      @api_key = options[:api_key]
      @framework = options[:framework] || ENV["TESTGENAI_FRAMEWORK"] || "rspec"
      @output_dir = options[:output_dir] || ENV["TESTGENAI_OUTPUT_DIR"]
      @pause = (options[:pause] || ENV["TESTGENAI_PAUSE"] || 1).to_f
    end

    def generator_class
      case framework
      when "rspec" then Generator::RspecGenerator
      when "minitest" then Generator::MinitestGenerator
      else raise ConfigurationError, "Unknown framework: #{framework}"
      end
    end

    def validator_class
      case framework
      when "rspec" then Validator::RspecValidator
      when "minitest" then Validator::MinitestValidator
      else raise ConfigurationError, "Unknown framework: #{framework}"
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/configuration_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/testgenai/configuration.rb spec/testgenai/configuration_spec.rb
git commit -m "feat: add Configuration with env/flag merging and strategy class selection"
```

---

## Task 3: CodeExtractor

**Files:**
- Modify: `lib/testgenai/code_extractor.rb`
- Create: `spec/testgenai/code_extractor_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/code_extractor_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/code_extractor_spec.rb
```

Expected: `NoMethodError: undefined method 'extract' for Testgenai::CodeExtractor`

- [ ] **Step 3: Implement `CodeExtractor`**

Replace `lib/testgenai/code_extractor.rb`:

```ruby
require "parser/current"

module Testgenai
  class CodeExtractor
    def self.extract(response)
      if (match = response.match(/```ruby\n(.*?)```/m))
        match[1]
      elsif (match = response.match(/```\n?(.*?)```/m))
        match[1]
      else
        response
      end
    end

    def self.valid_ruby?(code)
      Parser::CurrentRuby.parse(code)
      true
    rescue Parser::SyntaxError
      false
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/code_extractor_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/testgenai/code_extractor.rb spec/testgenai/code_extractor_spec.rb
git commit -m "feat: add CodeExtractor for stripping LLM response fences"
```

---

## Task 4: Scanner::Base + FileExistenceScanner

**Files:**
- Modify: `lib/testgenai/scanner/base.rb`
- Modify: `lib/testgenai/scanner/file_existence_scanner.rb`
- Create: `spec/testgenai/scanner/file_existence_scanner_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/scanner/file_existence_scanner_spec.rb`:

```ruby
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

      it "skips the file and returns an empty array" do
        expect { scanner.scan }.not_to raise_error
        expect(scanner.scan).to be_empty
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/scanner/file_existence_scanner_spec.rb
```

Expected: failures — `#scan` returns `nil` or raises.

- [ ] **Step 3: Implement `Scanner::Base`**

Replace `lib/testgenai/scanner/base.rb`:

```ruby
module Testgenai
  module Scanner
    class Base
      def scan
        raise NotImplementedError, "#{self.class} must implement #scan"
      end
    end
  end
end
```

- [ ] **Step 4: Implement `FileExistenceScanner`**

Replace `lib/testgenai/scanner/file_existence_scanner.rb`:

```ruby
require "parser/current"

module Testgenai
  module Scanner
    class FileExistenceScanner < Base
      def initialize(root: Dir.pwd)
        @root = root
      end

      def scan
        source_files.reject { |f| test_exists?(f) }.flat_map { |f| extract_methods(f) }
      end

      private

      def source_files
        %w[lib app].flat_map do |dir|
          full = File.join(@root, dir)
          Dir.exist?(full) ? Dir.glob(File.join(full, "**", "*.rb")) : []
        end
      end

      def test_exists?(source_file)
        rel = relative(source_file)
        base = rel.sub(/\A(?:lib|app)\//, "").sub(/\.rb\z/, "")
        File.exist?(File.join(@root, "spec", "#{base}_spec.rb")) ||
          File.exist?(File.join(@root, "test", "#{base}_test.rb"))
      end

      def relative(file)
        file.sub("#{@root}/", "")
      end

      def extract_methods(file)
        source = File.read(file)
        ast = Parser::CurrentRuby.parse(source)
        return [] unless ast
        collect_methods(ast, file, class_name: nil)
      rescue Parser::SyntaxError, EncodingError => e
        warn "Warning: could not parse #{file}: #{e.message}"
        []
      end

      def collect_methods(node, file, class_name:)
        return [] unless node.is_a?(Parser::AST::Node)

        case node.type
        when :class, :module
          current = [class_name, const_name(node.children[0])].compact.join("::")
          node.children.flat_map { |c| collect_methods(c, file, class_name: current) }
        when :def
          [method_descriptor(node, file, class_name, node.children[0].to_s)]
        when :defs
          [method_descriptor(node, file, class_name, "self.#{node.children[1]}")]
        else
          node.children.flat_map { |c| collect_methods(c, file, class_name: class_name) }
        end
      end

      def method_descriptor(node, file, class_name, method_name)
        {
          file: file,
          class: class_name,
          method: method_name,
          start_line: node.loc.line,
          end_line: node.loc.end.line
        }
      end

      def const_name(node)
        return nil unless node.is_a?(Parser::AST::Node) && node.type == :const
        parts = []
        current = node
        while current.is_a?(Parser::AST::Node) && current.type == :const
          parts.unshift(current.children[1].to_s)
          current = current.children[0]
        end
        parts.join("::")
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/scanner/file_existence_scanner_spec.rb
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/testgenai/scanner/base.rb lib/testgenai/scanner/file_existence_scanner.rb spec/testgenai/scanner/file_existence_scanner_spec.rb
git commit -m "feat: add FileExistenceScanner to detect untested files via AST"
```

---

## Task 5: SimplecovScanner

**Files:**
- Modify: `lib/testgenai/scanner/simplecov_scanner.rb`
- Create: `spec/testgenai/scanner/simplecov_scanner_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/scanner/simplecov_scanner_spec.rb`:

```ruby
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
        # Line 2 (def) has 1 execution, so method is tested
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
        # because at least one executable line has coverage
        write_coverage(source_file => [nil, 1, 1, 1, nil, 0, nil, nil, nil])
      end

      it "does not return the method (partial coverage counts)" do
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

      it "merges coverage across all runners" do
        results = scanner.scan
        expect(results.size).to eq(1)
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/scanner/simplecov_scanner_spec.rb
```

Expected: failures — `#scan` returns `nil` or raises.

- [ ] **Step 3: Implement `SimplecovScanner`**

Replace `lib/testgenai/scanner/simplecov_scanner.rb`:

```ruby
require "json"
require "parser/current"

module Testgenai
  module Scanner
    class SimplecovScanner < Base
      RESULTSET_PATH = "coverage/.resultset.json"

      def initialize(root: Dir.pwd)
        @root = root
      end

      def scan
        coverage = merged_coverage
        coverage.flat_map do |file, lines|
          next [] if test_file?(file)
          next [] unless File.exist?(file)
          extract_untested_methods(file, lines)
        end
      end

      private

      def merged_coverage
        resultset = JSON.parse(File.read(File.join(@root, RESULTSET_PATH)))
        result = {}
        resultset.each_value do |runner_data|
          (runner_data["coverage"] || {}).each do |file, data|
            lines = data["lines"]
            result[file] = merge_lines(result[file], lines)
          end
        end
        result
      end

      def merge_lines(existing, new_lines)
        return new_lines unless existing
        existing.zip(new_lines).map do |a, b|
          next nil if a.nil? && b.nil?
          (a || 0) + (b || 0)
        end
      end

      def test_file?(file)
        relative = file.sub("#{@root}/", "")
        relative.start_with?("spec/", "test/")
      end

      def extract_untested_methods(file, coverage_lines)
        source = File.read(file)
        ast = Parser::CurrentRuby.parse(source)
        return [] unless ast
        methods = collect_methods(ast, file, class_name: nil)
        methods.select { |m| untested?(coverage_lines, m[:start_line], m[:end_line]) }
      rescue Parser::SyntaxError, EncodingError => e
        warn "Warning: could not parse #{file}: #{e.message}"
        []
      end

      def untested?(coverage_lines, start_line, end_line)
        method_lines = coverage_lines[(start_line - 1)..(end_line - 1)] || []
        executable = method_lines.compact
        executable.any? && executable.all?(&:zero?)
      end

      def collect_methods(node, file, class_name:)
        return [] unless node.is_a?(Parser::AST::Node)
        case node.type
        when :class, :module
          current = [class_name, const_name(node.children[0])].compact.join("::")
          node.children.flat_map { |c| collect_methods(c, file, class_name: current) }
        when :def
          [{file: file, class: class_name, method: node.children[0].to_s,
            start_line: node.loc.line, end_line: node.loc.end.line}]
        when :defs
          [{file: file, class: class_name, method: "self.#{node.children[1]}",
            start_line: node.loc.line, end_line: node.loc.end.line}]
        else
          node.children.flat_map { |c| collect_methods(c, file, class_name: class_name) }
        end
      end

      def const_name(node)
        return nil unless node.is_a?(Parser::AST::Node) && node.type == :const
        parts = []
        current = node
        while current.is_a?(Parser::AST::Node) && current.type == :const
          parts.unshift(current.children[1].to_s)
          current = current.children[0]
        end
        parts.join("::")
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/scanner/simplecov_scanner_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/testgenai/scanner/simplecov_scanner.rb spec/testgenai/scanner/simplecov_scanner_spec.rb
git commit -m "feat: add SimplecovScanner to detect uncovered methods via coverage data"
```

---

## Task 6: ContextBuilder

**Files:**
- Modify: `lib/testgenai/context_builder.rb`
- Create: `spec/testgenai/context_builder_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/context_builder_spec.rb`:

```ruby
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

    it "excludes gem requires" do
      result = builder.build(method_info)
      gem_dep = result[:dependencies].find { |d| d.include?("json") }
      expect(gem_dep).to be_nil
    end

    it "returns empty array when no project requires exist" do
      write_file("lib/plain.rb", "class Plain; def foo; end; end")
      info = {file: File.join(root, "lib/plain.rb"), class: "Plain", method: "foo", start_line: 1, end_line: 1}
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/context_builder_spec.rb
```

Expected: failures — `#build` not defined.

- [ ] **Step 3: Implement `ContextBuilder`**

Replace `lib/testgenai/context_builder.rb`:

```ruby
require "parser/current"

module Testgenai
  class ContextBuilder
    def initialize(root: Dir.pwd)
      @root = root
    end

    def build(method_info)
      {
        target_file: File.read(method_info[:file]),
        dependencies: extract_dependencies(method_info[:file]),
        example_usage: find_usages(method_info[:method]),
        related_tests: find_related_tests(method_info[:file])
      }
    rescue => e
      raise Error, "Could not build context for #{method_info[:file]}: #{e.message}"
    end

    private

    def extract_dependencies(file)
      source = File.read(file)
      ast = Parser::CurrentRuby.parse(source)
      return [] unless ast
      find_requires(ast, File.dirname(file))
    rescue Parser::SyntaxError
      []
    end

    def find_requires(node, dir, results = [])
      return results unless node.is_a?(Parser::AST::Node)

      if node.type == :send && node.children[0].nil? && node.children[2]&.type == :str
        path = node.children[2].children[0]
        case node.children[1]
        when :require_relative
          resolved = File.expand_path("#{path}.rb", dir)
          results << resolved if File.exist?(resolved)
        when :require
          resolved = File.join(@root, "lib", "#{path}.rb")
          results << resolved if File.exist?(resolved)
        end
      end

      node.children.each { |c| find_requires(c, dir, results) }
      results
    end

    def find_usages(method_name)
      name = method_name.to_s.sub(/\Aself\./, "")
      usages = []
      pattern = /\.#{Regexp.escape(name)}[\s(]/

      source_files.each do |file|
        lines = File.readlines(file)
        lines.each_with_index do |line, i|
          next unless line.match?(pattern)
          start = [0, i - 2].max
          finish = [lines.size - 1, i + 2].min
          usages << lines[start..finish].join
          break if usages.size >= 3
        end
        break if usages.size >= 3
      end

      usages
    end

    def find_related_tests(source_file)
      rel = source_file.sub("#{@root}/", "")
      base = rel.sub(/\A(?:lib|app)\//, "").sub(/\.rb\z/, "")

      spec_path = File.join(@root, "spec", "#{base}_spec.rb")
      test_path = File.join(@root, "test", "#{base}_test.rb")

      if File.exist?(spec_path)
        File.read(spec_path)
      elsif File.exist?(test_path)
        File.read(test_path)
      end
    end

    def source_files
      %w[lib app].flat_map do |dir|
        full = File.join(@root, dir)
        Dir.exist?(full) ? Dir.glob(File.join(full, "**", "*.rb")) : []
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/context_builder_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/testgenai/context_builder.rb spec/testgenai/context_builder_spec.rb
git commit -m "feat: add ContextBuilder to assemble LLM context from source and usage"
```

---

## Task 7: Reporter

**Files:**
- Modify: `lib/testgenai/reporter.rb`
- Create: `spec/testgenai/reporter_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/reporter_spec.rb`:

```ruby
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

    it "reports a count" do
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
    it "reports the generated file path" do
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/reporter_spec.rb
```

Expected: failures — methods not defined.

- [ ] **Step 3: Implement `Reporter`**

Replace `lib/testgenai/reporter.rb`:

```ruby
require "stringio"

module Testgenai
  class Reporter
    def scan_results(methods)
      if methods.empty?
        puts "No untested methods found."
        return
      end
      puts "Found #{methods.size} untested method(s):"
      methods.each do |m|
        puts "  #{m[:class]}##{m[:method]}  #{m[:file]}:#{m[:start_line]}-#{m[:end_line]}"
      end
    end

    def context_result(method_info, context)
      puts "=== Context for #{method_info[:class]}##{method_info[:method]} ==="
      puts "  File: #{method_info[:file]}"
      unless context[:dependencies].empty?
        puts "  Dependencies:"
        context[:dependencies].each { |d| puts "    #{d}" }
      end
      unless context[:example_usage].empty?
        puts "  Example usages found: #{context[:example_usage].size}"
      end
      puts "  Related tests: #{context[:related_tests] ? "yes" : "none"}"
      puts
    end

    def success(method_info, result)
      puts "  ✓ #{method_info[:class]}##{method_info[:method]} → #{result[:output_path]} (#{result[:attempts]} attempt(s))"
    end

    def failure(method_info, result)
      puts "  ✗ #{method_info[:class]}##{method_info[:method]} failed after #{result[:attempts]} attempt(s)"
    end

    def skipped(method_info, error)
      puts "  - #{method_info[:class]}##{method_info[:method]} skipped: #{error.message}"
    end

    def summary(results)
      puts "\nSummary: #{results[:successful].size} generated, " \
           "#{results[:failed].size} failed, #{results[:skipped].size} skipped"
    end

    def fatal_error(error)
      puts "Fatal error: #{error.message}"
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/reporter_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/testgenai/reporter.rb spec/testgenai/reporter_spec.rb
git commit -m "feat: add Reporter as sole owner of user-visible output"
```

---

## Task 8: Generator::Base + RspecGenerator

**Files:**
- Modify: `lib/testgenai/generator/base.rb`
- Modify: `lib/testgenai/generator/rspec_generator.rb`
- Create: `spec/testgenai/generator/rspec_generator_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/generator/rspec_generator_spec.rb`:

```ruby
RSpec.describe Testgenai::Generator::RspecGenerator do
  let(:config) do
    Testgenai::Configuration.new(
      framework: "rspec",
      model: "claude-sonnet-4-6"
    )
  end
  let(:generator) { described_class.new(config) }

  let(:method_info) { {file: "/app/lib/widget.rb", class: "Widget", method: "display", start_line: 5, end_line: 7} }
  let(:context) do
    {
      target_file: "class Widget\n  def display\n    puts 'hi'\n  end\nend",
      dependencies: [],
      example_usage: [],
      related_tests: nil
    }
  end

  let(:llm_response) { "```ruby\nRSpec.describe Widget do\n  it 'displays' do\n  end\nend\n```" }

  before do
    allow(generator).to receive(:call_llm).and_return(llm_response)
  end

  describe "#generate" do
    it "returns extracted Ruby code" do
      result = generator.generate(method_info, context)
      expect(result).to include("RSpec.describe Widget")
      expect(result).not_to include("```")
    end

    it "passes feedback to a retry attempt" do
      expect(generator).to receive(:call_llm) do |prompt|
        expect(prompt).to include("failed")
        llm_response
      end
      generator.generate(method_info, context, feedback: "expected 1 got 2")
    end

    it "includes the method class and name in the prompt" do
      expect(generator).to receive(:call_llm) do |prompt|
        expect(prompt).to include("Widget")
        expect(prompt).to include("display")
        llm_response
      end
      generator.generate(method_info, context)
    end

    it "includes related tests in the prompt when present" do
      ctx_with_tests = context.merge(related_tests: "RSpec.describe Widget do; end")
      expect(generator).to receive(:call_llm) do |prompt|
        expect(prompt).to include("RSpec.describe Widget")
        llm_response
      end
      generator.generate(method_info, ctx_with_tests)
    end
  end

  describe "#output_path_for" do
    it "maps lib/widget.rb → spec/widget_spec.rb" do
      info = method_info.merge(file: "/app/lib/widget.rb")
      allow(Dir).to receive(:pwd).and_return("/app")
      expect(generator.output_path_for(info)).to eq("/app/spec/widget_spec.rb")
    end

    it "maps lib/myapp/services/widget.rb → spec/myapp/services/widget_spec.rb" do
      info = method_info.merge(file: "/app/lib/myapp/services/widget.rb")
      allow(Dir).to receive(:pwd).and_return("/app")
      expect(generator.output_path_for(info)).to eq("/app/spec/myapp/services/widget_spec.rb")
    end

    it "uses output_dir when configured" do
      cfg = Testgenai::Configuration.new(framework: "rspec", output_dir: "/custom/out")
      gen = described_class.new(cfg)
      result = gen.output_path_for(method_info)
      expect(result).to start_with("/custom/out/")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/generator/rspec_generator_spec.rb
```

Expected: failures — methods not defined.

- [ ] **Step 3: Implement `Generator::Base`**

Replace `lib/testgenai/generator/base.rb`:

```ruby
require "ruby_llm"

module Testgenai
  module Generator
    class Base
      def initialize(config)
        @config = config
        configure_llm
      end

      def generate(method_info, context, feedback: nil)
        prompt = build_prompt(method_info, context, feedback: feedback)
        response = call_llm(prompt)
        CodeExtractor.extract(response)
      end

      def output_path_for(method_info)
        raise NotImplementedError
      end

      private

      def configure_llm
        return unless @config.api_key
        provider = @config.provider || "anthropic"
        RubyLLM.configure do |c|
          c.public_send(:"#{provider}_api_key=", @config.api_key)
        end
      end

      def call_llm(prompt)
        model = @config.model || default_model
        chat = RubyLLM.chat(model: model)
        chat.ask(prompt).content
      end

      def default_model
        "claude-sonnet-4-6"
      end

      def build_prompt(method_info, context, feedback: nil)
        raise NotImplementedError
      end

      def custom_output_path(method_info, suffix)
        class_part = method_info[:class]&.downcase&.gsub("::", "/") || "unknown"
        method_part = method_info[:method].to_s.gsub(/\Aself\./, "").gsub(".", "_")
        File.join(@config.output_dir, "#{class_part}_#{method_part}#{suffix}")
      end
    end
  end
end
```

- [ ] **Step 4: Implement `RspecGenerator`**

Replace `lib/testgenai/generator/rspec_generator.rb`:

```ruby
module Testgenai
  module Generator
    class RspecGenerator < Base
      def output_path_for(method_info)
        return custom_output_path(method_info, "_spec.rb") if @config.output_dir

        rel = method_info[:file].sub("#{Dir.pwd}/", "")
        base = rel.sub(/\A(?:lib|app)\//, "").sub(/\.rb\z/, "")
        File.join(Dir.pwd, "spec", "#{base}_spec.rb")
      end

      private

      def build_prompt(method_info, context, feedback: nil)
        prompt = <<~PROMPT
          You are an expert Ruby developer. Write RSpec tests for the following method.

          ## Method to test
          Class: #{method_info[:class]}
          Method: #{method_info[:method]}
          Location: #{method_info[:file]}:#{method_info[:start_line]}-#{method_info[:end_line]}

          ## Source file
          ```ruby
          #{context[:target_file]}
          ```
        PROMPT

        unless context[:dependencies].empty?
          prompt += "\n## Dependencies\n"
          prompt += context[:dependencies].map { |d| "- #{d}" }.join("\n")
          prompt += "\n"
        end

        context[:example_usage].each_with_index do |usage, i|
          prompt += "\n## Example usage #{i + 1}\n```ruby\n#{usage}\n```\n"
        end

        if context[:related_tests]
          prompt += "\n## Existing tests (match this style)\n```ruby\n#{context[:related_tests]}\n```\n"
        end

        if feedback
          prompt += "\n## Previous attempt failed — fix these issues\n#{feedback}\n"
        end

        prompt + "\nWrite comprehensive RSpec tests using describe/context/let/before blocks. " \
                 "Return ONLY the test code in a ```ruby code block."
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/generator/rspec_generator_spec.rb
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/testgenai/generator/base.rb lib/testgenai/generator/rspec_generator.rb spec/testgenai/generator/rspec_generator_spec.rb
git commit -m "feat: add Generator base class and RspecGenerator with LLM prompt"
```

---

## Task 9: Generator::MinitestGenerator

**Files:**
- Modify: `lib/testgenai/generator/minitest_generator.rb`
- Create: `spec/testgenai/generator/minitest_generator_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/generator/minitest_generator_spec.rb`:

```ruby
RSpec.describe Testgenai::Generator::MinitestGenerator do
  let(:config) { Testgenai::Configuration.new(framework: "minitest") }
  let(:generator) { described_class.new(config) }

  let(:method_info) { {file: "/app/lib/widget.rb", class: "Widget", method: "display", start_line: 5, end_line: 7} }
  let(:context) do
    {target_file: "class Widget; end", dependencies: [], example_usage: [], related_tests: nil}
  end

  let(:llm_response) { "```ruby\nclass WidgetTest < Minitest::Test\n  def test_display\n  end\nend\n```" }

  before { allow(generator).to receive(:call_llm).and_return(llm_response) }

  describe "#generate" do
    it "returns Minitest test code without fences" do
      result = generator.generate(method_info, context)
      expect(result).to include("WidgetTest")
      expect(result).not_to include("```")
    end

    it "includes Minitest-specific framing in the prompt" do
      expect(generator).to receive(:call_llm) do |prompt|
        expect(prompt).to match(/minitest/i)
        llm_response
      end
      generator.generate(method_info, context)
    end
  end

  describe "#output_path_for" do
    it "maps lib/widget.rb → test/widget_test.rb" do
      info = method_info.merge(file: "/app/lib/widget.rb")
      allow(Dir).to receive(:pwd).and_return("/app")
      expect(generator.output_path_for(info)).to eq("/app/test/widget_test.rb")
    end

    it "uses output_dir when configured" do
      cfg = Testgenai::Configuration.new(framework: "minitest", output_dir: "/custom/out")
      gen = described_class.new(cfg)
      result = gen.output_path_for(method_info)
      expect(result).to start_with("/custom/out/")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/generator/minitest_generator_spec.rb
```

Expected: failures — methods not defined.

- [ ] **Step 3: Implement `MinitestGenerator`**

Replace `lib/testgenai/generator/minitest_generator.rb`:

```ruby
module Testgenai
  module Generator
    class MinitestGenerator < Base
      def output_path_for(method_info)
        return custom_output_path(method_info, "_test.rb") if @config.output_dir

        rel = method_info[:file].sub("#{Dir.pwd}/", "")
        base = rel.sub(/\A(?:lib|app)\//, "").sub(/\.rb\z/, "")
        File.join(Dir.pwd, "test", "#{base}_test.rb")
      end

      private

      def build_prompt(method_info, context, feedback: nil)
        prompt = <<~PROMPT
          You are an expert Ruby developer. Write Minitest tests for the following method.

          ## Method to test
          Class: #{method_info[:class]}
          Method: #{method_info[:method]}
          Location: #{method_info[:file]}:#{method_info[:start_line]}-#{method_info[:end_line]}

          ## Source file
          ```ruby
          #{context[:target_file]}
          ```
        PROMPT

        unless context[:dependencies].empty?
          prompt += "\n## Dependencies\n"
          prompt += context[:dependencies].map { |d| "- #{d}" }.join("\n")
          prompt += "\n"
        end

        context[:example_usage].each_with_index do |usage, i|
          prompt += "\n## Example usage #{i + 1}\n```ruby\n#{usage}\n```\n"
        end

        if context[:related_tests]
          prompt += "\n## Existing tests (match this style)\n```ruby\n#{context[:related_tests]}\n```\n"
        end

        if feedback
          prompt += "\n## Previous attempt failed — fix these issues\n#{feedback}\n"
        end

        prompt + "\nWrite comprehensive Minitest tests using test/setup methods and Minitest assertions. " \
                 "Subclass Minitest::Test. Return ONLY the test code in a ```ruby code block."
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/generator/minitest_generator_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/testgenai/generator/minitest_generator.rb spec/testgenai/generator/minitest_generator_spec.rb
git commit -m "feat: add MinitestGenerator with test/setup prompt framing"
```

---

## Task 10: Validator::Base + RspecValidator

**Files:**
- Modify: `lib/testgenai/validator/base.rb`
- Modify: `lib/testgenai/validator/rspec_validator.rb`
- Create: `spec/testgenai/validator/rspec_validator_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/validator/rspec_validator_spec.rb`:

```ruby
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
      require "totally_missing_gem_xyz"
      RSpec.describe "Widget" do
        it "something" do; end
      end
    RUBY
  end

  describe "#validate" do
    it "returns valid: true, passes: true for a passing test" do
      result = validator.validate(passing_code, output_path)
      expect(result[:valid]).to be true
      expect(result[:runs]).to be true
      expect(result[:passes]).to be true
      expect(result[:errors]).to be_empty
    end

    it "returns valid: true, passes: false for a failing test" do
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

    it "keeps the file when tests fail (not a load error)" do
      validator.validate(failing_code, output_path)
      expect(File.exist?(output_path)).to be true
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/validator/rspec_validator_spec.rb
```

Expected: failures — `#validate` not defined.

- [ ] **Step 3: Implement `Validator::Base`**

Replace `lib/testgenai/validator/base.rb`:

```ruby
require "fileutils"

module Testgenai
  module Validator
    class Base
      def validate(test_code, output_path)
        raise NotImplementedError
      end

      private

      def write_test_file(test_code, output_path)
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, test_code)
      end

      def cleanup(output_path)
        File.delete(output_path) if File.exist?(output_path)
      end
    end
  end
end
```

- [ ] **Step 4: Implement `RspecValidator`**

Replace `lib/testgenai/validator/rspec_validator.rb`:

```ruby
module Testgenai
  module Validator
    class RspecValidator < Base
      def validate(test_code, output_path)
        write_test_file(test_code, output_path)
        stdout, exit_status = run_rspec(output_path)
        parse_result(stdout, exit_status, output_path)
      end

      private

      def run_rspec(path)
        output = `bundle exec rspec #{path} --format documentation 2>&1`
        [output, $?.exitstatus]
      end

      def parse_result(output, exit_status, output_path)
        if load_error?(output)
          errors = extract_load_errors(output)
          cleanup(output_path)
          {valid: false, runs: false, passes: false, errors: errors}
        elsif exit_status == 0
          {valid: true, runs: true, passes: true, errors: []}
        else
          errors = extract_failures(output)
          {valid: true, runs: true, passes: false, errors: errors}
        end
      end

      def load_error?(output)
        output.match?(/LoadError|SyntaxError|NameError.*uninitialized constant|An error occurred while loading/)
      end

      def extract_load_errors(output)
        lines = output.lines
        error_lines = lines.select { |l| l.match?(/LoadError|SyntaxError|NameError|cannot load/) }
        error_lines.map(&:strip).first(3)
      end

      def extract_failures(output)
        failures = []
        in_failure = false
        output.each_line do |line|
          if line.match?(/^\s+\d+\)/)
            in_failure = true
            failures << line.strip
          elsif in_failure && line.match?(/^\s+(Failure|Error):/)
            failures.last << " #{line.strip}"
          elsif in_failure && line.strip.empty?
            in_failure = false
          end
        end
        failures.first(5)
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/validator/rspec_validator_spec.rb
```

Expected: all green. Note: these tests actually invoke `bundle exec rspec` on temp files, so they require a working RSpec setup.

- [ ] **Step 6: Commit**

```bash
git add lib/testgenai/validator/base.rb lib/testgenai/validator/rspec_validator.rb spec/testgenai/validator/rspec_validator_spec.rb
git commit -m "feat: add Validator base class and RspecValidator with load/assertion error parsing"
```

---

## Task 11: Validator::MinitestValidator

**Files:**
- Modify: `lib/testgenai/validator/minitest_validator.rb`
- Create: `spec/testgenai/validator/minitest_validator_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/validator/minitest_validator_spec.rb`:

```ruby
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
      require "totally_missing_gem_xyz"
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
    end

    it "removes the file when tests fail to load" do
      validator.validate(load_error_code, output_path)
      expect(File.exist?(output_path)).to be false
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/validator/minitest_validator_spec.rb
```

Expected: failures — `#validate` not defined.

- [ ] **Step 3: Implement `MinitestValidator`**

Replace `lib/testgenai/validator/minitest_validator.rb`:

```ruby
module Testgenai
  module Validator
    class MinitestValidator < Base
      def validate(test_code, output_path)
        write_test_file(test_code, output_path)
        stdout, exit_status = run_minitest(output_path)
        parse_result(stdout, exit_status, output_path)
      end

      private

      def run_minitest(path)
        output = `bundle exec ruby -Ilib -Itest #{path} 2>&1`
        [output, $?.exitstatus]
      end

      def parse_result(output, exit_status, output_path)
        if load_error?(output)
          errors = extract_load_errors(output)
          cleanup(output_path)
          {valid: false, runs: false, passes: false, errors: errors}
        elsif exit_status == 0
          {valid: true, runs: true, passes: true, errors: []}
        else
          errors = extract_failures(output)
          {valid: true, runs: true, passes: false, errors: errors}
        end
      end

      def load_error?(output)
        output.match?(/LoadError|SyntaxError|cannot load such file/)
      end

      def extract_load_errors(output)
        output.lines.select { |l| l.match?(/LoadError|SyntaxError|cannot load/) }.map(&:strip).first(3)
      end

      def extract_failures(output)
        output.lines.select { |l| l.match?(/FAIL|ERROR/) }.map(&:strip).first(5)
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/validator/minitest_validator_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/testgenai/validator/minitest_validator.rb spec/testgenai/validator/minitest_validator_spec.rb
git commit -m "feat: add MinitestValidator with subprocess test runner"
```

---

## Task 12: Pipeline

**Files:**
- Modify: `lib/testgenai/pipeline.rb`
- Create: `spec/testgenai/pipeline_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/pipeline_spec.rb`:

```ruby
RSpec.describe Testgenai::Pipeline do
  let(:generator) { instance_double(Testgenai::Generator::RspecGenerator) }
  let(:validator) { instance_double(Testgenai::Validator::RspecValidator) }
  let(:pipeline) { described_class.new(generator, validator) }

  let(:method_info) { {file: "lib/widget.rb", class: "Widget", method: "display", start_line: 2, end_line: 4} }
  let(:context) { {target_file: "class Widget; end", dependencies: [], example_usage: [], related_tests: nil} }
  let(:output_path) { "spec/widget_spec.rb" }
  let(:generated_code) { "RSpec.describe Widget do; end" }

  before do
    allow(generator).to receive(:output_path_for).with(method_info).and_return(output_path)
  end

  describe "#run" do
    context "when validation passes on first attempt" do
      before do
        allow(generator).to receive(:generate).with(method_info, context, feedback: nil)
          .and_return(generated_code)
        allow(validator).to receive(:validate).with(generated_code, output_path)
          .and_return({valid: true, runs: true, passes: true, errors: []})
      end

      it "returns success: true with 1 attempt" do
        result = pipeline.run(method_info, context)
        expect(result[:success]).to be true
        expect(result[:attempts]).to eq(1)
        expect(result[:output_path]).to eq(output_path)
        expect(result[:errors]).to be_empty
      end
    end

    context "when first attempt has assertion failures, second succeeds" do
      let(:fail_result) { {valid: true, runs: true, passes: false, errors: ["expected 1 got 2"]} }
      let(:pass_result) { {valid: true, runs: true, passes: true, errors: []} }

      before do
        allow(generator).to receive(:generate).with(method_info, context, feedback: nil)
          .and_return("attempt 1")
        allow(generator).to receive(:generate)
          .with(method_info, context, feedback: "The following tests failed: expected 1 got 2")
          .and_return("attempt 2")
        allow(validator).to receive(:validate).with("attempt 1", output_path).and_return(fail_result)
        allow(validator).to receive(:validate).with("attempt 2", output_path).and_return(pass_result)
      end

      it "returns success: true with 2 attempts" do
        result = pipeline.run(method_info, context)
        expect(result[:success]).to be true
        expect(result[:attempts]).to eq(2)
      end
    end

    context "when tests fail to load, passes load error feedback on retry" do
      let(:load_fail) { {valid: false, runs: false, passes: false, errors: ["cannot load missing"]} }
      let(:pass_result) { {valid: true, runs: true, passes: true, errors: []} }

      before do
        allow(generator).to receive(:generate).with(method_info, context, feedback: nil)
          .and_return("attempt 1")
        allow(generator).to receive(:generate)
          .with(method_info, context, feedback: "The following errors prevented the tests from running: cannot load missing")
          .and_return("attempt 2")
        allow(validator).to receive(:validate).with("attempt 1", output_path).and_return(load_fail)
        allow(validator).to receive(:validate).with("attempt 2", output_path).and_return(pass_result)
      end

      it "uses load error feedback phrasing" do
        result = pipeline.run(method_info, context)
        expect(result[:success]).to be true
      end
    end

    context "when all 3 attempts fail" do
      before do
        allow(generator).to receive(:generate).and_return(generated_code)
        allow(validator).to receive(:validate)
          .and_return({valid: true, runs: true, passes: false, errors: ["always fails"]})
      end

      it "returns success: false after exactly 3 attempts" do
        result = pipeline.run(method_info, context)
        expect(result[:success]).to be false
        expect(result[:attempts]).to eq(3)
        expect(generator).to have_received(:generate).exactly(3).times
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/pipeline_spec.rb
```

Expected: failures — `#run` not defined.

- [ ] **Step 3: Implement `Pipeline`**

Replace `lib/testgenai/pipeline.rb`:

```ruby
module Testgenai
  class Pipeline
    MAX_ATTEMPTS = 3

    def initialize(generator, validator)
      @generator = generator
      @validator = validator
    end

    def run(method_info, context)
      output_path = @generator.output_path_for(method_info)
      feedback = nil

      MAX_ATTEMPTS.times do |i|
        test_code = @generator.generate(method_info, context, feedback: feedback)
        result = @validator.validate(test_code, output_path)

        if result[:runs] && result[:passes]
          return {success: true, output_path: output_path, attempts: i + 1, errors: []}
        end

        feedback = build_feedback(result)
      end

      {success: false, output_path: output_path, attempts: MAX_ATTEMPTS, errors: [feedback]}
    end

    private

    def build_feedback(result)
      if result[:runs]
        "The following tests failed: #{result[:errors].join(", ")}"
      else
        "The following errors prevented the tests from running: #{result[:errors].join(", ")}"
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/pipeline_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/testgenai/pipeline.rb spec/testgenai/pipeline_spec.rb
git commit -m "feat: add Pipeline with 3-attempt retry loop and failure feedback"
```

---

## Task 13: BatchPipeline

**Files:**
- Modify: `lib/testgenai/batch_pipeline.rb`
- Create: `spec/testgenai/batch_pipeline_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/batch_pipeline_spec.rb`:

```ruby
RSpec.describe Testgenai::BatchPipeline do
  let(:config) { Testgenai::Configuration.new(pause: 0) }
  let(:context_builder) { instance_double(Testgenai::ContextBuilder) }
  let(:pipeline) { instance_double(Testgenai::Pipeline) }
  let(:reporter) { instance_double(Testgenai::Reporter, success: nil, failure: nil, skipped: nil, fatal_error: nil, summary: nil) }

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
        batch.run([method_info]) rescue nil
        expect(reporter).to have_received(:fatal_error)
      end
    end

    context "with multiple methods" do
      let(:method2) { method_info.merge(method: "initialize") }

      before do
        allow(context_builder).to receive(:build).and_return(context)
        allow(pipeline).to receive(:run).and_return({success: true, output_path: "x", attempts: 1, errors: []})
      end

      it "processes all methods" do
        results = batch.run([method_info, method2])
        expect(results[:successful].size).to eq(2)
      end

      it "does not sleep before the first method" do
        expect(batch).not_to receive(:sleep)
        batch.run([method_info])
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/batch_pipeline_spec.rb
```

Expected: failures — `#run` not defined.

- [ ] **Step 3: Implement `BatchPipeline`**

Replace `lib/testgenai/batch_pipeline.rb`:

```ruby
module Testgenai
  class BatchPipeline
    def initialize(config, context_builder, pipeline, reporter)
      @config = config
      @context_builder = context_builder
      @pipeline = pipeline
      @reporter = reporter
    end

    def run(untested_methods)
      results = {successful: [], failed: [], skipped: []}

      untested_methods.each_with_index do |method_info, i|
        sleep @config.pause if i > 0

        context = @context_builder.build(method_info)
        result = @pipeline.run(method_info, context)

        if result[:success]
          results[:successful] << result
          @reporter.success(method_info, result)
        else
          results[:failed] << result
          @reporter.failure(method_info, result)
        end
      rescue ConfigurationError => e
        @reporter.fatal_error(e)
        raise
      rescue => e
        results[:skipped] << {method_info: method_info, error: e.message}
        @reporter.skipped(method_info, e)
      end

      results
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/batch_pipeline_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/testgenai/batch_pipeline.rb spec/testgenai/batch_pipeline_spec.rb
git commit -m "feat: add BatchPipeline with rate limiting and error categorization"
```

---

## Task 14: CLI

**Files:**
- Modify: `lib/testgenai/cli.rb`
- Create: `spec/testgenai/cli_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/testgenai/cli_spec.rb`:

```ruby
RSpec.describe Testgenai::CLI do
  let(:root) { Dir.mktmpdir }
  after { FileUtils.rm_rf(root) }

  def run_cli(*args)
    stdout = StringIO.new
    stderr = StringIO.new
    allow($stdout).to receive(:puts) { |msg| stdout.puts(msg) }
    described_class.start(args)
    stdout.string
  rescue SystemExit
    stdout.string
  end

  describe "scan command" do
    before do
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib", "widget.rb"), "class Widget; def call; end; end")
      allow(Dir).to receive(:pwd).and_return(root)
    end

    it "outputs untested methods" do
      scanner = instance_double(Testgenai::Scanner::FileExistenceScanner)
      allow(scanner).to receive(:scan).and_return([
        {file: "lib/widget.rb", class: "Widget", method: "call", start_line: 1, end_line: 1}
      ])
      allow(Testgenai::Scanner::FileExistenceScanner).to receive(:new).and_return(scanner)

      reporter = instance_double(Testgenai::Reporter)
      allow(Testgenai::Reporter).to receive(:new).and_return(reporter)
      expect(reporter).to receive(:scan_results)

      described_class.start(["scan"])
    end
  end

  describe "version flag" do
    it "outputs the version" do
      expect { described_class.start(["--version"]) }.to output(/#{Testgenai::VERSION}/).to_stdout
    end
  end

  describe "scanner startup sequence" do
    let(:config) { Testgenai::Configuration.new }

    context "when resultset.json exists" do
      before do
        cov = File.join(root, "coverage")
        FileUtils.mkdir_p(cov)
        File.write(File.join(cov, ".resultset.json"), '{"RSpec":{"coverage":{}}}')
        allow(Dir).to receive(:pwd).and_return(root)
      end

      it "returns a SimplecovScanner" do
        cli = described_class.new
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
        cli = described_class.new
        scanner = cli.send(:build_scanner, config)
        expect(scanner).to be_a(Testgenai::Scanner::FileExistenceScanner)
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/testgenai/cli_spec.rb
```

Expected: failures — Thor commands not defined.

- [ ] **Step 3: Implement `CLI`**

Replace `lib/testgenai/cli.rb`:

```ruby
require "thor"

module Testgenai
  class CLI < Thor
    package_name "testgenai"

    class_option :output_dir, aliases: "-o", desc: "Output directory for generated tests"
    class_option :test_framework, aliases: "-t", default: "rspec", desc: "Test framework: rspec or minitest"
    class_option :provider, desc: "LLM provider (e.g. anthropic, openai)"
    class_option :model, desc: "LLM model name"
    class_option :api_key, desc: "API key (overrides env var)"
    class_option :pause, aliases: "-p", type: :numeric, default: 1, desc: "Pause between API calls in seconds"

    map "--version" => :version

    desc "version", "Show version"
    def version
      puts Testgenai::VERSION
    end

    desc "scan", "Scan for untested code and report it"
    def scan
      config = build_config
      scanner = build_scanner(config)
      methods = scanner.scan
      reporter.scan_results(methods)
    end

    desc "context", "Scan, build LLM context, and report it (diagnostic)"
    def context
      config = build_config
      scanner = build_scanner(config)
      methods = scanner.scan
      ctx_builder = ContextBuilder.new
      methods.each do |method_info|
        ctx = ctx_builder.build(method_info)
        reporter.context_result(method_info, ctx)
      end
    end

    desc "generate", "Full pipeline: scan → context → generate → validate"
    def generate
      config = build_config
      scanner = build_scanner(config)
      methods = scanner.scan

      if methods.empty?
        reporter.scan_results(methods)
        exit 0
      end

      generator = config.generator_class.new(config)
      validator = config.validator_class.new
      single_pipeline = Pipeline.new(generator, validator)
      ctx_builder = ContextBuilder.new
      batch = BatchPipeline.new(config, ctx_builder, single_pipeline, reporter)

      results = batch.run(methods)
      reporter.summary(results)
      exit(results[:successful].empty? ? 1 : 0)
    rescue ConfigurationError => e
      warn "Error: #{e.message}"
      exit 2
    end

    private

    def build_config
      Configuration.new(
        provider: options[:provider],
        model: options[:model],
        api_key: options[:api_key],
        framework: options[:test_framework],
        output_dir: options[:output_dir],
        pause: options[:pause]
      )
    rescue ConfigurationError => e
      warn "Configuration error: #{e.message}"
      exit 2
    end

    def build_scanner(config)
      resultset = File.join(Dir.pwd, "coverage", ".resultset.json")

      if File.exist?(resultset)
        return Scanner::SimplecovScanner.new
      end

      unless simplecov_in_gemfile?
        warn "Warning: SimpleCov not found in Gemfile or gemspec. Using file-existence scanner."
        warn "Note: file-existence scanner cannot detect untested methods in partially-tested files."
        return Scanner::FileExistenceScanner.new
      end

      warn "Running test suite to generate coverage data..."
      cmd = config.framework == "minitest" ? "bundle exec ruby -Itest test/**/*_test.rb" : "bundle exec rspec"
      system({"COVERAGE" => "true"}, cmd, out: File::NULL, err: File::NULL)

      if File.exist?(resultset)
        Scanner::SimplecovScanner.new
      else
        warn "Warning: Coverage generation failed. Using file-existence scanner."
        Scanner::FileExistenceScanner.new
      end
    end

    def simplecov_in_gemfile?
      gemfiles = Dir.glob(File.join(Dir.pwd, "{Gemfile,*.gemspec}"))
      gemfiles.any? { |f| File.read(f).include?("simplecov") }
    end

    def reporter
      @reporter ||= Reporter.new
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/testgenai/cli_spec.rb
```

Expected: all green.

- [ ] **Step 5: Run the full test suite**

```bash
bundle exec rspec
```

Expected: all examples passing.

- [ ] **Step 6: Commit**

```bash
git add lib/testgenai/cli.rb spec/testgenai/cli_spec.rb
git commit -m "feat: add CLI with scan/context/generate commands and scanner startup sequence"
```

---

## Self-Review

### Spec coverage check

| Spec section | Covered by task |
|---|---|
| Configuration (§2): env/flag merging, defaults | Task 2 |
| Configuration (§2): strategy class selection | Task 2 |
| CLI (§3): scan/context/generate commands | Task 14 |
| CLI (§3): global flags (--provider, --model, etc.) | Task 14 |
| Scanner startup sequence (§4): resultset.json check | Task 14 (build_scanner) |
| Scanner startup sequence (§4): COVERAGE=true run | Task 14 (build_scanner) |
| Scanner startup sequence (§4): SimpleCov not in Gemfile fallback | Task 14 (build_scanner) |
| Scanner startup sequence (§4): test run fails fallback | Task 14 (build_scanner) |
| SimpleCovScanner (§4): parse resultset.json | Task 5 |
| SimpleCovScanner (§4): zero/nil coverage detection | Task 5 |
| SimpleCovScanner (§4): skip spec/ and test/ files | Task 5 |
| FileExistenceScanner (§4): walk lib/app | Task 4 |
| FileExistenceScanner (§4): skip files with spec | Task 4 |
| FileExistenceScanner (§4): AST method extraction | Task 4 |
| Both scanners: same return shape | Tasks 4+5 (identical descriptor hash) |
| ContextBuilder (§5): full source file | Task 6 |
| ContextBuilder (§5): dependencies (require/require_relative) | Task 6 |
| ContextBuilder (§5): example usages (up to 3) | Task 6 |
| ContextBuilder (§5): related tests | Task 6 |
| Generator (§6): generate interface with feedback | Tasks 8+9 |
| Generator (§6): output path resolution | Tasks 8+9 |
| Generator (§6): CodeExtractor fence-stripping | Task 3 |
| Validator (§7): write file, run, parse output | Tasks 10+11 |
| Validator (§7): load error vs assertion failure distinction | Tasks 10+11 |
| Validator (§7): cleanup on load failure | Tasks 10+11 |
| Validator (§7): result shape { valid, runs, passes, errors } | Tasks 10+11 |
| Pipeline (§8): 3-attempt retry | Task 12 |
| Pipeline (§8): failure feedback passed to generator | Task 12 |
| BatchPipeline (§8): iterate methods | Task 13 |
| BatchPipeline (§8): pause between calls | Task 13 |
| BatchPipeline (§8): unexpected errors → skipped | Task 13 |
| Reporter (§8): separate from pipeline | Task 7 |
| Error handling (§9): auth failure → abort | Task 13 (ConfigurationError) |
| Error handling (§9): other API error → skip | Task 13 |
| Error handling (§9): scanner fallback on test fail | Task 14 |
| Exit codes (§9): 0 = success, 1 = all failed, 2 = config | Task 14 |
| CodeExtractor: ruby fence, generic fence, raw fallback | Task 3 |
| CodeExtractor: not using with_schema (any model support) | Task 3 (direct string extraction) |

All spec sections are covered. No gaps found.

### Placeholder scan

None found — all steps contain actual code.

### Type consistency

- Method descriptor shape `{file:, class:, method:, start_line:, end_line:}` used consistently in Tasks 4, 5, 6, 7, 8, 9, 12, 13, 14.
- Context shape `{target_file:, dependencies:, example_usage:, related_tests:}` used consistently in Tasks 6, 8, 9, 12, 13.
- Validator result shape `{valid:, runs:, passes:, errors:}` used consistently in Tasks 10, 11, 12.
- BatchPipeline result shape `{successful:, failed:, skipped:}` used consistently in Tasks 13, 14.
- `output_path_for` method defined in Base (Task 8) and called in Pipeline (Task 12) — consistent.
- `call_llm` is private in Base (Task 8) and stubbed in generator specs — consistent.

No type mismatches found.
