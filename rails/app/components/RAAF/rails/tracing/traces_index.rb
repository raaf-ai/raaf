# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # The trace listing: one filter strip, then the table.
      #
      # The design opens on a single glass strip — the active workflow, status
      # pills, and the count — not a five-field form above a row of headline
      # counts. The counts it dropped are the ones the Overview already shows,
      # and "Failed 60" as a number you cannot click says less than a Failed
      # pill that filters the table.
      #
      class TracesIndex < BaseComponent
        # @param workflows [Array<String>] every workflow name, for the strip's
        #   filter — the whole set, not just the ones on this page
        def initialize(traces:, stats: nil, workflows: [], params: {})
          @traces = traces
          @stats = stats
          @workflows = workflows
          @params = params
        end

        def view_template
          div(id: "tracing-dashboard", class: "raaf-page", data: dashboard_data) do
            connection_status
            filters
            traces_table
          end
        end

        private

        # Retained verbatim: the dashboard Stimulus controller reads these.
        def dashboard_data
          {
            controller: "dashboard",
            "dashboard-channel-name-value": "RubyAIAgentsFactory::Tracing::TracesChannel",
            "dashboard-polling-interval-value": "5000",
            "dashboard-auto-refresh-value": "true"
          }
        end

        # Populated by the dashboard controller when the websocket connects.
        def connection_status
          div(id: "connection-status", class: "raaf-hidden",
              data: { "dashboard-target": "connectionStatus" }) do
            render Molecules::Alert.new(:info, title: "Live updates") do
              p(class: "raaf-alert-text status-text") { "Connecting…" }
            end
          end
        end

        STATUSES = [
          { label: "All", value: nil },
          { label: "Completed", value: "completed" },
          { label: "Failed", value: "failed" },
          { label: "Running", value: "running" }
        ].freeze

        def filters
          render(Molecules::FilterBar.new(chips: status_chips, panel: true,
                                          lead: workflow_filter)) do
            render Atoms::Mono.new(count_label, tone: :muted)
          end
        end

        # The design opens the strip with this: a funnel and the workflow the
        # table is scoped to, filling the row.
        def workflow_filter
          Molecules::ScopeFilter.new(
            name: "workflow", value: @params[:workflow], options: @workflows,
            action: tracing_traces_path, prefix: "workflow",
            carry: { "status" => @params[:status], "range" => @params[:range] }
          )
        end

        def status_chips
          STATUSES.map do |status|
            { label: status[:label],
              active: @params[:status].presence == status[:value],
              href: filtered_path(status: status[:value]) }
          end
        end

        # Carries the other filters forward, so choosing a status does not
        # silently drop the workflow or the search.
        def filtered_path(overrides)
          carried = { search: @params[:search], workflow: @params[:workflow],
                      status: @params[:status], range: @params[:range] }
          tracing_traces_path(carried.merge(overrides).compact.reject { |_, v| v.to_s.empty? })
        end

        def count_label
          count = @stats&.dig(:total) || @traces.size
          delimited = count.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
          "#{delimited} #{'trace'.pluralize(count.to_i)}"
        end

        def traces_table
          div(id: "traces-table-container", data: { "dashboard-target": "tracesContainer" }) do
            render TracesTable.new(traces: @traces, params: @params)
          end
        end
      end
    end
  end
end
