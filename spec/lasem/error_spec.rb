# frozen_string_literal: true

RSpec.describe Lasem::Error do
  it "is a marker module, not a class" do
    expect(described_class).to be_a(Module)
    expect(described_class).not_to be_a(Class)
  end

  it "is rescuable as Lasem::Error for every gem error type" do
    [
      Lasem::OptionError.non_empty_source,
      Lasem::RenderError.new("boom"),
      Lasem::DependencyError.native_library_unavailable,
    ].each do |error|
      expect(error).to be_a(Lasem::Error)
    end
  end

  it "keeps OptionError rescuable as an ArgumentError" do
    expect(Lasem::OptionError.non_empty_source).to be_a(ArgumentError)
  end

  it "catches every gem error with a single rescue Lasem::Error" do
    [
      Lasem::OptionError.non_empty_source,
      Lasem::RenderError.new("boom"),
      Lasem::DependencyError.native_library_unavailable,
    ].each do |error|
      caught =
        begin
          raise error
        rescue Lasem::Error => e
          e
        end

      expect(caught).to equal(error)
    end
  end
end
