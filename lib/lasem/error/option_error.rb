# frozen_string_literal: true

module Lasem
  class OptionError < Error
    def self.invalid_choice(name:, allowed_values:)
      new("#{name} must be one of: #{allowed_values.join(', ')}")
    end

    def self.not_numeric(name:)
      new("#{name} must be numeric")
    end

    def self.not_positive(name:)
      new("#{name} must be greater than 0")
    end

    def self.incomplete_size_pair
      new("width and height must be provided together")
    end

    def self.unknown_options(names:)
      new("unknown option(s): #{names.join(', ')}")
    end
  end
end
