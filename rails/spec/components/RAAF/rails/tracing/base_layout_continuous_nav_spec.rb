# frozen_string_literal: true

require "rails_helper"

# Evaluators, Analytics and System status render correctly and were in no
# menu. Analytics is the only screen in the console that reports what
# evaluation itself costs; System status carries queue depth, backpressure and
# the configuration in force, and its own comment records that it raised
# NoMethodError for a long time and nobody noticed, because nothing linked it.
RSpec.describe RAAF::Rails::Tracing::BaseLayout, type: :component do
  def continuous_items
    described_class.new.send(:nav_groups)
                   .find { |group| group[:id] == :continuous }[:items]
  end

  it "reaches the three screens that were in no menu" do
    keys = continuous_items.map { |item| item[:key] }

    expect(keys).to include(:evaluators, :analytics, :system)
  end

  it "routes each of them" do
    added = continuous_items.select { |item| %i[evaluators analytics system].include?(item[:key]) }

    expect(added.map { |item| item[:href] })
      .to eq(["/raaf/continuous/evaluators",
              "/raaf/continuous/analytics",
              "/raaf/continuous/health/dashboard"])
  end

  # System status and Evaluator health are two different screens under one
  # word, so they take two nav entries rather than sharing a current key.
  it "keeps System status apart from Health" do
    keys = continuous_items.map { |item| item[:key] }

    expect(keys).to include(:health, :system)
  end
end
