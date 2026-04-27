# TestGenAI Design Spec

Date: 2026-04-27

## Overview

TestGenAI is a Ruby CLI gem that finds untested code in a Ruby codebase and generates tests for it using an AI language model. It is based on the architecture described in `docs/article.md`, which is a reference for concepts — not a strict implementation spec.

## Scope

**In scope for initial implementation:**
- `scan` command: find and report untested methods
- `context` command: scan + build and report LLM context
- `generate` command: full pipeline (scan → context → generate → validate)
- RSpec and Minitest support from the start
- SimpleCov-based scanning with file-existence fallback
- Retry loop with failure feedback (up to 3 attempts per method)

**Explicitly deferred:**
- `TestQualityChecker` (mutation testing for quality scoring)
- CI integration (`CITestGenerator`, GitHub review comments)

Both deferred components can be added later without modifying any existing class interfaces (see Section 10).

---

## 1. Architecture

The system uses a **staged pipeline with strategy injection**. Each stage is an independent, single-purpose class. Framework-specific behavior (RSpec vs Minitest) is encapsulated in strategy classes injected at startup. The CLI composes only the stages each command needs.

```
scan     →  Scanner
context  →  Scanner → ContextBuilder
generate →  Scanner → ContextBuilder → Generator → Validator (with retry)
```

### Directory structure

```
testgenai/
├── exe/
│   └── testgenai
├── lib/
│   └── testgenai/
│       ├── cli.rb
│       ├── configuration.rb
│       ├── code_extractor.rb
│       ├── context_builder.rb
│       ├── reporter.rb
│       ├── pipeline.rb
│       ├── batch_pipeline.rb
│       ├── scanner/
│       │   ├── base.rb
│       │   ├── simplecov_scanner.rb
│       │   └── file_existence_scanner.rb
│       ├── generator/
│       │   ├── base.rb
│       │   ├── rspec_generator.rb
│       │   └── minitest_generator.rb
│       └── validator/
│           ├── base.rb
│           ├── rspec_validator.rb
│           └── minitest_validator.rb
└── spec/
    └── testgenai/      # mirrors lib/ structure
```

---

## 2. Configuration

`Configuration` resolves at startup by merging env vars and CLI flags. Flags take precedence over env vars. After initialization, no class reads `ENV` directly — all consume the config object.

| Concern | Env var | CLI flag |
|---|---|---|
| LLM provider | `TESTGENAI_PROVIDER` | `--provider` |
| LLM model | `TESTGENAI_MODEL` | `--model` |
| API key | Provider-specific (e.g. `ANTHROPIC_API_KEY`) | `--api-key` |
| Test framework | `TESTGENAI_FRAMEWORK` | `-t, --test-framework` |
| Output directory | `TESTGENAI_OUTPUT_DIR` | `-o, --output-dir` |
| Pause between calls | `TESTGENAI_PAUSE` | `-p, --pause SECONDS` (default: 1) |

`Configuration` selects the correct scanner, generator, and validator strategy classes based on `--test-framework` (default: rspec).

---

## 3. CLI

Thor-based. Three commands plus standard global flags.

```
testgenai [options] <command>

Options:
    -h, --help                       Show help
    -v, --version                    Show version
    -o, --output-dir DIR             Output directory for generated tests
    -t, --test-framework FRAMEWORK   Test framework: rspec (default) or minitest
        --provider PROVIDER          LLM provider (e.g. anthropic, openai)
        --model MODEL                LLM model name
        --api-key KEY                API key (overrides env var)
    -p, --pause SECONDS              Pause between API calls (default: 1)

Commands:
    scan        Scan for untested code and report it
    context     Scan, build LLM context, and report it (diagnostic tool)
    generate    Full pipeline: scan → context → generate → validate
```

The `context` command is a transparency/diagnostic tool — it shows exactly what would be sent to the LLM before making any API calls.

---

## 4. Scanner

Returns an array of method descriptors:
```ruby
{ file:, class:, method:, start_line:, end_line: }
```

### Startup sequence
1. Check if `coverage/.resultset.json` exists
2. If not, attempt to run the test suite with `COVERAGE=true` to generate it
3. If SimpleCov is not in the project's Gemfile/gemspec, warn to stderr and use `FileExistenceScanner`
4. If the test run fails, warn to stderr and use `FileExistenceScanner`

### SimpleCovScanner
Parses `coverage/.resultset.json`, walks the AST using the `parser` gem, identifies methods where every line has zero or nil coverage. Skips files under `spec/` and `test/`.

### FileExistenceScanner (fallback)
Walks `lib/` and `app/`, finds `.rb` files with no corresponding `spec/**/*_spec.rb` or `test/**/*_test.rb`. Uses AST parsing to extract all methods from those files, treating every method as untested. Returns the same method-descriptor shape as `SimpleCovScanner`. The warning notes the key limitation: this scanner cannot detect untested methods in *partially*-tested files — it only catches files with no spec at all.

Both scanners return the same data shape; the rest of the pipeline is agnostic to which ran.

---

## 5. ContextBuilder

