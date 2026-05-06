# frozen_string_literal: true

RSpec.describe Lasem::Renderer do
  let(:mathml) do
    <<~MATHML
      <math xmlns="http://www.w3.org/1998/Math/MathML">
        <mrow>
          <mi>x</mi>
        </mrow>
      </math>
    MATHML
  end

  def render_mathml
    described_class.render(mathml, input_type: :mathml, format: :svg)
  end

  def stub_native_render
    allow(Lasem::Native).to receive(:render).and_return("<svg/>")
  end

  def expect_native_rendered(input, input_type)
    expect(Lasem::Native).to have_received(:render).with(
      input, input_type, "svg", 72.0, 1.0, nil, nil, 0.0, 0.0
    )
  end

  describe ".render" do
    it "validates the input type" do
      expect do
        described_class.render(mathml, input_type: :unknown)
      end.to raise_error(ArgumentError, /input_type/)
    end

    it "validates the output format" do
      expect do
        described_class.render(mathml, format: :jpeg)
      end.to raise_error(ArgumentError, /format/)
    end

    it "requires a positive ppi value" do
      expect do
        described_class.render(mathml, ppi: 0)
      end.to raise_error(ArgumentError, /ppi/)
    end

    it "requires a positive zoom value" do
      expect do
        described_class.render(mathml, zoom: -1)
      end.to raise_error(ArgumentError, /zoom/)
    end

    it "requires width and height to be provided together" do
      expect do
        described_class.render(mathml, width: 100)
      end.to raise_error(ArgumentError, /width and height/)
    end

    it "wraps bare LaTeX input in itex math delimiters" do
      stub_native_render

      expect(described_class.render("\\sum_d^d", input_type: :latex))
        .to eq("<svg/>")
      expect_native_rendered("$\\sum_d^d$", "latex")
    end

    it "preserves existing itex math delimiters" do
      stub_native_render

      expect(described_class.render("\\(\\sum_d^d\\)", input_type: :itex))
        .to eq("<svg/>")
      expect_native_rendered("\\(\\sum_d^d\\)", "itex")
    end

    it "renders SVG output when the native layer is available" do
      unless Lasem.native_available?
        skip "Lasem native library is not available"
      end

      expect(render_mathml).to include("<svg")
    end

    it "raises a dependency error when the native layer is unavailable" do
      skip "Lasem native library is available" if Lasem.native_available?

      expect { render_mathml }.to raise_error(Lasem::DependencyError)
    end
  end
end
