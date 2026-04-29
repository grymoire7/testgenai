# Creating a gem that writes your missing tests

Most Ruby codebases have that one corner where tests fear to tread. Maybe it's
the service object that seemed too simple to test when you wrote it. Maybe it's
the API controller that's been working fine for three years so why bother.
Maybe it's the entire authentication system that someone wrote before anyone on
the current team joined.

You know you should write tests for this stuff. You've probably started a few
times. But between feature deadlines and bug fixes, test coverage for legacy
code keeps sliding down the priority list.

Here's a different approach: build a pipeline that generates tests for you
while you're doing something else. Not by waving your hands and hoping AI
magically understands your code, but by creating a systematic process that
identifies untested code, feeds it to an LLM with the right context, validates
the results, and gives you files ready to review.

This isn't about replacing your judgment as a developer. It's about automating
the mechanical parts of test writing so you can focus on reviewing whether the
tests actually verify the right behavior.

The code in this guide is from
[TestGenAI](https://github.com/grymoire7/testgenai), a working Ruby CLI gem
you can install and run against your own codebase. We'll walk through how each
piece works.

## The basic architecture

The pipeline has five main stages:

1. Scan your codebase to find classes and methods without test coverage
2. Build context for each untested method
3. Generate tests using an LLM
4. Validate that the generated tests run and pass
5. Collect the results

Each stage needs to be reliable enough that you can walk away and trust the
process to complete. That means handling errors gracefully, providing clear
output about what happened, and making it easy to pick up where things left
off if something breaks.

Let's build this piece by piece.

## Finding untested code

Before you can generate tests, you need to know what needs testing. The right
answer depends on whether SimpleCov is available in your project, so the gem
uses two different scanners.

### The SimpleCov scanner

If SimpleCov is set up, TestGenAI runs your test suite with `COVERAGE=true`,
reads the resulting `coverage/.resultset.json`, and uses AST parsing to find
methods where every executable line has zero hits.

```ruby
class SimplecovScanner < Base
  RESULTSET_PATH = "coverage/.resultset.json"

  def scan
    coverage = merged_coverage
    coverage.flat_map do |file, lines|
      next [] if test_file?(file)
      next [] unless File.exist?(file)
      extract_untested_methods(file, lines)
    end
  end

  private

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
end
```

The `merged_coverage` method handles the case where SimpleCov has results from
multiple test runners. It sums the hit counts per line across all runners, so
a method only counts as untested if nothing touched it.

The `untested?` method has a subtle detail worth explaining. It filters out
`nil` entries with `.compact` before checking whether everything is zero. A
`nil` in SimpleCov's line array means that line isn't executable (a blank
line, a comment, an `end`). We only care about lines that can actually run.

This scanner correctly handles partially-tested files. It reports methods that
were never exercised, even if other methods in the same file have full
coverage.

### The file existence scanner

If SimpleCov isn't available, the scanner falls back to checking whether a
spec or test file exists for each source file.

```ruby
class FileExistenceScanner < Base
  def scan
    source_files.reject { |f| test_exists?(f) }.flat_map { |f| extract_methods(f) }
  end

  private

  def test_exists?(source_file)
    rel = relative(source_file)
    base = rel.sub(/\A(?:lib|app)\//, "").sub(/\.rb\z/, "")
    File.exist?(File.join(@root, "spec", "#{base}_spec.rb")) ||
      File.exist?(File.join(@root, "test", "#{base}_test.rb"))
  end
end
```

This scanner is less accurate. A file tested only through integration tests or
through specs for its subclasses will appear fully untested even if its methods
are exercised constantly. The SimpleCov scanner is worth setting up if you
care about precision.

### Shared AST parsing

Both scanners share a `Base` class that walks the AST and builds a list of
method descriptors.

```ruby
class Base
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
end
```

This gives you a list of method descriptors with their file locations,
namespaces, and line ranges. Everything downstream uses this format.

## Building context for the LLM

When you ask an LLM to write tests, you can't just paste in a single method
and expect good results. It needs to see how the code fits together: what
classes it inherits from, what methods it calls, what the dependencies are.

Context building is where most quick-and-dirty AI test generators fall apart.
They either give too little context (resulting in tests that don't compile) or
too much (hitting token limits and getting confused).

Here's the context builder:

```ruby
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
end
```

Each piece of context serves a specific purpose.

`target_file` is the full source file. Not just the method, but the whole
class. The LLM needs the class definition, any constants, and the other
methods it might interact with.

`dependencies` are files required or required_relative in the target. The
builder walks the AST to find `require` and `require_relative` calls and
resolves them to actual file paths on disk.

`example_usage` searches the codebase for calls to the method and returns a
few lines of surrounding context for each. This tells the LLM how the method
is actually used, which is often more useful than the implementation itself for
writing realistic tests.

`related_tests` looks for an existing spec file for the same class. If one
exists, it gets included in the prompt so the LLM can match the style and
conventions of tests you've already written.

## Generating tests with the LLM

TestGenAI uses `ruby_llm` to talk to the LLM. This keeps the generator code
clean and lets you swap providers by changing a config option.

```ruby
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

  private

  def configure_llm
    return unless @config.api_key && @config.provider
    RubyLLM.configure do |c|
      c.public_send(:"#{@config.provider}_api_key=", @config.api_key)
    end
  end

  def call_llm(prompt)
    # Validate provider and model configuration before making the API call
    # ...
    chat = RubyLLM.chat(model: @config.model)
    chat.ask(prompt).content
  end
end
```

The `CodeExtractor` handles the fact that LLMs sometimes wrap their output in
markdown fences even when you tell them not to.

```ruby
class CodeExtractor
  def self.extract(response)
    if (match = response.match(/```ruby\n(.*?)```/m))
      match[1]
    elsif (match = response.match(/```\w*\n(.*?)```/m))
      match[1]
    else
      response
    end
  end
end
```

The actual prompt construction lives in the generator subclasses. Here's the
RSpec version:

```ruby
class RspecGenerator < Base
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

    unless context[:dependencies].to_a.empty?
      prompt += "\n## Dependencies\n"
      prompt += context[:dependencies].map { |d| "- #{d}" }.join("\n")
      prompt += "\n"
    end

    context[:example_usage].to_a.each_with_index do |usage, i|
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
```

The prompt does several things that matter. It gives the LLM the full class
context, not just the method. It includes example usages so the LLM
understands how the method is called in practice. It provides existing tests as
a style reference. And it explicitly requests only code in a specific format,
which makes parsing the response reliable.

The `feedback:` parameter is for the retry loop, which we'll get to next.

There's also a `MinitestGenerator` with an equivalent prompt structure for
projects that use Minitest instead of RSpec.

## Validating generated tests

Generating test code is only half the battle. You need to know if the tests
actually work: do they run, do they pass, and do they fail for the right
reasons when they don't pass?

```ruby
class RspecValidator < Base
  def validate(test_code, output_path)
    write_test_file(test_code, output_path)
    output, exit_status = run_rspec(output_path)
    parse_result(output, exit_status, output_path)
  end

  private

  def run_rspec(path)
    output = `bundle exec rspec #{Shellwords.escape(path)} --format documentation 2>&1`
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
end
```

The validator distinguishes between three cases. Tests that fail to load have
syntax errors, undefined constants, or missing requires. The generated file
gets cleaned up because it's useless. Tests that run but fail have incorrect
behavior assumptions. Tests that pass are ready to commit.

Each case needs different handling in the retry loop.

## Handling failures and retries

Not every generation attempt succeeds on the first try. The LLM might
reference a constant that doesn't exist, make wrong assumptions about method
signatures, or produce malformed Ruby.

The pipeline retries up to three times, feeding errors back to the LLM with
each attempt:

```ruby
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
```

The feedback loop works because LLMs are good at fixing specific errors when
told what went wrong. Undefined constant errors, wrong method signatures, and
incorrect require paths almost always resolve in one retry. More complex
failures like incorrect behavior assumptions may not, and those end up in the
failed bucket for manual review.

## Processing an entire codebase

The `BatchPipeline` ties everything together:

```ruby
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
```

The `sleep @config.pause` between calls is rate limiting. One second by
default, configurable if you're hitting API rate limits.

The error handling separates configuration errors (which should stop
everything) from per-method errors (which should skip that method and
continue). A bad API key should fail fast. A method that's too complex to
parse shouldn't stop the entire run.

## The CLI

All of this is wired together through a Thor-based CLI with three commands:

```bash
testgenai scan      # Find untested methods (no API calls)
testgenai context   # Show what context would be sent to the LLM
testgenai generate  # Run the full pipeline
```

The `scan` command is useful for getting a quick picture of where you have
coverage gaps. The `context` command is a diagnostic that shows exactly what
the LLM will see before you spend API credits on generation.

```bash
testgenai generate --provider anthropic --model claude-opus-4-7
```

Configuration comes from environment variables or flags:

```bash
export TESTGENAI_PROVIDER=anthropic
export TESTGENAI_MODEL=claude-opus-4-7
export ANTHROPIC_API_KEY=your_api_key
testgenai generate
```

Both RSpec and Minitest are supported via `--test-framework minitest`.

Generated test files land in `spec/` or `test/`, mirroring the source file's
path under `lib/` or `app/`. A method in `lib/payments/processor.rb` gets a
test at `spec/payments/processor_spec.rb`.

## Setting up SimpleCov for accurate scanning

The SimpleCov scanner is worth setting up. The file-existence scanner has too
many false positives with shared utilities, base classes, and anything tested
indirectly.

Add SimpleCov to your Gemfile:

```ruby
gem "simplecov", require: false, group: [:development, :test]
```

Configure it to start when `COVERAGE=true` is set:

```ruby
# spec/spec_helper.rb
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start
end
```

Now when you run `testgenai generate`, it will run your test suite with
`COVERAGE=true` first to generate `coverage/.resultset.json`, then use that
data for accurate scanning. If `coverage/.resultset.json` already exists from
a previous run, TestGenAI uses it directly without re-running your suite.

## When AI-generated tests aren't enough

This pipeline makes one assumption: the right tests are mechanical enough to
be described by the code itself. That's often true for CRUD operations, data
transformations, and API endpoints.

It's less true for complex business logic where the "correct" behavior depends
on domain knowledge that isn't visible in the code. A payment processing method
might have edge cases around international transactions that you only know
about because you've dealt with the payment provider's quirks.

For code like this, AI-generated tests are a starting point. The pipeline
generates the basic structure and happy path tests. You add the domain-specific
edge cases yourself.

Generated tests that fail after three retries get collected in the failed
bucket. Those are worth looking at manually. They're usually the
methods where the code is too entangled to test in isolation, or where the
behavior depends on database state that's hard to set up correctly.

## Running it

Install the gem and point it at your project:

```bash
gem install testgenai
cd your_project
testgenai generate --provider anthropic --model claude-opus-4-7
```

Or add it to your Gemfile in the development group and use `bundle exec`:

```bash
bundle exec testgenai generate
```

Go make a sandwich. When you come back, you'll have generated test files ready
to review and commit.

The goal isn't to eliminate your role as a developer who understands your code
and makes thoughtful decisions about testing. It's to eliminate the tedious
part of translating those decisions into RSpec syntax, setting up test data,
and writing the same `describe` and `context` blocks over and over.

You make the decisions. The pipeline does the typing.

