# frozen_string_literal: true

require "fileutils"
require_relative "../lib/lasem/dependency_doctor"

LASEM_RAKE_ROOT = File.expand_path("..", __dir__)
LASEM_MESON_OPTIONS = %w[
  --buildtype=release
  -Ddocumentation=disabled
  -Dintrospection=disabled
  -Dviewer=disabled
].freeze
LASEM_BUILD_EXECUTABLES = %w[
  meson
  pkg-config
  bison
  flex
  msgfmt
].freeze

def lasem_rake_path(env_name, default)
  File.expand_path(ENV.fetch(env_name, default), LASEM_RAKE_ROOT)
end

def lasem_executable?(name)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |path|
    executable = File.join(path, name)
    File.executable?(executable) && !File.directory?(executable)
  end
end

def lasem_ninja?
  lasem_executable?("ninja") || lasem_executable?("ninja-build")
end

def lasem_missing_executables
  missing = LASEM_BUILD_EXECUTABLES.reject do |executable|
    lasem_executable?(executable)
  end
  missing << "ninja or ninja-build" unless lasem_ninja?
  missing
end

def lasem_require_build_tools!
  missing = lasem_missing_executables
  return if missing.empty?

  abort("Missing Lasem build tools: #{missing.join(', ')}")
end

def lasem_doctor_args
  case ENV.fetch("WARNINGS", nil)
  when "all"
    ["--all-warnings"]
  when "lasem"
    ["--lasem-conflict-warnings"]
  when "deps", "dependencies"
    ["--dep-conflict-warnings"]
  else
    []
  end
end

def lasem_setup_command(build_dir)
  command = ["meson", "setup"]
  command << "--reconfigure" if File.exist?(File.join(build_dir, "build.ninja"))
  command
end

# rubocop:disable Metrics/BlockLength
namespace :lasem do
  source_dir = lasem_rake_path("LASEM_SOURCE_DIR", "vendor/lasem/source")
  build_dir = lasem_rake_path("LASEM_BUILD_DIR", "vendor/lasem/build")
  install_dir = lasem_rake_path("LASEM_INSTALL_DIR", "vendor/lasem/install")

  desc "Configure vendored Lasem with Meson"
  task :configure do
    lasem_require_build_tools!

    meson_file = File.join(source_dir, "meson.build")
    unless File.exist?(meson_file)
      abort(
        "Lasem source not found at #{source_dir}. Put upstream Lasem there.",
      )
    end

    FileUtils.mkdir_p(build_dir)
    sh(
      *lasem_setup_command(build_dir),
      build_dir,
      source_dir,
      "--prefix=#{install_dir}",
      "--libdir=lib",
      *LASEM_MESON_OPTIONS,
    )
  end

  desc "Compile vendored Lasem"
  task compile: :configure do
    sh("meson", "compile", "-C", build_dir)
  end

  desc "Install vendored Lasem into vendor/lasem/install"
  task install: :compile do
    sh("meson", "install", "-C", build_dir)
  end

  desc "Build and install vendored Lasem"
  task build: :install

  desc "Check vendored Lasem build tool availability"
  task :doctor do
    status = Lasem::DependencyDoctor::CLI.call(lasem_doctor_args)
    next if status.zero?

    abort("Lasem dependency doctor found missing required dependencies.")
  end
end
# rubocop:enable Metrics/BlockLength
