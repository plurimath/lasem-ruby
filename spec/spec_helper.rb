# frozen_string_literal: true

unless ENV["NO_COVERAGE"]
  begin
    require "simplecov"
    SimpleCov.start do
      add_filter "/spec/"
    end
  rescue LoadError
    # Coverage is optional for minimal bootstrap environments.
  end
end

require "bundler/setup"
require "lasem"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end
