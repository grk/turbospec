require_relative "lib/turbospec/version"

Gem::Specification.new do |spec|
  spec.name          = "turbospec"
  spec.version       = Turbospec::VERSION
  spec.authors       = ["Grzegorz Kołodziejczyk"]
  spec.email         = ["gkolodziejczyk@hey.com"]

  spec.summary       = "A fast, pull-based parallel testing tool for RSpec."
  spec.description   = "Splits by example and distributes work to parallel workers using a pull model."
  spec.homepage      = "https://github.com/grk/turbospec"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0.0")

  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE.txt"]
  spec.bindir = "exe"
  spec.executables = ["turbospec"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rspec-core", ">= 3.0"
  spec.add_development_dependency "rspec"
end
