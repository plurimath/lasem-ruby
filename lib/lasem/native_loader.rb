# frozen_string_literal: true

require "rbconfig"
require "rubygems"

module Lasem
  module NativeLoader
    EXTENSION_REQUIRE_PATH = "lasem/lasem"

    module_function

    def available?
      load
      !!(defined?(Native) && Native.native_available?)
    rescue DependencyError
      false
    end

    def render(*)
      load!
      unless Native.native_available?
        raise DependencyError.native_library_unavailable
      end

      Native.render(*)
    end

    def load
      load!
    rescue DependencyError
      false
    end

    def load!
      return true if defined?(Native)

      raise DependencyError.native_library_unavailable unless extension_path

      require EXTENSION_REQUIRE_PATH
      true
    rescue LoadError => e
      raise DependencyError.native_library_unavailable(original_error: e)
    end

    def extension_path
      gem_extension_path || load_path_extension_path
    end

    def gem_extension_path
      Gem.find_files(File.join("lasem", extension_filename)).find do |path|
        File.file?(path)
      end
    end

    def load_path_extension_path
      $LOAD_PATH
        .map { |path| File.join(path, "lasem", extension_filename) }
        .find { |path| File.file?(path) }
    end

    def extension_filename
      @extension_filename ||= "lasem.#{RbConfig::CONFIG.fetch('DLEXT')}"
    end
  end
end
