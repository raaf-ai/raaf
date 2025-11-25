# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class PolicyList < Phlex::HTML
        include Phlex::Rails::Helpers::LinkTo
        include Phlex::Rails::Helpers::ButtonTo
        include Phlex::Rails::Helpers::Pluralize

        def initialize(policies:, page: 1, per_page: 25)
          @policies = policies
          @page = page
          @per_page = per_page
        end

        def view_template
          div(class: "container-fluid") do
            render_header
            render_policies_table
            render_pagination if @policies.respond_to?(:total_pages)
          end
        end

        private

        def render_header
          div(class: "d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom") do
            div do
              h1(class: "h2") { "Continuous Evaluation Policies" }
              p(class: "text-muted") { "Configure automatic evaluation of agent spans in production" }
            end

            div(class: "btn-toolbar mb-2 mb-md-0") do
              div(class: "btn-group me-2") do
                link_to("New Policy", new_continuous_policy_path, class: "btn btn-sm btn-primary")
              end
            end
          end
        end

        def render_policies_table
          div(class: "card") do
            div(class: "card-body") do
              if @policies.any?
                div(class: "table-responsive") do
                  table(class: "table table-sm table-hover") do
                    thead do
                      tr do
                        th { "Name" }
                        th { "Agent" }
                        th { "Environment" }
                        th { "Sampling" }
                        th { "Status" }
                        th { "Today's Evals" }
                        th(class: "text-end") { "Actions" }
                      end
                    end
                    tbody do
                      @policies.each do |policy|
                        render_policy_row(policy)
                      end
                    end
                  end
                end
              else
                div(class: "text-center py-5") do
                  i(class: "bi bi-shield-check display-4 text-muted")
                  h3(class: "mt-3") { "No policies configured" }
                  p(class: "text-muted") { "Create your first continuous evaluation policy to start monitoring agent quality." }
                  link_to("Create Policy", new_continuous_policy_path, class: "btn btn-primary mt-3")
                end
              end
            end
          end
        end

        def render_policy_row(policy)
          tr do
            td do
              strong { policy.name }
              if policy.description.present?
                br
                small(class: "text-muted") { policy.description }
              end
            end

            td do
              if policy.agent_name.present?
                span(class: "badge bg-info") { policy.agent_name }
              else
                span(class: "text-muted") { "All agents" }
              end
            end

            td do
              span(class: "badge bg-secondary") { policy.environment || "all" }
            end

            td do
              render_sampling_info(policy)
            end

            td do
              render_status_badge(policy)
            end

            td do
              if policy.respond_to?(:today_evaluation_count)
                count = policy.today_evaluation_count || 0
                limit = policy.max_daily_evaluations

                if limit
                  percentage = (count.to_f / limit * 100).round
                  badge_class = if percentage >= 90
                                  "bg-danger"
                                elsif percentage >= 70
                                  "bg-warning"
                                else
                                  "bg-success"
                                end
                  span(class: "badge #{badge_class}") { "#{count} / #{limit}" }
                else
                  plain count.to_s
                end
              else
                span(class: "text-muted") { "N/A" }
              end
            end

            td(class: "text-end") do
              div(class: "btn-group btn-group-sm") do
                link_to("View", continuous_policy_path(policy), class: "btn btn-outline-primary")
                link_to("Edit", edit_continuous_policy_path(policy), class: "btn btn-outline-secondary")

                if policy.active?
                  button_to("Deactivate",
                    deactivate_continuous_policy_path(policy),
                    method: :patch,
                    class: "btn btn-outline-warning",
                    data: { confirm: "Deactivate this policy?" })
                else
                  button_to("Activate",
                    activate_continuous_policy_path(policy),
                    method: :patch,
                    class: "btn btn-outline-success")
                end

                button_to("Delete",
                  continuous_policy_path(policy),
                  method: :delete,
                  class: "btn btn-outline-danger",
                  data: { confirm: "Are you sure? This will delete all associated queue items and results." })
              end
            end
          end
        end

        def render_sampling_info(policy)
          case policy.sampling_mode
          when 'percentage'
            div do
              small do
                strong { "#{policy.sample_rate}%" }
                plain " of spans"
              end
            end
          when 'every_n'
            div do
              small do
                plain "Every "
                strong { policy.sample_every_n.to_s }
                plain "th span"
              end
            end
          when 'all'
            span(class: "badge bg-primary") { "All spans" }
          else
            span(class: "text-muted") { "Not configured" }
          end
        end

        def render_status_badge(policy)
          if policy.active?
            span(class: "badge bg-success") do
              i(class: "bi bi-check-circle me-1")
              plain "Active"
            end
          else
            span(class: "badge bg-secondary") do
              i(class: "bi bi-pause-circle me-1")
              plain "Inactive"
            end
          end
        end

        def render_pagination
          # Basic pagination placeholder
          div(class: "d-flex justify-content-between align-items-center mt-3") do
            div do
              small(class: "text-muted") { "Page #{@page} of #{@policies.total_pages}" }
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
