# frozen_string_literal: true

require "rails_helper"

# `modifier` returned nil for a variant it did not recognise, so a wrong tone
# rendered as no tone: the component came out styled as its base and nothing
# said otherwise. That is how the policy form came to print its validation
# errors as bare text — `Molecules::Alert.new(:danger, …)`, where Alert's
# vocabulary is `error`, produced an alert with a transparent border and no
# background.
#
# An unrecognised variant is always a mistake at the call site. It is loud now
# where a developer or CI will see it, and still quiet in production, where a
# missing modifier is a cosmetic fault and raising would turn it into a blank
# screen.
RSpec.describe RAAF::Rails::Ui::Base, type: :component do
  let(:component) { Class.new(described_class).new }

  def modifier(variant)
    component.send(:modifier, "raaf-alert", variant, %i[success info warning error])
  end

  describe "a variant the component understands" do
    it "maps onto its modifier class" do
      expect(modifier(:warning)).to eq("raaf-alert--warning")
    end

    it "accepts the string form and the underscored form alike" do
      expect(modifier("warning")).to eq("raaf-alert--warning")
      expect(component.send(:modifier, "raaf-chip", :is_active, %i[is-active]))
        .to eq("raaf-chip--is-active")
    end
  end

  # Not an error: every component treats a nil variant as "no modifier", and
  # most callers pass one.
  describe "no variant at all" do
    it "is silent" do
      expect(modifier(nil)).to be_nil
    end
  end

  describe "a variant the component does not understand" do
    it "says so, naming what was passed and what was available" do
      expect { modifier(:danger) }
        .to raise_error(ArgumentError, /danger.*raaf-alert.*success, info, warning, error/m)
    end

    # A cosmetic fault must not become a 500 in front of a user.
    it "degrades to no modifier in production, as it always did" do
      allow(::Rails.env).to receive(:production?).and_return(true)

      expect(modifier(:danger)).to be_nil
    end
  end
end
