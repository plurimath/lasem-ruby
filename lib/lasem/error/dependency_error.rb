# frozen_string_literal: true

require_relative "../error"

module Lasem
  class DependencyError < StandardError
    include Error

    MESSAGE = "Lasem native library is not available. Install a system " \
              "Lasem development package, then rebuild the gem. Run " \
              "`lasem-doctor --all-warnings` or `bundle exec rake " \
              "lasem:doctor WARNINGS=all` for setup diagnostics."

    def self.native_library_unavailable(original_error: nil)
      message = MESSAGE
      if original_error
        message = "#{message} Original load error: #{original_error.message}"
      end

      new(message)
    end

    def self.unavailable(original_error: nil)
      native_library_unavailable(original_error: original_error)
    end
  end
end
