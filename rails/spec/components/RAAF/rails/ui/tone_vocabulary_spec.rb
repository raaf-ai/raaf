# frozen_string_literal: true

require "rails_helper"

# `modifier` raises on a variant a component does not understand, which catches
# any tone a spec actually renders. Most screens are not rendered by any spec,
# so this reads the source as well: a literal tone handed to a component whose
# vocabulary does not contain it is a wrong colour waiting for the first person
# to open that page.
#
# Two of these were live when the check was written. The policy form passed
# `Molecules::Alert.new(:danger, …)` — Alert's word is `error` — so validation
# errors rendered as bare text with no panel. The experiment comparison passed
# `:danger` to a `Mono` whose tones are ok/warn/bad, so every delta in its item
# table rendered colourless and a fall looked like an improvement.
RSpec.describe "the library's tone vocabularies" do
  COMPONENTS = File.expand_path("../../../../../app/components/RAAF/rails", __dir__)

  # Components whose vocabulary is a plain constant this check can read, and
  # which are handed a literal tone often enough to be worth policing.
  POLICED = {
    "Molecules::Alert" => RAAF::Rails::Ui::Molecules::Alert::VARIANTS,
    "Atoms::Mono" => RAAF::Rails::Ui::Atoms::Mono::TONES,
    "Atoms::Text" => RAAF::Rails::Ui::Atoms::Text::TONES,
    "Atoms::Icon" => RAAF::Rails::Ui::Atoms::Icon::TONES,
    "Atoms::ProgressBar" => RAAF::Rails::Ui::Atoms::ProgressBar::TONES
  }.freeze

  # `Alert` takes its variant positionally, every other one by keyword.
  PATTERNS = {
    "Molecules::Alert" => /Molecules::Alert\.new\(\s*:(\w+)/,
    "Atoms::Mono" => /Atoms::Mono\.new\([^)]*?tone:\s*:(\w+)/m,
    "Atoms::Text" => /Atoms::Text\.new\([^)]*?tone:\s*:(\w+)/m,
    "Atoms::Icon" => /Atoms::Icon\.new\([^)]*?tone:\s*:(\w+)/m,
    "Atoms::ProgressBar" => /Atoms::ProgressBar\.new\([^)]*?tone:\s*:(\w+)/m
  }.freeze

  def offenders
    Dir["#{COMPONENTS}/**/*.rb"].flat_map do |path|
      source = File.read(path)

      POLICED.flat_map do |component, allowed|
        source.scan(PATTERNS.fetch(component)).flatten
              .reject { |tone| allowed.include?(tone.to_sym) }
              .map { |tone| "#{path.split('app/components/').last}: #{component} :#{tone}" }
      end
    end
  end

  it "hands every component a tone it understands" do
    expect(offenders).to be_empty
  end
end