Builds a context package for a single method descriptor. Framework-agnostic — both generator strategies consume the same shape.

```ruby
{
  target_file:    String,   # full source of the file containing the method
  dependencies:   Array,    # required files and referenced constants in the file
  example_usage:  Array,    # up to 3 call sites found elsewhere in the codebase
  related_tests:  String?   # existing spec/test file for the same class, if present
}
```

- **Dependencies**: extracted from the AST — `require`/`require_relative` calls and referenced constants that resolve to project files (not gems)
- **Example usage**: searches `lib/` and `app/` for call sites of the method name, captures surrounding lines, capped at 3 examples
- **Related tests**: checks for an existing spec/test file using the standard path convention; includes its contents so the LLM can match the project's test style

---

## 6. Generator

### Interface
```ruby
def generate(method_info, context, feedback: nil) → String
```

`feedback` carries structured error output from a failed validation — passed on retry so the LLM knows what to fix.

### RspecGenerator / MinitestGenerator
Both implement the same interface with framework-specific prompts:
- **RSpec**: `describe`/`context`/`let`/`before`, standard RSpec matchers
- **Minitest**: `test`/`setup`, Minitest assertions

Both use RubyLLM for the API call, making provider/model selection transparent.

### Output path
The generator resolves the output path (framework-specific convention), overridden by `--output-dir` if provided:
- RSpec: `spec/**/*_spec.rb` (mirroring `lib/` or `app/`)
- Minitest: `test/**/*_test.rb`

### CodeExtractor
LLM responses are processed by `CodeExtractor` rather than simple fence-stripping. It tries strategies in order:
1. Extract content from ` ```ruby...``` ` fences
2. Extract content from generic ` ```...``` ` fences
3. Use the raw response as-is

Optionally validates the extracted string is parseable Ruby using the `parser` gem. One module, one test suite, used by both generator strategies.

This pattern is modeled on `JsonExtractor` from the Jojo project (`jojo/lib/jojo/json_extractor.rb`). RubyLLM's `with_schema` structured output is not used because it fails loudly on unsupported models — `CodeExtractor` works across any model the user configures.

---

## 7. Validator

### Interface
```ruby
def validate(test_code, output_path) → { valid:, runs:, passes:, errors: [] }
```

### RspecValidator / MinitestValidator
- **RspecValidator**: runs `bundle exec rspec <path> --format documentation`, parses stdout
- **MinitestValidator**: runs `bundle exec ruby -Itest <path>`, parses stdout

Both validators:
- Write the file before running (`FileUtils.mkdir_p` ensures the directory exists)
- Distinguish load failures (syntax errors, missing constants) from assertion failures — different failure types produce different feedback for the retry loop
- Clean up the written file if the test didn't load, so broken attempts don't persist
- Return the same result shape so `Pipeline` is agnostic to which ran

### Retry feedback
- Load errors: "The following errors prevented the tests from running: ..."
- Assertion failures: "The following tests failed: ..."

---

## 8. Pipeline & Batch Processing

### Pipeline
Orchestrates a single method through generate → validate → retry:

```ruby
def run(method_info, context) → { success:, output_path:, attempts:, errors: [] }
```

Holds references to the configured generator and validator strategies. Runs up to 3 attempts, passing failure feedback to the generator on each retry. No knowledge of the filesystem beyond what it delegates to the validator.

### BatchPipeline
Processes all untested methods from the scanner:

```ruby
def run(untested_methods) → { successful: [], failed: [], skipped: [] }
```

Iterates methods, calls `ContextBuilder` then `Pipeline` for each. Catches unexpected errors as `skipped`. Sleeps `config.pause` seconds between API calls for rate limiting.

### Reporter
Formats all user-visible output to stdout. Separate from Pipeline so `scan` and `context` commands share the same reporting style without coupling to generation. Nothing outside `Reporter` calls `puts` directly.

---

## 9. Error Handling

| Stage | Error | Behavior |
|---|---|---|
| Scanner | Test suite run fails | Warn to stderr, fall back to FileExistenceScanner |
| Scanner | SimpleCov not available | Warn to stderr, fall back to FileExistenceScanner |
| ContextBuilder | File unreadable / AST parse error | Skip method, count as `skipped` |
| Generator | Auth failure | Abort run immediately with clear message |
| Generator | Rate limit error | Respect `--pause`, retry |
| Generator | Other API error | Skip method, count as `skipped` |
| Validator | Subprocess error (e.g. bundler not set up) | Skip method, clean up written file |

### Exit codes
- `0` — at least one test successfully generated
- `1` — all methods failed or were skipped
- `2` — configuration error (bad framework, missing required config)

---

## 10. Deferred Components

### TestQualityChecker
Would slot in after validation in `Pipeline#run`, returning a quality score alongside the result. `BatchPipeline` would surface low-quality results in the report. No changes to existing interfaces required.

### CI Integration
A `CITestGenerator` that scans only files changed relative to a base branch, and a GitHub review comment creator. Would be a new `testgenai ci` command consuming the same Scanner/Generator/Validator strategies without modifying them.
