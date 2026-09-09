# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # What changed between two versions of a prompt.
      #
      # It used to render both versions in full, side by side, one tinted red
      # and one tinted green, with two dots underneath saying whether content
      # and model had changed. On a 400-line system prompt that tells the
      # reader something changed and leaves them to find it.
      #
      # It renders a line-level diff now, through the same diff2html bundle
      # the Replay screen uses — the controller asks for `bundles: [:diff]`,
      # and the `diff` Stimulus controller takes the two strings and draws
      # them.
      #
      class PromptDiff < RAAF::Rails::Tracing::BaseComponent
        def initialize(prompt:, diff:)
          @prompt = prompt
          @diff = diff
        end

        def view_template
          div(class: "raaf-page") do
            header
            @diff ? body : missing
          end
        end

        private

        def header
          render Organisms::RecordHead.new(
            parent: { label: @prompt.name, href: eval_prompt_path(@prompt) },
            title: title,
            description: @diff && summary,
            meta: @diff && model_line
          )
        end

        def title
          return "Diff" unless @diff

          "v#{@diff[:from][:version]} → v#{@diff[:to][:version]}"
        end

        # The two dots the old screen printed said "content changed" and
        # "model changed" beside a diff that shows the first of those. Only
        # the model is worth stating, because it is the one change a
        # line-level comparison of the wording cannot show.
        def summary
          return "The wording is identical between these two versions." unless @diff[:content_changed]

          "The wording changed. The comparison below is line by line."
        end

        def model_line
          from = @diff[:from][:model].presence || "no model"
          to = @diff[:to][:model].presence || "no model"

          @diff[:model_changed] ? "model #{from} → #{to}" : "model #{to}, unchanged"
        end

        def body
          render(Organisms::Card.new(title: "Difference", flush: true)) do
            div(data: { controller: "diff",
                        diff_original_value: @diff[:from][:content].to_s,
                        diff_replayed_value: @diff[:to][:content].to_s,
                        diff_output_style_value: "side-by-side" }) do
              toolbar
              div(class: "raaf-diff-surface", data: { diff_target: "container" }) do
                render Atoms::Text.new("Rendering the difference…", tone: :muted)
              end
            end
          end
        end

        def toolbar
          div(class: "raaf-diff-toolbar") do
            nav(class: "raaf-tabs", role: "tablist") do
              style_tab("Side by side", "side-by-side", active: true)
              style_tab("Unified", "line-by-line", active: false)
            end
          end
        end

        def style_tab(label, style, active:)
          button(type: "button", role: "tab",
                 class: "raaf-tab#{' is-active' if active}",
                 "aria-selected": active ? "true" : "false",
                 data: { action: "click->diff#toggleView", diff_output_style_param: style }) do
            span { label }
          end
        end

        def missing
          render Molecules::EmptyState.new(
            icon: "file-diff", title: "Nothing to compare",
            text: "Both versions have to exist. Pick two from the prompt's version history."
          )
        end
      end
    end
  end
end
