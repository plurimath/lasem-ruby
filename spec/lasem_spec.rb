# frozen_string_literal: true

RSpec.describe Lasem do
  it "has a version number" do
    expect(described_class::VERSION).not_to be_nil
  end

  it "exposes native availability" do
    expect(described_class.native_available?).to be(true).or be(false)
  end

  it "provides convenience render entry points" do
    expected_methods = %i[
      render render_mathml render_svg render_latex render_itex
    ]

    expect(described_class.public_methods).to include(*expected_methods)
  end
end
