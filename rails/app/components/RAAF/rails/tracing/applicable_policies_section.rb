# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      # Component that displays applicable evaluation policies for a span
      # and allows users to manually trigger evaluation
      class ApplicablePoliciesSection < BaseComponent
        def initialize(span:)
          @span = span
          @matching_policies = find_matching_policies
          @existing_results = find_existing_results
        end

        def view_template
          return unless continuous_evaluation_available?

          div(id: "evaluation-policies", class: "bg-white border border-gray-200 rounded-lg shadow-sm") do
            render_header
            render_content
          end
        end

        private

        def continuous_evaluation_available?
          defined?(RAAF::Eval::Continuous::PolicyMatcher) &&
            defined?(RAAF::Eval::Models::EvaluationPolicy)
        end

        def find_matching_policies
          return [] unless continuous_evaluation_available?

          matcher = RAAF::Eval::Continuous::PolicyMatcher.new(@span)
          matcher.matching_policies
        rescue StandardError => e
          ::Rails.logger.warn "[ApplicablePoliciesSection] Error finding policies: #{e.message}"
          []
        end

        def find_existing_results
          return [] unless defined?(RAAF::Eval::Models::ContinuousEvaluationResult)

          RAAF::Eval::Models::ContinuousEvaluationResult
            .where(span_id: @span.span_id)
            .includes(:evaluation_policy)
            .order(created_at: :desc)
            .limit(10)
        rescue StandardError
          []
        end

        def render_header
          div(class: "px-4 py-3 border-b border-gray-200 bg-gray-50 rounded-t-lg") do
            div(class: "flex items-center justify-between") do
              div(class: "flex items-center gap-2") do
                i(class: "bi-clipboard-check text-indigo-600")
                span(class: "text-sm font-semibold text-gray-900") { "Evaluation Policies" }
                if @matching_policies.any?
                  span(class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-indigo-100 text-indigo-800") do
                    "#{@matching_policies.count} applicable"
                  end
                end
              end
            end
          end
        end

        def render_content
          div(class: "p-4 space-y-4") do
            if @matching_policies.empty?
              render_no_policies_message
            else
              render_policies_list
            end

            render_existing_results if @existing_results.any?
          end
        end

        def render_no_policies_message
          div(class: "text-center py-6") do
            i(class: "bi-info-circle text-gray-400 text-2xl mb-2")
            p(class: "text-sm text-gray-500") { "No evaluation policies match this span." }
            p(class: "text-xs text-gray-400 mt-1") do
              "Create a policy targeting agent "
              code(class: "bg-gray-100 px-1 rounded") { extract_agent_name }
              plain " to enable evaluation."
            end
            a(
              href: continuous_policies_path,
              class: "inline-flex items-center gap-1 mt-3 text-sm text-indigo-600 hover:text-indigo-800"
            ) do
              i(class: "bi-plus-circle")
              plain "Create Policy"
            end
          end
        end

        def render_policies_list
          div(class: "space-y-3") do
            @matching_policies.each do |policy|
              render_policy_card(policy)
            end
          end
        end

        def render_policy_card(policy)
          existing_result = @existing_results.find { |r| r.evaluation_policy_id == policy.id }
          queue_item = find_queue_item(policy)

          div(class: "border border-gray-200 rounded-lg p-3 hover:border-indigo-300 transition-colors") do
            div(class: "flex items-start justify-between gap-3") do
              # Policy info
              div(class: "flex-1 min-w-0") do
                div(class: "flex items-center gap-2") do
                  span(class: "font-medium text-gray-900 truncate") { policy.name }
                  render_policy_status_badge(policy)
                end

                if policy.description.present?
                  p(class: "text-xs text-gray-500 mt-1 line-clamp-2") { policy.description }
                end

                # Show evaluators
                evaluator_names = policy.evaluators&.map { |e| e["name"] || e[:name] }&.compact || []
                if evaluator_names.any?
                  div(class: "flex flex-wrap gap-1 mt-2") do
                    evaluator_names.first(3).each do |name|
                      span(class: "inline-flex items-center px-1.5 py-0.5 rounded text-xs bg-gray-100 text-gray-600") do
                        name.to_s.humanize
                      end
                    end
                    if evaluator_names.count > 3
                      span(class: "text-xs text-gray-400") { "+#{evaluator_names.count - 3} more" }
                    end
                  end
                end
              end

              # Actions
              div(class: "flex-shrink-0") do
                if queue_item&.status == "running"
                  render_running_indicator
                elsif queue_item&.status == "pending"
                  render_pending_indicator
                else
                  render_evaluate_button(policy, existing_result)
                end
              end
            end

          end
        end

        def render_policy_status_badge(policy)
          if policy.active?
            span(class: "inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800") do
              "Active"
            end
          else
            span(class: "inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-600") do
              "Inactive"
            end
          end
        end

        def render_evaluate_button(policy, existing_result)
          button_text = existing_result ? "Re-evaluate" : "Evaluate"
          button_class = existing_result ? "text-gray-700 bg-gray-100 hover:bg-gray-200" : "text-white bg-indigo-600 hover:bg-indigo-700"

          form(
            action: evaluate_tracing_span_path(@span.span_id, policy_id: policy.id),
            method: "post",
            data: { turbo: true }
          ) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            button(
              type: "submit",
              class: "inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md transition-colors #{button_class}"
            ) do
              i(class: "bi-play-fill")
              plain button_text
            end
          end
        end

        def render_running_indicator
          div(class: "inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-amber-700 bg-amber-100 rounded-md") do
            div(class: "animate-spin h-3 w-3 border-2 border-amber-700 border-t-transparent rounded-full")
            plain "Running..."
          end
        end

        def render_pending_indicator
          div(class: "inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-blue-700 bg-blue-100 rounded-md") do
            i(class: "bi-hourglass-split")
            plain "Pending"
          end
        end

        def render_existing_results
          div(class: "border-t border-gray-200 pt-4 mt-4") do
            render RAAF::Rails::Continuous::RecentResultsPanel.new(
              results: @existing_results,
              title: "Recent Evaluation Results",
              limit: 5,
              show_evaluator: false,
              embedded: true
            )
          end
        end

        def find_queue_item(policy)
          return nil unless defined?(RAAF::Eval::Models::EvaluationQueueItem)

          RAAF::Eval::Models::EvaluationQueueItem
            .where(span_id: @span.span_id, policy_id: policy.id)
            .where(status: %w[pending running])
            .order(created_at: :desc)
            .first
        rescue StandardError
          nil
        end

        def extract_agent_name
          @span.span_attributes&.dig("agent", "name") ||
            @span.span_attributes&.dig("agent.name") ||
            @span.name&.gsub(/^agent[\.\:]\s*/i, '') ||
            "Unknown"
        end
      end
    end
  end
end
