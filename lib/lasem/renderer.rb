# frozen_string_literal: true

module Lasem
  class Renderer
    INPUT_TYPES = %w[xml mathml svg latex itex].freeze
    ITEX_INPUT_TYPES = %w[latex itex].freeze
    ITEX_DELIMITER_PAIRS = [
      ["$$", "$$"],
      ["$", "$"],
      ["\\(", "\\)"],
      ["\\[", "\\]"],
    ].freeze
    OUTPUT_FORMATS = %w[svg png pdf ps].freeze
    DEFAULT_PPI = 72.0
    DEFAULT_ZOOM = 1.0
    DEFAULT_OPTIONS = {
      input_type: :xml,
      format: :svg,
      ppi: DEFAULT_PPI,
      zoom: DEFAULT_ZOOM,
      width: nil,
      height: nil,
      offset_x: 0.0,
      offset_y: 0.0,
    }.freeze

    def self.render(input, **options)
      new(input, options).render
    end

    def initialize(input, options = {})
      options = DEFAULT_OPTIONS.merge(options)

      normalize_options(options)
      @input = normalize_input(String(input))
      validate_size_pair
    end

    def render
      Native.render(
        @input, @input_type, @format, @ppi, @zoom,
        @width, @height, @offset_x, @offset_y
      )
    end

    private

    def normalize_options(options)
      normalize_format_options(options)
      normalize_dimension_options(options)
      normalize_position_options(options)
    end

    def normalize_input(input)
      return input unless ITEX_INPUT_TYPES.include?(@input_type)

      stripped_input = input.strip
      return input if itex_delimited?(stripped_input)

      "$#{stripped_input}$"
    end

    def itex_delimited?(input)
      ITEX_DELIMITER_PAIRS.any? do |opening, closing|
        input.start_with?(opening) &&
          input.end_with?(closing) &&
          input.length > opening.length + closing.length
      end
    end

    def normalize_format_options(options)
      @input_type = choice(
        options.fetch(:input_type),
        INPUT_TYPES,
        "input_type",
      )
      @format = choice(options.fetch(:format), OUTPUT_FORMATS, "format")
    end

    def normalize_dimension_options(options)
      @ppi = positive_float(options.fetch(:ppi), "ppi")
      @zoom = positive_float(options.fetch(:zoom), "zoom")
      @width = optional_positive_float(options.fetch(:width), "width")
      @height = optional_positive_float(options.fetch(:height), "height")
    end

    def normalize_position_options(options)
      @offset_x = numeric(options.fetch(:offset_x), "offset_x")
      @offset_y = numeric(options.fetch(:offset_y), "offset_y")
    end

    def choice(value, allowed_values, name)
      normalized = value.to_s
      return normalized if allowed_values.include?(normalized)

      raise ArgumentError,
            "#{name} must be one of: #{allowed_values.join(', ')}"
    end

    def numeric(value, name)
      Float(value)
    rescue ArgumentError, TypeError
      raise ArgumentError, "#{name} must be numeric"
    end

    def positive_float(value, name)
      number = numeric(value, name)
      return number if number.positive? && number.finite?

      raise ArgumentError, "#{name} must be greater than 0"
    end

    def optional_positive_float(value, name)
      return nil if value.nil?

      positive_float(value, name)
    end

    def validate_size_pair
      return if @width.nil? && @height.nil?
      return unless @width.nil? || @height.nil?

      raise ArgumentError, "width and height must be provided together"
    end
  end
end
