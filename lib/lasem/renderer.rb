# frozen_string_literal: true

module Lasem
  class Renderer
    def self.render(input, **options)
      new(input, options).render
    end

    def initialize(input, options = {})
      @input = String(input)
      @options = RenderOptions.new(options)
    end

    def render
      NativeLoader.render(*@options.native_arguments(@input))
    end
  end
end
