# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # HeroHeader — the banner at the top of a page.
        #
        # @example
        #   render(Organisms::HeroHeader.new(
        #     eyebrow: "Tracing", title: trace.workflow_name,
        #     subtitle: "#{trace.spans.count} spans"
        #   )) { render Atoms::Button.new(label: "Replay", icon: "arrow-repeat") }
        #
        class HeroHeader < Base
          # @param title [String]
          # @param eyebrow [String, nil] uppercase kicker above the title
          # @param subtitle [String, nil]
          def initialize(title:, eyebrow: nil, subtitle: nil, class: nil, **attrs)
            @title = title
            @eyebrow = eyebrow
            @subtitle = subtitle
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: tokens("raaf-hero", @class), **@attrs) do
              div(class: "raaf-hero-body") do
                div(class: "raaf-hero-eyebrow") { @eyebrow } if @eyebrow
                h1(class: "raaf-hero-title") { @title }
                p(class: "raaf-hero-subtitle") { @subtitle } if @subtitle
              end

              div(class: "raaf-hero-actions", &block) if block
            end
          end
        end
      end
    end
  end
end
