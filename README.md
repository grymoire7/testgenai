# TestGenAI

✨ A CLI gem that adds tests for untested methods in your code ✨

![Ruby Version](https://img.shields.io/badge/Ruby-3.4.5-green?logo=Ruby&logoColor=red&label=Ruby%20version&color=green)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/grymoire7/testgenai/blob/main/LICENSE)

TestGenAI is a Ruby CLI gem for development environments that finds untested
methods in your codebase and generates tests for them using an AI service.

[!CAUTION]
TestGenAI is a work in progress and should not be used in production
environments. While is it works locally for me, it has not been tested in a
wide variety of projects yet and may have many edge cases or bugs. Use with
caution and please report any issues you encounter.


See `docs/article.md` for the concepts this is based on. The article code is
illustrative only and has never been run; this repository is the working
implementation.

## Installation

Add to your project's `Gemfile` in the development group, or install the gem directly:

```bash
gem install testgenai
```

## Setup

TestGenAI needs an LLM provider to generate tests. Configure it via environment variables or CLI flags:

| Env var                | Flag                     | Description                                         |
| ---------------------- | ------------------------ | --------------------------------------------------- |
| `TESTGENAI_PROVIDER`   | `--provider`             | LLM provider (e.g. `anthropic`, `openai`)           |
| `TESTGENAI_MODEL`      | `--model`                | Model name (e.g. `claude-opus-4-7`)                 |
| —                      | `--api-key`              | API key (overrides env var set by the provider SDK) |
| `TESTGENAI_FRAMEWORK`  | `--test-framework`, `-t` | Test framework: `rspec` (default) or `minitest`     |
| `TESTGENAI_OUTPUT_DIR` | `--output-dir`, `-o`     | Output directory for generated tests                |
| `TESTGENAI_PAUSE`      | `--pause`, `-p`          | Seconds to pause between API calls (default: 1)     |

## Commands

```
testgenai scan      Scan for untested methods and report them
testgenai context   Scan and show the LLM context that would be sent (diagnostic)
testgenai generate  Full pipeline: scan → context → generate → validate
testgenai version   Show version
testgenai help      Show help
```

### scan

Finds untested methods and prints them. No API calls are made.

```bash
bin/testgenai scan
bin/testgenai scan --test-framework minitest
```

### context

Like `scan`, but also prints the context snippet that would be sent to the LLM
for each method. Useful for inspecting what the generator will see before
running a full `generate`.

### generate

Runs the full pipeline: scan → build context → call LLM → validate generated tests → report results.

```bash
bin/testgenai generate --provider anthropic --model claude-opus-4-7
```

Generated test files are written to `spec/` (rspec) or `test/` (minitest) by
default, mirroring the source file's path under `lib/` or `app/`.

## How scanning works

TestGenAI uses one of two scanners depending on whether SimpleCov is available
in your project.

### SimpleCov scanner (accurate)

If your `Gemfile` or gemspec contains `simplecov`, TestGenAI runs your test
suite with `COVERAGE=true` to generate `coverage/.resultset.json`, then uses
that data to find methods where every executable line has zero hits.

This scanner correctly handles **partially-tested files** — it only reports
methods that were never exercised, even if other methods in the same file are
tested.

To use the SimpleCov scanner, add SimpleCov to your project and configure it to
start when `COVERAGE=true` is set:

```ruby
# Gemfile
gem "simplecov", require: false, group: [:development, :test]
```

```ruby
# spec/spec_helper.rb or test/test_helper.rb
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start
end
```

If `coverage/.resultset.json` already exists from a previous run, TestGenAI
uses it directly without re-running the test suite.

### File-existence scanner (fallback)

If SimpleCov is not detected, TestGenAI falls back to checking whether a
corresponding spec/test file exists for each source file. Any source file with
no matching test file has all its methods reported as untested.

This scanner **cannot detect untested methods in partially-tested files**. A
file tested only through integration tests or through specs for its subclasses
will appear fully untested even though its methods are exercised.

## Troubleshooting

### "SimpleCov not found in Gemfile or gemspec. Using file-existence scanner."

SimpleCov is not declared in your `Gemfile` or gemspec. The fallback scanner is
being used. See [Setup](#setup-simplecov) above to enable the accurate scanner.

### The file-existence scanner reports many false positives

Base classes, modules, and shared utilities that are only tested indirectly
(through subclass specs or integration tests) will be reported as untested by
the file-existence scanner. This is expected — it can only see whether a
matching test file exists, not whether code was actually executed. Use the
SimpleCov scanner for accurate results.

### "Coverage generation failed. Using file-existence scanner."

SimpleCov was found in the Gemfile, but running the test suite with `COVERAGE=true` did not produce `coverage/.resultset.json`. Check that:

1. SimpleCov is configured to start when `COVERAGE=true` is set (see above)
2. Your test suite runs successfully with `COVERAGE=true bundle exec rspec` (or equivalent for minitest)

### Parser warning about ruby34

```
warning: parser/current is loading parser/ruby34, which recognizes 3.4.0-dev-compliant syntax,
but you are running 3.4.5.
```

This warning comes from the `parser` gem (a dependency). It is harmless — the
parser handles Ruby 3.4.x syntax correctly. A 3.4.x release of the parser gem
is not yet available to silence it.

