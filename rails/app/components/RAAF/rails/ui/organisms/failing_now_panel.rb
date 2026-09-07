# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # FailingNowPanel — the error signatures currently firing.
        #
        # Grouped by signature rather than listed per occurrence, so a single
        # noisy failure cannot crowd out the rest.
        #
        class FailingNowPanel < Base
          def initialize(groups:, action_href: nil, class: nil, **attrs)
            @groups = groups
            @action_href = action_href
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            render(Molecules::Panel.new(title: "Failing now", icon: "exclamation-octagon",
                                        action: ("All errors" if @action_href),
                                        action_href: @action_href, class: @class, **@attrs)) do
              if @groups.blank?
                render Molecules::EmptyState.new(icon: "check-circle", title: "Nothing failing",
                                                 text: "No error signatures in this range.")
              else
                @groups.each { |group| row(group) }
              end
            end
          end

          private

          def row(group)
            a(href: group[:href] || "#", class: "raaf-fail-row") do
              div(class: "raaf-fail-head") do
                render Atoms::KindBadge.new(group[:kind]) if group[:kind]
                span(class: "raaf-fail-agent") { group[:agent] }
                render Atoms::Mono.new(group[:count], tone: :bad)
              end

              div(class: "raaf-fail-message") { group[:message] }
              div(class: "raaf-fail-meta") { group[:meta] } if group[:meta]
            end
          end
        end
      end
    end
  end
end
