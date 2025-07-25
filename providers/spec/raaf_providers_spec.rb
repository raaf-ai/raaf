# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Providers do
  it "has a version number" do
    expect(RAAF::Providers::VERSION).not_to be_nil
  end

  it "loads the main module" do
    expect(described_class).to be_a(Module)
  end
end
