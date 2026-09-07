# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # PipelineSteps — a pipeline's declared steps and how hot each one runs.
        #
        # Each step is a `MeterRow` in its inline variant, with the step index
        # and kind chip in the row's lead slot. The bar is the step's share of
        # the pipeline's wall clock, so the slow step is visible without
        # reading a single figure.
        #
        # @example
        #   render Organisms::PipelineSteps.new(steps: [
        #     { kind: "tool", name: "crm_upsert", pct: 33,
        #       duration: "4.0s", error_rate: 8.1, tone: :bad }
        #   ])
        #
        class PipelineSteps < Base
          # @param steps [Array<Hash>] :kind, :name, :pct, :duration, :error_rate,
          #   :tone, :index, :href
          # @param empty [Hash, nil] arguments for Molecules::EmptyState
          def initialize(steps:, empty: nil, class: nil, **attrs)
            @steps = Array(steps)
            @empty = empty
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-pipeline", @class), **@attrs) do
              if @steps.empty?
                render Molecules::EmptyState.new(**(@empty || default_empty))
              else
                @steps.each_with_index { |step, i| row(step, i) }
              end
            end
          end

          private

          def default_empty
            { icon: "list-ol", title: "No declared steps",
              text: "This workflow has not reported a pipeline structure." }
          end

          def row(step, index)
            tone = step[:tone] || :ok

            render(Molecules::MeterRow.new(
                     name: step[:name],
                     value: step[:duration],
                     pct: step[:pct].to_f,
                     meta: error_rate(step),
                     tone: tone == :ok ? nil : tone,
                     value_tone: tone == :bad ? :bad : nil,
                     inline: true,
                     tip: tip(step),
                     class: tokens("raaf-pipeline-step", "raaf-pipeline-step--#{tone}")
                   )) do
              render Atoms::Mono.new(number(step, index), tone: :muted,
                                                          class: "raaf-pipeline-index")
              render Atoms::KindBadge.new(step[:kind])
            end
          end

          def number(step, index)
            step[:index] || ("%02d" % (index + 1))
          end

          # The bar is the step's share of the pipeline's wall clock, which the
          # row prints nowhere — the figure beside it is the step's own
          # duration, and the one after it the error rate.
          def tip(step)
            share = step[:pct].to_f

            [step[:name],
             step[:duration],
             share.positive? ? "#{share.round}% of the run" : nil,
             step[:error_rate] ? "#{error_rate(step)} errored" : nil].compact.join(" · ")
          end

          def error_rate(step)
            return nil unless step[:error_rate]

            "#{'%.1f' % step[:error_rate].to_f}%"
          end
        end
      end
    end
  end
end
