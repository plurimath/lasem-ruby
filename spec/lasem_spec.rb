# frozen_string_literal: true

RSpec.describe Lasem do
  it "has a version number" do
    expect(described_class::VERSION).not_to be_nil
  end

  it "exposes native availability" do
    expect(described_class.native_available?).to be(true).or be(false)
  end

  it "provides the render entry point" do
    expect(described_class.public_methods).to include(:render)
  end

  it "does not expose per-input-type render shortcuts" do
    shortcuts = %i[render_mathml render_svg render_latex render_itex]

    expect(described_class.public_methods & shortcuts).to be_empty
  end
end
