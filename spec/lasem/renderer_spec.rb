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

  def render_sample_mathml
    described_class.render(mathml, input: :mathml, output: :svg)
  end

  def render_svg(**options)
    described_class.render(
      mathml,
      input: :mathml,
      output: :svg,
      **options,
    )
  end

  def render_output(format, **options)
    described_class.render(
      mathml,
      input: :mathml,
      output: format,
      **options,
    )
  end

  def png_dimensions(png)
    [
      png.byteslice(16, 4).unpack1("N"),
      png.byteslice(20, 4).unpack1("N"),
    ]
  end

  def first_use_coordinates(svg)
    match = svg.match(/<use\b[^>]*\sx="([^"]+)"[^>]*\sy="([^"]+)"/)
    raise "No SVG use element found" unless match

    [Float(match[1]), Float(match[2])]
  end

  def native_offset_deltas(**options)
    base_x, base_y = first_use_coordinates(render_svg(zoom: 2.0))
    offset_x, offset_y = first_use_coordinates(render_svg(zoom: 2.0, **options))

    [base_x - offset_x, base_y - offset_y]
  end

  def skip_without_native_lasem
    skip "Lasem native library is not available" unless Lasem.native_available?
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
        described_class.render(mathml, input: :unknown)
      end.to raise_error(Lasem::OptionError, /input/)
    end

    it "validates the output format" do
      expect do
        described_class.render(mathml, output: :jpeg)
      end.to raise_error(Lasem::OptionError, /output/)
    end

    it "rejects unknown options" do
      expect do
        described_class.render(mathml, zooom: 2.0)
      end.to raise_error(Lasem::OptionError, /unknown option.*zooom/)
    end

    it "requires source to be a string" do
      expect do
        described_class.render(nil)
      end.to raise_error(Lasem::OptionError, /source/)
    end

    it "requires source to be non-empty" do
      expect do
        described_class.render(" ")
      end.to raise_error(Lasem::OptionError, /source/)
    end

    it "does not mask a malformed #to_str as an empty-source error" do
      bad = Object.new
      def bad.to_str = 123

      expect { described_class.render(bad) }.to raise_error(TypeError)
    end

    it "transcodes non-UTF-8 source to UTF-8 before rendering" do
      stub_native_render

      described_class.render(mathml.encode(Encoding::UTF_16), input: :mathml)

      expect(Lasem::NativeLoader).to have_received(:render) do |source, *|
        expect(source.encoding).to eq(Encoding::UTF_8)
      end
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

    it "requires finite offset values" do
      expect do
        described_class.render(mathml, offset_x: Float::INFINITY)
      end.to raise_error(Lasem::OptionError, /offset_x/)
    end

    it "passes LaTeX input unchanged" do
      stub_native_render

      expect(described_class.render("\\sum_d^d", input: :latex))
        .to eq("<svg/>")
      expect_native_rendered("\\sum_d^d", "latex")
    end

    it "passes itex input unchanged" do
      stub_native_render

      expect(described_class.render("\\(\\sum_d^d\\)", input: :itex))
        .to eq("<svg/>")
      expect_native_rendered("\\(\\sum_d^d\\)", "itex")
    end

    it "renders SVG output when the native layer is available" do
      skip_without_native_lasem

      expect(render_sample_mathml).to include("<svg")
    end

    it "renders PNG output when the native layer is available" do
      skip_without_native_lasem

      # Non-square dimensions so a width/height swap would be caught.
      png = render_output(:png, width: 72, height: 36, ppi: 144.0)

      expect(png.byteslice(0, 8)).to eq("\x89PNG\r\n\x1A\n".b)
      expect(png_dimensions(png)).to eq([144, 72])
    end

    it "renders auto-sized PNG output (no explicit dimensions)" do
      skip_without_native_lasem

      png = render_output(:png, ppi: 144.0)
      width, height = png_dimensions(png)

      expect(png.byteslice(0, 8)).to eq("\x89PNG\r\n\x1A\n".b)
      expect(width).to be > 0
      expect(height).to be > 0
    end

    it "renders PDF output when the native layer is available" do
      skip_without_native_lasem

      expect(render_output(:pdf)).to start_with("%PDF")
    end

    it "renders PostScript output when the native layer is available" do
      skip_without_native_lasem

      expect(render_output(:ps)).to start_with("%!PS-Adobe")
    end

    it "scales explicit export dimensions by zoom" do
      skip_without_native_lasem

      expect(render_svg(width: 10, height: 20, zoom: 2.0)).to match(
        /width="20(?:pt)?" height="40(?:pt)?" viewBox="0 0 20 40"/,
      )
    end

    it "applies offsets with upstream zoom scaling" do
      skip_without_native_lasem

      expect(native_offset_deltas(offset_x: 1.0, offset_y: 1.0))
        .to all(be_within(0.001).of(4.0))
    end

    it "renders correctly from multiple threads" do
      skip_without_native_lasem

      threads = Array.new(4) { Thread.new { render_sample_mathml } }

      expect(threads.map(&:value)).to all(include("<svg"))
    end

    it "raises a render error for unparseable input" do
      skip_without_native_lasem

      expect do
        described_class.render("not xml at all >>><<<", input: :mathml)
      end.to raise_error(Lasem::RenderError, /could not parse/)
    end

    it "raises a render error for an oversized raster request" do
      skip_without_native_lasem

      expect do
        render_output(:png, width: 200_000, height: 200_000, ppi: 144.0)
      end.to raise_error(Lasem::RenderError, /exceeds the maximum/)
    end

    it "re-validates ppi at the native boundary" do
      skip_without_native_lasem

      expect do
        Lasem::Native.render(
          mathml, "mathml", "svg", 0.0, 1.0, nil, nil, 0.0, 0.0
        )
      end.to raise_error(Lasem::RenderError, /ppi/)
    end

    it "surfaces a dependency error from the native loader" do
      # Deterministic (does not depend on native availability): verifies the
      # contract a consumer like Plurimath rescues when only the stub is loaded.
      allow(Lasem::NativeLoader).to receive(:render)
        .and_raise(Lasem::DependencyError.native_library_unavailable)

      expect { render_sample_mathml }
        .to raise_error(Lasem::DependencyError, /not available/)
    end

    it "raises a dependency error when the native layer is unavailable" do
      skip "Lasem native library is available" if Lasem.native_available?

      expect { render_sample_mathml }.to raise_error(Lasem::DependencyError)
    end
  end
end
