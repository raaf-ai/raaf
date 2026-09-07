# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Every evaluator the registry can find, and whether anything grades with it.
      #
      # The route for this page existed from the start and rendered nothing:
      # the controller answered an HTML request with no template, so the list
      # was reachable only as JSON. What makes it worth rendering is the last
      # column — an evaluator no policy names is dead code that still looks
      # installed, and that is invisible from the policy side, where you can
      # only see the evaluators somebody already wired up.
      class EvaluatorList < RAAF::Rails::Tracing::BaseComponent
        def initialize(evaluators: [], policy_counts: {})
          @evaluators = evaluators
          @policy_counts = policy_counts
        end

        COLUMNS = [
          { label: "Evaluator", span: 2.2 },
          { label: "Type", span: 0.9 },
          { label: "Agent", span: 1.4 },
          { label: "Checks", span: 0.5, align: :right },
          { label: "Policies", span: 0.8, align: :right }
        ].freeze

        def view_template
          div(class: "raaf-page") do
            render(Organisms::Card.new(flush: true)) do
              render(Organisms::DataGrid.new(
                       columns: COLUMNS,
                       empty: { icon: "sliders", title: "No evaluators registered",
                                text: "Register evaluators before a policy can grade anything." }
                     )) do |grid|
                @evaluators.each { |evaluator| row(grid, evaluator) }
              end
            end
          end
        end

        private

        def row(grid, evaluator)
          name = evaluator[:name].to_s

          grid.row(href: continuous_evaluator_path(name), cells: [
                     { value: Molecules::TitleMeta.new(name, evaluator[:description], mono: true) },
                     { value: type_badge(evaluator[:type]) },
                     { value: Atoms::Mono.new(evaluator[:agent_name].presence || "any agent",
                                              tone: :muted) },
                     { value: Atoms::Mono.new(evaluator[:checks].to_a.size.to_s), align: :right },
                     { value: policy_count(name), align: :right }
                   ])
        end

        # Nothing grading with an evaluator is a finding, not a zero, so it is
        # said in words rather than left as a digit somebody has to notice.
        def policy_count(name)
          count = @policy_counts[name].to_i
          return Atoms::Badge.new("no policy", variant: :amber, size: :sm) if count.zero?

          Atoms::Mono.new(pluralize(count, "policy"), tone: :muted)
        end

        def type_badge(type)
          label = RAAF::Rails::Continuous::EvaluatorShow.format_type(type)
          return Atoms::Mono.new("—", tone: :muted) if label.nil?

          Atoms::Badge.new(label, variant: type_variant(type), size: :sm)
        end

        def type_variant(type)
          case type.to_s
          when "llm_judge" then :amber
          when "statistical" then :teal
          else :slate
          end
        end
      end
    end
  end
end
