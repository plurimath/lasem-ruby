# frozen_string_literal: true

require "open3"

module Lasem
  class DependencyDoctor
    class Probe
      def executable?(name)
        executable_candidates(name).any? do |candidate|
          ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |path|
            executable = File.join(path, candidate)
            File.executable?(executable) && !File.directory?(executable)
          end
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

      # On Windows an executable is found as e.g. `ruby.exe`, not `ruby`, so try
      # the bare name plus each PATHEXT extension. Elsewhere the bare name is
      # used as-is.
      def executable_candidates(name)
        return [name] unless Gem.win_platform?
        return [name] if name.match?(/\.\w+\z/)

        pathext = ENV.fetch("PATHEXT", ".COM;.EXE;.BAT;.CMD")
        extensions = pathext.split(";").map(&:downcase)
        [name, *extensions.map { |extension| "#{name}#{extension}" }]
      end

      def capture(*command)
        stdout, _stderr, status = Open3.capture3(*command)
        [stdout, status]
      end
    end
  end
end
