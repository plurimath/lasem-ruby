# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations

require "stringio"
require "lasem/dependency_doctor"

DependencyDoctorFakeProbe = Struct.new(
  :executables,
  :pkg_config_versions,
  :pkg_config_variables,
  :files,
  :os_release,
  :platform,
  keyword_init: true,
) do
  def executable?(name)
    executables.include?(name)
  end

  def file?(path)
    files.include?(path)
  end

  def pkg_config_version(package)
    pkg_config_versions[package]
  end

  def pkg_config_variable(package, variable)
    pkg_config_variables[[package, variable]]
  end
end

RSpec.describe Lasem::DependencyDoctor do
  let(:root) { "/repo" }
  let(:required_executables) do
    %w[cc make pkg-config meson ninja bison flex msgfmt]
  end
  let(:apt_executables) do
    [*required_executables, "apt-get"]
  end
  let(:all_pkg_config_versions) do
    {
      "glib-2.0" => "2.80.0",
      "gobject-2.0" => "2.80.0",
      "gio-2.0" => "2.80.0",
      "gdk-pixbuf-2.0" => "2.42.0",
      "cairo" => "1.18.0",
      "pangocairo" => "1.54.0",
      "libxml-2.0" => "2.12.0",
    }
  end

  def probe(**overrides)
    DependencyDoctorFakeProbe.new(
      {
        executables: [],
        pkg_config_versions: {},
        pkg_config_variables: {},
        files: [],
        os_release: {},
        platform: "x86_64-linux",
      }.merge(overrides),
    )
  end

  describe "#report" do
    it "reports missing dependencies with the best-known installer command" do
      report = described_class.new(
        root: root,
        probe: probe(executables: %w[apt-get pkg-config],
                     os_release: { "ID" => "ubuntu" }),
      ).report

      expect(report).not_to be_success
      expect(report.to_s).to include("Missing executables:")
      expect(report.to_s).to include("Missing pkg-config packages:")
      expect(report.to_s).to include(
        "Best-known install command for Debian/Ubuntu:",
      )
      expect(report.to_s).to include("sudo apt-get install")
    end

    it "passes when required dependencies are available" do
      report = described_class.new(
        root: root,
        probe: probe(executables: apt_executables,
                     pkg_config_versions: all_pkg_config_versions,
                     os_release: { "ID" => "ubuntu" }),
      ).report

      expect(report).to be_success
      expect(report.to_s).to include("Required dependencies look available.")
    end

    it "can include Lasem-specific setup warnings" do
      vendored_pc_dir = "/repo/vendor/lasem/install/lib/pkgconfig"
      report = described_class.new(
        root: root,
        probe: probe(
          executables: apt_executables,
          pkg_config_versions: all_pkg_config_versions,
          pkg_config_variables: {
            ["lasem-0.6", "pcfiledir"] => "/usr/lib/pkgconfig",
          },
          files: ["/repo/vendor/lasem/install/lib/pkgconfig/lasem-0.6.pc"],
          os_release: { "ID" => "ubuntu" },
        ),
      ).report(lasem_conflict_warnings: true)

      expect(report.to_s).to include("Lasem setup warnings:")
      expect(report.to_s).to include("run `bundle exec rake clean compile`")
      expect(report.to_s).to include(vendored_pc_dir)
    end

    it "can include dependency warnings" do
      report = described_class.new(
        root: root,
        probe: probe(executables: required_executables,
                     pkg_config_versions: all_pkg_config_versions),
      ).report(dep_conflict_warnings: true)

      expect(report.to_s).to include("Dependency warnings:")
      expect(report.to_s).to include(
        "No supported package installer was detected.",
      )
      expect(report.to_s).to include("Ruby headers were not found")
    end
  end

  describe described_class::CLI do
    it "returns a non-zero status when dependencies are missing" do
      output = StringIO.new
      status = described_class.call(
        [],
        output: output,
        error: StringIO.new,
        root: root,
        probe: probe,
      )

      expect(status).to eq(1)
      expect(output.string).to include("Missing executables:")
    end

    it "supports all warning flags" do
      output = StringIO.new
      status = described_class.call(
        ["--all-warnings"],
        output: output,
        error: StringIO.new,
        root: root,
        probe: probe,
      )

      expect(status).to eq(1)
      expect(output.string).to include("Lasem setup warnings:")
      expect(output.string).to include("Dependency warnings:")
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
