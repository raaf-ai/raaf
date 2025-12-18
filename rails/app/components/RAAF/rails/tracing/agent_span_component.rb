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
            render_tabbed_interface
            render_error_handling
          end
        end

        def render_tabbed_interface
          # Determine which tabs to show
          tabs = build_tab_list

          return if tabs.empty?

          # Generate unique ID for this tab container
          container_id = "tabs-#{@span.span_id.to_s.gsub(/[^a-zA-Z0-9]/, '')}"

          div(class: "bg-white border border-gray-200 rounded-lg shadow-sm overflow-hidden", id: container_id) do
            # Tab navigation
            nav(class: "flex gap-x-1 border-b border-gray-200 bg-gray-50 px-4", aria_label: "Tabs", role: "tablist") do
              tabs.each_with_index do |tab, index|
                render_tab_button(tab, index == 0, container_id, tabs)
              end
            end

            # Tab content panels
            div(class: "p-4") do
              tabs.each_with_index do |tab, index|
                render_tab_panel(tab, index == 0)
              end
            end

            # Inline script to set up tab click handlers
            render_tab_initialization_script(container_id)
          end
        end

        def render_tab_initialization_script(container_id)
          script_content = <<~JS
            (function() {
              document.querySelectorAll('.tab-btn-#{container_id}[data-tab-onclick]').forEach(function(tab) {
                tab.addEventListener('click', function(e) {
                  e.preventDefault();
                  var fn = new Function('event', tab.getAttribute('data-tab-onclick'));
                  fn.call(tab, e);
                });
              });
            })();
          JS

          script { raw safe(script_content) }
        end

        def build_tab_list
          tabs = []

          # System Prompt tab
          if system_prompt_content.present?
            tabs << { id: "system-prompt", label: "System Prompt", icon: "bi-gear" }
          end

          # User Prompt tab
          if user_prompt_content.present?
            tabs << { id: "user-prompt", label: "User Prompt", icon: "bi-person" }
          end

          # Response tab
          if final_agent_response.present?
            tabs << { id: "response", label: "Response", icon: "bi-robot" }
          end

          # Configuration tab
          tabs << { id: "configuration", label: "Configuration", icon: "bi-sliders" }

          # Statistics tab (combines stats + flow)
          if conversation_stats_data.present? || dialogue_messages.present? || tool_executions_data.present?
            tabs << { id: "statistics", label: "Statistics", icon: "bi-bar-chart" }
          end

          # Tools tab
          if tool_executions_data.present?
            tabs << { id: "tools", label: "Tools (#{tool_executions_data.length})", icon: "bi-tools" }
          end

          # Context tab
          if context_data.present?
            tabs << { id: "context", label: "Context", icon: "bi-layers" }
          end

          # Evaluation tab
          if continuous_evaluation_available?
            tabs << { id: "evaluation", label: "Evaluation", icon: "bi-clipboard-check" }
          end

          tabs
        end

        def render_tab_button(tab, is_active, container_id, all_tabs)
          active_classes = "border-blue-500 text-blue-600"
          inactive_classes = "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"

          # Build onclick handler that switches tabs
          panel_ids = all_tabs.map { |t| "panel-#{t[:id]}" }
          onclick_js = build_tab_onclick_js(tab[:id], panel_ids, container_id)

          a(
            href: "#panel-#{tab[:id]}",
            class: "tab-btn-#{container_id} py-4 px-3 inline-flex items-center gap-x-2 border-b-2 text-sm font-medium whitespace-nowrap focus:outline-none cursor-pointer #{is_active ? active_classes : inactive_classes}",
            aria_controls: "panel-#{tab[:id]}",
            role: "tab",
            aria_selected: is_active.to_s,
            data_tab_onclick: onclick_js
          ) do
            i(class: "#{tab[:icon]} text-base")
            plain tab[:label]
          end
        end

        def build_tab_onclick_js(active_tab_id, panel_ids, container_id)
          # JavaScript to switch tabs
          js_parts = []
          js_parts << "event.preventDefault();"

          # Hide all panels and show the active one
          panel_ids.each do |panel_id|
            if panel_id == "panel-#{active_tab_id}"
              js_parts << "document.getElementById('#{panel_id}').classList.remove('hidden');"
            else
              js_parts << "document.getElementById('#{panel_id}').classList.add('hidden');"
            end
          end

          # Update tab button styles
          js_parts << "document.querySelectorAll('.tab-btn-#{container_id}').forEach(function(t){"
          js_parts << "t.classList.remove('border-blue-500','text-blue-600');"
          js_parts << "t.classList.add('border-transparent','text-gray-500');"
          js_parts << "t.setAttribute('aria-selected','false');"
          js_parts << "});"
          js_parts << "this.classList.remove('border-transparent','text-gray-500');"
          js_parts << "this.classList.add('border-blue-500','text-blue-600');"
          js_parts << "this.setAttribute('aria-selected','true');"

          js_parts.join("")
        end

        def render_tab_panel(tab, is_active)
          div(
            id: "panel-#{tab[:id]}",
            role: "tabpanel",
            class: is_active ? "" : "hidden"
          ) do
            case tab[:id]
            when "system-prompt"
              render_system_prompt_tab_content
            when "user-prompt"
              render_user_prompt_tab_content
            when "response"
              render_response_tab_content
            when "configuration"
              render_configuration_tab_content
            when "statistics"
              render_statistics_tab_content
            when "tools"
              render_tools_tab_content
            when "context"
              render_context_tab_content
            when "evaluation"
              render_evaluation_tab_content
            end
          end
        end

        def render_prompts_tab_content
          div(class: "space-y-6") do
            render_system_prompt_section if system_prompt_content.present?
            render_user_prompt_section if user_prompt_content.present?

            # Show dialogue if we don't have separate prompts
            messages = dialogue_messages
            if messages.present? && messages.any? && (!system_prompt_content.present? || !user_prompt_content.present?)
              render_dialogue_section
            end
          end
        end

        def render_system_prompt_tab_content
          div(class: "space-y-4") do
            # Header with tags
            div(class: "flex items-center gap-3 mb-4") do
              i(class: "bi bi-gear text-blue-600 text-lg")
              h3(class: "text-lg font-semibold text-blue-900") { "System Prompt" }
              span(class: "px-2 py-1 text-xs font-medium bg-blue-100 text-blue-800 rounded-full") { "LLM Input" }
              if looks_like_json?(system_prompt_content)
                span(class: "px-2 py-1 text-xs font-medium bg-purple-100 text-purple-800 rounded-full") { "JSON" }
              end
            end

            render_full_content_with_formatting(system_prompt_content, "system-prompt")
          end
        end

        def render_user_prompt_tab_content
          div(class: "space-y-4") do
            # Header with tags
            div(class: "flex items-center gap-3 mb-4") do
              i(class: "bi bi-person text-green-600 text-lg")
              h3(class: "text-lg font-semibold text-green-900") { "User Prompt" }
              span(class: "px-2 py-1 text-xs font-medium bg-green-100 text-green-800 rounded-full") { "LLM Input" }
              if looks_like_json?(user_prompt_content)
                span(class: "px-2 py-1 text-xs font-medium bg-blue-100 text-blue-800 rounded-full") { "JSON" }
              end
            end

            render_full_content_with_formatting(user_prompt_content, "user-prompt")
          end
        end

        def render_response_tab_content
          render_agent_response_section_content
        end

        def render_configuration_tab_content
          render_agent_configuration_content
        end

        def render_statistics_tab_content
          div(class: "space-y-6") do
            render_conversation_statistics_content if conversation_stats_data.present?
            render_conversation_flow_content if dialogue_messages.present? || tool_executions_data.present?
          end
        end

        def render_tools_tab_content
          render_tool_executions_content
        end

        def render_context_tab_content
          render_context_content
        end

        def render_evaluation_tab_content
          render ApplicablePoliciesSection.new(span: @span) if continuous_evaluation_available?
        end

        private

        def render_section_navigation
          # Determine which sections will be rendered
          sections = []
          sections << { id: "evaluation-policies", label: "Evaluation", icon: "bi-clipboard-check" } if continuous_evaluation_available?
          sections << { id: "configuration", label: "Configuration", icon: "bi-gear" }
          sections << { id: "system-prompt", label: "System Prompt", icon: "bi-gear" } if system_prompt_content.present?
          sections << { id: "user-prompt", label: "User Prompt", icon: "bi-person" } if user_prompt_content.present?
          sections << { id: "dialogue", label: "Dialogue", icon: "bi-chat-dots" } if dialogue_messages.present?
          sections << { id: "response", label: "Response", icon: "bi-robot" } if final_agent_response.present?
          sections << { id: "statistics", label: "Statistics", icon: "bi-bar-chart" } if conversation_stats_data.present?
          sections << { id: "conversation-flow", label: "Flow", icon: "bi-chat-dots" } if dialogue_messages.present? || tool_executions_data.present?
          sections << { id: "tool-executions", label: "Tools", icon: "bi-tools" } if tool_executions_data.present?
          sections << { id: "context", label: "Context", icon: "bi-layers" } if context_data.present?

          return if sections.empty?

          div(class: "bg-white border border-gray-200 rounded-lg shadow-sm mb-6 sticky top-0 z-10") do
            div(class: "px-4 py-3") do
              div(class: "flex items-center gap-2 flex-wrap") do
                span(class: "text-sm font-medium text-gray-700 mr-2") { "Jump to:" }
                sections.each do |section|
                  a(
                    href: "##{section[:id]}",
                    class: "inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-gray-700 bg-gray-50 hover:bg-gray-100 rounded-md transition-colors border border-gray-200 hover:border-gray-300"
                  ) do
                    i(class: "#{section[:icon]} text-gray-500")
                    plain section[:label]
                  end
                end
              end
            end
          end
        end

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

        def provider_name
          @provider_name ||= begin
            # Try to get explicitly stored provider
            explicit_provider = extract_span_attribute("agent.provider") ||
                              extract_span_attribute("provider") ||
                              extract_span_attribute("llm.provider")

            # If found and not "N/A", use it
            return explicit_provider if explicit_provider && explicit_provider != "N/A"

            # Otherwise, detect from model name
            detect_provider_from_model(model_name)
          end
        end

        def detect_provider_from_model(model)
          case model.to_s.downcase
          when /^gpt-/, /^o1-/, /^o3-/
            "OpenAI"
          when /^gemini-/
            "Google Gemini"
          when /^claude-/
            "Anthropic"
          when /^sonar-/, /perplexity/
            "Perplexity AI"
          when /^command-/
            "Cohere"
          when /^mixtral-/, /^llama-/, /^gemma-/
            "Groq"
          else
            "Unknown Provider"
          end
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
                                   extract_span_attribute("user_prompt")
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
            "frequency_penalty" => extract_span_attribute("agent.frequency_penalty") || extract_span_attribute("frequency_penalty"),
            "presence_penalty" => extract_span_attribute("agent.presence_penalty") || extract_span_attribute("presence_penalty"),
            "tool_choice" => extract_span_attribute("agent.tool_choice") || extract_span_attribute("tool_choice"),
            "parallel_tool_calls" => extract_span_attribute("agent.parallel_tool_calls"),
            "response_format" => extract_span_attribute("agent.response_format") || extract_span_attribute("response_format"),
            "tools_count" => extract_span_attribute("agent.tools_count") || extract_span_attribute("tools.count")
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
          div(id: "configuration", class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200 scroll-mt-6") do
            # Modern compact header
            div(class: "px-4 py-3 border-b border-emerald-200 bg-emerald-50") do
              div(class: "flex items-center gap-2") do
                i(class: "bi bi-gear text-emerald-600 text-lg")
                h3(class: "text-base font-semibold text-emerald-900") { "Agent Configuration" }
              end
            end

            # Clean table layout
            div(class: "overflow-x-auto") do
              table(class: "min-w-full divide-y divide-gray-200") do
                # Table header
                thead(class: "bg-gray-50") do
                  tr do
                    th(class: "px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-1/3") { "Parameter" }
                    th(class: "px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Value" }
                  end
                end

                # Table body
                tbody(class: "bg-white divide-y divide-gray-100") do
                  # Basic agent information section
                  render_table_section_header("Basic Information")
                  render_table_row("Agent Name", agent_name)
                  render_table_row("Provider", provider_name)
                  render_table_row("Model", model_name, monospace: true)
                  render_table_row_with_block("Execution Status") { render_status_badge(@span.status) }
                  render_table_row_with_block("Duration") { render_duration_badge(@span.duration_ms) }
                  render_table_row("Tools Available", agent_config["tools_count"] || "0")

                  # Model parameters section
                  render_table_section_header("Model Parameters")
                  render_table_row_with_block("Temperature") { render_param_value(agent_config["temperature"]) }
                  render_table_row_with_block("Max Tokens") { render_param_value(agent_config["max_tokens"]) }
                  render_table_row_with_block("Top P") { render_param_value(agent_config["top_p"]) }
                  render_table_row_with_block("Frequency Penalty") { render_param_value(agent_config["frequency_penalty"]) }
                  render_table_row_with_block("Presence Penalty") { render_param_value(agent_config["presence_penalty"]) }
                  render_table_row_with_block("Parallel Tool Calls") { render_param_value(agent_config["parallel_tool_calls"]) }

                  # Tool configuration section (if applicable)
                  if agent_config["tool_choice"] && agent_config["tool_choice"] != "N/A"
                    render_table_row_json("Tool Choice", agent_config["tool_choice"])
                  end

                  # Response format section (if applicable)
                  if agent_config["response_format"] && agent_config["response_format"] != "N/A"
                    render_table_row_json("Response Format Schema", agent_config["response_format"])
                  end
                end
              end
            end
          end
        end

        # Render table section header (gray background row)
        def render_table_section_header(title)
          tr(class: "bg-gray-50") do
            td(colspan: "2", class: "px-4 py-2 text-xs font-semibold text-gray-700 uppercase tracking-wider") do
              title
            end
          end
        end

        # Render standard table row with string value
        def render_table_row(label, value, monospace: false)
          tr(class: "hover:bg-gray-50 transition-colors") do
            td(class: "px-4 py-2 text-sm font-medium text-gray-600 whitespace-nowrap") do
              plain label
            end
            td(class: "px-4 py-2 text-sm text-gray-900 #{'font-mono text-xs' if monospace}") do
              plain value.to_s
            end
          end
        end

        # Render table row with block for component content
        def render_table_row_with_block(label, &block)
          tr(class: "hover:bg-gray-50 transition-colors") do
            td(class: "px-4 py-2 text-sm font-medium text-gray-600 whitespace-nowrap") do
              plain label
            end
            td(class: "px-4 py-2 text-sm text-gray-900") do
              # Execute the block inside the table cell context
              block.call if block
            end
          end
        end

        # Render full-width row with JSON formatting (for Schema)
        def render_table_row_json(label, value)
          # Full-width header row for the label
          tr(class: "bg-gray-50") do
            td(colspan: "2", class: "px-4 py-2 text-xs font-semibold text-gray-700 uppercase tracking-wider") do
              label
            end
          end
          # Full-width data row for JSON
          tr(class: "hover:bg-gray-50 transition-colors") do
            td(colspan: "2", class: "px-4 py-2") do
              if is_json_value?(value)
                pre(class: "text-xs bg-gray-50 p-2 rounded border overflow-x-auto text-gray-900 max-h-96") do
                  code(class: "language-json") do
                    format_json_display(value)
                  end
                end
              else
                span(class: "text-sm text-gray-900 font-mono") { value }
              end
            end
          end
        end

        # Render parameter values with badges for N/A
        def render_param_value(value)
          if value.nil? || value == "N/A"
            span(class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-600") { "N/A" }
          else
            plain value.to_s
          end
        end

        # ============================================
        # Tab Content Methods (without card wrappers)
        # ============================================

        # Configuration tab content - table layout for agent settings
        def render_agent_configuration_content
          div(class: "overflow-x-auto") do
            table(class: "min-w-full divide-y divide-gray-200") do
              # Table header
              thead(class: "bg-gray-50") do
                tr do
                  th(class: "px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-1/3") { "Parameter" }
                  th(class: "px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Value" }
                end
              end

              # Table body
              tbody(class: "bg-white divide-y divide-gray-100") do
                # Basic agent information section
                render_table_section_header("Basic Information")
                render_table_row("Agent Name", agent_name)
                render_table_row("Provider", provider_name)
                render_table_row("Model", model_name, monospace: true)
                render_table_row_with_block("Execution Status") { render_status_badge(@span.status) }
                render_table_row_with_block("Duration") { render_duration_badge(@span.duration_ms) }
                render_table_row("Tools Available", agent_config["tools_count"] || "0")

                # Model parameters section
                render_table_section_header("Model Parameters")
                render_table_row_with_block("Temperature") { render_param_value(agent_config["temperature"]) }
                render_table_row_with_block("Max Tokens") { render_param_value(agent_config["max_tokens"]) }
                render_table_row_with_block("Top P") { render_param_value(agent_config["top_p"]) }
                render_table_row_with_block("Frequency Penalty") { render_param_value(agent_config["frequency_penalty"]) }
                render_table_row_with_block("Presence Penalty") { render_param_value(agent_config["presence_penalty"]) }
                render_table_row_with_block("Parallel Tool Calls") { render_param_value(agent_config["parallel_tool_calls"]) }

                # Tool configuration section (if applicable)
                if agent_config["tool_choice"] && agent_config["tool_choice"] != "N/A"
                  render_table_row_json("Tool Choice", agent_config["tool_choice"])
                end

                # Response format section (if applicable)
                if agent_config["response_format"] && agent_config["response_format"] != "N/A"
                  render_table_row_json("Response Format Schema", agent_config["response_format"])
                end
              end
            end
          end
        end

        # Response tab content - JSON response display
        def render_agent_response_section_content
          div(class: "space-y-4") do
            # Header with tags
            div(class: "flex items-center gap-3 mb-4") do
              i(class: "bi bi-robot text-purple-600 text-lg")
              h3(class: "text-lg font-semibold text-purple-900") { "Agent JSON Response" }
              span(class: "px-2 py-1 text-xs font-medium bg-purple-100 text-purple-800 rounded-full") { "LLM Output" }
            end

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

        # Statistics tab content - conversation statistics display
        def render_conversation_statistics_content
          return unless conversation_stats_data

          div(class: "space-y-4") do
            # Header
            div(class: "flex items-center gap-3 mb-4") do
              i(class: "bi bi-bar-chart text-purple-600 text-lg")
              h3(class: "text-lg font-semibold text-purple-900") { "Conversation Statistics" }
            end

            dl(class: "grid grid-cols-2 gap-x-4 gap-y-4 sm:grid-cols-3") do
              render_stat_item("Total Messages", conversation_stats_data["total_messages"])
              render_stat_item("User Messages", conversation_stats_data["user_messages"])
              render_stat_item("Assistant Messages", conversation_stats_data["assistant_messages"])
              render_stat_item("Tool Calls", conversation_stats_data["tool_calls"])
              render_stat_item("Has System Message", conversation_stats_data["has_system_message"] ? "Yes" : "No")
            end
          end
        end

        # Conversation flow content
        def render_conversation_flow_content
          div(class: "space-y-4") do
            # Header
            div(class: "flex items-center gap-3 mb-4") do
              i(class: "bi bi-chat-dots text-green-600 text-lg")
              h3(class: "text-lg font-semibold text-green-900") { "Conversation Flow" }
            end

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

        # Tools tab content - tool executions display
        def render_tool_executions_content
          div(class: "space-y-4") do
            # Header
            div(class: "flex items-center gap-3 mb-4") do
              i(class: "bi bi-tools text-yellow-600 text-lg")
              h3(class: "text-lg font-semibold text-yellow-900") do
                plain "Tool Executions (#{tool_executions_data.length})"
              end
            end

            div(class: "space-y-3") do
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

        # Context tab content - context variables display
        def render_context_content
          div(class: "space-y-4") do
            # Header
            div(class: "flex items-center gap-3 mb-4") do
              i(class: "bi bi-layers text-purple-600 text-lg")
              h3(class: "text-lg font-semibold text-purple-900") { "Context Variables" }
            end

            render_json_section("Agent Context", context_data, collapsed: true, use_json_highlighter: true)
          end
        end

        # ============================================
        # Original section methods (for backward compatibility)
        # ============================================

        def render_context_information
          div(id: "context", class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200 scroll-mt-6") do
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
          div(id: "system-prompt", class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200 scroll-mt-6") do
            div(class: "px-4 py-5 sm:px-6 border-b border-blue-200 bg-blue-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-gear text-blue-600 text-lg")
                h3(class: "text-lg font-semibold text-blue-900") { "System Prompt" }
                span(class: "px-2 py-1 text-xs font-medium bg-blue-100 text-blue-800 rounded-full") { "LLM Input" }
                # Show content type indicator
                if looks_like_json?(system_prompt_content)
                  span(class: "px-2 py-1 text-xs font-medium bg-purple-100 text-purple-800 rounded-full") { "JSON" }
                end
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              render_full_content_with_formatting(system_prompt_content, "system-prompt")
            end
          end
        end

        def render_user_prompt_section
          div(id: "user-prompt", class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200 scroll-mt-6") do
            div(class: "px-4 py-5 sm:px-6 border-b border-green-200 bg-green-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-person text-green-600 text-lg")
                h3(class: "text-lg font-semibold text-green-900") { "User Prompt" }
                span(class: "px-2 py-1 text-xs font-medium bg-green-100 text-green-800 rounded-full") { "LLM Input" }
                # Show content type indicator
                if looks_like_json?(user_prompt_content)
                  span(class: "px-2 py-1 text-xs font-medium bg-blue-100 text-blue-800 rounded-full") { "JSON" }
                end
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              render_full_content_with_formatting(user_prompt_content, "user-prompt")
            end
          end
        end

        # Render full content with appropriate formatting based on content type
        def render_full_content_with_formatting(content, section_id)
          return div(class: "text-gray-500 italic") { "No content provided" } if content.blank?

          if looks_like_json?(content)
            render_full_json_content(content, section_id)
          elsif looks_like_markdown?(content)
            render_full_markdown_content(content, section_id)
          else
            render_full_text_content(content, section_id)
          end
        end

        # Render full JSON content with syntax highlighting
        def render_full_json_content(content, section_id)
          text_id = "#{section_id}-#{@span.span_id}"

          div(data: { controller: "json-highlight" }) do
            div(id: text_id, class: "bg-gray-50 p-4 rounded-lg border relative") do
              pre(class: "text-sm bg-white p-4 rounded border overflow-x-auto text-gray-900") do
                code(
                  class: "language-json",
                  data: { json_highlight_target: "json" }
                ) do
                  format_content(content, force_type: :json)
                end
              end
            end
          end
        end

        # Render full markdown content
        def render_full_markdown_content(content, section_id)
          text_id = "#{section_id}-#{@span.span_id}"

          div(id: text_id, class: "bg-gray-50 p-4 rounded-lg border text-sm prose prose-sm max-w-none") do
            raw markdown_to_html(content)
          end
        end

        # Render full plain text content
        def render_full_text_content(content, section_id)
          text_id = "#{section_id}-#{@span.span_id}"

          div(id: text_id, class: "bg-gray-50 p-4 rounded-lg border text-sm font-mono whitespace-pre-wrap") do
            plain content
          end
        end

        def render_agent_response_section
          div(id: "response", class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200 scroll-mt-6") do
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
          div(id: "conversation-flow", class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200 scroll-mt-6") do
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
          div(id: "tool-executions", class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200 scroll-mt-6") do
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

          div(id: "statistics", class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200 scroll-mt-6") do
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
          preview_text = text[0..1000] + "..."  # Increased from 300 to 1000 chars

          div(data: { controller: "span-detail" }) do
            # RAAF EVAL: Full text visible by default for prompt visibility
            div(id: text_id, class: "bg-gray-50 p-4 rounded-lg border text-sm font-mono whitespace-pre-wrap") do
              plain text
            end
            # Preview hidden by default
            div(id: "#{text_id}-preview", class: "hidden bg-gray-50 p-4 rounded-lg border text-sm font-mono whitespace-pre-wrap") do
              plain preview_text
            end
            button(
              class: "mt-3 text-sm text-blue-600 hover:text-blue-800 px-3 py-1 hover:bg-blue-50 rounded transition-colors",
              data: {
                action: "click->span-detail#toggleSection",
                target: text_id,
                expanded_text: "Show Less",
                collapsed_text: "Show More"
              }
            ) { "Show Less" }
          end
        end

        def render_expandable_markdown_text(text, section_id)
          text_id = "#{section_id}-#{@span.span_id}"
          preview_text = text[0..1000] + "..."  # Increased from 300 to 1000 chars

          div(data: { controller: "span-detail" }) do
            # RAAF EVAL: Full content visible by default for prompt visibility
            div(id: text_id, class: "bg-gray-50 p-4 rounded-lg border text-sm prose prose-sm max-w-none") do
              if looks_like_markdown?(text)
                raw markdown_to_html(text)
              else
                div(class: "font-mono whitespace-pre-wrap") do
                  plain text
                end
              end
            end
            # Preview hidden by default
            div(id: "#{text_id}-preview", class: "hidden bg-gray-50 p-4 rounded-lg border text-sm prose prose-sm max-w-none") do
              if looks_like_markdown?(preview_text)
                raw markdown_to_html(preview_text)
              else
                div(class: "font-mono whitespace-pre-wrap") do
                  plain preview_text
                end
              end
            end
            button(
              class: "mt-3 text-sm text-blue-600 hover:text-blue-800 px-3 py-1 hover:bg-blue-50 rounded transition-colors",
              data: {
                action: "click->span-detail#toggleSection",
                target: text_id,
                expanded_text: "Show Less",
                collapsed_text: "Show More"
              }
            ) { "Show Less" }
          end
        end

        def render_expandable_json_text(json_text, section_id)
          text_id = "#{section_id}-#{@span.span_id}"
          preview_text = json_text[0..2000] + "..."  # Increased from 500 to 2000 chars

          div(data: { controller: "span-detail json-highlight" }) do
            # RAAF EVAL: Full JSON visible by default for debugging
            div(id: text_id, class: "bg-gray-50 p-4 rounded-lg border relative") do
              pre(class: "text-sm bg-white p-4 rounded border overflow-x-auto text-gray-900") do
                code(
                  class: "language-json",
                  data: { json_highlight_target: "json" }
                ) do
                  format_content(json_text, force_type: :json)
                end
              end
            end
            # Preview hidden by default
            div(id: "#{text_id}-preview", class: "hidden bg-gray-50 p-4 rounded-lg border relative") do
              pre(class: "text-sm bg-white p-4 rounded border overflow-x-auto text-gray-900") do
                code(
                  class: "language-json",
                  data: { json_highlight_target: "json" }
                ) do
                  format_content(preview_text, force_type: :json)
                end
              end
            end
            button(
              class: "mt-3 text-sm text-purple-600 hover:text-purple-800 px-3 py-1 hover:bg-purple-50 rounded transition-colors",
              data: {
                action: "click->span-detail#toggleSection click->json-highlight#highlightNew",
                target: text_id,
                expanded_text: "Show Less",
                collapsed_text: "Show More"
              }
            ) { "Show Less" }
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

        # Check if continuous evaluation gem is available
        def continuous_evaluation_available?
          defined?(RAAF::Eval::Continuous::PolicyMatcher) &&
            defined?(RAAF::Eval::Models::EvaluationPolicy)
        end

        # Render the evaluation policies section using the ApplicablePoliciesSection component
        def render_evaluation_policies_section
          return unless continuous_evaluation_available?

          render ApplicablePoliciesSection.new(span: @span)
        end
      end
    end
  end
end
