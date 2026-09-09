# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # LiveRunsPanel — traces as they arrive.
        #
        class LiveRunsPanel < Base
          def initialize(traces:, action_href: nil, class: nil, **attrs)
            @traces = traces
            @action_href = action_href
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            render(Molecules::Panel.new(title: "Live runs", icon: "activity",
                                        action: ("all traces" if @action_href),
                                        action_href: @action_href, class: @class, **@attrs)) do
              if @traces.blank?
                render Molecules::EmptyState.new(icon: "inbox", title: "No runs yet")
              else
                @traces.each { |trace| row(trace) }
              end
            end
          end

          private

          # A panel titled Live has to say how live it is. Without a start
          # time its top row could as easily be from yesterday as from ten
          # seconds ago, and the duration beside it answers a different
          # question — how long the run took, not when it began.
          def row(trace)
            a(href: trace[:href] || "#", class: "raaf-run-row") do
              render Atoms::Dot.new(tone: trace[:tone] || :idle, pulse: trace[:tone] == :info)
              span(class: "raaf-run-name") { trace[:workflow] }
              span(class: "raaf-run-meta") { meta_line(trace) }
              render Atoms::Mono.new(trace[:duration], tone: :muted)
            end
          end

          def meta_line(trace)
            [trace[:started].presence, trace[:spans].presence].compact.join(" · ")
          end
        end
      end
    end
  end
end
