---
title: SimpleCov Integration
date: 2026-04-28
status: approved
---

# SimpleCov Integration

## Problem

Running `bin/testgenai scan` in the testgenai repo itself produces a warning and falls back to the file-existence scanner because SimpleCov is not declared in the Gemfile. The file-existence scanner cannot detect untested methods in partially-tested files, making `scan` less useful for self-hosting.

## Solution

Add SimpleCov as a development dependency and configure it to run when the `COVERAGE=true` env var is set. The CLI already sets this env var when it triggers the test suite, so no changes to `cli.rb` are needed.

## Changes

### Gemfile
Add to the existing `:development, :test` group:
```ruby
gem "simplecov", require: false
```

### spec/spec_helper.rb
Add at the top, before `require "testgenai"`:
```ruby
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start
end
```

### Shell
Run `bundle install` to lock the new gem.

## Flow

1. `bin/testgenai scan` finds no `coverage/.resultset.json`
2. `simplecov_in_gemfile?` finds "simplecov" in the Gemfile — returns true
3. CLI runs `bundle exec rspec` with `COVERAGE=true`
4. SimpleCov writes `coverage/.resultset.json`
5. `SimplecovScanner` is used for accurate method-level coverage analysis

## Decision: COVERAGE guard

SimpleCov only starts when `COVERAGE=true` is set. This keeps normal `bundle exec rspec` runs fast during TDD and avoids writing coverage artifacts on every test run.
