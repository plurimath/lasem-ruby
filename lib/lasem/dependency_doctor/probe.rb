# frozen_string_literal: true

require "open3"

module Lasem
  class DependencyDoctor
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
  end
end
