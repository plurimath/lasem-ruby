#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerate the sample renders embedded in README.adoc.
# Run from the gem root:
#   bundle exec ruby docs/images/render_samples.rb

require "lasem"

abort "Lasem native extension not available" unless Lasem.native_available?

OUT_DIR = File.expand_path(__dir__)
PADDING_X = 24
PADDING_Y = 18

SAMPLES = [
  {
    name: "hero_quadratic",
    input: :latex,
    source: "$x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$",
    ppi: 192.0,
  },
  {
    name: "latex_euler",
    input: :latex,
    source: "$\\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}$",
    ppi: 192.0,
  },
  {
    name: "latex_integral",
    input: :latex,
    source: "$\\int_{0}^{\\infty} e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}$",
    ppi: 192.0,
  },
  {
    name: "mathml_matrix",
    input: :mathml,
    source: <<~MATHML,
      <math xmlns="http://www.w3.org/1998/Math/MathML" display="block">
        <mrow>
          <mi>A</mi>
          <mo>=</mo>
          <mfenced open="[" close="]">
            <mtable>
              <mtr><mtd><mn>1</mn></mtd><mtd><mn>2</mn></mtd><mtd><mn>3</mn></mtd></mtr>
              <mtr><mtd><mn>4</mn></mtd><mtd><mn>5</mn></mtd><mtd><mn>6</mn></mtd></mtr>
              <mtr><mtd><mn>7</mn></mtd><mtd><mn>8</mn></mtd><mtd><mn>9</mn></mtd></mtr>
            </mtable>
          </mfenced>
        </mrow>
      </math>
    MATHML
    ppi: 192.0,
  },
].freeze

def png_size(png)
  png.byteslice(16, 8).unpack("NN")
end

SAMPLES.each do |sample|
  natural_png = Lasem.render(
    sample[:source],
    input: sample[:input],
    output: :png,
    ppi: sample[:ppi],
  )
  natural_width, natural_height = png_size(natural_png)

  png = Lasem.render(
    sample[:source],
    input: sample[:input],
    output: :png,
    ppi: sample[:ppi],
    width: natural_width + (2 * PADDING_X),
    height: natural_height + (2 * PADDING_Y),
    offset_x: -PADDING_X,
    offset_y: -PADDING_Y,
  )

  path = File.join(OUT_DIR, "#{sample[:name]}.png")
  File.binwrite(path, png)
  puts "wrote #{path} (#{png.bytesize} bytes)"
end
