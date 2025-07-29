module Views
  module OpenaiAgents
    module Debug
      module Prompts
          class Index < ::Components::BaseComponent
            def initialize(prompts:, agents:, model_types:, recent_executions:, execution_result: nil, debug_output: nil, object_info: nil, session_id: nil, ai_params: nil, params: {})
            @prompts = prompts
            @agents = agents
            @model_types = model_types
            @recent_executions = recent_executions
            @execution_result = execution_result
            @debug_output = debug_output
            @object_info = object_info
            @session_id = session_id || SecureRandom.uuid
            @ai_params = ai_params || {}
            @params = params
          end

          def view_template
            Container(type: :default, class: "py-6") do
              PageHeader(
                title: "AI Debug Interface",
                subtitle: "Test and debug AI prompts and agents",
                icon: "bug"
              )

              # Top row - Configuration and Recent Executions side by side
              div(class: "grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6") do
                # Left - Configuration
                render_configuration_card

                # Right - Recent Executions
                render_recent_executions if recent_executions.any?
              end

              # Bottom row - Full width Results
              if execution_result && (execution_result.is_a?(Hash) || execution_result.respond_to?(:to_h))
                div(class: "mt-6") do
                  render_results_card
                end
              end
            end
          end

          private

          attr_reader :prompts, :agents, :model_types, :recent_executions,
                      :execution_result, :debug_output, :object_info, :session_id, :ai_params, :params

          # Helper to access execution_result data whether it's a Hash or OpenStruct
          def result_value(key)
            return nil unless execution_result

            # First check if the key exists directly on execution_result
            if execution_result.is_a?(Hash)
              value = execution_result[key]
            elsif execution_result.respond_to?(key)
              value = execution_result.send(key)
            else
              value = nil
            end

            # If not found and we have a nested execution_result, check there too
            if value.nil? && execution_result.respond_to?(:execution_result)
              nested = execution_result.execution_result
              if nested.is_a?(Hash)
                value = nested[key]
              elsif nested.respond_to?(key)
                value = nested.send(key)
              end
            end

            value
          end

          def render_configuration_card
            Card do
              CardHeader(
                title: "Configuration",
                subtitle: "Select prompt/agent and object to test"
              )

              Container(class: "p-6", data: { controller: "ai-debug" }) do
                form_with(
                  url: execute_openai_agents_debug_prompts_path,
                  method: :post,
                  local: true,
                  data: { turbo: false },
                  class: "space-y-4"
                ) do |form|
                  # Hidden type field - always prompt
                  input(type: "hidden", name: "type", value: "prompt")

                  # Prompt selection
                  div(class: "space-y-2") do
                    label(class: "text-sm font-medium text-gray-700") { "Select Prompt" }

                    # Prompts dropdown
                    select(
                      name: "class_name",
                      class: "mt-1 block w-full px-3 py-2 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 text-gray-900 dark:text-gray-100",
                      data: {
                        action: "change->ai-debug#updateObjectRequirement"
                      }
                    ) do
                      option(value: "") { "-- Select a prompt --" }
                      prompts.each do |prompt|
                        option(value: prompt[:class_name]) { prompt[:name] }
                      end
                    end
                  end

                  # Object selection
                  div(class: "space-y-2", data: { "ai-debug-target": "objectSection" }) do
                    label(class: "text-sm font-medium text-gray-700") { "Object (Optional)" }

                    div(class: "grid grid-cols-2 gap-2") do
                      select(
                        name: "model_type",
                        id: "model_type_select",
                        class: "block w-full px-3 py-2 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 text-gray-900 dark:text-gray-100",
                        data: {
                          "ai-debug-target": "modelType",
                          action: "change->ai-debug#loadObjects"
                        }
                      ) do
                        option(value: "") { "-- Select type --" }
                        model_types.each do |type|
                          option(value: type[:type]) { type[:name] }
                        end
                      end

                      select(
                        name: "model_id",
                        id: "model_id_select",
                        class: "block w-full px-3 py-2 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 text-gray-900 dark:text-gray-100",
                        data: { "ai-debug-target": "modelId" },
                        disabled: true
                      ) do
                        option(value: "") { "-- Select object --" }
                      end
                    end

                    p(class: "text-xs text-gray-500 mt-1") do
                      "Some prompts/agents require an object to work with"
                    end
                  end


                  # Hidden field for session ID
                  input(type: "hidden", name: "session_id", value: session_id)

                  # AI Parameter Overrides section
                  div(class: "mt-6 pt-4 border-t border-gray-200") do
                    h3(class: "text-sm font-medium text-gray-700 mb-3") { "AI Parameter Overrides (Optional)" }

                    # Collapsible parameters section
                    # Check if it was previously open based on params only
                    details_open = params[:ai_params_expanded] == "true"

                    details(
                      class: "space-y-4",
                      open: details_open,
                      data: {
                        controller: "details-state",
                        action: "toggle->details-state#updateState"
                      }
                    ) do
                      # Hidden field to track AI params expanded state - must be inside the details element
                      input(type: "hidden", name: "ai_params_expanded", value: details_open.to_s, data: { "details-state-target": "expandedState" })

                      summary(class: "cursor-pointer text-sm text-gray-600 hover:text-gray-800") do
                        "Click to customize AI model parameters"
                      end

                      div(class: "grid grid-cols-2 gap-4 mt-4", data: { controller: "ai-debug-provider" }) do
                        # Temperature
                        div(class: "space-y-2") do
                          label(class: "text-sm font-medium text-gray-700", for: "temperature") { "Temperature" }
                          input(
                            type: "number",
                            id: "temperature",
                            name: "ai_params[temperature]",
                            min: "0",
                            max: "2",
                            step: "0.1",
                            placeholder: "0.7",
                            class: "block w-full px-3 py-2 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 text-gray-900 dark:text-gray-100"
                          )
                          div(class: "text-xs text-gray-500") do
                            p { "Controls response randomness and creativity (0-2)" }
                            p(class: "mt-1") { "• 0.0 = Deterministic, focused responses" }
                            p { "• 0.7 = Balanced creativity (default)" }
                            p { "• 1.0+ = More creative, varied responses" }
                          end
                        end

                        # Max Tokens
                        div(class: "space-y-2") do
                          label(class: "text-sm font-medium text-gray-700", for: "max_tokens") { "Max Tokens" }
                          input(
                            type: "number",
                            id: "max_tokens",
                            name: "ai_params[max_tokens]",
                            min: "1",
                            max: "4096",
                            placeholder: "2048",
                            class: "block w-full px-3 py-2 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 text-gray-900 dark:text-gray-100"
                          )
                          div(class: "text-xs text-gray-500") do
                            p { "Maximum tokens in the response" }
                            p(class: "mt-1") { "• 1 token ≈ 0.75 words" }
                            p { "• Higher = longer responses" }
                            p { "• May cut off if limit reached" }
                          end
                        end

                        # Max Turns
                        div(class: "space-y-2") do
                          label(class: "text-sm font-medium text-gray-700", for: "max_turns") { "Max Turns" }
                          input(
                            type: "number",
                            id: "max_turns",
                            name: "ai_params[max_turns]",
                            min: "1",
                            max: "50",
                            placeholder: "Default from agent",
                            class: "block w-full px-3 py-2 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 text-gray-900 dark:text-gray-100"
                          )
                          div(class: "text-xs text-gray-500") do
                            p { "Maximum conversation turns for the agent" }
                            p(class: "mt-1") { "• 1 turn = 1 tool call + 1 response" }
                            p { "• Higher = more tool usage allowed" }
                            p { "• Prevents infinite loops" }
                          end
                        end

                        # Top P
                        div(class: "space-y-2") do
                          label(class: "text-sm font-medium text-gray-700", for: "top_p") { "Top P" }
                          input(
                            type: "number",
                            id: "top_p",
                            name: "ai_params[top_p]",
                            min: "0",
                            max: "1",
                            step: "0.01",
                            placeholder: "1.0",
                            class: "block w-full px-3 py-2 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 text-gray-900 dark:text-gray-100"
                          )
                          div(class: "text-xs text-gray-500") do
                            p { "Nucleus sampling threshold (0-1)" }
                            p(class: "mt-1") { "• Alternative to temperature" }
                            p { "• 0.1 = Only very likely tokens" }
                            p { "• 1.0 = Consider all tokens" }
                          end
                        end

                        # Frequency Penalty
                        div(class: "space-y-2") do
                          label(class: "text-sm font-medium text-gray-700", for: "frequency_penalty") { "Frequency Penalty" }
                          input(
                            type: "number",
                            id: "frequency_penalty",
                            name: "ai_params[frequency_penalty]",
                            min: "-2",
                            max: "2",
                            step: "0.1",
                            placeholder: "0",
                            class: "block w-full px-3 py-2 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 text-gray-900 dark:text-gray-100"
                          )
                          div(class: "text-xs text-gray-500") do
                            p { "Reduces word/phrase repetition (-2 to 2)" }
                            p(class: "mt-1") { "• Positive = Penalize repetition" }
                            p { "• 0 = No penalty (default)" }
                            p { "• Negative = Encourage repetition" }
                          end
                        end

                        # Presence Penalty
                        div(class: "space-y-2") do
                          label(class: "text-sm font-medium text-gray-700", for: "presence_penalty") { "Presence Penalty" }
                          input(
                            type: "number",
                            id: "presence_penalty",
                            name: "ai_params[presence_penalty]",
                            min: "-2",
                            max: "2",
                            step: "0.1",
                            placeholder: "0",
                            class: "block w-full px-3 py-2 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 text-gray-900 dark:text-gray-100"
                          )
                          div(class: "text-xs text-gray-500") do
                            p { "Encourages topic diversity (-2 to 2)" }
                            p(class: "mt-1") { "• Positive = Push new topics" }
                            p { "• 0 = No penalty (default)" }
                            p { "• Works regardless of frequency" }
                          end
                        end

                        # Provider Override
                        div(class: "space-y-2") do
                          label(class: "text-sm font-medium text-gray-700", for: "provider_override") { "Provider Override" }
                          select(
                            id: "provider_override",
                            name: "ai_params[provider]",
                            class: "block w-full px-3 py-2 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 text-gray-900 dark:text-gray-100",
                            data: {
                              action: "change->ai-debug-provider#loadModels",
                              "ai-debug-provider-target": "providerSelect"
                            }
                          ) do
                            option(value: "") { "Use agent default" }
                            # Providers will be loaded dynamically
                          end
                          div(class: "text-xs text-gray-500") do
                            p { "Choose a different AI provider" }
                            p(class: "mt-1") { "• Each provider has different models" }
                            p { "• Requires provider API keys" }
                          end
                        end

                        # Model Override
                        div(class: "space-y-2") do
                          label(class: "text-sm font-medium text-gray-700", for: "model_override") { "Model Override" }
                          select(
                            id: "model_override",
                            name: "ai_params[model]",
                            class: "block w-full px-3 py-2 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 text-gray-900 dark:text-gray-100",
                            data: {
                              "ai-debug-provider-target": "modelSelect",
                              "ai-debug-target": "modelSelect"
                            },
                            disabled: true
                          ) do
                            option(value: "") { "Select a provider first" }
                          end
                          div(class: "text-xs text-gray-500") do
                            p { "Override the agent's default model" }
                            p(class: "mt-1") { "• Different models have different capabilities" }
                            p { "• Some models are faster but less capable" }
                          end
                        end

                        # Tool Choice Override
                        div(class: "col-span-2 space-y-2") do
                          label(class: "text-sm font-medium text-gray-700", for: "tool_choice") { "Tool Choice Override" }
                          select(
                            id: "tool_choice",
                            name: "ai_params[tool_choice]",
                            class: "block w-full px-3 py-2 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 text-gray-900 dark:text-gray-100"
                          ) do
                            option(value: "") { "Use agent default" }
                            option(value: "auto") { "Auto - Let model decide" }
                            option(value: "required") { "Required - Must use a tool" }
                            option(value: "none") { "None - No tool usage" }
                          end
                          div(class: "text-xs text-gray-500") do
                            p { "Control tool usage behavior" }
                            p(class: "mt-1") { "• Auto = Model decides when to use tools" }
                            p { "• Required = Must use at least one tool" }
                            p { "• None = Disable all tool usage" }
                          end
                        end
                      end
                    end
                  end

                  # Execute button
                  div(class: "pt-4") do
                    button(
                      type: "submit",
                      class: "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                    ) do
                      i(class: "fas fa-file-text mr-2")
                      plain "Generate Prompt"
                    end
                  end
                end
              end
            end
          end

          def render_results_card
            Card do
              div(class: "flex items-center justify-between") do
                div(class: "flex items-center gap-3") do
                  # Error/success icon with warning state
                  if result_value(:success)
                    if result_value(:max_turns_reached)
                      i(class: "fas fa-exclamation-circle text-yellow-500 text-2xl")
                    else
                      i(class: "fas fa-check-circle text-green-500 text-2xl")
                    end
                  else
                    i(class: "fas fa-times-circle text-red-500 text-2xl")
                  end

                  CardHeader(
                    title: "Execution Results",
                    subtitle: if result_value(:max_turns_reached)
                      "Completed (max turns reached)"
                              elsif result_value(:success)
                      "Successfully executed"
                              else
                      "Execution failed"
                              end
                  )
                end

                # Show Execute Agent button if this is a prompt execution and it succeeded
                if result_value(:success) && !result_value(:agent_result) && result_value(:prompt_class)
                  div(class: "mr-6", data: { controller: "ai-debug" }) do
                    # Execute form
                    form_with(
                      url: execute_agent_openai_agents_debug_prompts_path,
                      method: :post,
                      local: true,
                      data: {
                        turbo: false,
                        action: "submit->ai-debug#showAgentLoadingState",
                        "ai-debug-target": "executeForm"
                      },
                      class: "inline-block"
                    ) do |f|
                      f.hidden_field :prompt_class, value: result_value(:prompt_class)
                      f.hidden_field :context, value: result_value(:prompt_context)&.to_json
                      f.hidden_field :object_type, value: object_info ? object_info[:type] : nil
                      f.hidden_field :object_id, value: object_info ? object_info[:id] : nil
                      f.hidden_field :session_id, value: session_id
                      f.hidden_field :ai_params_expanded, value: params[:ai_params_expanded] || "false"

                      # Preserve AI parameter overrides
                      if ai_params.present?
                        ai_params.each do |key, value|
                          f.hidden_field "ai_params[#{key}]", value: value if value.present?
                        end
                      end

                      button(
                        type: "submit",
                        class: "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500",
                        data: { "ai-debug-target": "agentButton" }
                      ) do
                        i(class: "fas fa-play mr-2")
                        plain "Execute Agent"
                      end
                    end

                    # Stop button (hidden by default)
                    div(
                      class: "hidden",
                      data: { "ai-debug-target": "stopForm" }
                    ) do
                      button(
                        type: "button",
                        class: "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500",
                        data: {
                          action: "click->ai-debug#stopExecution",
                          "session-id": session_id
                        }
                      ) do
                        i(class: "fas fa-stop mr-2")
                        plain "Stop Agent"
                      end
                    end
                  end
                end
              end

              Container(class: "p-6") do
                # Show warning if max turns was reached
                if result_value(:max_turns_reached)
                  div(class: "mb-4") do
                    Alert(
                      type: :warning,
                      title: "Maximum turns reached",
                      message: "The agent completed #{result_value(:warning)} You can increase the max_turns limit in AI Parameter Overrides."
                    )
                  end
                end

                # Define variables at the proper scope for both tabs and panels
                has_error = !result_value(:success) && result_value(:error_details)
                is_agent_execution = result_value(:agent_result).present?

                # Check if we have conversation messages
                agent_result_data = result_value(:agent_result)
                has_conversation = agent_result_data.is_a?(Hash) && (agent_result_data[:messages].present? || agent_result_data["messages"].present?)

                # Always show conversation tab
                show_conversation_tab = true

                # Tabbed interface
                div(data: { controller: "tabs" }) do
                  # Tab headers
                  div(class: "border-b border-gray-200") do
                    nav(class: "-mb-px flex space-x-8") do
                      # Track if this is the first tab for active styling
                      first_tab = true

                      # Agent Result tab (only show if successful or no error details)
                      if result_value(:agent_result) && !has_error
                        button(
                          class: "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm #{first_tab ? 'border-blue-500 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'}",
                          data: { action: "click->tabs#selectTab", tabs_target: "tab", tab_panel: "agent-result" }
                        ) do
                          span(class: "flex items-center gap-2") do
                            i(class: "fas fa-robot text-green-500")
                            plain "Agent Result"
                          end
                        end
                        first_tab = false
                      end

                      # System Prompt tab
                      if result_value(:system_prompt)
                        button(
                          class: "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm #{first_tab && !is_agent_execution ? 'border-blue-500 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'}",
                          data: { action: "click->tabs#selectTab", tabs_target: "tab", tab_panel: "system-prompt" }
                        ) do
                          span(class: "flex items-center gap-2") do
                            i(class: "fas fa-cog text-blue-500")
                            plain "System Prompt"
                          end
                        end
                        first_tab = false
                      end

                      # User Prompt tab
                      if result_value(:user_prompt)
                        button(
                          class: "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300",
                          data: { action: "click->tabs#selectTab", tabs_target: "tab", tab_panel: "user-prompt" }
                        ) do
                          span(class: "flex items-center gap-2") do
                            i(class: "fas fa-user text-green-500")
                            plain "User Prompt"
                          end
                        end
                        first_tab = false
                      end

                      # Context tab
                      if result_value(:prompt_context)
                        button(
                          class: "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300",
                          data: { action: "click->tabs#selectTab", tabs_target: "tab", tab_panel: "context" }
                        ) do
                          span(class: "flex items-center gap-2") do
                            i(class: "fas fa-database text-purple-500")
                            plain "Context"
                          end
                        end
                        first_tab = false
                      end

                      # Conversation tab (for agent executions)
                      if show_conversation_tab
                        button(
                          class: "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300",
                          data: { action: "click->tabs#selectTab", tabs_target: "tab", tab_panel: "conversation" }
                        ) do
                          span(class: "flex items-center gap-2") do
                            i(class: "fas fa-comments text-indigo-500")
                            plain "Conversation"
                          end
                        end
                        first_tab = false
                      end

                      # Object Info tab
                      if object_info
                        button(
                          class: "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300",
                          data: { action: "click->tabs#selectTab", tabs_target: "tab", tab_panel: "object-info" }
                        ) do
                          span(class: "flex items-center gap-2") do
                            i(class: "fas fa-info-circle text-indigo-500")
                            plain "Object Info"
                          end
                        end
                        first_tab = false
                      end

                      # Streaming Output tab (always shown)
                      button(
                        class: "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300",
                        data: { action: "click->tabs#selectTab", tabs_target: "tab", tab_panel: "streaming-output" }
                      ) do
                        span(class: "flex items-center gap-2") do
                          i(class: "fas fa-stream text-blue-500")
                          plain "Live Output"
                        end
                      end
                      first_tab = false

                      # Debug Output tab
                      if debug_output.present?
                        button(
                          class: "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300",
                          data: { action: "click->tabs#selectTab", tabs_target: "tab", tab_panel: "debug-output" }
                        ) do
                          span(class: "flex items-center gap-2") do
                            i(class: "fas fa-terminal text-gray-500")
                            plain "Debug Output"
                          end
                        end
                        first_tab = false
                      end

                      # Error tab (if present) - show first if there's an error
                      if !result_value(:success) && result_value(:error_details)
                        button(
                          class: "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm #{has_error && first_tab ? 'border-red-500 text-red-600' : 'border-transparent text-red-500 hover:text-red-700 hover:border-red-300'}",
                          data: { action: "click->tabs#selectTab", tabs_target: "tab", tab_panel: "error-details" }
                        ) do
                          span(class: "flex items-center gap-2") do
                            i(class: "fas fa-exclamation-triangle")
                            plain "Error Details"
                          end
                        end
                      end
                    end
                  end

                  # Tab panels
                  div(class: "mt-4") do
                    # Agent Result panel (shown by default if agent execution and no error)
                    if result_value(:agent_result)
                      div(id: "agent-result", class: (is_agent_execution && !has_error) ? "" : "hidden", data: { tabs_target: "panel" }) do
                        render_agent_result_panel
                      end
                    end

                    # System Prompt panel (shown by default if prompt execution and no error)
                    if result_value(:system_prompt)
                      div(id: "system-prompt", class: (!is_agent_execution && !has_error) ? "" : "hidden", data: { tabs_target: "panel" }) do
                        render_system_prompt_panel
                      end
                    end

                    # User Prompt panel
                    if result_value(:user_prompt)
                      div(id: "user-prompt", class: "hidden", data: { tabs_target: "panel" }) do
                        render_user_prompt_panel
                      end
                    end

                    # Context panel
                    if result_value(:prompt_context)
                      div(id: "context", class: "hidden", data: { tabs_target: "panel" }) do
                        render_context_panel
                      end
                    end

                    # Conversation panel
                    if show_conversation_tab
                      div(id: "conversation", class: "hidden", data: { tabs_target: "panel", controller: "conversation-updates", "conversation-updates-session-id-value": session_id }) do
                        render_conversation_panel
                      end
                    end

                    # Object Info panel
                    if object_info
                      div(id: "object-info", class: "hidden", data: { tabs_target: "panel" }) do
                        render_object_info_panel
                      end
                    end

                    # Streaming Output panel (always available)
                    div(id: "streaming-output", class: "hidden", data: { tabs_target: "panel" }) do
                      render_streaming_output_panel
                    end

                    # Debug Output panel
                    if debug_output.present?
                      div(id: "debug-output", class: "hidden", data: { tabs_target: "panel" }) do
                        render_debug_output_panel
                      end
                    end

                    # Error Details panel
                    if !result_value(:success) && result_value(:error_details)
                      # Show error panel by default if there's an error
                      div(id: "error-details", class: has_error ? "" : "hidden", data: { tabs_target: "panel" }) do
                        render_error_details_panel
                      end
                    end
                  end
                end
              end
            end
          end

          # Panel rendering methods
          def render_object_info_panel
            div(class: "bg-gray-50 rounded-lg p-4") do
              dl(class: "text-sm space-y-1") do
                object_info.each do |key, value|
                  div(class: "flex") do
                    dt(class: "font-medium text-gray-600 w-24") { "#{key.to_s.humanize}:" }
                    dd(class: "text-gray-900") { value.to_s }
                  end
                end
              end
            end
          end

          def render_context_panel
            initial_context = result_value(:initial_context) || result_value(:prompt_context)
            final_context = result_value(:final_context)

            div(class: "space-y-6") do
              # Initial Context
              div do
                h4(class: "font-medium text-gray-900 mb-2 flex items-center gap-2") do
                  i(class: "fas fa-play-circle text-blue-500")
                  plain "Initial Context"
                end
                pre(class: "bg-blue-50 p-4 rounded-lg overflow-x-auto text-sm") do
                  code { JSON.pretty_generate(initial_context) }
                end
              end

              # Final Context (if available and different from initial)
              if final_context && final_context != initial_context
                div do
                  h4(class: "font-medium text-gray-900 mb-2 flex items-center gap-2") do
                    i(class: "fas fa-check-circle text-green-500")
                    plain "Final Context (After Agent Execution)"
                  end
                  pre(class: "bg-green-50 p-4 rounded-lg overflow-x-auto text-sm") do
                    code { JSON.pretty_generate(final_context) }
                  end
                end

                # Context Changes Summary
                div do
                  h4(class: "font-medium text-gray-900 mb-2 flex items-center gap-2") do
                    i(class: "fas fa-exchange-alt text-purple-500")
                    plain "Context Changes"
                  end
                  div(class: "bg-purple-50 p-4 rounded-lg") do
                    render_context_changes(initial_context, final_context)
                  end
                end
              elsif final_context.nil? && result_value(:agent_result)
                # No final context available
                div(class: "bg-yellow-50 p-4 rounded-lg") do
                  p(class: "text-yellow-800 text-sm flex items-center gap-2") do
                    i(class: "fas fa-info-circle")
                    plain "Final context not captured. The agent may not support context tracking."
                  end
                end
              end
            end
          end

          def render_context_changes(initial, final)
            changes = detect_context_changes(initial, final)

            if changes.empty?
              p(class: "text-gray-600 text-sm") { "No changes detected in context." }
            else
              ul(class: "space-y-2 text-sm") do
                changes.each do |change|
                  li(class: "flex items-start gap-2") do
                    if change[:type] == :added
                      i(class: "fas fa-plus-circle text-green-500 mt-0.5")
                      div do
                        strong(class: "text-green-700") { "Added: #{change[:key]}" }
                        if change[:value].is_a?(Array) && change[:value].length > 0
                          div(class: "text-gray-600 mt-1") { "#{change[:value].length} items" }
                        elsif change[:value].is_a?(Hash)
                          div(class: "text-gray-600 mt-1") { "#{change[:value].keys.length} fields" }
                        else
                          div(class: "text-gray-600 mt-1 truncate") { change[:value].to_s }
                        end
                      end
                    elsif change[:type] == :modified
                      i(class: "fas fa-edit text-yellow-500 mt-0.5")
                      div do
                        strong(class: "text-yellow-700") { "Modified: #{change[:key]}" }
                        if change[:old].is_a?(Array) && change[:new].is_a?(Array)
                          div(class: "text-gray-600 mt-1") do
                            plain "#{change[:old].length} → #{change[:new].length} items"
                          end
                        elsif change[:old].is_a?(Numeric) && change[:new].is_a?(Numeric)
                          div(class: "text-gray-600 mt-1") do
                            plain "#{change[:old]} → #{change[:new]}"
                          end
                        else
                          div(class: "text-gray-600 mt-1") { "Value changed" }
                        end
                      end
                    elsif change[:type] == :removed
                      i(class: "fas fa-minus-circle text-red-500 mt-0.5")
                      div do
                        strong(class: "text-red-700") { "Removed: #{change[:key]}" }
                      end
                    end
                  end
                end
              end
            end
          end

          def detect_context_changes(initial, final)
            changes = []

            # Convert to hashes if needed
            initial_hash = initial.is_a?(Hash) ? initial : {}
            final_hash = final.is_a?(Hash) ? final : {}

            # Find added and modified keys
            final_hash.each do |key, value|
              if !initial_hash.key?(key)
                changes << { type: :added, key: key, value: value }
              elsif initial_hash[key] != value
                changes << { type: :modified, key: key, old: initial_hash[key], new: value }
              end
            end

            # Find removed keys
            initial_hash.each do |key, value|
              unless final_hash.key?(key)
                changes << { type: :removed, key: key, value: value }
              end
            end

            changes.sort_by { |c| [ c[:type].to_s, c[:key].to_s ] }
          end

          def render_system_prompt_panel
            pre(class: "bg-blue-50 p-4 rounded-lg overflow-x-auto text-sm whitespace-pre-wrap") do
              code { result_value(:system_prompt) }
            end
          end

          def render_user_prompt_panel
            pre(class: "bg-green-50 p-4 rounded-lg overflow-x-auto text-sm whitespace-pre-wrap") do
              code { result_value(:user_prompt) }
            end
          end

          def render_agent_result_panel
            agent_result = result_value(:agent_result)

            # If agent_result is nil or not a hash, show a simple message
            unless agent_result.is_a?(Hash) || agent_result.respond_to?(:to_h)
              pre(class: "bg-green-50 p-4 rounded-lg overflow-x-auto text-sm") do
                code { agent_result.inspect }
              end
              return
            end

            # Convert to hash if needed
            agent_data = agent_result.is_a?(Hash) ? agent_result : agent_result.to_h

            div(class: "space-y-6") do
              # Main result summary
              if agent_data[:workflow_status] || agent_data[:message]
                div(class: "bg-blue-50 p-4 rounded-lg") do
                  h4(class: "font-medium text-gray-900 mb-2") { "Execution Summary" }
                  dl(class: "space-y-1 text-sm") do
                    if agent_data[:workflow_status]
                      div(class: "flex") do
                        dt(class: "font-medium text-gray-600 w-32") { "Status:" }
                        dd(class: "text-gray-900") do
                          span(class: "px-2 py-1 rounded text-xs font-medium #{status_color_class(agent_data[:workflow_status])}") do
                            agent_data[:workflow_status].to_s.humanize
                          end
                        end
                      end
                    end

                    if agent_data[:message]
                      div(class: "flex") do
                        dt(class: "font-medium text-gray-600 w-32") { "Message:" }
                        dd(class: "text-gray-900") { agent_data[:message] }
                      end
                    end

                    if agent_data[:turns_completed]
                      div(class: "flex") do
                        dt(class: "font-medium text-gray-600 w-32") { "Turns Completed:" }
                        dd(class: "text-gray-900") { agent_data[:turns_completed] }
                      end
                    end
                  end
                end
              end

              # Tool calls history
              if agent_data[:tool_calls].present?
                div(class: "bg-gray-50 p-4 rounded-lg") do
                  h4(class: "font-medium text-gray-900 mb-3") { "Tool Calls (#{agent_data[:tool_calls].size})" }
                  div(class: "space-y-3") do
                    agent_data[:tool_calls].each_with_index do |tool_call, index|
                      div(class: "bg-white p-3 rounded border border-gray-200") do
                        div(class: "flex items-start justify-between mb-2") do
                          span(class: "font-medium text-sm") { "#{index + 1}. #{tool_call[:name] || tool_call['name'] || 'Unknown Tool'}" }
                          if tool_call[:timestamp] || tool_call["timestamp"]
                            span(class: "text-xs text-gray-500") { format_timestamp(tool_call[:timestamp] || tool_call["timestamp"]) }
                          end
                        end

                        if tool_call[:arguments] || tool_call["arguments"]
                          details(class: "mt-2") do
                            summary(class: "text-xs text-gray-600 cursor-pointer hover:text-gray-800") { "View Arguments" }
                            pre(class: "mt-2 bg-gray-100 p-2 rounded text-xs overflow-x-auto") do
                              code { JSON.pretty_generate(tool_call[:arguments] || tool_call["arguments"]) }
                            end
                          end
                        end

                        if tool_call[:result] || tool_call["result"]
                          details(class: "mt-2") do
                            summary(class: "text-xs text-gray-600 cursor-pointer hover:text-gray-800") { "View Result" }
                            pre(class: "mt-2 bg-gray-100 p-2 rounded text-xs overflow-x-auto") do
                              code { format_tool_result(tool_call[:result] || tool_call["result"]) }
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end

              # Messages/Conversation history
              if agent_data[:messages].present?
                div(class: "bg-indigo-50 p-4 rounded-lg") do
                  h4(class: "font-medium text-gray-900 mb-3") { "Conversation History (#{agent_data[:messages].size} messages)" }
                  div(class: "space-y-3") do
                    agent_data[:messages].each_with_index do |message, index|
                      role = message[:role] || message["role"]
                      content = message[:content] || message["content"]

                      div(class: "bg-white p-3 rounded border border-gray-200") do
                        div(class: "flex items-center gap-2 mb-2") do
                          icon_class = case role
                          when "system" then "fa-cog text-blue-500"
                          when "user" then "fa-user text-green-500"
                          when "assistant" then "fa-robot text-purple-500"
                          else "fa-comment text-gray-500"
                          end

                          i(class: "fas #{icon_class}")
                          span(class: "font-medium text-sm capitalize") { role }
                        end

                        pre(class: "whitespace-pre-wrap text-sm text-gray-700") { content }
                      end
                    end
                  end
                end
              end

              # Final result/response
              if agent_data[:final_result] || agent_data[:result]
                div(class: "bg-green-50 p-4 rounded-lg") do
                  h4(class: "font-medium text-gray-900 mb-2") { "Final Result" }
                  pre(class: "bg-white p-3 rounded border border-green-200 overflow-x-auto text-sm") do
                    code { JSON.pretty_generate(agent_data[:final_result] || agent_data[:result]) rescue (agent_data[:final_result] || agent_data[:result]).inspect }
                  end
                end
              end

              # Any additional data fields
              additional_fields = agent_data.reject { |k, _|
                [ :workflow_status, :message, :turns_completed, :tool_calls, :messages, :final_result, :result, :error, :error_message, :error_class, :backtrace ].include?(k.to_sym)
              }

              if additional_fields.any?
                div(class: "bg-yellow-50 p-4 rounded-lg") do
                  h4(class: "font-medium text-gray-900 mb-2") { "Additional Data" }
                  dl(class: "space-y-2 text-sm") do
                    additional_fields.each do |key, value|
                      div(class: "flex flex-col gap-1") do
                        dt(class: "font-medium text-gray-700") { "#{key.to_s.humanize}:" }
                        dd(class: "ml-4") do
                          if value.is_a?(Hash) || value.is_a?(Array)
                            details do
                              summary(class: "text-xs text-gray-600 cursor-pointer hover:text-gray-800") { "View Data" }
                              pre(class: "mt-2 bg-white p-2 rounded border border-gray-200 text-xs overflow-x-auto") do
                                code { JSON.pretty_generate(value) rescue value.inspect }
                              end
                            end
                          else
                            span(class: "text-gray-900") { value.to_s }
                          end
                        end
                      end
                    end
                  end
                end
              end

              # Raw data view (collapsible)
              details(class: "mt-6") do
                summary(class: "cursor-pointer text-sm text-gray-600 hover:text-gray-800 font-medium") do
                  "View Raw Agent Result Data"
                end
                pre(class: "mt-3 bg-gray-900 text-gray-100 p-4 rounded-lg overflow-x-auto text-xs") do
                  code { JSON.pretty_generate(agent_data) rescue agent_data.inspect }
                end
              end
            end
          end

          def status_color_class(status)
            case status.to_s
            when "completed", "success"
              "bg-green-100 text-green-800"
            when "stopped", "max_turns_reached"
              "bg-yellow-100 text-yellow-800"
            when "error", "failed"
              "bg-red-100 text-red-800"
            else
              "bg-gray-100 text-gray-800"
            end
          end

          def format_timestamp(timestamp)
            return "" unless timestamp

            if timestamp.is_a?(Integer)
              Time.at(timestamp).strftime("%H:%M:%S")
            else
              timestamp.to_s
            end
          end

          def format_tool_result(result)
            case result
            when String
              result.length > 500 ? "#{result[0..500]}..." : result
            when Hash, Array
              JSON.pretty_generate(result)
            else
              result.inspect
            end
          end

          def render_debug_output_panel
            pre(class: "bg-gray-900 text-gray-100 p-4 rounded-lg overflow-x-auto text-xs") do
              code { debug_output }
            end
          end

          def render_error_details_panel
            error_details = result_value(:error_details)
            return unless error_details

            div(class: "space-y-4") do
              Alert(
                type: :error,
                title: "Execution Error",
                message: error_details[:message] || error_details["message"] || "Unknown error"
              )

              backtrace = error_details[:backtrace] || error_details["backtrace"]
              if backtrace && backtrace.any?
                div do
                  h4(class: "text-sm font-medium text-gray-700 mb-2") { "Stack Trace" }
                  pre(class: "bg-red-50 p-4 rounded-lg overflow-x-auto text-xs") do
                    code { Array(backtrace).join("\n") }
                  end
                end
              end
            end
          end

          def render_conversation_panel
            agent_result = result_value(:agent_result)

            # Handle different cases
            if agent_result.nil?
              # No agent result at all (prompt-only execution)
              agent_data = {}
              messages = []
              is_prompt_only = true
            elsif agent_result.is_a?(Hash) || agent_result.respond_to?(:to_h)
              # Normal agent execution
              agent_data = agent_result.is_a?(Hash) ? agent_result : agent_result.to_h

              # Debug: log the structure
              Rails.logger.info "🔍 CONVERSATION DEBUG: agent_data keys: #{agent_data.keys.inspect}"
              Rails.logger.info "🔍 CONVERSATION DEBUG: agent_data[:messages] present? #{agent_data[:messages].present?}"
              Rails.logger.info "🔍 CONVERSATION DEBUG: agent_data[:agent_result] present? #{agent_data[:agent_result].present?}"
              if agent_data[:agent_result].is_a?(Hash)
                Rails.logger.info "🔍 CONVERSATION DEBUG: agent_data[:agent_result] keys: #{agent_data[:agent_result].keys.inspect}"
                Rails.logger.info "🔍 CONVERSATION DEBUG: agent_data[:agent_result][:messages] present? #{agent_data[:agent_result][:messages].present?}"
              end

              # Check multiple possible locations for messages
              messages = agent_data[:messages] ||
                        agent_data["messages"] ||
                        (agent_data[:agent_result].is_a?(Hash) && agent_data[:agent_result][:messages]) ||
                        []

              Rails.logger.info "🔍 CONVERSATION DEBUG: Final messages count: #{messages.size}"
              Rails.logger.info "🔍 CONVERSATION DEBUG: Messages sample: #{messages.first(2).inspect}" if messages.any?
              is_prompt_only = false
            else
              # Unexpected format
              agent_data = {}
              messages = []
              is_prompt_only = false
            end

            div(class: "space-y-4") do
              # Header with message count
              div(class: "flex items-center justify-between mb-4") do
                h3(class: "text-lg font-medium text-gray-900") do
                  "Conversation Flow (#{messages.size} messages)"
                end

                # Auto-refresh indicator for live updates
                div(class: "flex items-center gap-2 text-sm text-gray-500") do
                  i(class: "fas fa-sync-alt animate-spin", data: { "conversation-updates-target": "refreshIcon" })
                  span { "Live updates enabled" }
                end
              end

              # Messages container with live update support
              div(
                class: "space-y-4 max-h-[600px] overflow-y-auto",
                data: { "conversation-updates-target": "messagesContainer" }
              ) do
                if messages.empty?
                  # Empty state
                  div(class: "text-center py-8") do
                    div(class: "inline-flex items-center justify-center w-16 h-16 bg-gray-100 rounded-full mb-4") do
                      i(class: "fas fa-comments text-gray-400 text-2xl")
                    end

                    if is_prompt_only
                      # Prompt-only execution
                      p(class: "text-gray-500 mb-2") { "No conversation for prompt generation" }
                      p(class: "text-sm text-gray-400 max-w-md mx-auto") do
                        "This tab shows conversation messages when executing agents. For prompt-only generation, check the System Prompt and User Prompt tabs."
                      end
                    else
                      # Agent execution but no messages captured
                      p(class: "text-gray-500 mb-2") { "No conversation messages captured" }
                      p(class: "text-sm text-gray-400 max-w-md mx-auto") do
                        "Messages will appear here as the agent executes. The agent needs to log messages in a recognized format for them to be captured."
                      end

                      # Help text for debugging
                      details(class: "mt-4 text-left max-w-lg mx-auto") do
                        summary(class: "cursor-pointer text-sm text-gray-600 hover:text-gray-800") do
                          "Why don't I see messages?"
                        end
                        div(class: "mt-2 text-sm text-gray-600 space-y-2 bg-gray-50 p-4 rounded") do
                          p { "Messages are captured when they match these patterns:" }
                          ul(class: "list-disc list-inside ml-2 space-y-1") do
                            li { "SYSTEM MESSAGE:, USER MESSAGE:, ASSISTANT MESSAGE:" }
                            li { "System:, User:, Assistant: (at start of line)" }
                            li { "Messages with 🤖 (assistant) or 👤 (user) emojis" }
                          end
                          p(class: "mt-2") { "Check the Debug Output tab to see the raw agent logs." }
                        end
                      end
                    end
                  end
                else
                  messages.each_with_index do |message, index|
                    render_conversation_message(message, index)
                  end
                end
              end

              # Tool calls summary if present
              if agent_data[:tool_calls].present?
                div(class: "mt-6 bg-gray-50 p-4 rounded-lg") do
                  h4(class: "font-medium text-gray-900 mb-2") { "Tool Usage Summary" }
                  div(class: "grid grid-cols-2 gap-4 text-sm") do
                    div do
                      span(class: "text-gray-600") { "Total tool calls: " }
                      span(class: "font-medium") { agent_data[:tool_calls].size }
                    end
                    div do
                      span(class: "text-gray-600") { "Unique tools: " }
                      span(class: "font-medium") do
                        agent_data[:tool_calls].map { |tc| tc[:name] || tc["name"] }.uniq.size
                      end
                    end
                  end
                end
              end
            end
          end

          def render_conversation_message(message, index)
            role = message[:role] || message["role"]
            content = message[:content] || message["content"]
            tool_calls = message[:tool_calls] || message["tool_calls"]

            # Message wrapper with role-specific styling
            div(
              class: "rounded-lg border p-4 #{conversation_message_class(role)}",
              data: { "conversation-message-index": index }
            ) do
              # Message header
              div(class: "flex items-start justify-between mb-2") do
                div(class: "flex items-center gap-2") do
                  # Role icon
                  i(class: "fas #{conversation_role_icon(role)}")

                  # Role label
                  span(class: "font-medium text-sm capitalize") { role }

                  # Message index
                  span(class: "text-xs text-gray-500 ml-2") { "##{index + 1}" }
                end

                # Timestamp if available
                if message[:timestamp] || message["timestamp"]
                  span(class: "text-xs text-gray-500") do
                    format_timestamp(message[:timestamp] || message["timestamp"])
                  end
                end
              end

              # Message content
              if content && content.strip.length > 0
                render_message_content(content, role)
              end

              # Tool calls if present
              if tool_calls && tool_calls.any?
                div(class: "mt-3 space-y-2") do
                  h5(class: "text-xs font-medium text-gray-700 mb-1") { "Tool Calls:" }
                  tool_calls.each do |tool_call|
                    render_tool_call_in_conversation(tool_call)
                  end
                end
              end
            end
          end

          def render_message_content(content, role)
            # Try to detect and format JSON content
            if content.strip.start_with?("{", "[") || content.include?("```json")
              # Extract JSON from markdown code blocks if present
              json_content = if content.include?("```json")
                content.match(/```json\n(.*?)\n```/m)&.[](1) || content
              else
                content
              end

              begin
                parsed = JSON.parse(json_content)
                div(class: "mt-2") do
                  details(open: true) do
                    summary(class: "cursor-pointer text-sm font-medium text-gray-700 mb-2") do
                      "JSON Response"
                    end
                    pre(class: "bg-gray-900 text-gray-100 p-3 rounded-lg overflow-x-auto text-xs") do
                      code(class: "language-json") { JSON.pretty_generate(parsed) }
                    end
                  end
                end
              rescue JSON::ParserError
                # Not valid JSON, render as regular text
                pre(class: "whitespace-pre-wrap text-sm text-gray-700 mt-2") { content }
              end
            else
              # Regular text content
              pre(class: "whitespace-pre-wrap text-sm text-gray-700 mt-2") { content }
            end
          end

          def render_tool_call_in_conversation(tool_call)
            div(class: "bg-gray-100 p-2 rounded text-xs") do
              div(class: "flex items-center gap-2") do
                i(class: "fas fa-wrench text-gray-600")
                span(class: "font-medium") { tool_call[:name] || tool_call["name"] || "Unknown Tool" }
              end

              # Show arguments if present
              args = tool_call[:arguments] || tool_call["arguments"]
              if args && !args.empty?
                details(class: "mt-1") do
                  summary(class: "cursor-pointer text-gray-600") { "Arguments" }
                  pre(class: "mt-1 bg-white p-2 rounded overflow-x-auto") do
                    code { JSON.pretty_generate(args) rescue args.inspect }
                  end
                end
              end
            end
          end

          def conversation_message_class(role)
            case role
            when "system"
              "bg-blue-50 border-blue-200"
            when "user"
              "bg-green-50 border-green-200"
            when "assistant"
              "bg-purple-50 border-purple-200"
            when "tool"
              "bg-yellow-50 border-yellow-200"
            else
              "bg-gray-50 border-gray-200"
            end
          end

          def conversation_role_icon(role)
            case role
            when "system"
              "fa-cog text-blue-500"
            when "user"
              "fa-user text-green-500"
            when "assistant"
              "fa-robot text-purple-500"
            when "tool"
              "fa-wrench text-yellow-500"
            else
              "fa-comment text-gray-500"
            end
          end

          def render_streaming_output_panel
            div(
              data: {
                controller: "ai-debug-streaming",
                "ai-debug-streaming-session-id-value": session_id
              }
            ) do
              div(class: "mb-2 flex items-center justify-between") do
                div(class: "flex items-center gap-4") do
                  h4(class: "text-sm font-medium text-gray-700") { "Real-time Execution Logs" }
                  span(
                    class: "text-xs text-gray-500 ml-2",
                    data: { "ai-debug-streaming-target": "status" }
                  ) { "" }
                end

                p(class: "text-xs text-gray-500") do
                  "Session ID: #{session_id}"
                end
              end

              div(
                class: "bg-gray-900 text-gray-100 p-4 rounded-lg overflow-y-auto font-mono text-xs",
                style: "height: 800px;",
                data: { "ai-debug-streaming-target": "output" }
              ) do
                # Content will be dynamically added via JavaScript
              end
            end
          end

          def render_recent_executions
            Card do
              CardHeader(
                title: "Recent Executions",
                subtitle: "Last 5 executions"
              )

              Container(class: "p-6") do
                div(class: "space-y-2") do
                  recent_executions.first(5).each do |execution|
                    div(class: "flex items-center justify-between p-3 bg-gray-50 rounded-lg") do
                      div(class: "flex items-center space-x-3") do
                        if execution[:success]
                          i(class: "fas fa-check-circle h-4 w-4 text-green-500")
                        else
                          i(class: "fas fa-times-circle h-4 w-4 text-red-500")
                        end

                        div(class: "text-sm") do
                          span(class: "font-medium") { execution[:type].capitalize }

                          # Format the class name to be more descriptive
                          name_parts = execution[:class_name].split("::")
                          # Remove "Ai", "Prompts", and "Agents" from the name parts
                          name_parts = name_parts.reject { |part| [ "Ai", "Prompts", "Agents" ].include?(part) }
                          formatted_name = if name_parts.length > 1
                            name_parts.map(&:underscore).map(&:humanize).join(" - ")
                          else
                            name_parts.first&.underscore&.humanize || execution[:class_name]
                          end

                          span(class: "text-gray-500 ml-2") { formatted_name }
                          if execution[:model_type]
                            span(class: "text-gray-400 ml-2") do
                              "#{execution[:model_type]} ##{execution[:model_id]}"
                            end
                          end
                        end
                      end

                      span(class: "text-xs text-gray-500") { execution[:executed_at] }
                    end
                  end
                end
              end
            end
          end
          end
      end
    end
  end
end
