# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # One recorded feedback score.
      #
      # The header carries what was scored and what it scored; the list under
      # it carries the record's own fields. It rendered `bg-white` and
      # `text-gray-900` into the dark shell before this.
      #
      class FeedbackScoreShow < RAAF::Rails::Tracing::BaseComponent
        def initialize(score:)
          @score = score
        end

        def view_template
          div(class: "raaf-page") do
            header
            details
            reason_panel if @score.reason.present?
          end
        end

        private

        def header
          render Organisms::RecordHead.new(
            parent: { label: "Feedback scores", href: eval_feedback_scores_path },
            title: @score.name.to_s,
            mono: true,
            description: @score.reason.presence,
            meta: head_meta,
            stats: [{ label: "Value", value: value_text },
                    { label: "Type", value: @score.numerical? ? "numerical" : "categorical" }]
          )
        end

        def head_meta
          [@score.source.presence && "source #{@score.source}",
           @score.scored_by.presence && "by #{@score.scored_by}",
           @score.created_at&.strftime("%Y-%m-%d %H:%M:%S")].compact.join(" · ")
        end

        def value_text
          @score.numerical? ? @score.value.to_s : @score.category_value.to_s
        end

        def details
          render(Organisms::Card.new(title: "Record", flush: true)) do
            render Molecules::KeyValueList.new(pairs: pairs, layout: :rows, mono: true, flush: true)
          end
        end

        # The span or the trace, not both: a score is attached to one of them,
        # and printing an empty slot for the other reads as a missing link.
        def pairs
          {
            "Name" => @score.name.to_s,
            "Value" => value_text,
            target_label => target_id,
            "Source" => @score.source.presence || "—",
            "Scored by" => @score.scored_by.presence || "—",
            "Created" => @score.created_at&.strftime("%Y-%m-%d %H:%M:%S") || "—"
          }
        end

        def target_label
          @score.span_level? ? "Span" : "Trace"
        end

        def target_id
          @score.span_level? ? @score.span_id.to_s : @score.trace_id.to_s
        end

        # Prose, so it gets a panel of its own rather than a cell in a mono
        # list — a rater's sentence is the one part of this record written for
        # a person to read.
        def reason_panel
          render(Organisms::Card.new(title: "Reason")) do
            render Atoms::Text.new(@score.reason, tone: :secondary)
          end
        end
      end
    end
  end
end
