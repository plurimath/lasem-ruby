# frozen_string_literal: true

require_relative "lib/lasem/version"

Gem::Specification.new do |spec|
  spec.name          = "lasem-ruby"
  spec.version       = Lasem::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Ruby bindings for the Lasem SVG and MathML renderer."
  spec.description   = "Ruby bindings for the Lasem SVG and MathML renderer."
  spec.homepage      = "https://github.com/plurimath/lasem-ruby"
  spec.license       = "BSD-2-Clause"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/plurimath/lasem-ruby"
  spec.metadata["rubygems_mfa_required"] = "true"

  tracked_files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0")
  end
  spec.files = if tracked_files.empty?
                 Dir[
                   "LICENSE.txt",
                   "README.adoc",
                   "Rakefile",
                   "Gemfile",
                   "lasem-ruby.gemspec",
                   "lib/**/*.rb",
                 ]
               else
                 tracked_files
               end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
