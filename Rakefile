# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/extensiontask"
require "rspec/core/rake_task"

spec = Gem::Specification.load("lasem.gemspec")

Rake::ExtensionTask.new("lasem", spec) do |ext|
  ext.lib_dir = "lib/lasem"
end

Dir.glob("rakelib/*.rake").each { |task| import task }

RSpec::Core::RakeTask.new(:spec)

task default: %i[compile spec]
