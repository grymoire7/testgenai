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
