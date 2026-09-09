# frozen_string_literal: true

require "rails_helper"

# The shell prints a crumb line and the page title. A screen that then prints
# its own breadcrumb says the same thing twice within two lines. RecordHead —
# with a parent link where the shell's crumb cannot name the parent — is the
# one heading treatment.
RSpec.describe "one heading per screen" do
  # Every screen the console renders into the shell, so a new one cannot
  # quietly reintroduce the second breadcrumb.
  SCREENS = Dir[File.expand_path("../../../../../app/components/RAAF/rails/**/*.rb", __dir__)]

  # The library's own definition, the shell's topbar, and the style guide that
  # exists to render every component once.
  ALLOWED = %w[molecules/breadcrumb.rb organisms/topbar.rb ui/style_guide.rb].freeze

  it "renders no in-page breadcrumb on any screen" do
    offenders = SCREENS.reject { |path| ALLOWED.any? { |tail| path.end_with?(tail) } }
                       .select { |path| File.read(path).include?("Molecules::Breadcrumb") }
                       .map { |path| path.split("app/components/").last }

    expect(offenders).to be_empty
  end
end
