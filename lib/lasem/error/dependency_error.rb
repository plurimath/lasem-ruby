# frozen_string_literal: true

module Lasem
  class DependencyError < Error
    NATIVE_LIBRARY_UNAVAILABLE_MESSAGE = "Lasem native library is not " \
                                         "available. Run " \
                                         "`lasem-doctor --all-warnings` or " \
                                         "`bundle exec rake lasem:doctor " \
                                         "WARNINGS=all` for setup diagnostics."

    def self.native_library_unavailable(original_error: nil)
      message = NATIVE_LIBRARY_UNAVAILABLE_MESSAGE
      if original_error
        message = "#{message} Original load error: #{original_error.message}"
      end

      new(message)
    end
  end
end
