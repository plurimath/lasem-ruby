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

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z --recurse-submodules`.split("\x0")
      .grep(%r{
        \A(?:
          LICENSE\.txt
          | README\.adoc
          | lasem\.gemspec
          | exe/[^/]+
          | ext/lasem/[^/]+\.(?:c|rb)
          | lib/.+\.rb
          | vendor/lasem/source/
            (?:
              COPYING
              | NEWS\.md
              | README\.md
              | TODO
              | lasem\.doap
              | lasem\.svg
              | meson\.build
              | meson_options\.txt
              | org\.lasem\.Viewer\.json
              | (?:itex2mml|po|src|subprojects|tests|viewer)/[^./][^/]*
            )
        )\z
      }x)
      .sort
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.extensions = ["ext/lasem/extconf.rb"]
  spec.require_paths = ["lib"]
end
