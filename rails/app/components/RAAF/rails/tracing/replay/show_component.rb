# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Replay
        # Component for displaying replay results and comparison view
        #
        # Shows side-by-side comparison of original and replayed spans
        # with configuration changes, output diff, and performance metrics.
        class ShowComponent < BaseComponent
          def initialize(replay:, original_span:)
            @replay = replay
            @original_span = original_span
            @replayed_span = replay.replayed_span
          end

          def view_template
            div(class: "space-y-6") do
              render_header
              render_status_banner unless @replay.completed?

              if @replay.completed? && @replayed_span
                render_comparison_view
              elsif @replay.failed?
                render_error_view
              else
                render_pending_view
              end
            end
          end

          private

          def render_header
            div(class: "flex items-center justify-between") do
              div do
                # Breadcrumb
                nav(class: "flex text-sm text-gray-500 mb-2") do
                  a(href: tracing_spans_path, class: "hover:text-gray-700") { "Spans" }
                  span(class: "mx-2") { "/" }
                  a(href: tracing_span_path(@original_span.span_id), class: "hover:text-gray-700") do
                    @original_span.display_name
                  end
                  span(class: "mx-2") { "/" }
                  a(href: tracing_span_replays_path(@original_span.span_id), class: "hover:text-gray-700") do
                    "Replays"
                  end
                  span(class: "mx-2") { "/" }
                  span(class: "text-gray-900") { "Replay ##{@replay.id}" }
                end

                h1(class: "text-2xl font-bold text-gray-900") do
                  "Replay Results"
                end
                if @replay.notes.present?
                  p(class: "mt-1 text-sm text-gray-500") { @replay.notes }
                end
              end

              # Actions
              div(class: "flex items-center gap-3") do
                a(
                  href: new_tracing_span_replay_path(@original_span.span_id),
                  class: "inline-flex items-center px-4 py-2 border border-gray-300 rounded-lg text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                ) do
                  i(class: "bi bi-arrow-repeat mr-2")
                  plain "New Replay"
                end
              end
            end
          end

          def render_status_banner
            status_config = case @replay.status
                           when "pending"
                             { bg: "bg-yellow-50", border: "border-yellow-200", icon: "bi-hourglass-split", color: "text-yellow-800", message: "Replay is queued and waiting to be processed..." }
                           when "running"
                             { bg: "bg-blue-50", border: "border-blue-200", icon: "bi-arrow-repeat", color: "text-blue-800", message: "Replay is currently running..." }
                           when "failed"
                             { bg: "bg-red-50", border: "border-red-200", icon: "bi-exclamation-triangle", color: "text-red-800", message: "Replay failed" }
                           end

            div(class: "#{status_config[:bg]} #{status_config[:border]} border rounded-xl p-4") do
              div(class: "flex items-center") do
                i(class: "bi #{status_config[:icon]} #{status_config[:color]} text-xl mr-3")
                div do
                  span(class: "font-medium #{status_config[:color]}") { status_config[:message] }
                  if @replay.running?
                    span(class: "ml-2 text-sm #{status_config[:color]}") { "This page will update automatically." }
                  end
                end
              end
            end
          end

          def render_comparison_view
            # Metrics comparison cards
            render_metrics_comparison

            # Tab navigation for different views
            div(class: "bg-white rounded-xl border border-gray-200 shadow-sm", data: { controller: "tabs" }) do
              # Tab buttons
              div(class: "border-b border-gray-200") do
                nav(class: "flex -mb-px") do
                  render_tab_button("side-by-side", "Side-by-Side", true)
                  render_tab_button("config-changes", "Configuration", false)
                  render_tab_button("sequential", "Sequential", false)
                end
              end

              # Tab content
              div(class: "p-6") do
                render_side_by_side_tab
                render_config_changes_tab
                render_sequential_tab
              end
            end
          end

          def render_tab_button(id, label, active)
            button(
              type: "button",
              class: "px-4 py-3 text-sm font-medium border-b-2 #{active ? 'border-blue-500 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700'}",
              data: {
                tabs_target: "tab",
                action: "click->tabs#select",
                tab_id: id
              }
            ) { label }
          end

          def render_metrics_comparison
            div(class: "grid grid-cols-1 md:grid-cols-4 gap-4 mb-6") do
              # Duration comparison
              duration_data = @replay.duration_comparison
              render_metric_comparison_card(
                title: "Duration",
                original: format_duration(@original_span.duration_ms),
                replayed: format_duration(@replayed_span&.duration_ms),
                delta: duration_data&.dig(:percentage_change),
                icon: "bi-stopwatch"
              )

              # Token comparison (input)
              original_input_tokens = @original_span.span_attributes&.dig("llm", "usage", "input_tokens") || 0
              replayed_input_tokens = @replayed_span&.span_attributes&.dig("llm", "usage", "input_tokens") || 0
              render_metric_comparison_card(
                title: "Input Tokens",
                original: original_input_tokens.to_s,
                replayed: replayed_input_tokens.to_s,
                delta: calculate_delta(original_input_tokens, replayed_input_tokens),
                icon: "bi-box-arrow-in-right"
              )

              # Token comparison (output)
              original_output_tokens = @original_span.span_attributes&.dig("llm", "usage", "output_tokens") || 0
              replayed_output_tokens = @replayed_span&.span_attributes&.dig("llm", "usage", "output_tokens") || 0
              render_metric_comparison_card(
                title: "Output Tokens",
                original: original_output_tokens.to_s,
                replayed: replayed_output_tokens.to_s,
                delta: calculate_delta(original_output_tokens, replayed_output_tokens),
                icon: "bi-box-arrow-right"
              )

              # Model used
              original_model = @original_span.span_attributes&.dig("llm", "request", "model") || "Unknown"
              replayed_model = @replayed_span&.span_attributes&.dig("llm", "request", "model") || "Unknown"
              render_metric_comparison_card(
                title: "Model",
                original: truncate_model_name(original_model),
                replayed: truncate_model_name(replayed_model),
                delta: original_model == replayed_model ? nil : "changed",
                icon: "bi-cpu"
              )
            end
          end

          def render_metric_comparison_card(title:, original:, replayed:, delta:, icon:)
            div(class: "bg-white rounded-xl border border-gray-200 shadow-sm p-4") do
              div(class: "flex items-center gap-2 mb-3") do
                i(class: "bi #{icon} text-gray-400")
                span(class: "text-xs font-semibold text-gray-500 uppercase tracking-wider") { title }
              end

              div(class: "grid grid-cols-2 gap-4") do
                div do
                  span(class: "text-xs text-gray-400 block") { "Original" }
                  span(class: "text-lg font-semibold text-gray-900") { original }
                end
                div do
                  span(class: "text-xs text-gray-400 block") { "Replayed" }
                  span(class: "text-lg font-semibold text-gray-900") { replayed }
                end
              end

              if delta.present?
                render_delta_badge(delta)
              end
            end
          end

          def render_delta_badge(delta)
            return if delta.nil?

            if delta.is_a?(String)
              span(class: "mt-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800") do
                delta
              end
            elsif delta > 0
              span(class: "mt-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800") do
                "+#{delta.round(1)}%"
              end
            elsif delta < 0
              span(class: "mt-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800") do
                "#{delta.round(1)}%"
              end
            end
          end

          def render_side_by_side_tab
            original_output = extract_output(@original_span) || ""
            replayed_output = extract_output(@replayed_span) || ""

            div(data: { tabs_target: "panel", tab_id: "side-by-side" }) do
              # Diff container with controller (includes toggle buttons)
              div(
                data: {
                  controller: "diff",
                  diff_original_value: original_output,
                  diff_replayed_value: replayed_output,
                  diff_output_style_value: "side-by-side"
                }
              ) do
                # View toggle (inside controller scope)
                div(class: "flex justify-end mb-4") do
                  div(class: "inline-flex rounded-lg border border-gray-200 bg-white p-1") do
                    button(
                      type: "button",
                      class: "px-3 py-1.5 text-sm font-medium rounded-md bg-blue-100 text-blue-700",
                      data: { action: "click->diff#toggleView", diff_output_style_param: "side-by-side" }
                    ) { "Side by Side" }
                    button(
                      type: "button",
                      class: "px-3 py-1.5 text-sm font-medium rounded-md text-gray-600 hover:bg-gray-100",
                      data: { action: "click->diff#toggleView", diff_output_style_param: "line-by-line" }
                    ) { "Unified" }
                  end
                end

                # Diff output container
                div(
                  class: "bg-white rounded-lg border border-gray-200 overflow-hidden",
                  data: { diff_target: "container" }
                ) do
                  # Placeholder while diff renders
                  div(class: "p-4 text-gray-500") { "Loading diff..." }
                end
              end
            end
          end

          def render_config_changes_tab
            div(class: "hidden", data: { tabs_target: "panel", tab_id: "config-changes" }) do
              if @replay.configuration_changes.present?
                div(class: "space-y-4") do
                  @replay.configuration_changes.each do |key, value|
                    div(class: "flex items-center justify-between py-2 border-b border-gray-100") do
                      span(class: "text-sm font-medium text-gray-700") { key.to_s.titleize }
                      div(class: "flex items-center gap-2") do
                        span(class: "text-sm text-gray-500 line-through") do
                          original_value_for(key)
                        end
                        i(class: "bi bi-arrow-right text-gray-400")
                        span(class: "text-sm font-medium text-blue-600") { value.to_s }
                      end
                    end
                  end
                end
              else
                p(class: "text-sm text-gray-500 italic") { "No configuration changes were made." }
              end

              # System prompt changes
              if @replay.system_prompt.present?
                div(class: "mt-6") do
                  h4(class: "text-sm font-medium text-gray-700 mb-2") { "System Prompt (Modified)" }
                  div(class: "bg-gray-50 rounded-lg p-4 font-mono text-sm whitespace-pre-wrap") do
                    @replay.system_prompt
                  end
                end
              end
            end
          end

          def render_sequential_tab
            div(class: "hidden", data: { tabs_target: "panel", tab_id: "sequential" }) do
              div(class: "space-y-6") do
                # Original span card
                div(class: "bg-white rounded-lg border border-gray-200 p-4") do
                  div(class: "flex items-center justify-between mb-3") do
                    div(class: "flex items-center gap-2") do
                      span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800") do
                        "Original"
                      end
                      span(class: "text-sm text-gray-500") { @original_span.start_time&.strftime("%Y-%m-%d %H:%M:%S") }
                    end
                    a(
                      href: tracing_span_path(@original_span.span_id),
                      class: "text-sm text-blue-600 hover:text-blue-800"
                    ) { "View Details →" }
                  end
                  div(class: "bg-gray-50 rounded p-3 font-mono text-sm whitespace-pre-wrap max-h-48 overflow-y-auto") do
                    extract_output(@original_span) || "No output"
                  end
                end

                # Arrow
                div(class: "flex justify-center") do
                  i(class: "bi bi-arrow-down text-2xl text-gray-400")
                end

                # Replayed span card
                div(class: "bg-white rounded-lg border border-blue-200 p-4") do
                  div(class: "flex items-center justify-between mb-3") do
                    div(class: "flex items-center gap-2") do
                      span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800") do
                        "Replayed"
                      end
                      span(class: "text-sm text-gray-500") { @replayed_span&.start_time&.strftime("%Y-%m-%d %H:%M:%S") }
                    end
                    if @replayed_span
                      a(
                        href: tracing_span_path(@replayed_span.span_id),
                        class: "text-sm text-blue-600 hover:text-blue-800"
                      ) { "View Details →" }
                    end
                  end
                  div(class: "bg-blue-50 rounded p-3 font-mono text-sm whitespace-pre-wrap max-h-48 overflow-y-auto") do
                    extract_output(@replayed_span) || "No output"
                  end
                end
              end
            end
          end

          def render_error_view
            div(class: "bg-red-50 border border-red-200 rounded-xl p-6") do
              div(class: "flex items-start") do
                i(class: "bi bi-exclamation-triangle text-red-600 text-2xl mr-4")
                div do
                  h3(class: "text-lg font-medium text-red-800") { "Replay Failed" }
                  p(class: "mt-1 text-sm text-red-700") { @replay.error_message || "An unknown error occurred." }

                  div(class: "mt-4") do
                    a(
                      href: new_tracing_span_replay_path(@original_span.span_id),
                      class: "inline-flex items-center px-4 py-2 border border-red-300 rounded-lg text-sm font-medium text-red-700 bg-white hover:bg-red-50"
                    ) do
                      i(class: "bi bi-arrow-repeat mr-2")
                      plain "Try Again"
                    end
                  end
                end
              end
            end
          end

          def render_pending_view
            div(
              class: "bg-gray-50 border border-gray-200 rounded-xl p-8 text-center",
              id: "replay-status",
              data: { controller: "poll", poll_url_value: tracing_span_replay_path(@original_span.span_id, @replay.id), poll_interval_value: "2000" }
            ) do
              div(class: "inline-flex items-center justify-center w-12 h-12 bg-blue-100 rounded-full mb-4") do
                i(class: "bi bi-hourglass-split text-blue-600 text-xl animate-spin")
              end
              h3(class: "text-lg font-medium text-gray-900") { "Processing Replay..." }
              p(class: "mt-1 text-sm text-gray-500") do
                "Your replay is being processed. This page will update automatically when complete."
              end
            end
          end

          # Helper methods

          def extract_output(span)
            return nil unless span

            attrs = span.span_attributes || {}

            # Check all possible output locations (flat and nested paths) with logging
            content = nil
            source_key = nil

            if attrs["agent.final_agent_response"]
              content = attrs["agent.final_agent_response"]
              source_key = "agent.final_agent_response"
            elsif attrs["final_agent_response"]
              content = attrs["final_agent_response"]
              source_key = "final_agent_response"
            elsif attrs["response.content"]
              content = attrs["response.content"]
              source_key = "response.content"
            elsif attrs["llm.response.content"]
              content = attrs["llm.response.content"]
              source_key = "llm.response.content"
            elsif attrs.dig("llm", "response", "content")
              content = attrs.dig("llm", "response", "content")
              source_key = "llm.response.content (nested)"
            elsif attrs.dig("llm", "response", "choices", 0, "message", "content")
              content = attrs.dig("llm", "response", "choices", 0, "message", "content")
              source_key = "llm.response.choices[0].message.content"
            elsif attrs.dig("agent", "final_agent_response")
              content = attrs.dig("agent", "final_agent_response")
              source_key = "agent.final_agent_response (nested)"
            end

            ::Rails.logger.debug "[ShowComponent] extract_output for span #{span.span_id}: found at '#{source_key}', type: #{content.class}"

            # Pretty-print JSON for better diff comparison
            format_output_for_diff(content)
          end

          def format_output_for_diff(content)
            return "" if content.blank?

            ::Rails.logger.debug "[ShowComponent] format_output_for_diff input type: #{content.class}, preview: #{content.to_s[0..100]}"

            # If it's already a Hash/Array, pretty-print it
            if content.is_a?(Hash) || content.is_a?(Array)
              ::Rails.logger.debug "[ShowComponent] Content is Hash/Array, pretty-printing"
              return JSON.pretty_generate(content)
            end

            # Convert to string first
            str_content = content.to_s.strip

            # Strip markdown code fences if present
            str_content = str_content.gsub(/\A```(?:json)?\s*\n?/, "").gsub(/\n?\s*```\z/, "")

            ::Rails.logger.debug "[ShowComponent] After cleanup, first 100 chars: #{str_content[0..100]}"

            # Try to parse and pretty-print JSON
            begin
              parsed = JSON.parse(str_content)
              ::Rails.logger.debug "[ShowComponent] JSON parsed successfully, pretty-printing"
              JSON.pretty_generate(parsed)
            rescue JSON::ParserError => e
              ::Rails.logger.debug "[ShowComponent] JSON parse failed: #{e.message}"
              # Not valid JSON - but might be a Ruby hash/array string representation
              # Try to evaluate if it looks like a Ruby literal
              if str_content.start_with?("{") || str_content.start_with?("[")
                begin
                  # Convert Ruby hash syntax to JSON syntax
                  json_like = str_content.gsub(/:(\w+)=>/, '"\1":').gsub(/=>/, ':')
                  parsed = JSON.parse(json_like)
                  JSON.pretty_generate(parsed)
                rescue => e2
                  ::Rails.logger.debug "[ShowComponent] Ruby hash conversion also failed: #{e2.message}"
                  str_content
                end
              else
                str_content
              end
            end
          end

          def original_value_for(key)
            original_settings = @original_span.span_attributes&.dig("llm", "request") || {}
            original_settings[key.to_s] || "default"
          end

          def calculate_delta(original, replayed)
            return nil if original.zero? && replayed.zero?
            return 100.0 if original.zero?

            ((replayed - original).to_f / original * 100).round(1)
          end

          def truncate_model_name(model)
            return model if model.length <= 20

            "#{model[0..17]}..."
          end
        end
      end
    end
  end
end
