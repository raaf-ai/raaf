# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class PolicyList < RAAF::Rails::Tracing::BaseComponent

        def initialize(policies:, page: 1, per_page: 25)
          @policies = policies
          @page = page
          @per_page = per_page
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_policies_table
            render_pagination if @policies.respond_to?(:total_pages)
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { "Continuous Evaluation Policies" }
              p(class: "mt-1 text-sm text-gray-500") { "Configure automatic evaluation of agent spans in production" }
            end

            div(class: "mt-4 sm:mt-0 flex gap-2") do
              render_preline_button(
                text: "New Policy",
                href: new_continuous_policy_path,
                variant: "primary",
                icon: "bi-plus-lg"
              )
            end
          end
        end

        def render_policies_table
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            if @policies.any?
              div(class: "overflow-x-auto") do
                table(class: "min-w-full divide-y divide-gray-200") do
                  thead(class: "bg-gray-50") do
                    tr do
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Name" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Agent" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Environment" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Sampling" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Status" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Today's Evals" }
                      th(class: "px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider") { "Actions" }
                    end
                  end
                  tbody(class: "bg-white divide-y divide-gray-200") do
                    @policies.each do |policy|
                      render_policy_row(policy)
                    end
                  end
                end
              end
            else
              render_empty_state
            end
          end
        end

        def render_empty_state
          div(class: "flex flex-col items-center justify-center py-12") do
            i(class: "bi bi-shield-check text-5xl text-gray-400")
            h3(class: "mt-4 text-lg font-medium text-gray-900") { "No policies configured" }
            p(class: "mt-1 text-sm text-gray-500") { "Create your first continuous evaluation policy to start monitoring agent quality." }
            div(class: "mt-4") do
              render_preline_button(
                text: "Create Policy",
                href: new_continuous_policy_path,
                variant: "primary",
                icon: "bi-plus-lg"
              )
            end
          end
        end

        def render_policy_row(policy)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-4 text-sm") do
              div do
                span(class: "font-medium text-gray-900") { policy.name }
                if policy.description.present?
                  p(class: "mt-1 text-gray-500 text-xs") { policy.description }
                end
              end
            end

            td(class: "px-4 py-4 text-sm") do
              if policy.agent_name.present?
                # Split comma-separated agent names and render each as a separate badge
                agent_names = policy.agent_name.split(",").map(&:strip)
                div(class: "flex flex-wrap gap-1") do
                  agent_names.each do |name|
                    render_badge(name, "blue")
                  end
                end
              else
                span(class: "text-gray-400") { "All agents" }
              end
            end

            td(class: "px-4 py-4 text-sm") do
              render_badge(policy.environment || "all", "gray")
            end

            td(class: "px-4 py-4 text-sm") do
              render_sampling_info(policy)
            end

            td(class: "px-4 py-4 text-sm") do
              render_status_indicator(policy)
            end

            td(class: "px-4 py-4 text-sm") do
              render_daily_usage(policy)
            end

            td(class: "px-4 py-4 text-sm text-right") do
              render_actions(policy)
            end
          end
        end

        def render_sampling_info(policy)
          case policy.sampling_mode
          when 'percentage'
            div(class: "text-gray-900") do
              span(class: "font-medium") { "#{policy.sample_rate}%" }
              span(class: "text-gray-500") { " of spans" }
            end
          when 'every_n'
            div(class: "text-gray-900") do
              span(class: "text-gray-500") { "Every " }
              span(class: "font-medium") { policy.sample_every_n.to_s }
              span(class: "text-gray-500") { "th span" }
            end
          when 'all'
            render_badge("All spans", "blue")
          else
            span(class: "text-gray-400") { "Not configured" }
          end
        end

        def render_status_indicator(policy)
          if policy.active?
            span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800") do
              i(class: "bi bi-check-circle mr-1")
              plain "Active"
            end
          else
            span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800") do
              i(class: "bi bi-pause-circle mr-1")
              plain "Inactive"
            end
          end
        end

        def render_daily_usage(policy)
          if policy.respond_to?(:today_evaluation_count)
            count = policy.today_evaluation_count || 0
            limit = policy.max_daily_evaluations

            if limit
              percentage = (count.to_f / limit * 100).round
              badge_color = if percentage >= 90
                              "red"
                            elsif percentage >= 70
                              "yellow"
                            else
                              "green"
                            end
              render_badge("#{count} / #{limit}", badge_color)
            else
              span(class: "text-gray-900") { count.to_s }
            end
          else
            span(class: "text-gray-400") { "N/A" }
          end
        end

        def render_actions(policy)
          div(class: "flex items-center justify-end gap-2") do
            link_to(
              "View",
              continuous_policy_path(policy),
              class: "text-blue-600 hover:text-blue-800 text-sm font-medium"
            )
            link_to(
              "Edit",
              edit_continuous_policy_path(policy),
              class: "text-gray-600 hover:text-gray-800 text-sm font-medium"
            )

            if policy.active?
              button_to(
                "Deactivate",
                deactivate_continuous_policy_path(policy),
                method: :patch,
                class: "text-yellow-600 hover:text-yellow-800 text-sm font-medium",
                data: { confirm: "Deactivate this policy?" }
              )
            else
              button_to(
                "Activate",
                activate_continuous_policy_path(policy),
                method: :patch,
                class: "text-green-600 hover:text-green-800 text-sm font-medium"
              )
            end

            button_to(
              "Delete",
              continuous_policy_path(policy),
              method: :delete,
              class: "text-red-600 hover:text-red-800 text-sm font-medium",
              data: { confirm: "Are you sure? This will delete all associated queue items and results." }
            )
          end
        end

        def render_badge(text, color)
          color_classes = case color
                         when "blue" then "bg-blue-100 text-blue-800"
                         when "green" then "bg-green-100 text-green-800"
                         when "red" then "bg-red-100 text-red-800"
                         when "yellow" then "bg-yellow-100 text-yellow-800"
                         when "gray" then "bg-gray-100 text-gray-800"
                         else "bg-gray-100 text-gray-800"
                         end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{color_classes}") do
            text
          end
        end

        def render_pagination
          div(class: "flex items-center justify-between px-4 py-3 border-t border-gray-200") do
            div do
              span(class: "text-sm text-gray-500") { "Page #{@page} of #{@policies.total_pages}" }
            end
            div do
              # Pagination links would go here
            end
          end
        end
      end
    end
  end
end
