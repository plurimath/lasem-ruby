# frozen_string_literal: true

require "mkmf"
require "shellwords"

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

pkg_config_candidates =
  if ENV["LASEM_PKG_CONFIG"] && !ENV["LASEM_PKG_CONFIG"].empty?
    [ENV["LASEM_PKG_CONFIG"]]
  else
    %w[lasem-0.6 lasem lasem-0.4]
  end

lasem_package = find_lasem_package(pkg_config_candidates)

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
