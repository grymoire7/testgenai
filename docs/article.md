# A coding guide to build an AI-assisted test generation pipeline using Ruby agents

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
identifies untested code, feeds it to Claude with the right context, validates
the results, and gives you a pull request to review.

This isn't about replacing your judgment as a developer. It's about automating
the mechanical parts of test writing so you can focus on reviewing whether the
tests actually verify the right behavior.

## The basic architecture

The pipeline has five main stages:

1. Scan your codebase to find classes and methods without test coverage
2. Build context for each piece of untested code
3. Generate tests using Claude
4. Validate that the generated tests run and pass
5. Collect the results into reviewable pull requests

Each stage needs to be reliable enough that you can walk away and trust the
process to complete. That means handling errors gracefully, providing clear
output about what happened, and making it easy to pick up where things left off
if something breaks.

Let's build this piece by piece.

## Finding untested code

Before you can generate tests, you need to know what needs testing. SimpleCov
is the standard tool for Ruby coverage analysis, but its output is designed for
humans reading HTML reports. You need something machine-readable.

Here's a simple coverage analyzer that identifies untested methods:

```ruby
require 'parser/current'
require 'simplecov'

class CoverageAnalyzer
  def initialize(coverage_data)
    @coverage_data = coverage_data
  end

  def untested_methods
    untested = []
    
    @coverage_data.each do |filename, coverage|
      next if filename.include?('spec/')
      next if filename.include?('test/')
      
      source = File.read(filename)
      ast = Parser::CurrentRuby.parse(source)
      
      methods = extract_methods(ast, filename)
      methods.each do |method_info|
        if method_uncovered?(method_info, coverage)
          untested << method_info
        end
      end
    end
    
    untested
  end

  private

  def extract_methods(node, filename, namespace = [])
    return [] unless node.is_a?(Parser::AST::Node)
    
    methods = []
    
    case node.type
    when :class, :module
      class_name = node.children[0].children.last
      new_namespace = namespace + [class_name]
      node.children.each do |child|
        methods.concat(extract_methods(child, filename, new_namespace))
      end
    when :def
      method_name = node.children[0]
      location = node.location
      methods << {
        file: filename,
        class: namespace.join('::'),
        method: method_name,
        start_line: location.line,
        end_line: location.last_line
      }
    else
      node.children.each do |child|
        methods.concat(extract_methods(child, filename, namespace))
      end
    end
    
    methods
  end

  def method_uncovered?(method_info, coverage)
    (method_info[:start_line]..method_info[:end_line]).all? do |line|
      coverage[line - 1].nil? || coverage[line - 1].zero?
    end
  end
end
```

This gives you a list of methods with their locations and namespaces. Run your
existing test suite with SimpleCov enabled, feed the results to this analyzer,
and you'll know exactly what needs tests.

But knowing you need tests isn't enough. The AI needs to understand what the
code actually does.

## Building context for the AI

When you ask Claude to write tests, you can't just paste in a single method and
expect good results. The AI needs to see how the code fits together. What
classes does it inherit from? What methods does it call? What are the
dependencies?

