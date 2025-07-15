# frozen_string_literal: true

module RubyAIAgentsFactory
  module Tracing
    class FilterForm < Phlex::HTML
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::OptionsForSelect
      include Components::Preline

      def initialize(url:, search: nil, workflow: nil, status: nil, start_time: nil, end_time: nil)
        @url = url
        @search = search
        @workflow = workflow
        @status = status
        @start_time = start_time
        @end_time = end_time
      end

      def template
        Card(class: "mb-6") do |card|
          card.body do
            Form(url: @url, method: :get, local: true, class: "grid grid-cols-1 md:grid-cols-6 gap-4") do
              # Search field
              GridItem(span: 2) do
                Input(
                  name: "search",
                  value: @search,
                  placeholder: "Search traces...",
                  label: "Search"
                )
              end

              # Workflow select
              GridItem do
                Select(
                  name: "workflow",
                  label: "Workflow",
                  value: @workflow,
                  options: workflow_select_options
                )
              end

              # Status select
              GridItem do
                Select(
                  name: "status",
                  label: "Status",
                  value: @status,
                  options: status_select_options
                )
              end

              # Start time
              GridItem do
                Input(
                  name: "start_time",
                  type: "datetime-local",
                  value: @start_time,
                  label: "Start Time"
                )
              end

              # End time
              GridItem do
                Input(
                  name: "end_time",
                  type: "datetime-local",
                  value: @end_time,
                  label: "End Time"
                )
              end

              # Submit button
              Flex(align: :end) do
                Button(
                  type: "submit",
                  variant: :primary,
                  class: "w-full"
                ) do
                  "Apply Filter"
                end
              end
            end
          end
        end
      end

      private

      def workflow_select_options
        options = [["All Workflows", ""]]
        workflow_options.each do |workflow|
          options << [workflow, workflow]
        end
        options
      end

      def status_select_options
        [
          ["All Statuses", ""],
          ["Completed", "completed"],
          ["Failed", "failed"],
          ["Running", "running"],
          ["Pending", "pending"]
        ]
      end

      def workflow_options
        # This would typically come from the controller
        OpenAIAgents::Tracing::TraceRecord.distinct.pluck(:workflow_name).compact
      rescue StandardError
        []
      end
    end
  end
end
