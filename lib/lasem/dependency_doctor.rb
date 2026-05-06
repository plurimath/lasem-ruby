# frozen_string_literal: true

require "open3"
require "optparse"
require "rbconfig"
require "rubygems"

module Lasem
  class DependencyDoctor
    ROOT = File.expand_path("../..", __dir__)

    ExecutableDependency = Struct.new(:name, :executables, keyword_init: true)
    PkgConfigDependency = Struct.new(:name, :requirement, keyword_init: true)
    Installer = Struct.new(:name, :label, :command, keyword_init: true)
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

    INSTALLERS = [
      Installer.new(
        name: "apt-get",
        label: "Debian/Ubuntu",
        command: "sudo apt-get install build-essential ruby-dev pkg-config " \
                 "meson ninja-build bison flex gettext libglib2.0-dev " \
                 "libgdk-pixbuf-2.0-dev libcairo2-dev libpango1.0-dev " \
                 "libxml2-dev fonts-lyx",
      ),
      Installer.new(
        name: "dnf",
        label: "Fedora",
        command: "sudo dnf install gcc make ruby-devel pkgconf-pkg-config " \
                 "meson ninja-build bison flex gettext glib2-devel " \
                 "gdk-pixbuf2-devel cairo-devel pango-devel libxml2-devel " \
                 "lyx-fonts",
      ),
      Installer.new(
        name: "yum",
        label: "RHEL/CentOS",
        command: "sudo yum install gcc make ruby-devel pkgconf-pkg-config " \
                 "meson ninja-build bison flex gettext glib2-devel " \
                 "gdk-pixbuf2-devel cairo-devel pango-devel libxml2-devel",
      ),
      Installer.new(
        name: "pacman",
        label: "Arch Linux",
        command: "sudo pacman -S base-devel ruby pkgconf meson ninja bison " \
                 "flex gettext glib2 gdk-pixbuf2 cairo pango libxml2",
      ),
      Installer.new(
        name: "apk",
        label: "Alpine Linux",
        command: "sudo apk add build-base ruby-dev pkgconf meson ninja bison " \
                 "flex gettext-dev glib-dev gdk-pixbuf-dev cairo-dev " \
                 "pango-dev libxml2-dev",
      ),
      Installer.new(
        name: "zypper",
        label: "openSUSE",
        command: "sudo zypper install gcc make ruby-devel pkg-config meson " \
                 "ninja bison flex gettext-tools glib2-devel " \
                 "gdk-pixbuf-devel cairo-devel pango-devel libxml2-devel " \
                 "lyx-fonts",
      ),
      Installer.new(
        name: "brew",
        label: "macOS/Homebrew",
        command: "brew install pkg-config meson ninja bison flex gettext " \
                 "glib gdk-pixbuf cairo pango libxml2",
      ),
    ].freeze
    OS_INSTALLER_IDS = {
      "apt-get" => %w[debian ubuntu],
      "dnf" => %w[fedora],
      "yum" => %w[rhel centos],
      "pacman" => %w[arch],
      "apk" => %w[alpine],
      "zypper" => %w[suse opensuse],
    }.freeze

    def initialize(root: ROOT, probe: Probe.new)
      @root = root
      @probe = probe
    end

    def report(lasem_conflict_warnings: false, dep_conflict_warnings: false)
      Report.new(
        installer: detect_installer,
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

    def detect_installer
      os_release = probe.os_release
      preferred_installer(os_release) || available_installer
    end

    def preferred_installer(os_release)
      return installer_named("brew") if probe.platform.include?("darwin")

      ids = [os_release["ID"], *os_release.fetch("ID_LIKE", "").split].compact
      installer_name = OS_INSTALLER_IDS.find do |_name, aliases|
        ids.intersect?(aliases)
      end&.first
      installer_named(installer_name) if installer_name
    end

    def available_installer
      INSTALLERS.find { |installer| probe.executable?(installer.name) }
    end

    def installer_named(name)
      installer = INSTALLERS.find { |candidate| candidate.name == name }
      return unless installer && probe.executable?(name)

      installer
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
      if detect_installer.nil?
        warnings << "No supported package installer was detected."
      end
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

    class Report
      def initialize(attributes)
        @installer = attributes.fetch(:installer)
        @missing_executables = attributes.fetch(:missing_executables)
        @missing_pkg_config = attributes.fetch(:missing_pkg_config)
        @outdated_pkg_config = attributes.fetch(:outdated_pkg_config)
        @lasem_warnings = attributes.fetch(:lasem_warnings)
        @dependency_warnings = attributes.fetch(:dependency_warnings)
      end

      def success?
        missing_executables.empty? &&
          missing_pkg_config.empty? &&
          outdated_pkg_config.empty?
      end

      def to_s
        lines = ["Lasem dependency doctor"]
        append_status(lines)
        append_install_suggestion(lines)
        append_warnings(lines, "Lasem setup warnings", lasem_warnings)
        append_warnings(lines, "Dependency warnings", dependency_warnings)
        lines.join("\n")
      end

      private

      attr_reader :installer, :missing_executables, :missing_pkg_config,
                  :outdated_pkg_config, :lasem_warnings, :dependency_warnings

      def append_status(lines)
        lines << ""
        lines << installer_line
        append_dependency_status(lines)
        lines << "Required dependencies look available." if success?
      end

      def append_dependency_status(lines)
        append_list(
          lines,
          "Missing executables",
          missing_executables.map(&:name),
        )
        append_list(lines, "Missing pkg-config packages", pkg_config_names)
        append_outdated_pkg_config(lines)
      end

      def append_outdated_pkg_config(lines)
        append_list(
          lines,
          "Outdated pkg-config packages",
          outdated_pkg_config_names,
        )
      end

      def append_install_suggestion(lines)
        return if success?

        lines << ""
        if installer
          lines << "Best-known install command for #{installer.label}:"
          lines << "  #{installer.command}"
        else
          lines << "No supported installer was detected. Install equivalent " \
                   "development packages for the missing items above."
        end
      end

      def append_warnings(lines, heading, warnings)
        return if warnings.empty?

        lines << ""
        append_list(lines, heading, warnings)
      end

      def append_list(lines, heading, values)
        return if values.empty?

        lines << "#{heading}:"
        values.each { |value| lines << "  - #{value}" }
      end

      def installer_line
        if installer
          return "Detected installer: #{installer.name} (#{installer.label})"
        end

        "Detected installer: unknown"
      end

      def pkg_config_names
        missing_pkg_config.map do |dependency|
          next dependency.name unless dependency.requirement

          "#{dependency.name} #{dependency.requirement}"
        end
      end

      def outdated_pkg_config_names
        outdated_pkg_config.map do |package|
          "#{package.dependency.name} #{package.dependency.requirement} " \
            "(found #{package.version})"
        end
      end
    end

    class Probe
      def executable?(name)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |path|
          executable = File.join(path, name)
          File.executable?(executable) && !File.directory?(executable)
        end
      end

      def file?(path)
        File.file?(path)
      end

      def os_release
        return {} unless file?("/etc/os-release")

        File.readlines("/etc/os-release").to_h do |line|
          key, value = line.strip.split("=", 2)
          [key, value&.delete_prefix("\"")&.delete_suffix("\"")]
        end
      end

      def platform
        RUBY_PLATFORM
      end

      def pkg_config_version(package)
        return unless executable?("pkg-config")

        output, status = capture("pkg-config", "--modversion", package)
        status.success? ? output.strip : nil
      end

      def pkg_config_variable(package, variable)
        return unless executable?("pkg-config")

        output, status = capture(
          "pkg-config",
          "--variable=#{variable}",
          package,
        )
        status.success? && !output.strip.empty? ? output.strip : nil
      end

      private

      def capture(*command)
        stdout, _stderr, status = Open3.capture3(*command)
        [stdout, status]
      end
    end

    class CLI
      def self.call(
        argv,
        output: $stdout,
        error: $stderr,
        root: ROOT,
        probe: Probe.new
      )
        new(argv, output: output, error: error, root: root, probe: probe).call
      end

      def initialize(argv, output:, error:, root:, probe:)
        @argv = argv.dup
        @output = output
        @error = error
        @root = root
        @probe = probe
        @options = {
          lasem_conflict_warnings: false,
          dep_conflict_warnings: false,
        }
      end

      def call
        parser.parse!(argv)
        run_doctor
      rescue OptionParser::InvalidOption => e
        error.puts(e.message)
        error.puts(parser)
        2
      end

      private

      attr_reader :argv, :output, :error, :root, :probe, :options

      def run_doctor
        doctor = DependencyDoctor.new(root: root, probe: probe)
        report = doctor.report(**options)
        output.puts(report)
        report.success? ? 0 : 1
      end

      def parser
        @parser ||= OptionParser.new do |opts|
          opts.banner = "Usage: lasem-doctor [options]"
          add_warning_options(opts)
        end
      end

      def add_warning_options(opts)
        opts.on("--lasem-conflict-warnings", "Show Lasem setup warnings") do
          options[:lasem_conflict_warnings] = true
        end
        opts.on("--dep-conflict-warnings", "Show dependency warnings") do
          options[:dep_conflict_warnings] = true
        end
        opts.on("--all-warnings", "Show all warnings") do
          options[:lasem_conflict_warnings] = true
          options[:dep_conflict_warnings] = true
        end
      end
    end
  end
end