Context building is where most quick-and-dirty AI test generators fall apart.
They either give too little context (resulting in tests that don't compile) or
too much (hitting token limits and getting confused).

Here's a context builder that finds the sweet spot:

```ruby
class ContextBuilder
  def initialize(project_root)
    @project_root = project_root
  end

  def build_context(method_info)
    file_content = File.read(method_info[:file])
    ast = Parser::CurrentRuby.parse(file_content)
    
    context = {
      target_file: file_content,
      dependencies: find_dependencies(ast),
      example_usage: find_example_usage(method_info),
      related_tests: find_related_tests(method_info)
    }
    
    context
  end

  private

  def find_dependencies(ast)
    dependencies = []
    
    # Find required files
    ast.each_node(:send) do |node|
      if node.children[1] == :require || node.children[1] == :require_relative
        dependencies << node.children[2].children[0]
      end
    end
    
    # Find class/module dependencies
    ast.each_node(:const) do |node|
      const_name = fully_qualified_const_name(node)
      if const_name && project_file?(const_name)
        dependencies << const_name
      end
    end
    
    dependencies.uniq
  end

  def find_example_usage(method_info)
    # Search for calls to this method in the codebase
    usage_pattern = /#{method_info[:method]}/
    examples = []
    
    Dir.glob("#{@project_root}/**/*.rb").each do |file|
      next if file.include?('spec/')
      
      File.readlines(file).each_with_index do |line, idx|
        if line.match?(usage_pattern)
          examples << {
            file: file,
            line_number: idx + 1,
            context: surrounding_lines(file, idx)
          }
        end
      end
      
      break if examples.size >= 3
    end
    
    examples
  end

  def find_related_tests(method_info)
    # Look for existing tests for the same class
    spec_file = method_info[:file].gsub(/\.rb$/, '_spec.rb')
                                  .gsub(/^(app|lib)\//, 'spec/')
    
    if File.exist?(spec_file)
      File.read(spec_file)
    else
      nil
    end
  end

  def surrounding_lines(file, center_line, radius = 3)
    lines = File.readlines(file)
    start_line = [0, center_line - radius].max
    end_line = [lines.size - 1, center_line + radius].min
    
    lines[start_line..end_line].join
  end
end
```

This builder creates a context package that includes the target file, its
dependencies, examples of how the method is actually used in your codebase, and
any existing tests for related methods. That's enough for Claude to understand
what your code does without drowning in irrelevant details.

## Generating tests with Claude

Now comes the interesting part. You have untested code and context. How do you
prompt Claude to generate actually useful tests?

The key is being specific about what "useful" means. You don't want tests that
just call the method and check it doesn't crash. You want tests that verify
behavior, handle edge cases, and would actually catch bugs if the
implementation changed.

Here's a prompt structure that works:

```ruby
class TestGenerator
  def initialize(api_key)
    @client = Anthropic::Client.new(api_key: api_key)
  end

  def generate_test(method_info, context)
    prompt = build_prompt(method_info, context)
    
    response = @client.messages.create(
      model: "claude-3-5-sonnet-20241022",
      max_tokens: 4096,
      messages: [
        {
          role: "user",
          content: prompt
        }
      ]
    )
    
    extract_test_code(response.content[0].text)
  end

  private

  def build_prompt(method_info, context)
    <<~PROMPT
      I need comprehensive RSpec tests for the following Ruby method:

      File: #{method_info[:file]}
      Class: #{method_info[:class]}
      Method: #{method_info[:method]}

      Here's the implementation:
      ```ruby
      #{context[:target_file]}
      ```

      #{dependency_context(context[:dependencies])}
      #{usage_context(context[:example_usage])}
      #{existing_test_context(context[:related_tests])}

      Generate RSpec tests that:
      1. Test the happy path with typical inputs
      2. Test edge cases (nil, empty, boundary values)
      3. Test error conditions if applicable
      4. Verify interactions with dependencies if the method calls other objects
      5. Use appropriate RSpec matchers and be idiomatic
      6. Include descriptive test names that explain what behavior is being verified

      Follow these conventions:
      - Use `describe` for the class and `context` for different scenarios
      - Use `let` blocks for test data setup
      - Use `before` blocks for setup that applies to multiple tests
      - Mock external dependencies appropriately
      - Make tests independent and not reliant on execution order

      Return only the RSpec test code, no explanations or markdown formatting except the code block.
    PROMPT
  end

  def dependency_context(dependencies)
    return "" if dependencies.empty?
    
    <<~CONTEXT
      This code depends on:
      #{dependencies.map { |d| "- #{d}" }.join("\n")}
    CONTEXT
  end

  def usage_context(examples)
    return "" if examples.empty?
    
    <<~CONTEXT
      Here are some examples of how this method is used in the codebase:
      #{examples.map { |ex| "#{ex[:file]}:#{ex[:line_number]}\n#{ex[:context]}" }.join("\n\n")}
    CONTEXT
  end

  def existing_test_context(related_tests)
    return "" if related_tests.nil?
    
    <<~CONTEXT
      Here are existing tests for related methods in the same class. Use similar style and conventions:
      ```ruby
      #{related_tests}
      ```
    CONTEXT
  end

  def extract_test_code(response_text)
    # Claude sometimes wraps code in markdown fences despite instructions
    if response_text.include?('```ruby')
      response_text[/```ruby\n(.*?)```/m, 1]
    elsif response_text.include?('```')
      response_text[/```\n(.*?)```/m, 1]
    else
      response_text
    end
  end
end
```

The prompt does several important things. It gives Claude the full context it
needs to understand the code. It explicitly lists what makes a good test. It
provides existing test examples so the generated code matches your project's
style. And it's specific about formatting to make parsing easier.

## Validating generated tests

Generating test code is only half the battle. You need to know if the tests
actually work. Do they run? Do they pass? Do they test anything meaningful?

Here's a validation harness:

```ruby
class TestValidator
  def initialize(project_root)
    @project_root = project_root
  end

  def validate(test_code, spec_file_path)
    result = {
      valid: false,
      runs: false,
      passes: false,
      errors: []
    }

    # Write the test file
    write_test_file(spec_file_path, test_code)
    
    # Try to run it
    output, status = run_rspec(spec_file_path)
    
    result[:runs] = status.success? || output.include?('examples')
    
    if result[:runs]
      result[:passes] = status.success?
      result[:valid] = status.success?
      
      unless status.success?
        result[:errors] = parse_failures(output)
      end
    else
      result[:errors] = parse_syntax_errors(output)
    end
    
    result
  end

  private

  def write_test_file(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def run_rspec(spec_file)
    output = `cd #{@project_root} && bundle exec rspec #{spec_file} --format documentation 2>&1`
    [output, $?]
  end

  def parse_failures(output)
    failures = []
    
    output.scan(/^\s+\d+\)(.*?)(?=^\s+\d+\)|Finished in|$)/m).each do |match|
      failures << match[0].strip
    end
    
    failures
  end

  def parse_syntax_errors(output)
    errors = []
    
    output.each_line do |line|
      if line.include?('SyntaxError') || line.include?('NameError') || line.include?('LoadError')
        errors << line.strip
      end
    end
    
    errors
  end
