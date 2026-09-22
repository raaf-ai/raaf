# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Ui::Base do
  it "keeps its public helpers public" do
    expect(described_class.public_method_defined?(:slot)).to be(true)
    expect(described_class.public_method_defined?(:tokens)).to be(true)
    expect(described_class.public_method_defined?(:modifier)).to be(true)
  end

  it "keeps the raise machinery to itself" do
    expect(described_class.private_method_defined?(:production?)).to be(true)
    expect(described_class.private_method_defined?(:raise_unknown_variant)).to be(true)
  end
end
