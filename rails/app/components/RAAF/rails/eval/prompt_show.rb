# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class PromptShow < RAAF::Rails::Tracing::BaseComponent
        def initialize(prompt:, versions:, active_version:)
          @prompt = prompt
          @versions = versions
          @active_version = active_version
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_active_version
            render_versions_table
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { @prompt.name }
              p(class: "mt-1 text-sm text-gray-500") { @prompt.description } if @prompt.description.present?
              span(class: "text-xs text-gray-400") { "Agent: #{@prompt.agent_name}" } if @prompt.agent_name
            end
            div(class: "mt-4 sm:mt-0 flex gap-2") do
              render_preline_button(text: "New Version", href: eval_prompt_path(@prompt), variant: "primary", icon: "bi-plus-lg")
            end
          end
        end

        def render_active_version
          div(class: "mb-6") do
            h2(class: "text-lg font-semibold text-gray-900 mb-3") { "Active Version" }
            if @active_version
              div(class: "bg-white shadow rounded-lg p-6") do
                div(class: "flex justify-between items-center mb-3") do
                  span(class: "text-sm font-medium text-gray-600") { "v#{@active_version.version_number}" }
                  span(class: "px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800") { "Published" }
                end
                if @active_version.model
                  div(class: "text-xs text-gray-500 mb-2") { "Model: #{@active_version.model}" }
                end
                pre(class: "bg-gray-50 rounded-lg p-4 text-sm text-gray-800 overflow-x-auto whitespace-pre-wrap") do
                  @active_version.content
                end
              end
            else
              div(class: "bg-yellow-50 border border-yellow-200 rounded-lg p-4 text-sm text-yellow-700") do
                "No published version. Create and publish a version to make it active."
              end
            end
          end
        end

        def render_versions_table
          h2(class: "text-lg font-semibold text-gray-900 mb-3") { "Version History" }
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            if @versions.any?
              table(class: "min-w-full divide-y divide-gray-200") do
                thead(class: "bg-gray-50") do
                  tr do
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Version" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Status" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Message" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Model" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Created By" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Created" }
                    th(class: "px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase") { "Actions" }
                  end
                end
                tbody(class: "bg-white divide-y divide-gray-200") do
                  @versions.each { |v| render_version_row(v) }
                end
              end
            else
              div(class: "p-8 text-center text-gray-500") { "No versions yet." }
            end
          end
        end

        def render_version_row(version)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-3 text-sm font-medium text-gray-900") { "v#{version.version_number}" }
            td(class: "px-4 py-3") do
              badge_class = case version.status
                           when "published" then "bg-green-100 text-green-800"
                           when "draft" then "bg-yellow-100 text-yellow-800"
                           else "bg-gray-100 text-gray-800"
                           end
              span(class: "px-2 py-0.5 rounded-full text-xs font-medium #{badge_class}") { version.status }
            end
            td(class: "px-4 py-3 text-sm text-gray-600") { version.commit_message || "-" }
            td(class: "px-4 py-3 text-sm text-gray-600") { version.model || "-" }
            td(class: "px-4 py-3 text-sm text-gray-500") { version.created_by || "-" }
            td(class: "px-4 py-3 text-sm text-gray-500") { version.created_at&.strftime("%Y-%m-%d %H:%M") }
            td(class: "px-4 py-3 text-right flex gap-1 justify-end") do
              if version.draft?
                render_preline_button(text: "Publish", href: "#{eval_prompt_path(@prompt)}/versions/#{version.id}/publish", variant: "success", size: "xs")
              end
              unless version.archived?
                render_preline_button(text: "Archive", href: "#{eval_prompt_path(@prompt)}/versions/#{version.id}/archive", variant: "secondary", size: "xs")
              end
            end
          end
        end
      end
    end
  end
end
