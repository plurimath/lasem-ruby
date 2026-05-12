# frozen_string_literal: true

require_relative "lib/lasem/version"

Gem::Specification.new do |spec|
  spec.name = "lasem"
  spec.version = Lasem::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Ruby bindings for the Lasem SVG and MathML renderer."
  spec.description = "Provides a native Ruby extension for rendering " \
                     "MathML, SVG, and Lasem-supported TeX input through " \
                     "the Lasem C library."
  spec.homepage = "https://github.com/plurimath/lasem-ruby"
  spec.license = "BSD-2-Clause"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")

  spec.metadata = {
    "rubygems_mfa_required" => "true",
    "source_code_uri" => spec.homepage,
  }

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads files that have been added to git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{^(test|spec|features|vendor)/})
    end
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.extensions    = ["ext/lasem/extconf.rb"]
  spec.require_paths = ["lib"]
end
