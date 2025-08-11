# frozen_string_literal: true

require "active_support/concern"

module RAAF
  module DSL
    module Agents
      # DSL for defining AI agents in a declarative way
      #
      # Provides a clean, readable interface for configuring agents with
      # instructions, tools, schemas, and other properties.
      #
      # Usage:
      #   class MyAgent < RAAF::DSL::Agents::Base
      #     include RAAF::DSL::Agents::AgentDsl
      #
      #     agent_name "MyAgent"
      #     model "gpt-4o"
      #     max_turns 5
      #
      #     uses_tool :web_search
      #     uses_tool :calculator, weight: 0.8
      #
      #     prompt_class MyPromptClass
      #
      #     schema do
      #       field :results, type: :array, required: true do
      #         field :name, type: :string
      #         field :score, type: :integer, range: 0..100
      #       end
      #       field :summary, type: :string, required: true
      #     end
      #   end
      #
      module AgentDsl
        extend ActiveSupport::Concern

        included do
          # Use thread-local storage for DSL configuration to ensure thread safety
          # This prevents race conditions when multiple threads create agents simultaneously
          def self._agent_config
            Thread.current[:raaf_dsl_agent_config] ||= {}
          end

          def self._agent_config=(value)
            Thread.current[:raaf_dsl_agent_config] = value
          end

          def self._tools_config
            Thread.current[:raaf_dsl_tools_config] ||= []
          end

          def self._tools_config=(value)
            Thread.current[:raaf_dsl_tools_config] = value
          end

          def self._schema_config
            Thread.current[:raaf_dsl_schema_config] ||= {}
          end

          def self._schema_config=(value)
            Thread.current[:raaf_dsl_schema_config] = value
          end

          def self._prompt_config
            Thread.current[:raaf_dsl_prompt_config] ||= {}
          end

          def self._prompt_config=(value)
            Thread.current[:raaf_dsl_prompt_config] = value
          end

          # Initialize with empty configurations for each class
          self._agent_config = {}
          self._tools_config = []
          self._schema_config = {}
          self._prompt_config = {}
        end

        class_methods do
          # Ensure each subclass gets its own configuration
          def inherited(subclass)
            super
            subclass._agent_config = {}
            subclass._tools_config = []
            subclass._schema_config = {}
            subclass._prompt_config = {}
          end

          # Configure agent basic properties
          def agent_name(name = nil)
            if name
              _agent_config[:name] = name
            else
              _agent_config[:name]
            end
          end

          def model(model_name = nil)
            if model_name
              _agent_config[:model] = model_name
            else
              # Check YAML config first, then agent config, then default
              _agent_config[:model] ||
                RAAF::DSL::Config.model_for(agent_name) ||
                "gpt-4o"
            end
          end

          def max_turns(turns = nil)
            if turns
              _agent_config[:max_turns] = turns
            else
              # Check YAML config first, then agent config, then default
              _agent_config[:max_turns] ||
                RAAF::DSL::Config.max_turns_for(agent_name) ||
                3
            end
          end

          def description(desc = nil)
            if desc
              _agent_config[:description] = desc
            else
              _agent_config[:description]
            end
          end

          # Configure tools
          def uses_tool(tool_name, options = {})
            _tools_config << { name: tool_name, options: options }
          end

          def uses_tools(*tool_names)
            tool_names.each { |name| uses_tool(name) }
          end

          # Configure multiple tools with a hash of options
          def configure_tools(tools_hash)
            tools_hash.each do |tool_name, options|
              uses_tool(tool_name, options || {})
            end
          end

          # Add tools with conditional logic
          def uses_tool_if(condition, tool_name, options = {})
            uses_tool(tool_name, options) if condition
          end

          # Configure prompt templates
          def instruction_template(template = nil)
            if template
              _prompt_config[:instruction_template] = template
            else
              _prompt_config[:instruction_template]
            end
          end

          def prompt_class(klass = nil)
            if klass
              _prompt_config[:class] = klass
            else
              _prompt_config[:class]
            end
          end

          def instruction_variables(&block)
            if block_given?
              variables_builder = RAAF::DSL::InstructionVariables.new
              variables_builder.instance_eval(&block)
              _prompt_config[:instruction_variables] = variables_builder.variables
            else
              _prompt_config[:instruction_variables] || {}
            end
          end

          def static_instructions(instructions = nil)
            if instructions
              _prompt_config[:static_instructions] = instructions
            else
              _prompt_config[:static_instructions]
            end
          end

          # Configure response schema
          def schema(&block)
            if block_given?
              schema_builder = RAAF::DSL::SchemaBuilder.new
              schema_builder.instance_eval(&block)
              self._schema_config = schema_builder.to_hash
            else
              _schema_config
            end
          end

          # Configure handoffs (for orchestrator agents)
          def hands_off_to(*agent_classes)
            _agent_config[:handoff_agents] = agent_classes
          end

          def handoff_to(agent_class, options = {})
            _agent_config[:handoff_agents] ||= []
            _agent_config[:handoff_agents] << { agent: agent_class, options: options }
          end

          def configure_handoffs(handoffs_hash)
            handoffs_hash.each do |agent_class, options|
              handoff_to(agent_class, options || {})
            end
          end

          def handoff_to_if(condition, agent_class, options = {})
            handoff_to(agent_class, options) if condition
          end

          def handoff_sequence(*agent_classes)
            _agent_config[:handoff_sequence] = agent_classes
            _agent_config[:handoff_agents] = agent_classes
          end

          def workflow(&block)
            return unless block_given?

            workflow_builder = RAAF::DSL::WorkflowBuilder.new
            workflow_builder.instance_eval(&block)
            handoff_sequence(*workflow_builder.agents)
          end

          def orchestrates(&block)
            workflow(&block)
          end

          def discovery_workflow(&block)
            workflow(&block)
          end

          def coordinates(&block)
            workflow(&block)
          end

          # Helper method to get agent name for YAML config lookup
          def inferred_agent_name
            agent_class_name = name

            # Remove the agent namespace and get just the class name
            # e.g., RAAF::DSL::Agents::Company::Discovery -> Company::Discovery
            class_path = if agent_class_name.start_with?("RAAF::DSL::Agents::")
                           agent_class_name.sub("RAAF::DSL::Agents::", "")
                         else
                           agent_class_name
                         end

            # Convert to underscore format for YAML config
            # e.g., Company::Discovery -> company_discovery
            # e.g., Product::MarketResearch -> market_research
            # e.g., Orchestrator -> orchestrator
            class_path.underscore.gsub("/", "_")
          end
        end

        # Instance methods that use the DSL configuration
        def agent_name
          self.class.agent_name || self.class.name.demodulize
        end

        def model_name
          self.class.model
        end

        def max_turns
          self.class.max_turns
        end

        def tools
          @tools ||= begin
            tool_list = build_tools_from_config
            # Convert DSL tools to FunctionTool instances for RAAF compatibility
            tool_list.map { |tool| convert_to_function_tool(tool) }.compact
          end
        end

        def build_instructions
          if prompt_class_configured?
            prompt_instance.render(:system)
          elsif self.class.instruction_template
            build_templated_instructions
          elsif self.class.static_instructions
            self.class.static_instructions
          else
            "You are #{agent_name}. Respond with helpful and accurate information."
          end
        end

        def build_user_prompt
          raise RAAF::DSL::Error, "No prompt class configured for #{self.class.name}" unless prompt_class_configured?

          prompt_instance.render(:user)
        end

        def prompt_class_configured?
          self.class._prompt_config[:class].present? || default_prompt_class.present?
        end

        def prompt_instance
          @prompt_instance ||= build_prompt_instance
        end

        def default_prompt_class
          @default_prompt_class ||= begin
            # Convert agent class name to prompt class name
            # E.g., RAAF::DSL::Agents::Product::MarketResearch -> RAAF::DSL::Prompts::Product::MarketResearch
            agent_class_name = self.class.name

            if agent_class_name.start_with?("RAAF::DSL::Agents::")
              prompt_class_name = agent_class_name.sub("RAAF::DSL::Agents::", "RAAF::DSL::Prompts::")
              prompt_class_name.constantize
            elsif agent_class_name.include?("::Agents::")
              # Handle any namespace that follows the ::Agents:: -> ::Prompts:: pattern
              prompt_class_name = agent_class_name.sub("::Agents::", "::Prompts::")
              prompt_class_name.constantize
            end
          rescue NameError
            nil
          end
        end

        def build_schema
          schema = self.class.schema
          if schema.nil? || schema.empty?
            {
              type: "object",
              properties: {},
              additionalProperties: false
            }
          else
            schema
          end
        end

        def handoffs
          @handoffs ||= build_handoffs_from_config
        end

        private

        # Helper method to access context as a hash in lambda blocks
        def context_hash
          @context.to_h
        end

        def build_tools_from_config
          self.class._tools_config.map do |tool_config|
            create_tool_instance(tool_config[:name], tool_config[:options])
          end
        end

        def create_tool_instance(tool_name, options)
          tool_class = resolve_tool_class(tool_name)
          tool_class.new(options)
        end

        def resolve_tool_class(tool_name)
          # First check the registry for registered tools
          if RAAF::DSL::ToolRegistry.registered?(tool_name)
            return RAAF::DSL::ToolRegistry.get(tool_name)
          end

          # Fall back to name resolution for backwards compatibility
          # Map common tool names to their actual classes
          tool_mappings = {
            web_search: "WebSearch",
            tavily_search: "TavilySearch",
            database_query: "DatabaseQuery",
            calculator: "Calculator"
          }

          # Get the mapped name or use the original
          mapped_name = tool_mappings[tool_name.to_sym] || tool_name.to_s.camelize

          # Try multiple namespaces in order of preference
          candidates = [
            "RAAF::DSL::Tools::#{mapped_name}",
            "Ai::Tools::#{mapped_name}",
            mapped_name
          ]

          candidates.each do |class_name|
            return class_name.constantize
          rescue NameError
            next
          end

          raise "Unknown tool: #{tool_name}. Tried: #{candidates.join(', ')}"
        end

        def build_templated_instructions
          template = self.class.instruction_template
          variables = self.class.instruction_variables.merge(
            agent_name: agent_name
          )

          # Evaluate lambda variables
          variables = variables.transform_values do |value|
            value.is_a?(Proc) ? instance_exec(&value) : value
          end

          # Simple template substitution
          template.gsub(/\{(\w+)\}/) do |match|
            key = Regexp.last_match(1).to_sym
            variables[key] || match
          end
        end

        def build_prompt_instance
          prompt_class = self.class._prompt_config[:class] || default_prompt_class
          return unless prompt_class

          # Build core context for prompt class - merge context variables directly
          prompt_context = @context.to_h.merge({
                                                 processing_params: @processing_params,
                                                 agent_name: agent_name,
                                                 context_variables: @context
                                               })

          prompt_class.new(**prompt_context)
        end

        def build_handoffs_from_config
          handoff_agent_configs = self.class._agent_config[:handoff_agents] || []
          handoff_agent_configs.map do |handoff_config|
            if handoff_config.is_a?(Hash)
              handoff_agent_class = handoff_config[:agent]
              options = handoff_config[:options] || {}
              merged_context = @context.merge(options[:context] || {})
              merged_params = @processing_params.merge(options[:processing_params] || {})
              handoff_agent_class.new(context: merged_context, processing_params: merged_params)
            else
              # Direct agent class
              handoff_config.new(context: @context, processing_params: @processing_params)
            end
          end
        end
      end
    end

    # Helper class for building instruction variables
    class InstructionVariables
      attr_reader :variables

      def initialize
        @variables = {}
      end

      def method_missing(method_name, *args, &block)
        if block_given?
          @variables[method_name] = block
        elsif args.length == 1
          @variables[method_name] = args.first
        else
          super
        end
      end

      def respond_to_missing?(_method_name, _include_private = false)
        true
      end
    end

    # Helper class for building JSON schemas
    class SchemaBuilder
      def initialize
        @schema = {
          type: "object",
          properties: {},
          required: [],
          additionalProperties: false
        }
      end

      def field(name, type:, required: false, **options, &block)
        field_schema = build_field_schema(type, options)

        if block_given?
          case type
          when :object
            nested_builder = RAAF::DSL::SchemaBuilder.new
            nested_builder.instance_eval(&block)
            nested_schema = nested_builder.to_hash.except(:type)
            # Ensure nested objects have additionalProperties: false for OpenAI strict mode
            nested_schema[:additionalProperties] = false
            field_schema.merge!(nested_schema)
          when :array
            if options[:items_type]
              field_schema[:items] = build_field_schema(options[:items_type], options)
            else
              # Array of objects
              nested_builder = RAAF::DSL::SchemaBuilder.new
              nested_builder.instance_eval(&block)
              nested_schema = nested_builder.to_hash
              # Ensure nested objects in arrays have additionalProperties: false for OpenAI strict mode
              nested_schema[:additionalProperties] = false
              field_schema[:items] = nested_schema
            end
          end
        end

        @schema[:properties][name] = field_schema
        @schema[:required] << name if required
      end

      def to_hash
        @schema
      end

      private

      def build_field_schema(type, options)
        schema = { type: type.to_s }

        # Add type-specific constraints
        case type
        when :integer
          schema[:minimum] = options[:min] if options[:min]
          schema[:maximum] = options[:max] if options[:max]
          if options[:range]
            schema[:minimum] = options[:range].begin
            schema[:maximum] = options[:range].end
          end
        when :string
          schema[:minLength] = options[:min_length] if options[:min_length]
          schema[:maxLength] = options[:max_length] if options[:max_length]
          schema[:enum] = options[:enum] if options[:enum]
        when :array
          schema[:minItems] = options[:min_items] if options[:min_items]
          schema[:maxItems] = options[:max_items] if options[:max_items]
          schema[:items] = { type: options[:items_type].to_s } if options[:items_type]
        end

        # Common attributes
        schema[:description] = options[:description] if options[:description]
        schema[:default] = options[:default] if options.key?(:default)

        schema
      end
    end

    # Helper class for building workflows
    class WorkflowBuilder
      attr_reader :agents

      def initialize
        @agents = []
      end

      def step(agent, _description = nil)
        @agents << agent
      end

      def then_step(agent, _description = nil)
        @agents << agent
      end

      def agent(agent_class)
        @agents << agent_class
      end

      def then_agent(agent_class)
        @agents << agent_class
      end

      def step_if(condition, agent)
        @agents << agent if condition
      end

      def method_missing(method_name, *args, &block)
        if args.length == 1 && args.first.is_a?(Class)
          @agents << args.first
        else
          super
        end
      end

      def respond_to_missing?(_method_name, _include_private = false)
        true
      end
    end
  end
end
