# frozen_string_literal: true

require "rails_helper"

# The nav doubled as a roadmap: an item with no href rendered as a "soon"
# placeholder. What it actually did was offer the reader a screen and then
# refuse to go there.
RSpec.describe RAAF::Rails::Tracing::BaseLayout, type: :component do
  def nav_groups
    described_class.new.send(:nav_groups)
  end

  def nav_items
    nav_groups.flat_map { |group| group[:items] }
  end

  it "routes every item it offers" do
    unrouted = nav_items.reject { |item| item[:href].present? }

    expect(unrouted).to be_empty
  end

  it "no longer offers Chat" do
    expect(nav_items.map { |item| item[:key] }).not_to include(:chat)
  end

  # Its group held Chat and Replays; with Chat gone, a group labelled
  # "Conversations" holding one replay list describes neither.
  it "keeps Replays, under Tracing" do
    tracing = nav_groups.find { |group| group[:id] == :tracing }

    expect(tracing[:items].map { |item| item[:key] }).to include(:replays)
    expect(nav_groups.map { |group| group[:id] }).not_to include(:converse)
  end
end
