# frozen_string_literal: true

module Lasem
  # Single source of truth for how Lasem is located via pkg-config. Required by
  # both the native build (ext/lasem/extconf.rb) and the dependency doctor so
  # the two never drift on the candidate package names or the override env var.
  module PkgConfig
    # Candidate pkg-config package names, in preference order.
    CANDIDATES = %w[lasem-0.6 lasem lasem-0.4].freeze

    # Pkg-config names to probe, honoring the LASEM_PKG_CONFIG override.
    def self.candidates(env: ENV)
      override = env["LASEM_PKG_CONFIG"]
      return [override] if override && !override.empty?

      CANDIDATES
    end
  end
end
