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
    described_class.render(mathml, input_type: :mathml, output_format: :svg)
  end

  def stub_native_render
    allow(Lasem::NativeLoader).to receive(:render).and_return("<svg/>")
  end

  def expect_native_rendered(input, input_type)
    expect(Lasem::NativeLoader).to have_received(:render).with(
      input, input_type, "svg", 72.0, 1.0, nil, nil, 0.0, 0.0
    )
  end

  describe ".render" do
    it "validates the input type" do
      expect do
        described_class.render(mathml, input_type: :unknown)
      end.to raise_error(Lasem::OptionError, /input_type/)
    end

    it "validates the output format" do
      expect do
        described_class.render(mathml, output_format: :jpeg)
      end.to raise_error(Lasem::OptionError, /output_format/)
    end

    it "rejects unknown options" do
      expect do
        described_class.render(mathml, format: :png)
      end.to raise_error(Lasem::OptionError, /unknown option.*format/)
    end

    it "requires a positive ppi value" do
      expect do
        described_class.render(mathml, ppi: 0)
      end.to raise_error(Lasem::OptionError, /ppi/)
    end

    it "requires a positive zoom value" do
      expect do
        described_class.render(mathml, zoom: -1)
      end.to raise_error(Lasem::OptionError, /zoom/)
    end

    it "requires width and height to be provided together" do
      expect do
        described_class.render(mathml, width: 100)
      end.to raise_error(Lasem::OptionError, /width and height/)
    end

    it "passes LaTeX input unchanged" do
      stub_native_render

      expect(described_class.render("\\sum_d^d", input_type: :latex))
        .to eq("<svg/>")
      expect_native_rendered("\\sum_d^d", "latex")
    end

    it "passes itex input unchanged" do
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
