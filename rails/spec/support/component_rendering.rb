# frozen_string_literal: true

# Capybara for its matchers over a rendered string, not for a browser: this gem
# drives no JavaScript and boots no server.
require "capybara"

# Renders a Phlex component to a string.
#
# Phlex 1 shipped `Phlex::Testing::ViewHelper` for this; Phlex 2 dropped it, and
# with it every component spec that required the file. The components here reach
# for Rails helpers -- `pluralize`, `time_ago_in_words`, `truncate` -- and
# phlex-rails resolves those through the view context it finds under
# `:rails_view_context`, so one is put there.
module ComponentRendering
  def render(component, &)
    component.call(context: { rails_view_context: component_view_context }, &)
  end

  # The ViewComponent-shaped half of the same thing: render, then make Capybara
  # matchers (`have_css`, `have_content`) available over the result.
  def render_inline(component, &)
    @rendered_component = Capybara.string(render(component, &))
  end

  attr_reader :rendered_component

  alias page rendered_component

  # `ActionView::Base.empty` has no controller behind it, so the CSRF helper
  # every screen with a button reaches for is missing. Screens that post
  # something -- pausing a policy, running an evaluation -- cannot render at all
  # without it, and the token's value is nothing a component spec is about.
  def component_view_context
    @component_view_context ||= ActionView::Base.empty.tap do |context|
      context.define_singleton_method(:form_authenticity_token) { |*| "test-csrf-token" }
    end
  end
end

RSpec.configure do |config|
  config.include ComponentRendering, type: :component
  config.define_derived_metadata(file_path: %r{/spec/components/}) do |metadata|
    metadata[:type] = :component
  end
end
