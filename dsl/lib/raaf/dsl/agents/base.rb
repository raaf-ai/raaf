# frozen_string_literal: true

require "raaf-core"
require_relative "../config/config"
require_relative "../core/context_variables"
require_relative "../result"

module RAAF
  module DSL
    module Agents
      class Base
        include RAAF::Logger

        class << self
          attr_reader :required_context_keys

          def required_context(*keys)
            @required_context_keys = keys
          end
        end

        attr_reader :processing_params, :context, :debug_enabled

        def initialize(context: nil, context_variables: nil, processing_params: {}, debug: nil)
          @debug_enabled = debug || (defined?(::Rails) && ::Rails.env.development?) || false
          @processing_params = processing_params
          context_param = context || context_variables
          @context = initialize_context(context_param)
          validate_context! if self.class.required_context_keys
          log_debug("Agent configuration initialized", agent_class: self.class.name, context_size: @context.size) if @debug_enabled
        end

        def create_agent
          log_debug("Creating OpenAI agent instance", agent_name: agent_name, model: model_name, max_turns: max_turns, tools_count: tools.length, handoffs_count: handoffs.length)
          create_openai_agent_instance
        end

        def run(context: nil, stop_checker: nil)
          result = execute_run(context: context, stop_checker: stop_checker)
          if result.success?
            process_result(result)
          else
            handle_failure(result)
          end
        end

        def process_result(result)
          result.success? ? result.data : nil
        end

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
          schema = build_schema
          return if schema.nil? || (self.class.respond_to?(:_agent_config) && self.class._agent_config[:output_format] == :unstructured)
          { type: "json_schema", json_schema: { name: schema_name, strict: true, schema: schema } }
        end

        def schema_name
          "#{agent_name.to_s.underscore}_response"
        end

        def handoffs
          respond_to?(:build_handoffs_from_config, true) ? build_handoffs_from_config : []
        end

        def find_handoff(handoff_name)
          handoffs.find { |agent| agent.name == handoff_name || (agent.respond_to?(:agent_name) && agent.agent_name == handoff_name) }
        end

        protected

        def model_name
          self.class.respond_to?(:_agent_config) ? self.class._agent_config[:model] || "gpt-4o" : "gpt-4o"
        end

        def tools
          tool_list = respond_to?(:build_tools_from_config, true) ? build_tools_from_config : []
          tool_list.map { |tool| convert_to_function_tool(tool) }.compact
        end

        def convert_to_function_tool(tool)
          return tool if tool.is_a?(RAAF::FunctionTool)
          callable = tool.respond_to?(:call) ? proc { |**kwargs| tool.call(**kwargs) } : proc { |**kwargs| tool.send(tool.tool_name.to_sym, **kwargs) }
          parameters_schema = tool.respond_to?(:tool_definition) ? tool.tool_definition.dig(:function, :parameters) : { type: "object", properties: {}, required: [] }
          RAAF::FunctionTool.new(callable, name: tool.tool_name, description: tool.description || "Tool: #{tool.tool_name}", parameters: parameters_schema)
        end

        def max_turns
          defined?(RAAF::DSL::Config) ? RAAF::DSL::Config.max_turns_for(agent_name) : 15
        end

        private

        def initialize_context(context_param)
          case context_param
          when RAAF::DSL::ContextVariables
            context_param
          when Hash
            RAAF::DSL::ContextVariables.new(context_param, debug: @debug_enabled)
          when nil
            RAAF::DSL::ContextVariables.new({}, debug: @debug_enabled)
          else
            raise ArgumentError, "context must be ContextVariables instance, Hash, or nil"
          end
        end

        def validate_context!
          missing_keys = self.class.required_context_keys.reject { |key| @context.key?(key) }
          raise ArgumentError, "Required context keys missing: #{missing_keys.join(', ')}" if missing_keys.any?
        end
        
        def handle_failure(result)
            if method(:process_result).owner != self.class.superclass
              process_result(result)
            else
              log_error("Agent run failed, not processing result", error: result.error, agent_name: agent_name)
              nil
            end
        end

        def execute_run(context: nil, stop_checker: nil)
          run_context = resolve_run_context(context)
          openai_agent = create_agent
          user_prompt = build_user_prompt_with_context(run_context)
          runner = RAAF::Runner.new(agent: openai_agent, stop_checker: stop_checker)
          raw_result = runner.run(user_prompt, context: run_context)
          transform_openai_result(raw_result, run_context)
        rescue StandardError => e
          log_error("Agent execution failed", error_class: e.class.name, error_message: e.message, agent_name: agent_name, backtrace: e.backtrace&.first(5))
          RAAF::DSL::Result.new(success: false, data: nil, error: e.message, context_variables: run_context || @context)
        end

        def resolve_run_context(context)
          context ? initialize_context(context) : @context
        end

        def build_user_prompt_with_context(_context)
          build_user_prompt || "Please process the provided context and respond according to your instructions."
        end

        def transform_openai_result(run_result, run_context)
          if run_result.success?
            # RunResult has final_output, not result or context_variables
            RAAF::DSL::Result.new(success: true, data: run_result.final_output, context_variables: run_context)
          else
            RAAF::DSL::Result.new(success: false, data: nil, error: run_result.error || "Unknown error", context_variables: run_context)
          end
        end

        def create_openai_agent_instance
          agent_params = { name: agent_name, instructions: build_instructions, model: model_name, tools: tools, handoffs: handoffs, response_format: response_format, max_turns: max_turns }
          agent_params[:hooks] = build_hooks_config if respond_to?(:build_hooks_config, true)
          RAAF::Agent.new(**agent_params)
        end

        def build_hooks_config
          respond_to?(:combined_hooks_config, true) ? combined_hooks_config : nil
        end
      end
    end
  end
end
