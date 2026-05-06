# frozen_string_literal: true

require "mkmf"
require "fileutils"
require "shellwords"

ROOT = File.expand_path("../..", __dir__)
VENDORED_INSTALL_DIR = File.expand_path(
  ENV.fetch("LASEM_INSTALL_DIR", "vendor/lasem/install"),
  ROOT,
)
VENDORED_SOURCE_DIR = File.expand_path(
  ENV.fetch("LASEM_SOURCE_DIR", "vendor/lasem/source"),
  ROOT,
)
VENDORED_BUILD_DIR = File.expand_path(
  ENV.fetch("LASEM_BUILD_DIR", "vendor/lasem/build"),
  ROOT,
)
VENDORED_MESON_OPTIONS = %w[
  --buildtype=release
  -Ddocumentation=disabled
  -Dintrospection=disabled
  -Dviewer=disabled
].freeze

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

def meson_setup_command
  command = ["meson", "setup"]
  build_file = File.join(VENDORED_BUILD_DIR, "build.ninja")
  command << "--reconfigure" if File.exist?(build_file)
  command
end

def run_vendored_lasem_build
  system(
    *meson_setup_command,
    VENDORED_BUILD_DIR,
    VENDORED_SOURCE_DIR,
    "--prefix=#{VENDORED_INSTALL_DIR}",
    "--libdir=lib",
    *VENDORED_MESON_OPTIONS,
  ) &&
    system("meson", "compile", "-C", VENDORED_BUILD_DIR) &&
    system("meson", "install", "-C", VENDORED_BUILD_DIR)
end

def build_vendored_lasem
  return false unless File.exist?(File.join(VENDORED_SOURCE_DIR, "meson.build"))

  unless find_executable("meson")
    warn "Vendored Lasem source exists, but Meson was not found."
    return false
  end

  FileUtils.mkdir_p(VENDORED_BUILD_DIR)
  run_vendored_lasem_build
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

if lasem_package.nil? && build_vendored_lasem
  add_pkg_config_path(File.join(VENDORED_INSTALL_DIR, "lib", "pkgconfig"))
  add_pkg_config_path(File.join(VENDORED_INSTALL_DIR, "lib64", "pkgconfig"))
  lasem_package = find_lasem_package(pkg_config_candidates)
end

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
  $objs = ["lasem_ext.o"]
  warn "Building lasem-ruby against #{lasem_package}."
else
  $srcs = ["lasem_stub.c"]
  $objs = ["lasem_stub.o"]
  warn "Lasem was not found; building a stub extension."
  warn "Run `bundle exec rake lasem:build` or install a system " \
       "Lasem development package, then rebuild."
end

create_makefile("lasem/lasem")
