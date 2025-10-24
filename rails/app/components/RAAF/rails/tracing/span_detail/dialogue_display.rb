# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module SpanDetail
        class DialogueDisplay < BaseComponent
          include MarkdownRenderer
          def initialize(messages:, title: "Conversation", collapsible: true)
            @messages = messages || []
            @title = title
            @collapsible = collapsible
            @section_id = "dialogue-#{SecureRandom.hex(4)}"
          end

          def view_template
            return render_empty_state if @messages.empty?

            div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200 mb-6") do
              render_header
              render_content
            end
          end

          private

          def render_empty_state
            div(class: "bg-gray-50 rounded-lg p-8 text-center") do
              i(class: "bi bi-chat-dots text-gray-400 text-3xl mb-2")
              p(class: "text-gray-500 text-sm") { "No conversation data available" }
            end
          end

          def render_header
            div(class: "px-4 py-5 sm:px-6 border-b border-blue-200 bg-blue-50") do
              div(class: "flex items-center justify-between") do
                div(class: "flex items-center gap-3") do
                  i(class: "bi bi-chat-dots text-blue-600 text-lg")
                  h3(class: "text-lg font-semibold text-blue-900") { @title }
                  span(class: "px-2 py-1 text-xs bg-blue-100 text-blue-800 rounded-full") { "#{@messages.length} messages" }
                end

                if @collapsible
                  button(
                    class: "text-blue-600 hover:text-blue-800 text-sm flex items-center gap-1",
                    data: {
                      controller: "span-detail",
                      action: "click->span-detail#toggleSection",
                      target: @section_id,
                      expanded_text: "Collapse",
                      collapsed_text: "Expand"
                    }
                  ) do
                    i(class: "bi bi-chevron-down toggle-icon")
                    span(class: "button-text") { "Toggle Details" }
                  end
                end
              end
            end
          end

          def render_content
            div(id: @section_id, class: @collapsible ? "" : "block") do
              div(class: "px-4 py-5 sm:p-6") do
                # Removed max-h-96 overflow-y-auto to prevent truncation when expanding messages
                # Messages can now expand to their full height without container constraints
                div(class: "space-y-4") do
                  sorted_messages.each_with_index do |message, index|
                    render_message(message, index)
                  end
                end
              end
            end
          end

          def render_message(message, index)
            role = message["role"] || message[:role] || "unknown"
            content = message["content"] || message[:content] || ""
            tool_calls = message["tool_calls"] || message[:tool_calls]

            div(class: "flex gap-3 #{message_alignment_class(role)}") do
              # Avatar/Icon
              render_role_avatar(role)

              # Message content
              div(class: "flex-1 min-w-0") do
                # Message header
                div(class: "flex items-center gap-2 mb-2") do
                  span(class: "text-sm font-semibold #{role_color_class(role)}") { role.capitalize }
                  span(class: "text-xs text-gray-500") { "##{index + 1}" }
                  if tool_calls&.any?
                    span(class: "px-1.5 py-0.5 text-xs bg-purple-100 text-purple-800 rounded") { "#{tool_calls.length} tools" }
                  end
                end

                # Message content
                render_message_content(content, role)

                # Tool calls if present
                if tool_calls&.any?
                  render_tool_calls(tool_calls)
                end
              end
            end
          end

          def render_role_avatar(role)
            icon_class, bg_class = case role.downcase
                                  when "user"
                                    ["bi-person", "bg-blue-100 text-blue-600"]
                                  when "assistant"
                                    ["bi-robot", "bg-green-100 text-green-600"]
                                  when "system"
                                    ["bi-gear", "bg-gray-100 text-gray-600"]
                                  when "tool"
                                    ["bi-wrench", "bg-purple-100 text-purple-600"]
                                  else
                                    ["bi-question-circle", "bg-orange-100 text-orange-600"]
                                  end

            div(class: "w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 #{bg_class}") do
              i(class: "#{icon_class} text-sm")
            end
          end

          def render_message_content(content, role)
            return if content.blank?

            content_class = case role.downcase
                           when "user" then "bg-blue-50 border-blue-200"
                           when "assistant" then "bg-green-50 border-green-200"
                           when "system" then "bg-gray-50 border-gray-200"
                           when "tool" then "bg-purple-50 border-purple-200"
                           else "bg-orange-50 border-orange-200"
                           end

            div(class: "#{content_class} border rounded-lg p-3 mb-2") do
              if content.length > 500
                render_expandable_content(content)
              else
                render_formatted_content(content)
              end
            end
          end

          def render_expandable_content(content)
            content_id = "content-#{SecureRandom.hex(4)}"
            preview_content = content[0..500] + "..."

            div(data: { controller: "span-detail" }) do
              # Preview section - limited to first 500 chars
              div(id: "#{content_id}-preview", class: "text-sm text-gray-800 overflow-hidden") do
                render_formatted_content(preview_content)
              end
              # Full content section - unrestricted, hidden by default
              div(id: content_id, class: "hidden text-sm text-gray-800 whitespace-normal break-words max-w-full") do
                render_formatted_content(content)
              end
              button(
                class: "mt-2 text-xs text-blue-600 hover:text-blue-800 px-2 py-1 bg-white border rounded transition-colors",
                data: {
                  action: "click->span-detail#toggleSection",
                  target: content_id,
                  expanded_text: "Show Less",
                  collapsed_text: "Show More"
                }
              ) do
                span(class: "button-text") { "Show More" }
              end
            end
          end

          def render_formatted_content(content)
            # Check if content looks like JSON
            if looks_like_json?(content)
              pre(
                class: "text-xs font-mono bg-white p-2 rounded border whitespace-pre-wrap overflow-x-auto",
                data: {
                  controller: "json-highlight",
                  json_highlight_target: "json"
                }
              ) do
                format_json_content(content)
              end
            elsif looks_like_markdown?(content)
              # Render markdown content - with no max-width constraints to prevent truncation
              div(class: "text-sm prose prose-sm max-w-none w-full overflow-visible") do
                raw markdown_to_html(content)
              end
            else
              # Regular text content with line breaks preserved
              div(class: "text-sm whitespace-pre-wrap break-words w-full") { content }
            end
          end

          def render_tool_calls(tool_calls)
            div(class: "mt-3 space-y-2") do
              tool_calls.each_with_index do |tool_call, index|
                render_tool_call(tool_call, index)
              end
            end
          end

          def render_tool_call(tool_call, index)
            function_name = tool_call.dig("function", "name") || tool_call[:function]&.dig(:name) || "Unknown"
            arguments = tool_call.dig("function", "arguments") || tool_call[:function]&.dig(:arguments) || {}

            div(class: "bg-purple-50 border border-purple-200 rounded p-3") do
              div(class: "flex items-center gap-2 mb-2") do
                i(class: "bi bi-wrench text-purple-600")
                span(class: "text-sm font-medium text-purple-900") { "Tool Call ##{index + 1}" }
                span(class: "text-xs text-purple-700 font-mono bg-purple-100 px-2 py-1 rounded") { function_name }
              end

              if arguments.present?
                div(class: "text-xs") do
                  strong(class: "text-purple-800") { "Arguments:" }
                  pre(
                    class: "mt-1 bg-white p-2 rounded border text-purple-900 font-mono overflow-x-auto",
                    data: {
                      controller: "json-highlight",
                      json_highlight_target: "json"
                    }
                  ) do
                    format_json_content(arguments)
                  end
                end
              end
            end
          end

          def message_alignment_class(role)
            case role.downcase
            when "assistant", "tool" then ""
            else ""
            end
          end

          def role_color_class(role)
            case role.downcase
            when "user" then "text-blue-800"
            when "assistant" then "text-green-800"
            when "system" then "text-gray-800"
            when "tool" then "text-purple-800"
            else "text-orange-800"
            end
          end

          def looks_like_json?(content)
            return false unless content.is_a?(String)
            content.strip.start_with?("{", "[") && content.strip.end_with?("}", "]")
          end

          def format_json_content(content)
            case content
            when String
              begin
                parsed = JSON.parse(content)
                JSON.pretty_generate(parsed)
              rescue JSON::ParserError
                content
              end
            when Hash, Array
              JSON.pretty_generate(content)
            else
              content.to_s
            end
          end

          def sorted_messages
            # Sort messages by role priority: system -> user -> assistant -> tool
            role_priority = {
              "system" => 1,
              "user" => 2,
              "assistant" => 3,
              "tool" => 4
            }

            @messages.sort_by do |message|
              role = (message["role"] || message[:role] || "unknown").downcase
              priority = role_priority[role] || 99

              # For messages with the same role, preserve original order
              original_index = @messages.index(message)
              [priority, original_index]
            end
          end
        end
      end
    end
  end
end