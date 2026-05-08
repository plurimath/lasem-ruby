# frozen_string_literal: true

module Lasem
  autoload :Error, "lasem/error"
  autoload :VERSION, "lasem/version"
  autoload :DependencyError, "lasem/error/dependency_error"
  autoload :OptionError, "lasem/error/option_error"
  autoload :RenderError, "lasem/error/render_error"
  autoload :Renderer, "lasem/renderer"
  autoload :NativeLoader, "lasem/native_loader"
  autoload :RenderOptions, "lasem/render_options"
  autoload :DependencyDoctor, "lasem/dependency_doctor"

  def self.native_available?
    NativeLoader.available?
  end

  def self.render(input, input_type: :xml, output_format: :svg, **)
    Renderer.render(
      input,
      input_type: input_type,
      output_format: output_format,
      **,
    )
  end
end
