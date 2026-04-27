# TestGenAI

TestGenAI is a development environment Ruby CLI gem that finds and generates
missing tests for your Ruby codebase.

It is based on the article here: `./docs/article.md` and the code in this
repository is a reference implementation of the ideas presented in that
article.  Note that the code in the article has never been run or testied
and is only meant to illustrate the concepts.

## Usage

To use TestGenAI, you can run the following command in your terminal:

```pre
Usage: testgenai [options] [command]

Options:
    -h, --help                       Show this help message
    -v, --version                    Show version information
    -o, --output-dir DIR             Specify the output directory for generated tests
                                     (default for rspec is `spec/` and for minitest is `test/`)
    -t, --test-framework FRAMEWORK   Specify the test framework to use (default: rspec)

Commands:
    scan                             Scan the codebase for untested code and report it
    context                          Scan and build context for untested code and report it
    generate                         Generate tests for untested code - all steps


```

### All steps

1. Scan your codebase to find classes and methods without test coverage
2. Build context for each piece of untested code
3. Generate tests using AI service
4. Validate that the generated tests run and pass
5. Collect the results into reviewable pull requests

