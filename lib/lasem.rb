# frozen_string_literal: true

require "lasem/version"
require "lasem/error"

module Lasem
  DEPENDENCY_ERROR_MESSAGE = "Lasem native library is not available. " \
                             "Build vendored Lasem with " \
                             "`bundle exec rake lasem:build` or " \
                             "install a system Lasem package."

  begin
    require "lasem/lasem"
  rescue LoadError
    module Native
      def self.native_available?
        false
      end

      def self.render(*)
        raise DependencyError, DEPENDENCY_ERROR_MESSAGE
      end
    end
  end

  require "lasem/renderer"

  def self.native_available?
    Native.native_available?
  end

  def self.render(input, input_type: :xml, format: :svg, **)
    Renderer.render(input, input_type: input_type, format: format, **)
  end

  def self.render_mathml(input, **)
    render(input, input_type: :mathml, **)
  end

  def self.render_svg(input, **)
    render(input, input_type: :svg, **)
  end

  def self.render_latex(input, **)
    render(input, input_type: :latex, **)
  end

  def self.render_itex(input, **)
    render(input, input_type: :itex, **)
  end
end
