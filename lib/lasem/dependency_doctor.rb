# frozen_string_literal: true

require "rbconfig"
require "rubygems"
require_relative "pkg_config"

module Lasem
  class DependencyDoctor
    autoload :CLI, "lasem/dependency_doctor/cli"
    autoload :Probe, "lasem/dependency_doctor/probe"
    autoload :Report, "lasem/dependency_doctor/report"

    ROOT = File.expand_path("../..", __dir__)

    ExecutableDependency = Struct.new(:name, :executables, keyword_init: true)
    PkgConfigDependency = Struct.new(
      :name,
      :requirement,
      :candidates,
      keyword_init: true,
    )
    OutdatedPackage = Struct.new(:dependency, :version, keyword_init: true)

    # Tools required to compile the gem's native extension against any Lasem
    # (system or vendored). Missing any of these fails the doctor.
    CORE_EXECUTABLE_DEPENDENCIES = [
      ExecutableDependency.new(
        name: "C compiler (cc, gcc, or clang)",
        executables: %w[cc gcc clang],
      ),
      ExecutableDependency.new(name: "make", executables: %w[make]),
      ExecutableDependency.new(name: "pkg-config", executables: %w[pkg-config]),
    ].freeze

    # Tools needed ONLY to build the vendored Lasem from source
    # (`rake lasem:build`). These are not required for the released-gem path
    # that links against a system Lasem, so they only fail the doctor when a
    # vendored source checkout is present.
    VENDORED_BUILD_EXECUTABLE_DEPENDENCIES = [
      ExecutableDependency.new(name: "meson", executables: %w[meson]),
      ExecutableDependency.new(
        name: "ninja or ninja-build",
        executables: %w[ninja ninja-build],
      ),
      ExecutableDependency.new(name: "bison", executables: %w[bison]),
      ExecutableDependency.new(name: "flex", executables: %w[flex]),
      ExecutableDependency.new(
        name: "msgfmt (gettext)",
        executables: %w[msgfmt],
      ),
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
        missing_build_executables: missing_build_executables,
        building_from_source: building_from_source?,
        missing_pkg_config: missing_pkg_config,
        outdated_pkg_config: outdated_pkg_config,
        unverifiable_pkg_config: unverifiable_pkg_config,
        lasem_warnings: lasem_warnings(lasem_conflict_warnings),
        dependency_warnings: dependency_warnings(dep_conflict_warnings),
      )
    end

    private

    attr_reader :root, :probe

    def missing_executables
      reject_present(CORE_EXECUTABLE_DEPENDENCIES)
    end

    def missing_build_executables
      reject_present(VENDORED_BUILD_EXECUTABLE_DEPENDENCIES)
    end

    def reject_present(dependencies)
      dependencies.reject do |dependency|
        dependency.executables.any? do |executable|
          probe.executable?(executable)
        end
      end
    end

    # True only when a vendored Lasem source checkout is present, i.e. the user
    # is set up to build Lasem from source and therefore needs the build tools.
    def building_from_source?
      probe.file?(File.join(root, "vendor/lasem/source/meson.build"))
    end

    def pkg_config_versions
      @pkg_config_versions ||= pkg_config_dependencies.to_h do |dependency|
        version = pkg_config_candidates_for(dependency).filter_map do |package|
          probe.pkg_config_version(package)
        end.first

        [dependency, version]
      end
    end

    def pkg_config_dependencies
      [lasem_pkg_config_dependency, *PKG_CONFIG_DEPENDENCIES]
    end

    def lasem_pkg_config_dependency
      PkgConfigDependency.new(
        name: lasem_pkg_config_candidates.join(" or "),
        candidates: lasem_pkg_config_candidates,
      )
    end

    def pkg_config_candidates_for(dependency)
      dependency.candidates || [dependency.name]
    end

    def missing_pkg_config
      pkg_config_versions.filter_map do |dependency, version|
        dependency if version.nil?
      end
    end

    def outdated_pkg_config
      pkg_config_versions.filter_map do |dependency, version|
        next if version.nil? || dependency.requirement.nil?
        # Skip versions Gem::Version cannot parse here (handled by
        # unverifiable_pkg_config) so the comparison below never raises.
        next unless Gem::Version.correct?(version)
        next if Gem::Requirement.new(dependency.requirement).satisfied_by?(
          Gem::Version.new(version),
        )

        OutdatedPackage.new(dependency: dependency, version: version)
      end
    end

    # Required packages whose reported version cannot be parsed, so we cannot
    # confirm the requirement. Reported and failed-closed rather than crashing
    # (old behavior) or silently passing.
    def unverifiable_pkg_config
      pkg_config_versions.filter_map do |dependency, version|
        next if version.nil? || dependency.requirement.nil?
        next if Gem::Version.correct?(version)

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

    # Only relevant in a source checkout (where .gitmodules is present and the
    # vendored build applies). The published gem ships no .gitmodules, so this
    # never advises installed-gem users to run a meaningless submodule command.
    def missing_submodule_warning
      return unless probe.file?(File.join(root, ".gitmodules"))

      source_meson = File.join(root, "vendor/lasem/source/meson.build")
      return if probe.file?(source_meson)

      "Lasem submodule source was not found; run " \
        "`git submodule update --init vendor/lasem/source`."
    end

    def stale_extension_warning
      extension = File.join(
        root,
        "lib/lasem/lasem.#{RbConfig::CONFIG.fetch('DLEXT')}",
      )
      return unless probe.file?(vendored_pc) && !probe.file?(extension)

      "Vendored Lasem is installed, but the native extension is missing; run " \
        "`bundle exec rake clean compile`."
    end

    def pkg_config_precedence_warning
      return unless probe.file?(vendored_pc)

      resolved_package, resolved_pc_dir = resolved_lasem_pkg_config
      return if resolved_pc_dir.nil?
      return if File.expand_path(resolved_pc_dir) == vendored_pc_dir

      "`pkg-config #{resolved_package}` resolves to #{resolved_pc_dir}, " \
        "while vendored Lasem is installed at #{vendored_pc_dir}."
    end

    def resolved_lasem_pkg_config
      lasem_pkg_config_candidates.filter_map do |package|
        pc_dir = probe.pkg_config_variable(package, "pcfiledir")
        [package, pc_dir] unless pc_dir.nil?
      end.first
    end

    def lasem_pkg_config_candidates
      Lasem::PkgConfig.candidates
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
