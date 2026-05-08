# frozen_string_literal: true

require "optparse"

module Lasem
  class DependencyDoctor
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
