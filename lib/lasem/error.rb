# frozen_string_literal: true

module Lasem
  # Mixed into every error this gem raises so callers can rescue all
  # Lasem-originated failures with a single `rescue Lasem::Error`, regardless of
  # each error's concrete superclass. In particular OptionError remains an
  # ArgumentError (so `rescue ArgumentError` keeps working) while still being a
  # Lasem::Error.
  module Error
  end
end
