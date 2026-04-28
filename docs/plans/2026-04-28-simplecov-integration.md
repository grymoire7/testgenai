# SimpleCov Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SimpleCov as a development dependency so `bin/testgenai scan` uses accurate coverage-based scanning in its own repo.

**Architecture:** Add SimpleCov to the Gemfile dev/test group and configure it to start only when `COVERAGE=true` is set. The CLI already sets this env var when triggering the test suite, so no changes to `cli.rb` are needed.

**Tech Stack:** SimpleCov gem, RSpec spec_helper.rb

---

## File Map

- Modify: `Gemfile` — add `simplecov` to `:development, :test` group
- Modify: `spec/spec_helper.rb` — start SimpleCov when `COVERAGE=true`
- Modify: `spec/testgenai/cli_spec.rb` — add missing happy-path test for scanner startup
- Shell: `bundle install`

---

### Task 1: Add happy-path scanner test

The existing `cli_spec.rb` tests the fallback paths but is missing the case where SimpleCov is in the Gemfile and the coverage run succeeds — the `SimplecovScanner` should be returned.

**Files:**
- Modify: `spec/testgenai/cli_spec.rb`

- [ ] **Step 1: Write the failing test**

Add inside the `"scanner startup sequence"` describe block, after the existing `"when simplecov is in Gemfile but coverage run fails"` context (around line 52):

```ruby
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
```

- [ ] **Step 2: Run the test to verify it fails or passes**

Run: `bundle exec rspec spec/testgenai/cli_spec.rb --format documentation`

Expected: the new example passes (the code path already exists in `cli.rb`) and all other examples pass. If any example fails, investigate before continuing.

- [ ] **Step 3: Commit**

```bash
git add spec/testgenai/cli_spec.rb
git commit -m "test: add happy-path test for SimplecovScanner selection"
```

---

### Task 2: Add SimpleCov to Gemfile

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Write a test that verifies simplecov is detectable in the project Gemfile**

This is a lightweight sanity check. Add to `spec/testgenai/cli_spec.rb` inside the `"scanner startup sequence"` describe block:

```ruby
context "when run in the testgenai repo itself" do
  it "finds simplecov in the project Gemfile" do
    cli_instance = described_class.new
    expect(cli_instance.send(:simplecov_in_gemfile?)).to be true
  end
end
```

Run: `bundle exec rspec spec/testgenai/cli_spec.rb -e "finds simplecov in the project Gemfile"`

Expected: FAIL — `simplecov` is not yet in the Gemfile.

- [ ] **Step 2: Add simplecov to Gemfile**

Open `Gemfile` and add to the `:development, :test` group:

```ruby
group :development, :test do
  gem "rspec", "~> 3.13"
  gem "standard", "~> 1.40"
  gem "minitest"
  gem "simplecov", require: false
end
```

- [ ] **Step 3: Run bundle install**

```bash
bundle install
```

Expected output includes: `Installing simplecov` (or `Using simplecov` if already cached). Gemfile.lock is updated.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/testgenai/cli_spec.rb -e "finds simplecov in the project Gemfile"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add simplecov to development dependencies"
```

---

### Task 3: Configure SimpleCov in spec_helper.rb

**Files:**
- Modify: `spec/spec_helper.rb`

- [ ] **Step 1: Add SimpleCov configuration**

Open `spec/spec_helper.rb`. Add the following **before** `require "testgenai"`:

```ruby
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start
end
```

The full file should look like:

```ruby
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start
end

require "bundler/setup"
require "tmpdir"
require "fileutils"
require "testgenai"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.order = :random
end
```

- [ ] **Step 2: Verify coverage data is generated**

Run the test suite with `COVERAGE=true`:

```bash
COVERAGE=true bundle exec rspec
```

Expected: all tests pass and `coverage/.resultset.json` is created:

```bash
ls coverage/.resultset.json
```

Expected: file exists.

- [ ] **Step 3: Clean up coverage artifact**

```bash
rm -rf coverage/
```

- [ ] **Step 4: Commit**

```bash
git add spec/spec_helper.rb
git commit -m "chore: configure simplecov in spec_helper for COVERAGE=true runs"
```

---

### Task 4: End-to-end verification

- [ ] **Step 1: Run the full test suite**

```bash
bundle exec rspec
```

Expected: all examples pass, no coverage artifacts created (COVERAGE not set).

- [ ] **Step 2: Run scan and verify no warning**

```bash
bin/testgenai scan
```

Expected output: no "SimpleCov not found" warning. The CLI runs `bundle exec rspec` with `COVERAGE=true`, generates coverage data, and uses `SimplecovScanner`. Output will list any untested methods found in the `lib/` directory.

- [ ] **Step 3: Clean up coverage artifacts**

```bash
rm -rf coverage/
```

- [ ] **Step 4: Commit the plan doc**

```bash
git add docs/plans/2026-04-28-simplecov-integration.md
git commit -m "docs: add SimpleCov integration implementation plan"
```
