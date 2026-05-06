# frozen_string_literal: true

require_relative "lib/lasem/version"

Gem::Specification.new do |spec|
  spec.name          = "lasem"
  spec.version       = Lasem::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Ruby bindings for the Lasem SVG and MathML renderer."
  spec.description   = "Provides a native Ruby extension for rendering " \
                       "MathML, SVG, and Lasem-supported TeX input through " \
                       "the Lasem C library."
  spec.homepage      = "https://github.com/plurimath/lasem-ruby"
  spec.license       = "BSD-2-Clause"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")

  spec.metadata["source_code_uri"] = "https://github.com/plurimath/lasem-ruby"
  spec.metadata["rubygems_mfa_required"] = "true"

  excluded_files = %r{
    \A(?:spec|features)/
    |
    \Avendor/lasem/source/(?:\.github|docs|tests/data|tools)/
  }x
  tracked_files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z --recurse-submodules`.split("\x0")
  end
  spec.files = if tracked_files.empty?
                 Dir[
                   "LICENSE.txt",
                   "README.adoc",
                   "Rakefile",
                   "Gemfile",
                   "lasem.gemspec",
                   ".gitmodules",
                   "exe/*",
                   "lib/**/*.rb",
                   "ext/**/*.{c,rb}",
                   "rakelib/**/*.rake",
                   "vendor/lasem/source/{COPYING,NEWS.md,README.md,TODO}",
                   "vendor/lasem/source/meson.build",
                   "vendor/lasem/source/meson_options.txt",
                   "vendor/lasem/source/itex2mml/**/*",
                   "vendor/lasem/source/po/**/*",
                   "vendor/lasem/source/src/**/*",
                   "vendor/lasem/source/tests/*",
                   "vendor/lasem/source/viewer/**/*",
                 ]
               else
                 tracked_files.grep_v(excluded_files)
               end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.extensions    = ["ext/lasem/extconf.rb"]
  spec.require_paths = ["lib"]
end
