# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations

require "stringio"
require "tmpdir"

RSpec.describe Lasem::DependencyDoctor do
  let(:fake_probe_class) do
    Struct.new(
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
  end

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
      "lasem-0.6" => "0.6.0",
    }
  end

  def probe(**overrides)
    fake_probe_class.new(
      {
        executables: [],
        pkg_config_versions: {},
        pkg_config_variables: {},
        files: [],
      }.merge(overrides),
    )
  end

  def with_env(values)
    original = values.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def with_lasem_pkg_config(value)
    original = ENV.fetch("LASEM_PKG_CONFIG", nil)
    if value.nil?
      ENV.delete("LASEM_PKG_CONFIG")
    else
      ENV["LASEM_PKG_CONFIG"] = value
    end
    yield
  ensure
    if original.nil?
      ENV.delete("LASEM_PKG_CONFIG")
    else
      ENV["LASEM_PKG_CONFIG"] = original
    end
  end

  describe "#report" do
    it "reports missing dependencies" do
      report = described_class.new(
        root: root,
        probe: probe(executables: %w[pkg-config]),
      ).report

      expect(report).not_to be_success
      expect(report.to_s).to include("Missing executables:")
      expect(report.to_s).to include("Missing pkg-config packages:")
    end

    it "passes when required dependencies are available" do
      report = described_class.new(
        root: root,
        probe: probe(executables: apt_executables,
                     pkg_config_versions: all_pkg_config_versions),
      ).report

      expect(report).to be_success
      expect(report.to_s).to include("Required dependencies look available.")
    end

    it "passes for a system install without the vendored-build toolchain" do
      report = described_class.new(
        root: root,
        probe: probe(executables: %w[cc make pkg-config],
                     pkg_config_versions: all_pkg_config_versions),
      ).report

      expect(report).to be_success
      expect(report.to_s).to include("only needed to build Lasem from source")
    end

    it "requires the vendored-build toolchain when building from source" do
      report = described_class.new(
        root: root,
        probe: probe(
          executables: %w[cc make pkg-config],
          pkg_config_versions: all_pkg_config_versions,
          files: ["/repo/vendor/lasem/source/meson.build"],
        ),
      ).report

      expect(report).not_to be_success
      expect(report.to_s).to include("Missing vendored-build tools")
    end

    it "fails closed (without crashing) on an unverifiable required version" do
      versions = all_pkg_config_versions.merge("cairo" => "1.18.0_p1")
      report = described_class.new(
        root: root,
        probe: probe(executables: apt_executables,
                     pkg_config_versions: versions),
      ).report

      expect { report.to_s }.not_to raise_error
      expect(report).not_to be_success
      expect(report.to_s).to include("Unverifiable pkg-config versions")
    end

    it "requires a Lasem pkg-config package" do
      versions = all_pkg_config_versions.reject do |package, _version|
        package.start_with?("lasem")
      end
      report = described_class.new(
        root: root,
        probe: probe(executables: apt_executables,
                     pkg_config_versions: versions),
      ).report

      expect(report).not_to be_success
      expect(report.to_s).to include("lasem-0.6 or lasem or lasem-0.4")
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
        ),
      ).report(lasem_conflict_warnings: true)

      expect(report.to_s).to include("Lasem setup warnings:")
      expect(report.to_s).to include("run `bundle exec rake clean compile`")
      expect(report.to_s).to include(vendored_pc_dir)
    end

    it "uses the first resolved Lasem pkg-config candidate in setup warnings" do
      vendored_pc_dir = "/repo/vendor/lasem/install/lib/pkgconfig"
      report = with_lasem_pkg_config(nil) do
        described_class.new(
          root: root,
          probe: probe(
            executables: apt_executables,
            pkg_config_versions: all_pkg_config_versions,
            pkg_config_variables: {
              ["lasem", "pcfiledir"] => "/usr/lib/pkgconfig",
            },
            files: ["/repo/vendor/lasem/install/lib/pkgconfig/lasem-0.6.pc"],
          ),
        ).report(lasem_conflict_warnings: true)
      end

      expect(report.to_s).to include("`pkg-config lasem` resolves")
      expect(report.to_s).to include(vendored_pc_dir)
    end

    it "uses LASEM_PKG_CONFIG in setup warnings" do
      report = with_lasem_pkg_config("lasem") do
        described_class.new(
          root: root,
          probe: probe(
            executables: apt_executables,
            pkg_config_versions: all_pkg_config_versions,
            pkg_config_variables: {
              ["lasem", "pcfiledir"] => "/usr/lib/pkgconfig",
              ["lasem-0.6", "pcfiledir"] => "/other/pkgconfig",
            },
            files: ["/repo/vendor/lasem/install/lib/pkgconfig/lasem-0.6.pc"],
          ),
        ).report(lasem_conflict_warnings: true)
      end

      expect(report.to_s).to include("`pkg-config lasem` resolves")
      expect(report.to_s).not_to include("`pkg-config lasem-0.6` resolves")
    end

    it "can include dependency warnings" do
      report = described_class.new(
        root: root,
        probe: probe(executables: required_executables,
                     pkg_config_versions: all_pkg_config_versions),
      ).report(dep_conflict_warnings: true)

      expect(report.to_s).to include("Dependency warnings:")
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

    it "reports an invalid option without raising" do
      errio = StringIO.new
      status = described_class.call(
        ["--nope"],
        output: StringIO.new,
        error: errio,
        root: root,
        probe: probe,
      )

      expect(status).to eq(2)
      expect(errio.string).to include("invalid option")
    end
  end

  describe described_class::Probe do
    subject(:real_probe) { described_class.new }

    it "detects an executable present on PATH" do
      expect(real_probe.executable?("ruby")).to be(true)
    end

    it "reports an absent executable as missing" do
      expect(real_probe.executable?("lasem-not-a-real-binary-xyz"))
        .to be(false)
    end

    it "finds a Windows executable by its PATHEXT extension" do
      Dir.mktmpdir do |dir|
        tool = File.join(dir, "tool.exe")
        File.write(tool, "")
        File.chmod(0o755, tool)
        allow(Gem).to receive(:win_platform?).and_return(true)

        with_env("PATH" => dir, "PATHEXT" => ".EXE") do
          expect(real_probe.executable?("tool")).to be(true)
        end
      end
    end

    it "does not append executable extensions off Windows" do
      Dir.mktmpdir do |dir|
        tool = File.join(dir, "tool.exe")
        File.write(tool, "")
        File.chmod(0o755, tool)
        allow(Gem).to receive(:win_platform?).and_return(false)

        with_env("PATH" => dir) do
          expect(real_probe.executable?("tool")).to be(false)
        end
      end
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
