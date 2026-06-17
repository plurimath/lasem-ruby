# frozen_string_literal: true

RSpec.describe Lasem do
  it "has a version number" do
    expect(described_class::VERSION).not_to be_nil
  end

  it "delegates native availability to NativeLoader" do
    allow(Lasem::NativeLoader).to receive(:available?).and_return(:sentinel)

    expect(described_class.native_available?).to eq(:sentinel)
  end

  it "delegates render to Renderer with the given input/output" do
    allow(Lasem::Renderer).to receive(:render).and_return("<svg/>")

    expect(described_class.render("x", input: :mathml, output: :png))
      .to eq("<svg/>")
    expect(Lasem::Renderer).to have_received(:render)
      .with("x", input: :mathml, output: :png)
  end

  it "does not expose per-input-type render shortcuts" do
    shortcuts = %i[render_mathml render_svg render_latex render_itex]

    expect(described_class.public_methods & shortcuts).to be_empty
  end
end
