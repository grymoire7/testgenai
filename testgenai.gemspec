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

  spec.files = Dir["lib/**/*.rb", "bin/**/*", "*.md", "*.gemspec", "Gemfile"].reject { |f| f.match?(/\A(CLAUDE|AGENTS)\.md\z/) }
  spec.bindir = "bin"
  spec.executables = ["testgenai"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "ruby_llm", "~> 1.14"
  spec.add_dependency "parser", "~> 3.3"
end
