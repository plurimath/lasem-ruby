# frozen_string_literal: true

require_relative "../error"

module Lasem
  class OptionError < ArgumentError
    include Error

    def self.unknown_options(names:)
      new("unknown option(s): #{names.join(', ')}")
    end

    def self.non_empty_source
      new("source must be a non-empty string")
    end

    def self.invalid_choice(name:, allowed_values:)
      new("#{name} must be one of: #{allowed_values.join(', ')}")
    end

    def self.not_numeric(name:)
      new("#{name} must be numeric")
    end

    def self.not_finite(name:)
      new("#{name} must be finite")
    end

    def self.not_positive(name:)
      new("#{name} must be greater than 0")
    end

    def self.incomplete_size_pair
      new("width and height must be provided together")
    end
  end
end
