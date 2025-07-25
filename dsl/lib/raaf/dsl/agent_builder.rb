# frozen_string_literal: true

module RAAF
  module DSL
    ##
    # Agent builder for DSL-based agent construction
    #
    # Provides a fluent interface for building agents using the DSL syntax.
    # Supports declarative agent definition with tools, configurations, and behaviors.
    #
    class AgentBuilder
      include RAAF::Logging

      @@count = 0

      ##
      # Build agent using DSL block
      #
      # @param name [String] Optional agent name
      # @param &block [Block] DSL configuration block
      # @return [Agent] Configured agent
      #
      def self.build(name = nil, &block)
        builder = new(name)
        builder.instance_eval(&block) if block_given?
        builder.build
      end

      # @return [String] Agent name
      attr_reader :agent_name

      # @return [Hash] Agent configuration
      attr_reader :config

      # @return [Array<Tool>] Agent tools
      attr_reader :tools

      # @return [Array<Proc>] Event handlers
      attr_reader :handlers

      ##
      # Initialize agent builder
      #
      # @param name [String] Agent name
      #
      def initialize(name = nil)
        @agent_name = name
        @config = {}
        @tools = []
        @handlers = {}
        @conditions = []
        @macros = []
        @templates = []
        @@count += 1
      end

      ##
      # Set agent name
      #
      # @param name [String] Agent name
      #
      def name(name)
        @agent_name = name
      end

      ##
      # Set agent instructions
      #
      # @param instructions [String] Agent instructions
      #
      def instructions(instructions)
        @config[:instructions] = instructions
      end

      ##
      # Set agent model
      #
      # @param model [String] Model name
      #
      def model(model)
        @config[:model] = model
      end

      ##
      # Set agent provider
      #
      # @param provider [Object] Provider instance
      #
      def provider(provider)
        @config[:provider] = provider
      end

      ##
      # Set agent temperature
      #
      # @param temperature [Float] Temperature value
      #
      def temperature(temperature)
        @config[:temperature] = temperature
      end

      ##
      # Set agent max tokens
      #
      # @param max_tokens [Integer] Maximum tokens
      #
      def max_tokens(max_tokens)
        @config[:max_tokens] = max_tokens
      end

      ##
      # Set agent timeout
      #
      # @param timeout [Integer] Timeout in seconds
      #
      def timeout(timeout)
        @config[:timeout] = timeout
      end

      ##
      # Configure agent logging
      #
      # @param options [Hash] Logging options
      #
      def logging(**options)
        @config[:logging] = options
      end

      ##
      # Configure agent tracing
      #
      # @param options [Hash] Tracing options
      #
      def tracing(**options)
        @config[:tracing] = options
      end

      ##
      # Configure agent memory
      #
      # @param options [Hash] Memory options
      #
      def memory(**options)
        @config[:memory] = options
      end

      ##
      # Configure agent guardrails
      #
      # @param options [Hash] Guardrails options
      #
      def guardrails(**options)
        @config[:guardrails] = options
      end

      ##
      # Define a tool
      #
      # @param name [Symbol] Tool name
      # @param options [Hash] Tool options
      # @param block [Proc] Tool definition block
      #
      def tool(name, **options, &block)
        tool_builder = ToolBuilder.new(name)
        tool_builder.instance_eval(&block) if block_given?

        # Merge options
        tool_config = tool_builder.build_config.merge(options)

        @tools << {
          name: name,
          config: tool_config,
          block: block
        }
      end

      ##
      # Add existing tool
      #
      # @param tool [Tool] Tool instance
      #
      def add_tool(tool)
        @tools << tool
      end

      ##
      # Define error handler
      #
      # @param block [Proc] Error handler block
      #
      def on_error(&block)
        @handlers[:error] = block
      end

      ##
      # Define before handler
      #
      # @param block [Proc] Before handler block
      #
      def before(&block)
        @handlers[:before] = block
      end

      ##
      # Define after handler
      #
      # @param block [Proc] After handler block
      #
      def after(&block)
        @handlers[:after] = block
      end

      ##
      # Define completion handler
      #
      # @param block [Proc] Completion handler block
      #
      def on_completion(&block)
        @handlers[:completion] = block
      end

      ##
      # Define streaming handler
      #
      # @param block [Proc] Streaming handler block
      #
      def on_stream(&block)
        @handlers[:stream] = block
      end

      ##
      # Define handoff handler
      #
      # @param block [Proc] Handoff handler block
      #
      def on_handoff(&block)
        @handlers[:handoff] = block
      end

      ##
      # Add conditional logic
      #
      # @param condition [Proc] Condition block
      # @param block [Proc] Action block
      #
      def when(condition, &block)
        @conditions << {
          condition: condition,
          action: block
        }
      end

      ##
      # Add if-then-else logic
      #
      # @param condition [Proc] Condition block
      #
      def if_then(condition)
        IfThenBuilder.new(self, condition)
      end

      ##
      # Use macro
      #
      # @param macro_name [Symbol] Macro name
      # @param options [Hash] Macro options
      #
      def use_macro(macro_name, **options)
        @macros << {
          name: macro_name,
          options: options
        }
      end

      ##
      # Use template
      #
      # @param template_name [Symbol] Template name
      # @param variables [Hash] Template variables
      #
      def use_template(template_name, **variables)
        @templates << {
          name: template_name,
          variables: variables
        }
      end

      ##
      # Set agent metadata
      #
      # @param metadata [Hash] Agent metadata
      #
      def metadata(**metadata)
        @config[:metadata] = (@config[:metadata] || {}).merge(metadata)
      end

      ##
      # Set agent tags
      #
      # @param tags [Array<String>] Agent tags
      #
      def tags(*tags)
        @config[:tags] = tags.flatten
      end

      ##
      # Set agent description
      #
      # @param description [String] Agent description
      #
      def description(description)
        @config[:description] = description
      end

      ##
      # Set agent version
      #
      # @param version [String] Agent version
      #
      def version(version)
        @config[:version] = version
      end

      ##
      # Configure agent for streaming
      #
      # @param options [Hash] Streaming options
      #
      def streaming(**options)
        @config[:streaming] = options
      end

      ##
      # Configure agent for handoffs
      #
      # @param options [Hash] Handoff options
      #
      def handoffs(**options)
        @config[:handoffs] = options
      end

      ##
      # Configure agent context
      #
      # @param options [Hash] Context options
      #
      def context(**options)
        @config[:context] = options
      end

      ##
      # Configure agent validation
      #
      # @param options [Hash] Validation options
      #
      def validation(**options)
        @config[:validation] = options
      end

      ##
      # Configure agent caching
      #
      # @param options [Hash] Caching options
      #
      def caching(**options)
        @config[:caching] = options
      end

      ##
      # Configure agent retries
      #
      # @param options [Hash] Retry options
      #
      def retry_policy(**options)
        @config[:retry_policy] = options
      end

      ##
      # Build the agent
      #
      # @return [Agent] Configured agent
      #
      def build
        validate_configuration!

        # Create agent instance
        agent = RAAF::Agent.new(
          name: @agent_name,
          instructions: @config[:instructions],
          model: @config[:model],
          **@config.except(:instructions, :model)
        )

        # Apply macros
        apply_macros(agent)

        # Apply templates
        apply_templates(agent)

        # Add tools
        add_tools_to_agent(agent)

        # Add event handlers
        add_handlers_to_agent(agent)

        # Add conditions
        add_conditions_to_agent(agent)

        log_info("Agent built successfully", agent_name: @agent_name, tools: @tools.size)
        agent
      end

      ##
      # Get builder statistics
      #
      # @return [Hash] Builder statistics
      def statistics
        {
          name: @agent_name,
          tools_count: @tools.size,
          handlers_count: @handlers.size,
          conditions_count: @conditions.size,
          macros_count: @macros.size,
          templates_count: @templates.size
        }
      end

      ##
      # Get total count of agents built
      #
      # @return [Integer] Total count
      def self.count
        @@count
      end

      ##
      # Reset count
      #
      def self.reset_count!
        @@count = 0
      end

      private

      def validate_configuration!
        errors = []

        errors << "Agent name is required" unless @agent_name
        errors << "Agent instructions are required" unless @config[:instructions]
        errors << "Agent model is required" unless @config[:model]

        # Validate tools
        @tools.each do |tool|
          errors << "Tool name is required" if tool.is_a?(Hash) && !tool[:name]
        end

        # Validate temperature
        if @config[:temperature] && (@config[:temperature].negative? || @config[:temperature] > 2)
          errors << "Temperature must be between 0 and 2"
        end

        # Validate max_tokens
        errors << "Max tokens must be positive" if @config[:max_tokens] && @config[:max_tokens] < 1

        raise DSL::ValidationError, errors.join(", ") if errors.any?
      end

      def apply_macros(agent)
        @macros.each do |macro_def|
          macro = MacroProcessor.get_macro(macro_def[:name])
          next unless macro

          # Apply macro to agent
          macro.apply(agent, macro_def[:options])
        end
      end

      def apply_templates(agent)
        @templates.each do |template_def|
          template = TemplateEngine.get_template(template_def[:name])
          next unless template

          # Apply template to agent
          template.apply(agent, template_def[:variables])
        end
      end

      def add_tools_to_agent(agent)
        @tools.each do |tool_def|
          if tool_def.is_a?(Hash) && tool_def[:name]
            # Build tool from definition
            tool = RAAF::FunctionTool.new(
              name: tool_def[:name],
              description: tool_def[:config][:description],
              parameters: tool_def[:config][:parameters],
              &tool_def[:block]
            )
            agent.add_tool(tool)
          else
            # Add existing tool
            agent.add_tool(tool_def)
          end
        end
      end

      def add_handlers_to_agent(agent)
        @handlers.each do |event, handler|
          case event
          when :error
            agent.on_error(&handler)
          when :before
            agent.before_run(&handler)
          when :after
            agent.after_run(&handler)
          when :completion
            agent.on_completion(&handler)
          when :stream
            agent.on_stream(&handler)
          when :handoff
            agent.on_handoff(&handler)
          end
        end
      end

      def add_conditions_to_agent(agent)
        @conditions.each do |condition_def|
          agent.add_condition(condition_def[:condition], &condition_def[:action])
        end
      end
    end

    ##
    # If-then-else builder for conditional logic
    #
    class IfThenBuilder
      def initialize(agent_builder, condition)
        @agent_builder = agent_builder
        @condition = condition
      end

      def then(&block)
        @then_block = block
        self
      end

      def else(&block)
        @else_block = block
        self
      end

      def build
        @agent_builder.when(@condition, &@then_block)
        @agent_builder.when(->(context) { !@condition.call(context) }, &@else_block) if @else_block
      end
    end
  end
end
