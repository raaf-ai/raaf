# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class LlmSpanComponent < SpanDetailBase
        def view_template
          div(class: "space-y-6") do
            render_llm_overview
            render_dialogue_section if request_messages.present?
            render_request_response_flow
            render_token_usage if usage_data.present?
            render_cost_metrics if cost_data.present?
            render_model_parameters if model_params.present?
            render_error_handling
          end
        end

        private

        def model_name
          @model_name ||= extract_span_attribute("llm.model") ||
                         extract_span_attribute("model") ||
                         extract_span_attribute("model_name") ||
                         "Unknown Model"
        end

        def provider_name
          @provider_name ||= extract_span_attribute("llm.provider") ||
                            extract_span_attribute("provider") ||
                            model_name.split("-").first&.capitalize ||
                            "Unknown Provider"
        end

        def request_data
          @request_data ||= extract_span_attribute("llm.request") ||
                           extract_span_attribute("request") ||
                           extract_span_attribute("input")
        end

        def response_data
          @response_data ||= extract_span_attribute("llm.response") ||
                            extract_span_attribute("response") ||
                            extract_span_attribute("output")
        end

        def usage_data
          @usage_data ||= extract_span_attribute("llm.usage") ||
                         extract_span_attribute("usage") ||
                         extract_span_attribute("token_usage")
        end

        def cost_data
          @cost_data ||= extract_span_attribute("llm.cost") ||
                        extract_span_attribute("cost") ||
                        calculate_estimated_cost
        end

        def model_params
          @model_params ||= {
            "temperature" => extract_span_attribute("llm.temperature") || extract_span_attribute("temperature"),
            "max_tokens" => extract_span_attribute("llm.max_tokens") || extract_span_attribute("max_tokens"),
            "top_p" => extract_span_attribute("llm.top_p") || extract_span_attribute("top_p"),
            "frequency_penalty" => extract_span_attribute("llm.frequency_penalty") || extract_span_attribute("frequency_penalty"),
            "presence_penalty" => extract_span_attribute("llm.presence_penalty") || extract_span_attribute("presence_penalty"),
            "stream" => extract_span_attribute("llm.stream") || extract_span_attribute("stream")
          }.compact
        end

        def request_messages
          @request_messages ||= extract_span_attribute("llm.request.messages") ||
                               extract_span_attribute("llm")&.dig("request", "messages") ||
                               request_data&.dig("messages") ||
                               []
        end

        def response_messages
          @response_messages ||= begin
            # Get the actual response content
            response_content = extract_span_attribute("llm.response.content") ||
                              response_data&.dig("choices", 0, "message", "content")

            response_role = extract_span_attribute("llm.response.role") ||
                           response_data&.dig("choices", 0, "message", "role") ||
                           "assistant"

            tool_calls = extract_span_attribute("llm.response.tool_calls") ||
                        response_data&.dig("choices", 0, "message", "tool_calls")

            return [] unless response_content || tool_calls

            message = {
              "role" => response_role,
              "content" => response_content
            }

            message["tool_calls"] = tool_calls if tool_calls

            [message]
          end
        end

        def full_conversation
          @full_conversation ||= begin
            messages = []
            messages.concat(request_messages) if request_messages.present?
            messages.concat(response_messages) if response_messages.present?
            messages
          end
        end

        def render_llm_overview
          render_span_overview_header(
            "bi bi-cpu",
            "LLM Request",
            "#{provider_name} • #{model_name}"
          )
        end

        def render_dialogue_section
          render SpanDetail::DialogueDisplay.new(
            messages: full_conversation,
            title: "LLM Conversation"
          )
        end

        def render_request_response_flow
          div(class: "grid grid-cols-1 lg:grid-cols-2 gap-6") do
            # Request Section
            div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
              div(class: "px-4 py-5 sm:px-6 border-b border-blue-200 bg-blue-50") do
                div(class: "flex items-center gap-3") do
                  i(class: "bi bi-arrow-up-right text-blue-600 text-lg")
                  h3(class: "text-lg font-semibold text-blue-900") { "Request" }
                end
              end
              div(class: "px-4 py-5 sm:p-6") do
                if request_data
                  render_json_section("Request Data", request_data, collapsed: true, use_json_highlighter: true)
                else
                  div(class: "text-center py-8 text-gray-500") do
                    i(class: "bi bi-arrow-up-right text-gray-400 text-2xl mb-2")
                    p(class: "text-sm") { "No request data available" }
                  end
                end
              end
            end

            # Response Section
            div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
              div(class: "px-4 py-5 sm:px-6 border-b border-green-200 bg-green-50") do
                div(class: "flex items-center gap-3") do
                  i(class: "bi bi-arrow-down-left text-green-600 text-lg")
                  h3(class: "text-lg font-semibold text-green-900") { "Response" }
                end
              end
              div(class: "px-4 py-5 sm:p-6") do
                if response_data
                  render_json_section("Response Data", response_data, collapsed: true, use_json_highlighter: true)
                else
                  div(class: "text-center py-8 text-gray-500") do
                    i(class: "bi bi-arrow-down-left text-gray-400 text-2xl mb-2")
                    p(class: "text-sm") { "No response data available" }
                  end
                end
              end
            end
          end
        end

        def render_token_usage
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-purple-200 bg-purple-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-speedometer text-purple-600 text-lg")
                h3(class: "text-lg font-semibold text-purple-900") { "Token Usage" }
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              case usage_data
              when Hash
                dl(class: "grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-3") do
                  if usage_data["prompt_tokens"] || usage_data["input_tokens"]
                    prompt_tokens = usage_data["prompt_tokens"] || usage_data["input_tokens"]
                    render_detail_item("Prompt Tokens", prompt_tokens.to_s, monospace: true)
                  end
                  
                  if usage_data["completion_tokens"] || usage_data["output_tokens"]
                    completion_tokens = usage_data["completion_tokens"] || usage_data["output_tokens"]
                    render_detail_item("Completion Tokens", completion_tokens.to_s, monospace: true)
                  end
                  
                  if usage_data["total_tokens"]
                    render_detail_item("Total Tokens", usage_data["total_tokens"].to_s, monospace: true)
                  end
                end
              else
                render_json_section("Usage Data", usage_data, collapsed: false)
              end
            end
          end
        end

        def render_cost_metrics
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-yellow-200 bg-yellow-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-currency-dollar text-yellow-600 text-lg")
                h3(class: "text-lg font-semibold text-yellow-900") { "Cost Metrics" }
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              case cost_data
              when Hash
                dl(class: "grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2") do
                  if cost_data["input_cost"] || cost_data["prompt_cost"]
                    input_cost = cost_data["input_cost"] || cost_data["prompt_cost"]
                    render_detail_item("Input Cost", format_cost(input_cost))
                  end
                  
                  if cost_data["output_cost"] || cost_data["completion_cost"]
                    output_cost = cost_data["output_cost"] || cost_data["completion_cost"]
                    render_detail_item("Output Cost", format_cost(output_cost))
                  end
                  
                  if cost_data["total_cost"]
                    render_detail_item("Total Cost", format_cost(cost_data["total_cost"]))
                  end
                  
                  if cost_data["currency"]
                    render_detail_item("Currency", cost_data["currency"])
                  end
                end
              when Numeric
                render_detail_item("Estimated Cost", format_cost(cost_data))
              else
                render_json_section("Cost Data", cost_data, collapsed: false)
              end
            end
          end
        end

        def render_model_parameters
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-semibold text-gray-900") { "Model Parameters" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              dl(class: "grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2") do
                render_detail_item("Model", model_name, monospace: true)
                render_detail_item("Provider", provider_name)
                
                model_params.each do |key, value|
                  formatted_key = key.humanize
                  formatted_value = case key
                                   when "stream"
                                     value ? "Enabled" : "Disabled"
                                   else
                                     value.to_s
                                   end
                  render_detail_item(formatted_key, formatted_value)
                end
              end
            end
          end
        end

        def calculate_estimated_cost
          return nil unless usage_data.is_a?(Hash)
          
          # Simple cost estimation based on common pricing
          # This is very approximate and should be replaced with actual pricing data
          prompt_tokens = usage_data["prompt_tokens"] || usage_data["input_tokens"] || 0
          completion_tokens = usage_data["completion_tokens"] || usage_data["output_tokens"] || 0
          
          return nil if prompt_tokens == 0 && completion_tokens == 0
          
          # Rough estimate for GPT-4 pricing (per 1K tokens)
          input_rate = 0.03 / 1000.0  # $0.03 per 1K tokens
          output_rate = 0.06 / 1000.0 # $0.06 per 1K tokens
          
          (prompt_tokens * input_rate) + (completion_tokens * output_rate)
        end

        def format_cost(cost)
          return "N/A" unless cost.is_a?(Numeric)
          
          if cost < 0.01
            "$#{(cost * 1000).round(3)}¢"
          else
            "$#{cost.round(4)}"
          end
        end
      end
    end
  end
end
