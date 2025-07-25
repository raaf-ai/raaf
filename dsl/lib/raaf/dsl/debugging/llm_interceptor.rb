# frozen_string_literal: true

module RAAF
  module DSL
    module Debugging
      # Intercepts and logs LLM API calls for debugging
      #
      # This class provides deep visibility into OpenAI API interactions by
      # intercepting API calls and logging both requests and responses. It's
      # invaluable for debugging issues with tool usage, prompt formatting,
      # and understanding why the AI responds in certain ways.
      #
      # @example Basic usage
      #   interceptor = LLMInterceptor.new
      #   interceptor.intercept_openai_calls do
      #     agent.run
      #   end
      #
      # @example With custom logger
      #   interceptor = LLMInterceptor.new(logger: my_logger)
      #   interceptor.intercept_openai_calls do
      #     result = agent.process_request
      #   end
      #
      # @example Debugging tool usage
      #   # When tools aren't being called as expected
      #   interceptor = LLMInterceptor.new
      #   interceptor.intercept_openai_calls do
      #     # Check the logged API requests to see tool configurations
      #     agent_with_tools.run
      #   end
      #
      # @since 0.1.0
      class LLMInterceptor
        # @return [Logger] The logger instance used for output
        attr_reader :logger

        # Initialize a new LLM interceptor
        #
        # @param logger [Logger] Logger instance for output (defaults to Rails.logger)
        # @example
        #   interceptor = LLMInterceptor.new(logger: Rails.logger)
        def initialize(logger: nil)
          @logger = logger || ::Logger.new($stdout)
          @original_chat_method = nil
        end

        # Intercept OpenAI API calls and log detailed information
        #
        # Temporarily patches the OpenAI client to intercept and log all
        # chat completion requests and responses. The patch is automatically
        # removed after the block executes, even if an error occurs.
        #
        # @yield Block to execute with API interception enabled
        # @return [Object] The return value of the yielded block
        # @example
        #   result = interceptor.intercept_openai_calls do
        #     agent.run("What's the weather?")
        #   end
        def intercept_openai_calls
          return yield unless defined?(OpenAI::Client)

          patch_openai_client

          begin
            yield
          ensure
            restore_openai_client
          end
        end

        private

        def patch_openai_client
          openai_class = OpenAI::Client
          @original_chat_method = openai_class.instance_method(:chat)

          # Define our debugging wrapper
          openai_class.define_method(:chat) do |parameters:, **kwargs|
            # Log the complete request payload to OpenAI
            log_openai_request(parameters)

            # Call the original method and log response
            response = @original_chat_method.bind(self).call(parameters: parameters, **kwargs)

            # Log response details
            log_openai_response(response)

            response
          end
        end

        def restore_openai_client
          return unless @original_chat_method && defined?(OpenAI::Client)

          OpenAI::Client.define_method(:chat, @original_chat_method)
          @original_chat_method = nil
        end

        def log_openai_request(parameters)
          logger.info "   #{'=' * 80}"
          logger.info "   🚀 COMPLETE OPENAI API REQUEST:"
          logger.info "   📋 Model: #{parameters[:model] || 'unknown'}"
          logger.info "   🌡️  Temperature: #{parameters[:temperature] || 'default'}"
          logger.info "   🔄 Max Tokens: #{parameters[:max_tokens] || 'unlimited'}"

          log_tools_configuration(parameters[:tools])
          log_tool_choice(parameters[:tool_choice])
          log_messages(parameters[:messages])

          logger.info "   #{'=' * 80}"
        end

        def log_tools_configuration(tools)
          if tools && !tools.empty?
            logger.info "   🛠️  TOOLS CONFIGURED:"
            tools.each_with_index do |tool, idx|
              logger.info "   │ #{idx + 1}. Type: #{tool[:type] || tool['type']}"

              case tool[:type] || tool["type"]
              when "function"
                log_function_tool(tool)
              when "web_search"
                log_web_search_tool(tool)
              end

              logger.info "   │    Full config: #{tool.inspect}"
            end
          else
            logger.info "   ⚠️  NO TOOLS CONFIGURED"
          end
        end

        def log_function_tool(tool)
          func = tool[:function]
          logger.info "   │    Function Name: #{func[:name]}"
          logger.info "   │    Description: #{func[:description]}"
          logger.info "   │    Parameters: #{func[:parameters].inspect}"

          # Check for parameter issues
          if func[:parameters].nil? || func[:parameters].empty?
            logger.error "   │    ❌ ERROR: Function has no parameters!"
          elsif func[:parameters][:properties].nil? || func[:parameters][:properties].empty?
            logger.error "   │    ❌ ERROR: Function has no properties defined!"
          else
            logger.info "   │    ✅ Properties: #{func[:parameters][:properties].keys}"
            logger.info "   │    ✅ Required: #{func[:parameters][:required]}"
          end
        end

        def log_web_search_tool(tool)
          logger.info "   │    User Location: #{tool[:user_location] || tool['user_location']}"
          logger.info "   │    Search Context Size: #{tool[:search_context_size] || tool['search_context_size']}"
        end

        def log_tool_choice(tool_choice)
          return unless tool_choice

          logger.info "   🎯 Tool Choice: #{tool_choice}"
        end

        def log_messages(messages)
          return unless messages

          logger.info "   💬 MESSAGES:"
          messages.each_with_index do |message, idx|
            role = message[:role] || message["role"]
            content = message[:content] || message["content"]

            logger.info "   #{idx + 1}. #{role.upcase} MESSAGE:"
            log_message_content(content) if content

            # Log tool calls if present
            tool_calls = message[:tool_calls] || message["tool_calls"]
            if tool_calls
              logger.info "   │ 🛠️  TOOL CALLS: #{tool_calls.length}"
              tool_calls.each do |call|
                logger.info "   │   - #{begin
                  call['function']['name']
                rescue StandardError
                  call.inspect
                end}"
              end
            end

            logger.info "   #{'-' * 40}"
          end
        end

        def log_message_content(content)
          content_lines = content.to_s.strip.split("\n")
          content_lines.first(10).each do |line|
            logger.info "   │ #{line}"
          end
          logger.info "   │ ... (#{content_lines.length - 10} more lines)" if content_lines.length > 10
        end

        def log_openai_response(response)
          logger.info "   📤 OPENAI RESPONSE:"
          if response.dig("choices", 0, "message", "tool_calls")
            tool_calls = response.dig("choices", 0, "message", "tool_calls")
            logger.info "   │ 🛠️  Tool calls in response: #{tool_calls.length}"
            tool_calls.each do |call|
              logger.info "   │   - Function: #{call['function']['name']}"
              logger.info "   │     Args: #{call['function']['arguments'][0..100]}..."
            end
          else
            logger.info "   │ ❌ No tool calls in response"
          end
          logger.info "   #{'=' * 80}"
        end
      end
    end
  end
end
