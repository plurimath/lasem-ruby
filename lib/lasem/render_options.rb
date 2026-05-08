# frozen_string_literal: true

module Lasem
  class RenderOptions
    INPUT_TYPES = %w[xml mathml svg latex itex].freeze
    OUTPUT_FORMATS = %w[svg png pdf ps].freeze
    DEFAULT_OPTIONS = {
      input_type: :xml,
      output_format: :svg,
      ppi: 72.0,
      zoom: 1.0,
      width: nil,
      height: nil,
      offset_x: 0.0,
      offset_y: 0.0,
    }.freeze

    attr_reader :input_type, :output_format, :ppi, :zoom, :width, :height,
                :offset_x, :offset_y

    def initialize(options = {})
      validate_option_names(options)
      options = DEFAULT_OPTIONS.merge(options)

      normalize_format_options(options)
      normalize_dimension_options(options)
      normalize_position_options(options)
      validate_size_pair
    end

    def native_arguments(input)
      [
        input,
        input_type,
        output_format,
        ppi,
        zoom,
        width,
        height,
        offset_x,
        offset_y,
      ]
    end

    private

    def validate_option_names(options)
      unknown_names = options.keys - DEFAULT_OPTIONS.keys
      return if unknown_names.empty?

      raise OptionError.unknown_options(names: unknown_names)
    end

    def normalize_format_options(options)
      @input_type = choice(
        options.fetch(:input_type),
        INPUT_TYPES,
        "input_type",
      )
      @output_format = choice(
        options.fetch(:output_format),
        OUTPUT_FORMATS,
        "output_format",
      )
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

      raise OptionError.invalid_choice(
        name: name,
        allowed_values: allowed_values,
      )
    end

    def numeric(value, name)
      Float(value)
    rescue ArgumentError, TypeError
      raise OptionError.not_numeric(name: name)
    end

    def positive_float(value, name)
      number = numeric(value, name)
      return number if number.positive? && number.finite?

      raise OptionError.not_positive(name: name)
    end

    def optional_positive_float(value, name)
      return nil if value.nil?

      positive_float(value, name)
    end

    def validate_size_pair
      return if width.nil? && height.nil?
      return unless width.nil? || height.nil?

      raise OptionError.incomplete_size_pair
    end
  end
end
