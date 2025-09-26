# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class AgentSpanComponent < SpanDetailBase
        include RAAF::Logger
        include MarkdownRenderer
        def view_template
          div(class: "space-y-6") do
            render_agent_overview
            render_agent_configuration

            # Show sections in the desired order: System -> User -> Dialogue -> Response -> Statistics
            messages = dialogue_messages

            # 1. System Prompt - show if content is available
            render_system_prompt_section if system_prompt_content.present?

            # 2. User Prompt - show if content is available
            render_user_prompt_section if user_prompt_content.present?

            # 3. Dialogue - show unified conversation if messages are available and individual sections aren't sufficient
            if messages.present? && messages.any? && (!system_prompt_content.present? || !user_prompt_content.present? || !final_agent_response.present?)
              render_dialogue_section
            end

            # 4. Agent Response - show if content is available
            render_agent_response_section if final_agent_response.present?

            # 5. Conversation Statistics - moved up in priority
            render_conversation_statistics_section if conversation_stats_data.present?

            render_conversation_flow_section if messages.present? || tool_executions_data.present?
            render_tool_executions_section if tool_executions_data.present?
            render_context_information if context_data.present?
            render_error_handling
          end
        end

        private

        def agent_name
          @agent_name ||= extract_span_attribute("agent.name") ||
                         extract_span_attribute("name") ||
                         extract_span_attribute("agent_name") ||
                         @span.name&.gsub(/^agent[\.\:]\s*/i, '') ||
                         "Unknown Agent"
        end

        def model_name
          @model_name ||= extract_span_attribute("agent.model") ||
                         extract_span_attribute("model") ||
                         extract_span_attribute("llm.model") ||
                         "Unknown Model"
        end

        def context_data
          @context_data ||= extract_span_attribute("context") ||
                           extract_span_attribute("initial_context") ||
                           extract_span_attribute("agent.context")
        end


        def dialogue_messages
          @dialogue_messages ||= begin
            # Try prefixed name first (what collector actually stores)
            messages_json = extract_span_attribute("agent.conversation_messages") ||
                           extract_span_attribute("conversation_messages")
            if messages_json.present? && messages_json != "[]"
              begin
                return JSON.parse(messages_json)
              rescue JSON::ParserError => e
                # Handle truncated or malformed JSON - try to extract partial conversation
                log_warn("Truncated conversation messages JSON detected",
                        length: messages_json.length,
                        span_id: @span.span_id)
                return parse_truncated_conversation_json(messages_json)
              end
            end

            # Fallback to LLM span attributes
            llm_messages = extract_span_attribute("llm.request.messages") ||
                          extract_span_attribute("llm")&.dig("request", "messages")

            return llm_messages if llm_messages.present?

            # NEW: Try to reconstruct conversation from individual prompt components
            messages = []

            # Add system message if present
            system_content = system_prompt_content
            if system_content.present?
              messages << {
                "role" => "system",
                "content" => system_content
              }
            end

            # Add user message if present
            user_content = user_prompt_content
            if user_content.present?
              messages << {
                "role" => "user",
                "content" => user_content
              }
            end

            # Add assistant message if present
            agent_response = final_agent_response
            if agent_response.present?
              messages << {
                "role" => "assistant",
                "content" => agent_response
              }
            end

            # Return reconstructed messages if we found any
            return messages if messages.any?

            # If not found directly, check child LLM spans
            extract_dialogue_from_children
          rescue JSON::ParserError => e
            log_warn("Failed to parse conversation messages", error: e.message, span_id: @span.span_id)
            extract_dialogue_from_children
          end
        end

        def extract_dialogue_from_children
          return [] unless @span.respond_to?(:children)

          # Find LLM child spans and extract their messages
          llm_children = @span.children.select { |child| child.kind&.downcase == "llm" }

          llm_children.each do |llm_span|
            messages = llm_span.span_attributes&.dig("llm.request.messages") ||
                      llm_span.span_attributes&.dig("llm", "request", "messages")
            return messages if messages.present?
          end

          []
        end

        def system_instructions
          @system_instructions ||= extract_span_attribute("agent.system_instructions") ||
                                   extract_span_attribute("system_instructions")
        end

        def initial_user_prompt
          @initial_user_prompt ||= extract_span_attribute("agent.initial_user_prompt") ||
                                   extract_span_attribute("initial_user_prompt")
        end

        def final_agent_response
          @final_agent_response ||= extract_span_attribute("agent.final_agent_response") ||
                                    extract_span_attribute("final_agent_response") ||
                                    extract_span_attribute("response.content") ||
                                    extract_span_attribute("llm.response.content")
        end

        def system_prompt_content
          @system_prompt_content ||= extract_span_attribute("agent.system_instructions") ||
                                     extract_span_attribute("system_instructions") ||
                                     extract_span_attribute("system_prompt") ||
                                     extract_span_attribute("llm.request.system") ||
                                     extract_dialogue_system_prompt
        end

        def user_prompt_content
          @user_prompt_content ||= extract_span_attribute("agent.initial_user_prompt") ||
                                   extract_span_attribute("initial_user_prompt") ||
                                   extract_span_attribute("user_prompt") ||
                                   extract_dialogue_user_prompt
        end

        def extract_dialogue_system_prompt
          return nil unless dialogue_messages.present?
          system_message = dialogue_messages.find { |msg| msg["role"] == "system" }
          system_message&.dig("content")
        end

        def extract_dialogue_user_prompt
          return nil unless dialogue_messages.present?
          user_message = dialogue_messages.find { |msg| msg["role"] == "user" }
          user_message&.dig("content")
        end

        def tool_executions_data
          @tool_executions_data ||= begin
            tool_json = extract_span_attribute("agent.tool_executions") ||
                       extract_span_attribute("tool_executions")
            if tool_json.present? && tool_json != "[]"
              JSON.parse(tool_json)
            else
              []
            end
          rescue JSON::ParserError => e
            log_warn("Failed to parse tool executions", error: e.message, span_id: @span.span_id)
            []
          end
        end

        def conversation_stats_data
          @conversation_stats_data ||= begin
            stats_json = extract_span_attribute("agent.conversation_stats") ||
                        extract_span_attribute("conversation_stats")
            if stats_json.present?
              JSON.parse(stats_json)
            else
              nil
            end
          rescue JSON::ParserError => e
            log_warn("Failed to parse conversation stats", error: e.message, span_id: @span.span_id)
            nil
          end
        end

        def agent_config
          @agent_config ||= {
            "temperature" => extract_span_attribute("agent.temperature") || extract_span_attribute("temperature"),
            "max_tokens" => extract_span_attribute("agent.max_tokens") || extract_span_attribute("max_tokens"),
            "top_p" => extract_span_attribute("agent.top_p") || extract_span_attribute("top_p"),
            "tools_count" => extract_span_attribute("agent.tools_count") || extract_span_attribute("tools.count"),
            "parallel_tool_calls" => extract_span_attribute("agent.parallel_tool_calls")
          }.compact
        end

        def render_agent_overview
          render_span_overview_header(
            "bi bi-robot",
            "Agent Execution",
            "#{agent_name} • #{model_name}"
          )
        end

        def render_dialogue_section
          render SpanDetail::DialogueDisplay.new(
            messages: dialogue_messages,
            title: "Agent Dialogue & Conversation"
          )
        end

        def render_agent_configuration
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-semibold text-gray-900") { "Agent Configuration" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              dl(class: "grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2") do
                render_detail_item("Agent Name", agent_name)
                render_detail_item("Model", model_name, monospace: true)
                render_detail_item("Execution Status", render_status_badge(@span.status))
                render_detail_item("Duration", render_duration_badge(@span.duration_ms))
                
                # Model configuration
                if agent_config["temperature"]
                  render_detail_item("Temperature", agent_config["temperature"])
                end
                
                if agent_config["max_tokens"]
                  render_detail_item("Max Tokens", agent_config["max_tokens"])
                end
                
                if agent_config["top_p"]
                  render_detail_item("Top P", agent_config["top_p"])
                end
                
                if agent_config["tools_count"]
                  render_detail_item("Tools Available", agent_config["tools_count"])
                end
                
                if agent_config["parallel_tool_calls"]
                  render_detail_item("Parallel Tool Calls", agent_config["parallel_tool_calls"] ? "Enabled" : "Disabled")
                end
              end
            end
          end
        end

        def render_context_information
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-purple-200 bg-purple-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-layers text-purple-600 text-lg")
                h3(class: "text-lg font-semibold text-purple-900") { "Context Variables" }
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              render_json_section("Agent Context", context_data, collapsed: true, use_json_highlighter: true)
            end
          end
        end


        def render_system_prompt_section
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-blue-200 bg-blue-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-gear text-blue-600 text-lg")
                h3(class: "text-lg font-semibold text-blue-900") { "System Prompt" }
                span(class: "px-2 py-1 text-xs font-medium bg-blue-100 text-blue-800 rounded-full") { "LLM Input" }
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              if system_prompt_content && system_prompt_content.length > 300
                render_expandable_markdown_text(system_prompt_content, "system-prompt")
              else
                div(class: "bg-gray-50 p-4 rounded-lg border text-sm prose prose-sm max-w-none") do
                  if looks_like_markdown?(system_prompt_content)
                    raw markdown_to_html(system_prompt_content)
                  else
                    div(class: "font-mono whitespace-pre-wrap") do
                      plain system_prompt_content || "No system prompt provided"
                    end
                  end
                end
              end
            end
          end
        end

        def render_user_prompt_section
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-green-200 bg-green-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-person text-green-600 text-lg")
                h3(class: "text-lg font-semibold text-green-900") { "User Prompt" }
                span(class: "px-2 py-1 text-xs font-medium bg-green-100 text-green-800 rounded-full") { "LLM Input" }
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              if user_prompt_content && user_prompt_content.length > 300
                render_expandable_markdown_text(user_prompt_content, "user-prompt")
              else
                div(class: "bg-gray-50 p-4 rounded-lg border text-sm prose prose-sm max-w-none") do
                  if looks_like_markdown?(user_prompt_content)
                    raw markdown_to_html(user_prompt_content)
                  else
                    div(class: "font-mono whitespace-pre-wrap") do
                      plain user_prompt_content || "No user prompt provided"
                    end
                  end
                end
              end
            end
          end
        end

        def render_agent_response_section
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-purple-200 bg-purple-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-robot text-purple-600 text-lg")
                h3(class: "text-lg font-semibold text-purple-900") { "Agent JSON Response" }
                span(class: "px-2 py-1 text-xs font-medium bg-purple-100 text-purple-800 rounded-full") { "LLM Output" }
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              if final_agent_response && final_agent_response.length > 500
                render_expandable_json_text(final_agent_response, "agent-response")
              else
                div(class: "bg-gray-50 p-4 rounded-lg border relative", data: { controller: "json-highlight" }) do
                  pre(class: "text-sm bg-white p-4 rounded border overflow-x-auto text-gray-900") do
                    code(
                      class: "language-json",
                      data: { json_highlight_target: "json" }
                    ) do
                      format_content(final_agent_response, force_type: :json)
                    end
                  end
                end
              end
            end
          end
        end

        def render_system_instructions_section
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-blue-200 bg-blue-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-file-text text-blue-600 text-lg")
                h3(class: "text-lg font-semibold text-blue-900") { "System Instructions" }
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              if system_instructions && system_instructions.length > 300
                render_expandable_markdown_text(system_instructions, "system-instructions")
              else
                div(class: "bg-gray-50 p-4 rounded-lg border text-sm prose prose-sm max-w-none") do
                  if looks_like_markdown?(system_instructions)
                    raw markdown_to_html(system_instructions)
                  else
                    div(class: "font-mono whitespace-pre-wrap") do
                      plain system_instructions || "No system instructions provided"
                    end
                  end
                end
              end
            end
          end
        end

        def render_conversation_flow_section
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-green-200 bg-green-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-chat-dots text-green-600 text-lg")
                h3(class: "text-lg font-semibold text-green-900") { "Conversation Flow" }
              end
            end
            div(class: "px-4 py-5 sm:p-6 space-y-4") do
              # System Prompt (show as simple label if present)
              if system_prompt_content.present?
                div(class: "border-l-4 border-gray-400 pl-4") do
                  div(class: "text-sm font-semibold text-gray-700 mb-1") { "System Instructions:" }
                  div(class: "bg-gray-50 p-3 rounded border text-sm italic text-gray-600") do
                    plain "system prompt"
                  end
                end
              end

              # Initial User Prompt (show as simple label if present)
              if initial_user_prompt && initial_user_prompt != "No user message found"
                div(class: "border-l-4 border-blue-400 pl-4") do
                  div(class: "text-sm font-semibold text-gray-700 mb-1") { "User Input:" }
                  div(class: "bg-blue-50 p-3 rounded border text-sm italic text-blue-600") do
                    plain "user prompt"
                  end
                end
              end

              # Tool Executions (if any)
              if tool_executions_data.present?
                div(class: "border-l-4 border-yellow-400 pl-4") do
                  div(class: "text-sm font-semibold text-gray-700 mb-1") do
                    plain "Tool Calls (#{tool_executions_data.length}):"
                  end
                  tool_executions_data.each_with_index do |tool_exec, index|
                    div(class: "bg-yellow-50 p-3 rounded border text-sm mb-2") do
                      div(class: "font-semibold text-yellow-800") { tool_exec["name"] || "unknown" }
                      if tool_exec["arguments"] && tool_exec["arguments"] != "{}"
                        div(class: "text-xs text-gray-600 mt-1") do
                          plain "Args: #{tool_exec["arguments"]}"
                        end
                      end
                      if tool_exec["result"]
                        div(class: "text-xs text-gray-700 mt-1 border-t pt-1") do
                          plain "Result: #{tool_exec["result"]}"
                        end
                      end
                    end
                  end
                end
              end

              # Final Agent Response
              if final_agent_response && final_agent_response != "No agent response found"
                div(class: "border-l-4 border-green-400 pl-4") do
                  div(class: "text-sm font-semibold text-gray-700 mb-1") { "Agent Response:" }
                  div(class: "bg-green-50 p-3 rounded border text-sm prose prose-sm max-w-none") do
                    if looks_like_json?(final_agent_response)
                      pre(class: "text-xs font-mono bg-white p-2 rounded border whitespace-pre-wrap overflow-x-auto text-gray-900") do
                        format_content(final_agent_response, force_type: :json)
                      end
                    elsif looks_like_markdown?(final_agent_response)
                      raw markdown_to_html(final_agent_response)
                    else
                      div(class: "whitespace-pre-wrap") do
                        plain final_agent_response.to_s
                      end
                    end
                  end
                end
              end
            end
          end
        end

        def render_tool_executions_section
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-yellow-200 bg-yellow-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-tools text-yellow-600 text-lg")
                h3(class: "text-lg font-semibold text-yellow-900") do
                  plain "Tool Executions (#{tool_executions_data.length})"
                end
              end
            end
            div(class: "px-4 py-5 sm:p-6 space-y-3") do
              tool_executions_data.each_with_index do |tool_exec, index|
                div(class: "border rounded-lg p-4 bg-gray-50") do
                  div(class: "flex items-center justify-between mb-2") do
                    div(class: "font-semibold text-gray-900") { tool_exec["name"] || "Unknown Tool" }
                    div(class: "text-xs text-gray-500") { "Call ID: #{tool_exec["call_id"] || 'unknown'}" }
                  end

                  if tool_exec["arguments"] && tool_exec["arguments"] != "{}"
                    div(class: "mb-2") do
                      div(class: "text-sm font-medium text-gray-700 mb-1") { "Arguments:" }
                      render_json_section("", tool_exec["arguments"], collapsed: true, compact: true, use_json_highlighter: true)
                    end
                  end

                  if tool_exec["result"]
                    div(class: "mb-2") do
                      div(class: "text-sm font-medium text-gray-700 mb-1") { "Result:" }
                      render_json_section("", tool_exec["result"], collapsed: true, compact: true, use_json_highlighter: true)
                    end
                  end
                end
              end
            end
          end
        end

        def render_conversation_statistics_section
          return unless conversation_stats_data

          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-purple-200 bg-purple-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-bar-chart text-purple-600 text-lg")
                h3(class: "text-lg font-semibold text-purple-900") { "Conversation Statistics" }
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              dl(class: "grid grid-cols-2 gap-x-4 gap-y-4 sm:grid-cols-3") do
                render_stat_item("Total Messages", conversation_stats_data["total_messages"])
                render_stat_item("User Messages", conversation_stats_data["user_messages"])
                render_stat_item("Assistant Messages", conversation_stats_data["assistant_messages"])
                render_stat_item("Tool Calls", conversation_stats_data["tool_calls"])
                render_stat_item("Has System Message", conversation_stats_data["has_system_message"] ? "Yes" : "No")
              end
            end
          end
        end

        def render_stat_item(label, value)
          div do
            dt(class: "text-sm font-medium text-gray-500") { label }
            dd(class: "mt-1 text-lg font-semibold text-gray-900") { value }
          end
        end

        def render_expandable_text(text, section_id)
          text_id = "#{section_id}-#{@span.span_id}"
          preview_text = text[0..300] + "..."

          div(data: { controller: "span-detail" }) do
            div(id: "#{text_id}-preview", class: "bg-gray-50 p-4 rounded-lg border text-sm font-mono whitespace-pre-wrap") do
              plain preview_text
            end
            div(id: text_id, class: "hidden bg-gray-50 p-4 rounded-lg border text-sm font-mono whitespace-pre-wrap") do
              plain text
            end
            button(
              class: "mt-3 text-sm text-blue-600 hover:text-blue-800 px-3 py-1 hover:bg-blue-50 rounded transition-colors",
              data: {
                action: "click->span-detail#toggleSection",
                target: text_id
              }
            ) { "Show Full Text" }
          end
        end

        def render_expandable_markdown_text(text, section_id)
          text_id = "#{section_id}-#{@span.span_id}"
          preview_text = text[0..300] + "..."

          div(data: { controller: "span-detail" }) do
            div(id: "#{text_id}-preview", class: "bg-gray-50 p-4 rounded-lg border text-sm prose prose-sm max-w-none") do
              if looks_like_markdown?(preview_text)
                raw markdown_to_html(preview_text)
              else
                div(class: "font-mono whitespace-pre-wrap") do
                  plain preview_text
                end
              end
            end
            div(id: text_id, class: "hidden bg-gray-50 p-4 rounded-lg border text-sm prose prose-sm max-w-none") do
              if looks_like_markdown?(text)
                raw markdown_to_html(text)
              else
                div(class: "font-mono whitespace-pre-wrap") do
                  plain text
                end
              end
            end
            button(
              class: "mt-3 text-sm text-blue-600 hover:text-blue-800 px-3 py-1 hover:bg-blue-50 rounded transition-colors",
              data: {
                action: "click->span-detail#toggleSection",
                target: text_id
              }
            ) { "Show Full Text" }
          end
        end

        def render_expandable_json_text(json_text, section_id)
          text_id = "#{section_id}-#{@span.span_id}"
          preview_text = json_text[0..500] + "..."

          div(data: { controller: "span-detail json-highlight" }) do
            div(id: "#{text_id}-preview", class: "bg-gray-50 p-4 rounded-lg border relative") do
              pre(class: "text-sm bg-white p-4 rounded border overflow-x-auto text-gray-900") do
                code(
                  class: "language-json",
                  data: { json_highlight_target: "json" }
                ) do
                  format_content(preview_text, force_type: :json)
                end
              end
            end
            div(id: text_id, class: "hidden bg-gray-50 p-4 rounded-lg border relative") do
              pre(class: "text-sm bg-white p-4 rounded border overflow-x-auto text-gray-900") do
                code(
                  class: "language-json",
                  data: { json_highlight_target: "json" }
                ) do
                  format_content(json_text, force_type: :json)
                end
              end
            end
            button(
              class: "mt-3 text-sm text-purple-600 hover:text-purple-800 px-3 py-1 hover:bg-purple-50 rounded transition-colors",
              data: {
                action: "click->span-detail#toggleSection click->json-highlight#highlightNew",
                target: text_id
              }
            ) { "Show Full JSON" }
          end
        end

        def parse_truncated_conversation_json(truncated_json)
          # Try to extract complete messages from truncated JSON
          # Look for complete message objects by finding role/content pairs
          messages = []

          # Basic regex to find complete message structures
          # This will match: {"role":"system","content":"..."}
          message_pattern = /"role":"(system|user|assistant|tool)","content":"([^"]*(?:\\.[^"]*)*)"/

          truncated_json.scan(message_pattern) do |role, content|
            # Unescape JSON content
            unescaped_content = content.gsub(/\\n/, "\n")
                                      .gsub(/\\"/, '"')
                                      .gsub(/\\\\/, "\\")

            messages << {
              "role" => role,
              "content" => unescaped_content
            }
          end

          # If we couldn't parse any messages, return empty array
          if messages.empty?
            log_warn("Could not extract any messages from truncated JSON", span_id: @span.span_id)
            return []
          end

          log_info("Extracted messages from truncated JSON",
                   message_count: messages.length,
                   span_id: @span.span_id)
          messages
        end
      end
    end
  end
end
