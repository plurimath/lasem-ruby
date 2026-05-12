# frozen_string_literal: true

RSpec.describe Lasem::OptionError do
  describe ".invalid_choice" do
    subject(:error) do
      described_class.invalid_choice(
        name: "output",
        allowed_values: %w[svg png],
      )
    end

    it "builds an invalid choice error" do
      expect(error).to have_attributes(
        class: described_class,
        message: "output must be one of: svg, png",
      )
    end
  end

  describe ".non_empty_source" do
    it "builds a source validation error" do
      error = described_class.non_empty_source

      expect(error).to have_attributes(
        class: described_class,
        message: "source must be a non-empty string",
      )
    end
  end

  describe ".not_numeric" do
    it "builds a numeric type error" do
      error = described_class.not_numeric(name: "ppi")

      expect(error).to have_attributes(
        class: described_class,
        message: "ppi must be numeric",
      )
    end
  end

  describe ".not_finite" do
    it "builds a finite number error" do
      error = described_class.not_finite(name: "offset_x")

      expect(error).to have_attributes(
        class: described_class,
        message: "offset_x must be finite",
      )
    end
  end

  describe ".not_positive" do
    it "builds a positive number error" do
      error = described_class.not_positive(name: "zoom")

      expect(error).to have_attributes(
        class: described_class,
        message: "zoom must be greater than 0",
      )
    end
  end

  describe ".incomplete_size_pair" do
    it "builds a width and height pairing error" do
      error = described_class.incomplete_size_pair

      expect(error).to have_attributes(
        class: described_class,
        message: "width and height must be provided together",
      )
    end
  end

  describe ".unknown_options" do
    it "builds an unknown options error" do
      error = described_class.unknown_options(names: %i[format scale])

      expect(error).to have_attributes(
        class: described_class,
        message: "unknown option(s): format, scale",
      )
    end
  end
end
