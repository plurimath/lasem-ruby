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

    # String.try_convert returns nil for non-String-like input (nil/Symbol/
    # Integer), which we reject. A misbehaving #to_str (raising, or returning a
    # non-String) propagates to the caller -- a programmer error on their
    # object, not a Lasem input error, so we let it surface unmasked.
    #
    # Encoding is the caller's responsibility: XML/MathML/SVG declare their own
    # encoding and Lasem (libxml2) reads it, so we pass bytes through untouched
    # and let Lasem report bad input as a RenderError. The blank check is
    # byte-level: `.b.strip` trims ASCII whitespace and NUL without decoding
    # (so it never raises on non-UTF-8 bytes), so e.g. a BOM-only UTF-16 string
    # is still non-empty afterwards, passes through, and surfaces as a
    # RenderError.
    def normalize_source(source)
      normalized = String.try_convert(source)
      if normalized.nil? || normalized.b.strip.empty?
        raise OptionError.non_empty_source
      end

      normalized
    end
  end
end
