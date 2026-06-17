# frozen_string_literal: true

require "rbconfig"

RSpec.describe Lasem::NativeLoader do
  it "derives the extension filename from the platform DLEXT" do
    expect(described_class.extension_filename)
      .to eq("lasem.#{RbConfig::CONFIG.fetch('DLEXT')}")
  end

  describe ".available?" do
    it "returns a boolean" do
      expect([true, false]).to include(described_class.available?)
    end
  end

  describe ".render" do
    it "raises DependencyError when the native library reports unavailable" do
      allow(described_class).to receive(:load!).and_return(true)
      stub_const("Lasem::Native", Class.new do
        def self.native_available? = false
      end)

      expect { described_class.render("x") }
        .to raise_error(Lasem::DependencyError)
    end
  end
end