end
```

This validator actually runs the generated tests and categorizes the results.
Tests might fail because they have syntax errors, because they reference
classes that don't exist, or because they make incorrect assumptions about
behavior. Each type of failure needs different handling.

If tests fail because of incorrect behavior assumptions, that's actually
interesting. Either the AI misunderstood your code, or there's a real bug.
Either way, you want to review those cases manually.

## Handling failures and retries

Not every test generation attempt succeeds on the first try. Claude might
generate tests that reference a constant that doesn't exist in your project. It
might make assumptions about method signatures that aren't true. It might just
have a bad day and output malformed Ruby.

A robust pipeline needs retry logic with feedback:

```ruby
class TestGenerationPipeline
  MAX_RETRIES = 3

  def initialize(api_key, project_root)
    @generator = TestGenerator.new(api_key)
    @validator = TestValidator.new(project_root)
    @context_builder = ContextBuilder.new(project_root)
  end

  def generate_and_validate(method_info)
    context = @context_builder.build_context(method_info)
    spec_file_path = determine_spec_path(method_info)
    
    attempt = 0
    feedback = nil
    
    while attempt < MAX_RETRIES
      attempt += 1
      
      test_code = @generator.generate_test(method_info, context, feedback)
      validation_result = @validator.validate(test_code, spec_file_path)
      
      if validation_result[:valid]
        return {
          success: true,
          spec_file: spec_file_path,
          test_code: test_code,
          attempts: attempt
        }
      end
      
      feedback = build_feedback(validation_result)
    end
    
    # All retries exhausted
    {
      success: false,
      spec_file: spec_file_path,
      errors: validation_result[:errors],
      attempts: attempt
    }
  end

  private

  def determine_spec_path(method_info)
    method_info[:file]
      .gsub(/^(app|lib)\//, 'spec/')
      .gsub(/\.rb$/, '_spec.rb')
  end

  def build_feedback(validation_result)
    return nil if validation_result[:valid]
    
    feedback = "The generated tests failed with the following errors:\n\n"
    
    validation_result[:errors].each do |error|
      feedback += "#{error}\n"
    end
    
    feedback += "\nPlease fix these issues and generate corrected tests."
    feedback
  end
end
```

The feedback loop is crucial. When tests fail, the pipeline tells Claude
exactly what went wrong and asks it to fix the issues. This usually works for
simple problems like undefined constants or incorrect method names.

You need to update the generator to accept feedback:

```ruby
class TestGenerator
  def generate_test(method_info, context, feedback = nil)
    prompt = build_prompt(method_info, context, feedback)
    # rest of the method...
  end

  private

  def build_prompt(method_info, context, feedback)
    base_prompt = # previous prompt building logic
    
    if feedback
      base_prompt += "\n\n#{feedback}"
    end
    
    base_prompt
  end
end
```

## Processing an entire codebase

Now you have all the pieces. Let's orchestrate them to process your whole codebase:

```ruby
class BatchTestGenerator
  def initialize(api_key, project_root)
    @pipeline = TestGenerationPipeline.new(api_key, project_root)
    @project_root = project_root
  end

  def generate_tests_for_project
    # Get coverage data
    puts "Analyzing test coverage..."
    coverage_data = load_coverage_data
    analyzer = CoverageAnalyzer.new(coverage_data)
    untested_methods = analyzer.untested_methods
    
    puts "Found #{untested_methods.size} untested methods"
    
    results = {
      successful: [],
      failed: [],
      skipped: []
    }
    
    untested_methods.each_with_index do |method_info, index|
      puts "\n[#{index + 1}/#{untested_methods.size}] Generating tests for #{method_info[:class]}##{method_info[:method]}"
      
      begin
        result = @pipeline.generate_and_validate(method_info)
        
        if result[:success]
          puts "  ✓ Success (#{result[:attempts]} attempt(s))"
          results[:successful] << result
        else
          puts "  ✗ Failed after #{result[:attempts]} attempts"
          results[:failed] << { method: method_info, result: result }
        end
      rescue => e
        puts "  ⚠ Skipped due to error: #{e.message}"
        results[:skipped] << { method: method_info, error: e }
      end
      
      # Rate limiting
      sleep 1
    end
    
    generate_summary(results)
    create_pull_request(results) if results[:successful].any?
    
    results
  end

  private

  def load_coverage_data
    # SimpleCov stores coverage data in coverage/.resultset.json
    resultset_path = File.join(@project_root, 'coverage', '.resultset.json')
    data = JSON.parse(File.read(resultset_path))
    data.dig('RSpec', 'coverage') || {}
  end

  def generate_summary(results)
    puts "\n" + "=" * 60
    puts "Test Generation Summary"
    puts "=" * 60
    puts "Successful: #{results[:successful].size}"
    puts "Failed: #{results[:failed].size}"
    puts "Skipped: #{results[:skipped].size}"
    puts "\nGenerated test files:"
    results[:successful].each do |result|
      puts "  - #{result[:spec_file]}"
    end
    
    if results[:failed].any?
      puts "\nFailed methods:"
      results[:failed].each do |failed|
        method = failed[:method]
        puts "  - #{method[:class]}##{method[:method]}"
        failed[:result][:errors].each do |error|
          puts "    #{error}"
        end
      end
    end
  end

  def create_pull_request(results)
    # Stage the generated files
    spec_files = results[:successful].map { |r| r[:spec_file] }
    system("git checkout -b ai-generated-tests-#{Time.now.to_i}")
    system("git add #{spec_files.join(' ')}")
    
    commit_message = <<~MSG
      Add AI-generated tests for #{results[:successful].size} untested methods
      
      Generated comprehensive RSpec tests for previously untested code.
      All generated tests have been validated to run and pass.
      
      Files modified:
      #{spec_files.map { |f| "- #{f}" }.join("\n")}
    MSG
    
    system("git commit -m '#{commit_message}'")
    puts "\n✓ Created branch and committed generated tests"
    puts "Review the changes and push when ready"
  end
end
```

This batch processor ties everything together. It finds untested methods,
generates tests for each one, validates the results, and organizes everything
into a reviewable branch.

Run it like this:

```ruby
# First, generate coverage data by running your existing tests
system("COVERAGE=true bundle exec rspec")

# Then generate tests for uncovered code
generator = BatchTestGenerator.new(ENV['ANTHROPIC_API_KEY'], Dir.pwd)
results = generator.generate_tests_for_project
```

Go get coffee. Come back to a branch full of tests.

## Making the tests actually useful

Generated tests that pass aren't necessarily good tests. They might test
implementation details instead of behavior. They might make brittle
assumptions. They might pass now but break the moment you refactor.

Here's where you add quality checks. One useful heuristic is mutation testing.
If you change the implementation and the tests still pass, the tests aren't
testing anything meaningful:

```ruby
class TestQualityChecker
  def check_quality(method_info, spec_file)
    original_code = File.read(method_info[:file])
    mutations = generate_mutations(method_info, original_code)
    
    surviving_mutations = []
    
    mutations.each do |mutation|
      # Apply mutation
      File.write(method_info[:file], mutation[:code])
      
      # Run tests
      output, status = run_tests(spec_file)
      
      if status.success?
        # Tests still pass with mutated code - bad sign
        surviving_mutations << mutation
      end
      
      # Restore original
      File.write(method_info[:file], original_code)
    end
    
    {
      quality_score: 1.0 - (surviving_mutations.size.to_f / mutations.size),
      surviving_mutations: surviving_mutations
    }
  end

  private

  def generate_mutations(method_info, code)
    mutations = []
    
    # Simple mutations: flip conditionals, change operators, etc.
    # This is simplified - a real implementation would use a proper mutation testing library
    
    # Flip == to !=
    if code.include?('==')
      mutated = code.gsub('==', '!=')
      mutations << { type: 'flip_equality', code: mutated }
    end
    
    # Change && to ||
    if code.include?('&&')
      mutated = code.gsub('&&', '||')
      mutations << { type: 'change_logical_operator', code: mutated }
    end
    
    # Return nil instead of actual return value
    ast = Parser::CurrentRuby.parse(code)
    # ... more sophisticated mutations ...
    
    mutations
  end

  def run_tests(spec_file)
    output = `bundle exec rspec #{spec_file} 2>&1`
    [output, $?]
  end
end
```

You can integrate this into your pipeline to flag tests that look suspicious:

```ruby
class TestGenerationPipeline
  def generate_and_validate(method_info)
    # ... existing code ...
    
    if validation_result[:valid]
      quality = @quality_checker.check_quality(method_info, spec_file_path)
      
      if quality[:quality_score] < 0.5
        puts "  ⚠ Warning: Low quality tests (score: #{quality[:quality_score]})"
        # Add to review queue
      end
      
      return {
        success: true,
        spec_file: spec_file_path,
        test_code: test_code,
        quality: quality,
        attempts: attempt
      }
    end
    
    # ... rest of method ...
  end
end
```

Low quality scores don't mean you should reject the tests outright. They mean
you should pay extra attention when reviewing them.

## Different types of tests for different code

Not everything needs the same kind of tests. Service objects need unit tests.
Controllers need integration tests. Complex algorithms might benefit from
property-based testing.

You can extend the generator to choose appropriate test strategies:

```ruby
class TestGenerator
  def generate_test(method_info, context, feedback = nil)
    test_type = determine_test_type(method_info, context)
    
    case test_type
    when :unit
      generate_unit_test(method_info, context, feedback)
    when :integration
      generate_integration_test(method_info, context, feedback)
    when :property_based
      generate_property_test(method_info, context, feedback)
    end
  end

  private

  def determine_test_type(method_info, context)
    if method_info[:file].include?('controllers/')
      :integration
    elsif method_info[:class].include?('Service')
      :unit
    elsif complex_algorithm?(method_info, context)
      :property_based
    else
      :unit
    end
  end

  def complex_algorithm?(method_info, context)
    # Heuristic: methods with lots of conditionals and loops
    # might benefit from property-based testing
    source = context[:target_file]
    source.scan(/if |unless |while |until |case /).size > 3
  end

  def generate_integration_test(method_info, context, feedback)
    # Different prompt for integration tests
    prompt = <<~PROMPT
      Generate integration tests for this Rails controller action using rack-test.
      
      #{base_context(method_info, context)}
      
      The tests should:
      1. Set up necessary database state
      2. Make HTTP requests to the endpoint
      3. Verify response status codes
      4. Verify response body content
      5. Verify database state changes if applicable
      
      Use factories for test data setup if available.
      
      #{feedback}
    PROMPT
    
    # ... send to Claude and parse response ...
  end

  def generate_property_test(method_info, context, feedback)
    prompt = <<~PROMPT
      Generate property-based tests using rspec-quickcheck for this method.
      
      #{base_context(method_info, context)}
      
      The tests should:
      1. Define properties that should hold for all valid inputs
      2. Use Rspec::Given's `property` to test these properties with generated inputs
      3. Cover edge cases through the property definitions
      
      Think about invariants like:
      - Idempotence (calling twice gives same result)
      - Round-trip properties (encode then decode returns original)
      - Comparison properties (result should be consistent with a simpler implementation)
      
      #{feedback}
    PROMPT
    
    # ... send to Claude and parse response ...
  end
end
```

Property-based tests are particularly interesting for AI generation because
defining good properties requires understanding the code at a conceptual level,
which Claude actually does well.

## Integrating into your development workflow

The batch processor is great for catching up on legacy code. But how do you
prevent new untested code from accumulating?

Add the pipeline to your CI process:

```ruby
# scripts/generate_tests_for_new_code.rb

class CITestGenerator
  def generate_tests_for_changes
    # Get list of changed files in this branch
    changed_files = `git diff --name-only main...HEAD`.split("\n")
    ruby_files = changed_files.select { |f| f.end_with?('.rb') && !f.include?('spec/') }
    
    ruby_files.each do |file|
      # Check coverage for this specific file
      coverage = get_file_coverage(file)
      
      if coverage < 80
        puts "#{file} has #{coverage}% coverage"
        
        # Generate tests for new methods in this file
        new_methods = find_new_methods(file)
        new_methods.each do |method_info|
          result = @pipeline.generate_and_validate(method_info)
          
          if result[:success]
            puts "  ✓ Generated tests for #{method_info[:method]}"
          else
            # Create a GitHub comment suggesting tests are needed
            create_review_comment(file, method_info, result)
          end
        end
      end
    end
  end

  private

  def find_new_methods(file)
    # Compare current version with main branch
    current_version = File.read(file)
    main_version = `git show main:#{file}`
    
    current_ast = Parser::CurrentRuby.parse(current_version)
    main_ast = Parser::CurrentRuby.parse(main_version)
    
    current_methods = extract_all_methods(current_ast)
    main_methods = extract_all_methods(main_ast)
    
    # Methods in current but not in main
    current_methods - main_methods
  end

  def create_review_comment(file, method_info, result)
    comment = <<~COMMENT
      The method `#{method_info[:method]}` in this file lacks test coverage.
      
      I attempted to generate tests automatically but encountered issues:
      #{result[:errors].join("\n")}
      
      Please add tests for this method or review the generated tests in the suggested commit.
    COMMENT
    
    # Use GitHub API to post review comment
    # Implementation depends on your CI setup
  end
end
```

This scans pull requests for new code without tests, attempts to generate tests
automatically, and creates review comments when it can't.

You can also run it as a git pre-commit hook to catch untested code before it
even gets pushed:

```ruby
#!/usr/bin/env ruby
# .git/hooks/pre-commit

require_relative '../lib/test_generation_pipeline'

staged_files = `git diff --cached --name-only`.split("\n")
ruby_files = staged_files.select { |f| f.end_with?('.rb') && !f.include?('spec/') }

untested_methods = []

ruby_files.each do |file|
  # Quick check: does this file have a corresponding spec?
  spec_file = file.gsub(/^(app|lib)\//, 'spec/').gsub(/\.rb$/, '_spec.rb')
  
  unless File.exist?(spec_file)
    puts "Warning: #{file} has no spec file"
    # Optionally generate one
  end
end

# Exit 0 to allow commit, or exit 1 to block it
exit 0
```

## When AI-generated tests aren't enough

This whole pipeline makes one big assumption: that the right tests are
mechanical enough to be described by the code itself. That's often true for
simple CRUD operations, data transformations, and API endpoints.

It's less true for complex business logic where the "correct" behavior depends
on domain knowledge that isn't visible in the code. A payment processing method
might have edge cases around international transactions that you only know
about because you've dealt with the payment provider's quirks.

For code like this, AI-generated tests are a starting point, not a finish line.
The pipeline can generate the basic structure and happy path tests. You add the
domain-specific edge cases yourself.

Here's how you might structure that workflow:

```ruby
class HybridTestGenerator
  def generate_with_human_review(method_info)
    # Generate initial tests
    result = @pipeline.generate_and_validate(method_info)
    
    if result[:success]
      # Create a PR with the generated tests
      create_draft_pr(result)
      
      # Add comments highlighting areas that need human attention
      flag_complex_logic(result[:spec_file], method_info)
      
      # Generate a checklist of things to review
      create_review_checklist(method_info, result)
    end
  end

  private

  def flag_complex_logic(spec_file, method_info)
    source = File.read(method_info[:file])
    
    comments = []
    
    # Check for external API calls
    if source.include?('HTTP') || source.include?('RestClient') || source.include?('Net::HTTP')
      comments << "This method makes external API calls. Verify the tests properly mock/stub them."
    end
    
    # Check for database transactions
    if source.include?('transaction') || source.include?('ActiveRecord')
      comments << "This method uses database transactions. Ensure tests verify transactional behavior."
    end
    
    # Check for time-dependent logic
    if source.include?('Time') || source.include?('Date') || source.include?('DateTime')
      comments << "This method uses time/date logic. Verify tests use time mocking appropriately."
    end
    
    # Add these as TODO comments in the test file
    spec_content = File.read(spec_file)
    header_comment = comments.map { |c| "# TODO: #{c}" }.join("\n")
    
    File.write(spec_file, "#{header_comment}\n\n#{spec_content}")
  end

  def create_review_checklist(method_info, result)
    checklist = <<~CHECKLIST
      ## Generated Test Review Checklist
      
      Tests have been generated for `#{method_info[:class]}##{method_info[:method]}`
      
      Please review:
      - [ ] Tests cover the happy path
      - [ ] Tests cover error cases
      - [ ] Tests cover edge cases specific to your domain
      - [ ] Mocking/stubbing is appropriate
      - [ ] Test data setup is realistic
      - [ ] Test names clearly describe what's being tested
      - [ ] Tests are independent and can run in any order
      
      Quality score: #{result[:quality][:quality_score]}
      
      Consider adding tests for:
      - Domain-specific edge cases not visible in the code
      - Integration with external systems
      - Performance characteristics if relevant
    CHECKLIST
    
    # Write this to the PR description or a review comment
    checklist
  end
end
```

The AI generates the scaffolding. You add the nuance.

## The reality of technical debt

If you're practicing TDD from the beginning, you don't need most of this. You
write tests before implementation. Your code is testable by design because you
literally can't write untestable code when you write tests first.

But reality is messier than best practices. Most codebases have untested code.
Some of it was written before the team adopted TDD. Some of it was a quick fix
during an outage. Some of it seemed too obvious to test at the time.

That untested code doesn't become less important just because it lacks tests.
It still runs in production. It still has bugs. It still needs to be
maintained.

AI-assisted test generation gives you a way to address that technical debt
without halting feature development. You can point this pipeline at your
codebase, let it generate tests overnight, and review them the next morning.
Maybe you merge 80% of them as-is and improve the other 20%. That's still a
massive improvement over manual test writing.

The key is treating generated tests as a first draft, not a final product.
Review them. Question them. Improve them. But don't let perfect be the enemy of
good enough. Some test coverage is better than no test coverage, and
AI-generated tests that pass basic quality checks are significantly better than
nothing.

## Putting it all together

Here's a complete script that runs the entire pipeline:

```ruby
#!/usr/bin/env ruby

require 'bundler/setup'
require_relative 'lib/coverage_analyzer'
require_relative 'lib/context_builder'
require_relative 'lib/test_generator'
require_relative 'lib/test_validator'
require_relative 'lib/test_quality_checker'
require_relative 'lib/test_generation_pipeline'
require_relative 'lib/batch_test_generator'

# Configuration
API_KEY = ENV['ANTHROPIC_API_KEY']
PROJECT_ROOT = Dir.pwd
MIN_QUALITY_SCORE = 0.6

# Step 1: Generate coverage data
puts "Step 1: Generating coverage data..."
system("COVERAGE=true bundle exec rspec") or abort("Failed to generate coverage")

# Step 2: Initialize the pipeline
puts "\nStep 2: Initializing test generation pipeline..."
generator = BatchTestGenerator.new(API_KEY, PROJECT_ROOT)

# Step 3: Generate tests
puts "\nStep 3: Generating tests for untested code..."
results = generator.generate_tests_for_project

# Step 4: Report results
puts "\n" + "=" * 60
puts "FINAL RESULTS"
puts "=" * 60

successful_count = results[:successful].size
failed_count = results[:failed].size
low_quality_count = results[:successful].count { |r| r[:quality][:quality_score] < MIN_QUALITY_SCORE }

puts "Successfully generated: #{successful_count}"
puts "Failed to generate: #{failed_count}"
puts "Low quality (needs review): #{low_quality_count}"

if successful_count > 0
  puts "\nGenerated tests have been committed to a new branch."
  puts "Run 'git push origin HEAD' to push and create a PR."
end

# Step 5: Create a summary document
summary_file = "test_generation_summary.md"
File.write(summary_file, generate_markdown_summary(results))
puts "\nDetailed summary written to #{summary_file}"

def generate_markdown_summary(results)
  <<~MARKDOWN
    # AI Test Generation Summary
    
    Generated: #{Time.now}
    
    ## Statistics
    
    - Successful: #{results[:successful].size}
    - Failed: #{results[:failed].size}
    - Skipped: #{results[:skipped].size}
    
    ## Successful Tests
    
    #{results[:successful].map { |r| 
      quality_emoji = r[:quality][:quality_score] >= 0.8 ? "✅" : "⚠️"
      "#{quality_emoji} `#{r[:spec_file]}` (quality: #{r[:quality][:quality_score].round(2)})"
    }.join("\n")}
    
    ## Failed Tests
    
    #{results[:failed].map { |f|
      "- `#{f[:method][:class]}##{f[:method][:method]}`\n  Errors: #{f[:result][:errors].first}"
    }.join("\n")}
    
    ## Recommendations
    
    1. Review tests with quality scores below 0.6
    2. Manually add tests for failed methods
    3. Consider whether skipped methods need different approaches
  MARKDOWN
end
```

Save this as `bin/generate_tests`, make it executable with `chmod +x bin/generate_tests`, and run it:

```bash
export ANTHROPIC_API_KEY=your_api_key
./bin/generate_tests
```

Then go make a sandwich. When you come back, you'll have a branch full of tests
ready for review.

That's the goal. Not to eliminate your role as a developer who understands your
code and makes thoughtful decisions about testing. But to eliminate the tedious
part of translating those decisions into RSpec syntax, setting up test data,
and writing the same patterns over and over.

You make the decisions. The AI does the typing.

