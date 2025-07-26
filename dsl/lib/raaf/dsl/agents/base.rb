# frozen_string_literal: true

require "raaf-core"
require_relative "../config/config"
require_relative "../core/context_variables"

# Base class for all AI agents in the AI Agent DSL framework
#
# This is a pure configuration class that builds agent configuration and delegates
# all execution to the raaf-ruby library. It does not contain any execution
# logic, API calls, or result processing - only configuration and delegation.
#
# @abstract Subclasses must implement {#agent_name}, {#build_instructions}, and {#build_schema}
#
# @example Creating a basic agent
#   class MyAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::Agents::AgentDsl
#
#     agent_name "MyAgent"
#     model "gpt-4o"
#     max_turns 3
#
#     def build_instructions
#       "You are a helpful assistant that processes data."
#     end
#
#     def build_schema
#       {
#         type: "object",
#         properties: {
#           result: { type: "string" }
#         },
#         required: ["result"],
#         additionalProperties: false
#       }
#     end
#   end
#
# @example Using the agent
#   context = { document: { name: "test.pdf" } }
#   params = { content_type: "report" }
#   agent = MyAgent.new(context: context, processing_params: params)
#   result = agent.run  # Delegates to raaf-ruby
#
# @see RAAF::DSL::AgentDsl For DSL configuration methods
# @see RAAF::DSL::Config For configuration management
# @since 0.1.0
#
module RAAF
  module DSL
    module Agents
      class Base
        include RAAF::Logger

        # @return [Hash] Processing parameters that control agent behavior
        attr_reader :processing_params

        # @return [ContextVariables] Unified context for all agent data
        attr_reader :context

        # @return [Boolean] Whether debug mode is enabled for this agent
        attr_reader :debug_enabled

        # Initialize a new agent configuration instance
        #
        # @param context [ContextVariables, Hash, nil] Unified context for all agent data
        # @param context_variables [ContextVariables, Hash, nil] Alternative parameter name for context (backward compatibility)
        # @param processing_params [Hash] Parameters that control how the agent processes content
        # @param debug [Boolean, nil] Enable debug logging for this agent instance (nil = auto-detect Rails.env.development?)
        #
        def initialize(context: nil, context_variables: nil, processing_params: {}, debug: nil)
          @debug_enabled = debug || (defined?(::Rails) && ::Rails.env.development?) || false
          @processing_params = processing_params

          # Support both context and context_variables parameters
          context_param = context || context_variables

          # Initialize unified context
          @context = case context_param
                     when RAAF::DSL::ContextVariables
                       context_param
                     when Hash
                       RAAF::DSL::ContextVariables.new(context_param, debug: @debug_enabled)
                     when nil
                       RAAF::DSL::ContextVariables.new({}, debug: @debug_enabled)
                     else
                       raise ArgumentError, "context must be ContextVariables instance, Hash, or nil"
                     end

          return unless @debug_enabled

          log_debug("Agent configuration initialized",
                    agent_class: self.class.name,
                    context_size: @context.size)
        end

        # Creates and returns an OpenAI Agent instance for API communication
        #
        # This method creates an RAAF::Agent instance configured with all
        # the settings from this DSL agent. The returned OpenAI agent is what actually
        # communicates with the OpenAI API to execute conversations.
        #
        # @return [RAAF::Agent] Configured OpenAI agent instance ready for execution
        #
        def create_agent
          log_debug("Creating OpenAI agent instance",
                    agent_name: agent_name,
                    model: model_name,
                    max_turns: max_turns,
                    tools_count: tools.length,
                    handoffs_count: handoffs.length)

          create_openai_agent_instance
        end

        # Runs the agent by delegating to raaf-ruby
        #
        # This method is pure delegation - it creates an OpenAI agent with the DSL
        # configuration and lets raaf-ruby handle all execution logic.
        #
        # @param context [ContextVariables, Hash, nil] Context to use (overrides instance context)
        # @param input_context_variables [ContextVariables, Hash, nil] Alternative parameter name for context (SwarmDebugger compatibility)
        # @param stop_checker [Proc] Optional stop checker for execution control
        # @return [Hash] Result hash from raaf-ruby execution
        #
        def run(context: nil, input_context_variables: nil, stop_checker: nil)
          # Resolve context for this run (support both parameter names)
          run_context = resolve_run_context(context || input_context_variables)

          # Create OpenAI agent with DSL configuration
          openai_agent = create_agent

          # Build user prompt with context if available
          user_prompt = build_user_prompt_with_context(run_context)

          # Create RAAF runner and delegate execution
          runner_params = { agent: openai_agent }
          runner_params[:stop_checker] = stop_checker if stop_checker

          runner = RAAF::Runner.new(**runner_params)

          # Pure delegation to raaf-ruby
          run_result = runner.run(user_prompt, context: run_context)

          # Transform result to expected DSL format
          transform_openai_result(run_result, run_context)
        rescue StandardError => e
          log_error("Agent execution failed", {
                      error_class: e.class.name,
                      error_message: e.message,
                      agent_name: agent_name,
                      backtrace: e.backtrace&.first(5)
                    })

          # Return error result in expected format
          {
            workflow_status: "error",
            error: e.message,
            success: false,
            results: nil,
            context_variables: run_context,
            summary: "Agent execution failed: #{e.message}"
          }
        end

        # Abstract methods - must be implemented by subclasses
        def agent_name
          raise NotImplementedError, "Subclasses must implement #agent_name"
        end

        def build_instructions
          raise NotImplementedError, "Subclasses must implement #build_instructions"
        end

        def build_schema
          raise NotImplementedError, "Subclasses must implement #build_schema"
        end

        def build_user_prompt
          nil
        end

        # RAAF compatibility methods
        def instructions
          build_instructions
        end

        def name
          agent_name
        end

        def tools?
          tools.any?
        end

        def response_format
          # Check if unstructured output is requested
          return if self.class.respond_to?(:_agent_config) && self.class._agent_config[:output_format] == :unstructured

          # Check if schema is nil (indicating unstructured output)
          schema = build_schema
          return if schema.nil?

          # Return structured format with JSON schema
          {
            type: "json_schema",
            json_schema: {
              name: schema_name,
              strict: true,
              schema: schema
            }
          }
        end

        def schema_name
          "#{agent_name.to_s.underscore}_response"
        end

        def handoffs
          if respond_to?(:build_handoffs_from_config, true)
            build_handoffs_from_config
          else
            []
          end
        end

        def find_handoff(handoff_name)
          handoffs.find do |agent|
            agent.name == handoff_name || (agent.respond_to?(:agent_name) && agent.agent_name == handoff_name)
          end
        end

        protected

        # Configuration methods
        def model_name
          if self.class.respond_to?(:_agent_config)
            self.class._agent_config[:model] || "gpt-4o"
          else
            "gpt-4o"
          end
        end

        def tools
          tool_list = if respond_to?(:build_tools_from_config, true)
                        build_tools_from_config
                      else
                        []
                      end

          # Log tools if debug is enabled
          if @debug_enabled
            log_debug_tools("Agent tools loaded",
                            agent_name: agent_name,
                            tool_count: tool_list.length,
                            tool_names: tool_list.map(&:name))

            tool_list.each_with_index do |tool, idx|
              log_debug_tools("Tool details",
                              tool_index: idx + 1,
                              tool_class: tool.class.name,
                              tool_name: tool.respond_to?(:name) ? tool.name : "unnamed",
                              has_parameters: tool.respond_to?(:parameters))
            end
          end

          tool_list
        end

        def max_turns
          if defined?(RAAF::DSL::Config)
            RAAF::DSL::Config.max_turns_for(agent_name)
          else
            15
          end
        end

        # Context helper methods
        def document_name
          @context.get(:document)&.dig(:name) || "Unknown Document"
        end

        def document_description
          @context.get(:document)&.dig(:description) || ""
        end

        def content_type
          processing_params[:content_type] || "General content"
        end

        # Essential context helper methods
        def product_context
          @context.get(:product)
        end

        def processing_context
          @processing_params
        end

        def format_context_for_instructions(context_hash)
          context_hash.map { |k, v| "#{k.to_s.humanize}: #{v}" }.join("\n")
        end

        def format_list
          formats = processing_params[:formats]
          case formats
          when Array
            formats.join(", ")
          when String
            formats
          else
            "PDF, DOCX"
          end
        end

        def max_pages
          processing_params[:max_pages] || 50
        end

        def language_focus
          processing_params[:language_focus] || "English"
        end

        # Context builders for instruction generation
        def build_document_context
          {
            name: document_name,
            description: document_description,
            content_type: content_type,
            formats: format_list
          }
        end

        def build_processing_context
          {
            max_pages: max_pages,
            content_type: content_type,
            formats: format_list,
            language_focus: language_focus,
            analysis_depth: processing_params[:analysis_depth] || "Standard analysis"
          }
        end

        private

        # Resolve context for this run
        def resolve_run_context(context)
          case context
          when RAAF::DSL::ContextVariables
            context
          when Hash
            RAAF::DSL::ContextVariables.new(context, debug: @debug_enabled)
          when nil
            @context
          else
            raise ArgumentError, "context must be ContextVariables instance, Hash, or nil"
          end
        end

        # Build user prompt with context
        def build_user_prompt_with_context(_context)
          # Default implementation - can be overridden by subclasses
          build_user_prompt || "Please process the provided context and respond according to your instructions."
        end

        # Transform RAAF result to expected DSL format
        def transform_openai_result(run_result, run_context)
          if run_result.respond_to?(:success?) && run_result.success?
            # Extract context variables from the result if available
            result_context = if run_result.respond_to?(:context_variables)
                               run_result.context_variables
                             else
                               run_context
                             end

            {
              workflow_status: "completed",
              success: true,
              results: run_result.respond_to?(:result) ? run_result.result : run_result,
              context_variables: result_context,
              summary: "Agent #{agent_name} completed successfully"
            }
          else
            {
              workflow_status: "error",
              success: false,
              error: run_result.respond_to?(:error) ? run_result.error : "Unknown error",
              results: nil,
              context_variables: run_context,
              summary: "Agent execution failed"
            }
          end
        end

        # Create OpenAI Agent instance with DSL configuration
        def create_openai_agent_instance
          agent_params = {
            name: agent_name,
            instructions: build_instructions,
            model: model_name,
            tools: tools,
            handoffs: handoffs,
            response_format: response_format,
            max_turns: max_turns
          }

          # Add hooks configuration if available
          if respond_to?(:build_hooks_config, true)
            hooks_config = build_hooks_config
            agent_params[:hooks] = hooks_config if hooks_config
          end

          RAAF::Agent.new(**agent_params)
        end

        # Build hooks configuration for RAAF
        def build_hooks_config
          return unless respond_to?(:combined_hooks_config, true)

          combined_hooks_config
        end
      end
    end
  end
end
