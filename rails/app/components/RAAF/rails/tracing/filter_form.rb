# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # The shared filter bar above the trace and span listings.
      #
      # Every control is a library atom wrapped in a Field, so the form spaces
      # and labels itself the same way as every other form in the dashboard.
      #
      class FilterForm < BaseComponent
        STATUSES = [
          %w[Completed completed],
          %w[Failed failed],
          %w[Running running],
          %w[Pending pending]
        ].freeze

        def initialize(url:, search: nil, workflow: nil, status: nil, start_time: nil, end_time: nil)
          @url = url
          @search = search
          @workflow = workflow
          @status = status
          @start_time = start_time
          @end_time = end_time
        end

        def view_template
          render(Organisms::Card.new(tight: true)) do
            form_with(url: @url, method: :get, local: true) do
              div(class: "raaf-field-grid") do
                search_field
                workflow_field
                status_field
                time_field("Start time", :start_time, @start_time)
                time_field("End time", :end_time, @end_time)
              end

              div(class: "raaf-form-actions") do
                render Atoms::Button.new(label: "Apply filter", type: "submit")
                render Atoms::Button.new(label: "Reset", href: @url, variant: :secondary)
              end
            end
          end
        end

        private

        def search_field
          render(Molecules::Field.new(label: "Search")) do
            render Atoms::Input.new(name: "search", value: @search, type: "search",
                                    placeholder: "Search traces…")
          end
        end

        def workflow_field
          render(Molecules::Field.new(label: "Workflow")) do
            render Atoms::Select.new(name: "workflow", selected: @workflow,
                                     include_blank: "All workflows", options: workflow_options)
          end
        end

        def status_field
          render(Molecules::Field.new(label: "Status")) do
            render Atoms::Select.new(name: "status", selected: @status,
                                     include_blank: "All statuses", options: STATUSES)
          end
        end

        def time_field(label, name, value)
          render(Molecules::Field.new(label: label)) do
            render Atoms::Input.new(name: name, type: "datetime-local", value: value)
          end
        end

        # Distinct workflow names, or nothing if the table is unavailable.
        def workflow_options
          RAAF::Rails::Tracing::TraceRecord.distinct.pluck(:workflow_name).compact.sort
        rescue StandardError
          []
        end
      end
    end
  end
end
