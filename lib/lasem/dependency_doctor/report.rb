# frozen_string_literal: true

module Lasem
  class DependencyDoctor
    class Report
      def initialize(attributes)
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
        append_warnings(lines, "Lasem setup warnings", lasem_warnings)
        append_warnings(lines, "Dependency warnings", dependency_warnings)
        lines.join("\n")
      end

      private

      attr_reader :missing_executables, :missing_pkg_config,
                  :outdated_pkg_config, :lasem_warnings, :dependency_warnings

      def append_status(lines)
        lines << ""
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
  end
end
