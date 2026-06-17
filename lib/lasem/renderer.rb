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

    # String.try_convert returns nil for anything that is not String-like
    # (so nil/Symbol/Integer are rejected cleanly) and raises TypeError only
    # when a #to_str is present but misbehaves -- which we deliberately let
    # surface rather than masking it as an empty-source error.
    def normalize_source(source)
      normalized = String.try_convert(source)
      raise OptionError.non_empty_source if normalized.nil?

      # Transcode before the emptiness check: String#strip raises on
      # ASCII-incompatible encodings (e.g. UTF-16).
      normalized = normalize_encoding(normalized)
      raise OptionError.non_empty_source if normalized.strip.empty?

      normalized
    end

    # Lasem's parsers read UTF-8 bytes; transcode text in another encoding so
    # callers passing e.g. UTF-16 source do not feed mis-decoded bytes to the
    # parser. Binary/UTF-8 strings are passed through unchanged.
    def normalize_encoding(source)
      return source if [Encoding::UTF_8, Encoding::BINARY].include?(source.encoding)

      source.encode(Encoding::UTF_8)
    end
  end
end
