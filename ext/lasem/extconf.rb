# frozen_string_literal: true

require "mkmf"
require "shellwords"
require_relative "../../lib/lasem/pkg_config"

ROOT = File.expand_path("../..", __dir__)
VENDORED_INSTALL_DIR = File.expand_path(
  ENV.fetch("LASEM_INSTALL_DIR", "vendor/lasem/install"),
  ROOT,
)

def add_pkg_config_path(path)
  return unless Dir.exist?(path)

  paths = ENV.fetch("PKG_CONFIG_PATH", "").split(File::PATH_SEPARATOR)
  paths.unshift(path)
  ENV["PKG_CONFIG_PATH"] = paths.uniq.join(File::PATH_SEPARATOR)
end

def add_runtime_library_path(path)
  return unless Dir.exist?(path)

  $DLDFLAGS << " -Wl,-rpath,#{Shellwords.escape(path)}"
end

def find_lasem_package(candidates)
  candidates.find { |candidate| pkg_config(candidate) }
end

add_pkg_config_path(File.join(VENDORED_INSTALL_DIR, "lib", "pkgconfig"))
add_pkg_config_path(File.join(VENDORED_INSTALL_DIR, "lib64", "pkgconfig"))

lasem_package = find_lasem_package(Lasem::PkgConfig.candidates)

required_headers = %w[
  lsm.h
  lsmdomparser.h
  lsmmathmldocument.h
  cairo-svg.h
  cairo-pdf.h
  cairo-ps.h
]
has_lasem_headers = lasem_package && required_headers.all? do |header|
  have_header(header)
end

if has_lasem_headers
  add_runtime_library_path(File.join(VENDORED_INSTALL_DIR, "lib"))
  add_runtime_library_path(File.join(VENDORED_INSTALL_DIR, "lib64"))

  # Embed the resolved package's own libdir as a runtime path too, so a system
  # Lasem installed under a non-default prefix (Homebrew/mise/Nix) loads without
  # the user having to set LD_LIBRARY_PATH. Use mkmf's pkg_config so the same
  # pkg-config tool that resolved the package supplies the libdir.
  # add_runtime_library_path skips missing/standard dirs, so this is a no-op for
  # /usr-style installs.
  lasem_libdir = pkg_config(lasem_package, "variable=libdir")&.strip
  add_runtime_library_path(lasem_libdir) if lasem_libdir && !lasem_libdir.empty?

  $defs << "-DHAVE_LASEM"
  $srcs = ["lasem_ext.c"]
  warn "Building lasem against #{lasem_package}."
else
  $srcs = ["lasem_stub.c"]
  warn "Lasem was not found; building a stub extension."
  warn "Install a system Lasem development package, then rebuild the gem."
  warn "Run `lasem-doctor` for setup guidance after installation."
end

create_makefile("lasem/lasem")
