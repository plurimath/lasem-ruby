# frozen_string_literal: true

module Lasem
  class Renderer
    def self.render(source, **options)
      new(source, options).render
    end

    def initialize(source, options = {})
      @source = normalize_source(source)
      @options = RenderOptions.new(options)
    end

    def render
      NativeLoader.render(*@options.native_arguments(@source))
    end

    private

    def normalize_source(source)
      normalized = source.to_str
      raise OptionError.non_empty_source if normalized.strip.empty?

      normalized
    rescue NoMethodError
      raise OptionError.non_empty_source
    end
  end
end
