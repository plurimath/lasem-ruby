# frozen_string_literal: true

require "rbconfig"
require "rubygems"

module Lasem
  class DependencyDoctor
    autoload :CLI, "lasem/dependency_doctor/cli"
    autoload :Probe, "lasem/dependency_doctor/probe"
    autoload :Report, "lasem/dependency_doctor/report"

    ROOT = File.expand_path("../..", __dir__)

    ExecutableDependency = Struct.new(:name, :executables, keyword_init: true)
    PkgConfigDependency = Struct.new(:name, :requirement, keyword_init: true)
    OutdatedPackage = Struct.new(:dependency, :version, keyword_init: true)

    EXECUTABLE_DEPENDENCIES = [
      ExecutableDependency.new(
        name: "C compiler (cc, gcc, or clang)",
        executables: %w[cc gcc clang],
      ),
      ExecutableDependency.new(name: "make", executables: %w[make]),
      ExecutableDependency.new(name: "pkg-config", executables: %w[pkg-config]),
      ExecutableDependency.new(name: "meson", executables: %w[meson]),
      ExecutableDependency.new(
        name: "ninja or ninja-build",
        executables: %w[ninja ninja-build],
      ),
      ExecutableDependency.new(name: "bison", executables: %w[bison]),
      ExecutableDependency.new(name: "flex", executables: %w[flex]),
      ExecutableDependency.new(name: "msgfmt", executables: %w[msgfmt]),
    ].freeze

    PKG_CONFIG_DEPENDENCIES = [
      PkgConfigDependency.new(name: "glib-2.0", requirement: ">= 2.36"),
      PkgConfigDependency.new(name: "gobject-2.0"),
      PkgConfigDependency.new(name: "gio-2.0"),
      PkgConfigDependency.new(name: "gdk-pixbuf-2.0"),
      PkgConfigDependency.new(name: "cairo", requirement: ">= 1.2"),
      PkgConfigDependency.new(name: "pangocairo", requirement: ">= 1.16.0"),
      PkgConfigDependency.new(name: "libxml-2.0"),
    ].freeze

    def initialize(root: ROOT, probe: Probe.new)
      @root = root
      @probe = probe
    end

    def report(lasem_conflict_warnings: false, dep_conflict_warnings: false)
      Report.new(
        missing_executables: missing_executables,
        missing_pkg_config: missing_pkg_config,
        outdated_pkg_config: outdated_pkg_config,
        lasem_warnings: lasem_warnings(lasem_conflict_warnings),
        dependency_warnings: dependency_warnings(dep_conflict_warnings),
      )
    end

    private

    attr_reader :root, :probe

    def missing_executables
      EXECUTABLE_DEPENDENCIES.reject do |dependency|
        dependency.executables.any? do |executable|
          probe.executable?(executable)
        end
      end
    end

    def pkg_config_versions
      @pkg_config_versions ||= PKG_CONFIG_DEPENDENCIES.to_h do |dependency|
        [dependency, probe.pkg_config_version(dependency.name)]
      end
    end

    def missing_pkg_config
      pkg_config_versions.filter_map do |dependency, version|
        dependency if version.nil?
      end
    end

    def outdated_pkg_config
      pkg_config_versions.filter_map do |dependency, version|
        next if version.nil? || dependency.requirement.nil?
        next if Gem::Requirement.new(dependency.requirement).satisfied_by?(
          Gem::Version.new(version),
        )

        OutdatedPackage.new(dependency: dependency, version: version)
      end
    end

    def lasem_warnings(enabled)
      return [] unless enabled

      [
        missing_submodule_warning,
        stale_extension_warning,
        pkg_config_precedence_warning,
      ].compact
    end

    def missing_submodule_warning
      source_meson = File.join(root, "vendor/lasem/source/meson.build")
      return if probe.file?(source_meson)

      "Lasem submodule source was not found; run " \
        "`git submodule update --init vendor/lasem/source`."
    end

    def stale_extension_warning
      extension = File.join(root, "lib/lasem/lasem.so")
      return unless probe.file?(vendored_pc) && !probe.file?(extension)

      "Vendored Lasem is installed, but the native extension is missing; run " \
        "`bundle exec rake clean compile`."
    end

    def pkg_config_precedence_warning
      resolved_pc_dir = probe.pkg_config_variable("lasem-0.6", "pcfiledir")
      return unless probe.file?(vendored_pc)
      return if resolved_pc_dir.nil?
      return if File.expand_path(resolved_pc_dir) == vendored_pc_dir

      "`pkg-config lasem-0.6` resolves to #{resolved_pc_dir}, while vendored " \
        "Lasem is installed at #{vendored_pc_dir}."
    end

    def dependency_warnings(enabled)
      return [] unless enabled

      warnings = []
      warnings << ruby_headers_warning
      warnings.compact
    end

    def vendored_pc_dir
      File.join(root, "vendor/lasem/install/lib/pkgconfig")
    end

    def vendored_pc
      File.join(vendored_pc_dir, "lasem-0.6.pc")
    end

    def ruby_headers_warning
      ruby_header = File.join(RbConfig::CONFIG.fetch("rubyhdrdir"), "ruby.h")
      return if probe.file?(ruby_header)

      "Ruby headers were not found at #{ruby_header}; install the Ruby " \
        "development package for this Ruby version."
    end
  end
end
