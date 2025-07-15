# frozen_string_literal: true

module AiAgentDsl
  # DSL for defining AI agents in a declarative way
  #
  # Provides a clean, readable interface for configuring agents with
  # instructions, tools, schemas, and other properties.
  #
  # Usage:
  #   class MyAgent < AiAgentDsl::Agents::Base
  #     include AiAgentDsl::AgentDsl
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
      class_attribute :_agent_config
      class_attribute :_tools_config
      class_attribute :_schema_config
      class_attribute :_prompt_config

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
            AiAgentDsl::Config.model_for(agent_name) ||
            "gpt-4o"
        end
      end

      def max_turns(turns = nil)
        if turns
          _agent_config[:max_turns] = turns
        else
          # Check YAML config first, then agent config, then default
          _agent_config[:max_turns] ||
            AiAgentDsl::Config.max_turns_for(agent_name) ||
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

      # Configure tool choice behavior for the agent
      #
      # Controls how the AI model should select and use tools during execution.
      # This gives you fine-grained control over tool usage patterns.
      #
      # @param choice [String, Hash, nil] Tool choice configuration
      # @option choice [String] "auto" Let the model decide when to use tools (default)
      # @option choice [String] "none" Never use tools, only respond with text
      # @option choice [String] "required" Must use a tool before responding
      # @option choice [Hash] { type: "function", function: { name: "tool_name" } } Force specific tool
      #
      # @example Auto tool selection (default)
      #   tool_choice "auto"
      #
      # @example Disable all tools
      #   tool_choice "none"
      #
      # @example Require tool usage
      #   tool_choice "required"
      #
      # @example Force specific tool
      #   tool_choice({ type: "function", function: { name: "web_search" } })
      #
      # @example Force specific tool (simplified syntax)
      #   tool_choice "web_search"  # Automatically converted to function format
      #
      def tool_choice(choice = nil)
        if choice
          # Handle simplified syntax for tool names
          _agent_config[:tool_choice] = if choice.is_a?(String) && !["auto", "none", "required"].include?(choice)
                                          {
                                            type:     "function",
                                            function: { name: choice }
                                          }
                                        else
                                          choice
                                        end
        else
          # Check YAML config first, then agent config, then framework default
          _agent_config[:tool_choice] ||
            AiAgentDsl::Config.tool_choice_for(agent_name) ||
            AiAgentDsl.configuration.default_tool_choice
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

      # Configure context storage keys
      #
      # Defines which keys from the agent's response should be stored in the
      # shared context for use by subsequent agents in the workflow.
      #
      # @param keys [Array<Symbol>] The keys to store in context
      #
      # @example Register search strategy results
      #   stores_in_context :search_strategies, :market_insights
      #
      # @example Register company discovery results
      #   stores_in_context :discovered_companies
      #
      def stores_in_context(*keys)
        if keys.any?
          _agent_config[:context_storage_keys] = keys.map(&:to_sym)
        else
          _agent_config[:context_storage_keys] || []
        end
      end

      # Add a single context storage key
      def store_in_context(key)
        current_keys = _agent_config[:context_storage_keys] || []
        _agent_config[:context_storage_keys] = (current_keys + [key.to_sym]).uniq
      end

      # Get all context storage keys (including inherited ones)
      def context_storage_keys
        _agent_config[:context_storage_keys] || []
      end

      # Configure prompt class with automatic inference
      def prompt_class(klass = nil)
        if klass
          _prompt_config[:class] = klass
        else
          _prompt_config[:class] || infer_default_prompt_class
        end
      end

      # Infer the default prompt class based on naming conventions
      #
      # Converts agent class names to prompt class names:
      # Examples:
      #   Ai::Agents::Search::Strategy -> Ai::Prompts::Search::Strategy
      #   Ai::Agents::Company::Discovery -> Ai::Prompts::Company::Discovery
      #   MyAgent -> MyPrompt
      #
      # @return [Class] The inferred prompt class
      # @raise [NameError] If the prompt class doesn't exist
      def infer_default_prompt_class
        agent_class_name = name

        # Convert agent namespace to prompt namespace
        prompt_class_name = agent_class_name.gsub("::Agents::", "::Prompts::")

        # Handle cases where the base class name needs conversion
        # This handles non-namespaced classes or different patterns
        unless prompt_class_name.include?("::Prompts::")
          if agent_class_name.include?("::")
            # If it has namespace but not ::Agents::, try to replace the last part
            parts = agent_class_name.split("::")
            if parts.length >= 2
              # Replace second-to-last part if it looks like "Agents"
              if parts[-2] == "Agents"
                parts[-2] = "Prompts"
              else
                # Insert Prompts before the last part
                parts.insert(-1, "Prompts")
              end
              prompt_class_name = parts.join("::")
            end
          else
            # No namespace - simple conversion
            prompt_class_name = agent_class_name.gsub(/Agent$/, "Prompt")
          end
        end

        prompt_class_name.constantize
      rescue NameError => e
        raise NameError, "No prompt class found for #{name}. " \
                         "Expected: #{prompt_class_name}. " \
                         "Please specify prompt_class explicitly or create #{prompt_class_name}. " \
                         "Original error: #{e.message}"
      end

      # Configure response schema
      def schema(&block)
        if block_given?
          schema_builder = SchemaBuilder.new
          schema_builder.instance_eval(&block)
          self._schema_config = schema_builder.to_hash
        else
          _schema_config
        end
      end

      # Alias for schema (for test compatibility)
      alias_method :schema_definition, :schema

      # Configure output format
      def output_format(format = nil)
        if format.nil?
          # Getter: return the configured output format
          _agent_config[:output_format]
        else
          # Setter: configure the output format
          case format.to_sym
          when :text, :plain, :unstructured
            _agent_config[:output_format] = :unstructured
          when :json, :structured, :schema
            _agent_config[:output_format] = :structured
          else
            raise ArgumentError,
              "Invalid output format: #{format}. Use :text, :plain, :unstructured, :json, :structured, or :schema"
          end
        end
      end

      # Convenience methods for output format
      def text_output
        output_format(:text)
      end

      def structured_output
        output_format(:structured)
      end

      def unstructured_output
        output_format(:unstructured)
      end

      # Configure result storage for the agent
      #
      # Controls whether the agent should automatically store its results in the
      # shared context for use by subsequent agents in multi-agent workflows.
      # When enabled, the agent's response will be parsed and stored using the
      # keys defined by the stores_in_context configuration.
      #
      # @param enabled [Boolean, nil] Enable or disable result storage
      # @return [Boolean] Current result storage setting
      #
      # @example Enable result storage (default)
      #   result_storage_enabled true
      #
      # @example Disable result storage
      #   result_storage_enabled false
      #
      # @example Check current setting
      #   agent.result_storage_enabled? # => true
      #
      def result_storage_enabled(enabled = nil)
        if enabled.nil?
          # Getter: return the configured setting, default to true
          _agent_config.fetch(:result_storage_enabled, true)
        else
          # Setter: configure the setting
          _agent_config[:result_storage_enabled] = enabled
        end
      end

      # Configure handoffs (for orchestrator agents)
      def hands_off_to(*agent_classes)
        _agent_config[:handoff_agents] = agent_classes
      end

      # Add a single handoff agent (or get the configured handoff agent)
      def handoff_to(agent_class = nil, options = {})
        if agent_class.nil?
          # Getter: return the configured handoff agent
          handoff_agents = _agent_config[:handoff_agents]
          return if handoff_agents.nil? || handoff_agents.empty?

          # Return the first handoff agent (for single handoff scenarios)
          first_handoff = handoff_agents.first
          first_handoff.is_a?(Hash) ? first_handoff[:agent] : first_handoff
        else
          # Setter: add a handoff agent
          _agent_config[:handoff_agents] ||= []
          _agent_config[:handoff_agents] << { agent: agent_class, options: options }
        end
      end

      # Configure multiple handoffs with options
      def configure_handoffs(handoffs_hash)
        handoffs_hash.each do |agent_class, options|
          handoff_to(agent_class, options || {})
        end
      end

      # Conditional handoff
      def handoff_to_if(condition, agent_class, options = {})
        handoff_to(agent_class, options) if condition
      end

      # Set handoff sequence/workflow
      def handoff_sequence(*agent_classes)
        _agent_config[:handoff_sequence] = agent_classes
        # Register each agent in the sequence as a handoff
        agent_classes.each do |agent_class|
          handoff_to(agent_class)
        end
      end

      # DSL-style workflow definition
      def workflow(&block)
        return unless block_given?

        workflow_builder = WorkflowBuilder.new
        workflow_builder.instance_eval(&block)
        handoff_sequence(*workflow_builder.agents)
      end

      # Alternative DSL methods for readability
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
        # e.g., AiAgentDsl::Agents::Company::Discovery -> Company::Discovery
        class_path = if agent_class_name.start_with?("AiAgentDsl::Agents::")
                       agent_class_name.sub("AiAgentDsl::Agents::", "")
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

    # Check if result storage is enabled for this agent
    #
    # This method returns whether the agent should automatically store its
    # results in the shared context for use by subsequent agents. The value
    # is configured through the DSL and defaults to true to enable seamless
    # multi-agent workflows.
    #
    # @return [Boolean] True if result storage is enabled, false otherwise
    #
    # @example
    #   class MyAgent < AiAgentDsl::Agents::Base
    #     include AiAgentDsl::AgentDsl
    #     result_storage_enabled false
    #   end
    #
    #   agent = MyAgent.new(context: {}, processing_params: {})
    #   agent.result_storage_enabled? # => false
    #
    def result_storage_enabled?
      self.class.result_storage_enabled
    end

    # Alias for compatibility with OpenAI agents that expect .name method
    def name
      agent_name
    end

    # Get the AI model name configured for this agent
    #
    # This method returns the name of the AI model (e.g., "gpt-4o", "gpt-4o-mini")
    # that will be used for this agent's execution. The model determines the
    # capabilities, performance, and cost characteristics of the agent.
    #
    # The value is resolved through the configuration hierarchy:
    # 1. DSL class configuration (if set)
    # 2. YAML agent-specific configuration
    # 3. YAML global configuration
    # 4. Framework default ("gpt-4o")
    #
    # @return [String] The AI model name
    #
    # @example
    #   class MyAgent < AiAgentDsl::Agents::Base
    #     include AiAgentDsl::AgentDsl
    #     model "gpt-4o-mini"
    #   end
    #
    #   agent.model_name # => "gpt-4o-mini"
    #
    def model_name
      self.class.model
    end

    # Alias for OpenAI Agents Runner compatibility
    def model
      model_name
    end

    # Get the tool choice configuration for this agent
    #
    # This method returns the configured tool choice behavior that controls
    # how the AI model should select and use tools during execution. This
    # provides fine-grained control over tool usage patterns.
    #
    # The value is resolved through the configuration hierarchy:
    # 1. DSL class configuration (if set)
    # 2. YAML agent-specific configuration
    # 3. YAML global configuration
    # 4. Framework default ("auto")
    #
    # @return [String, Hash] The tool choice configuration
    #
    # @example
    #   class MyAgent < AiAgentDsl::Agents::Base
    #     include AiAgentDsl::AgentDsl
    #     tool_choice "required"
    #   end
    #
    #   agent.tool_choice_config # => "required"
    #
    def tool_choice_config
      self.class.tool_choice
    end

    # Get the maximum number of conversation turns for this agent
    #
    # This method returns the configured maximum number of turns (back-and-forth
    # exchanges) the agent is allowed to have with the AI service. This setting
    # helps control costs and prevents infinite loops in agent execution.
    #
    # The value is resolved through the configuration hierarchy:
    # 1. DSL class configuration (if set)
    # 2. YAML agent-specific configuration
    # 3. YAML global configuration
    # 4. Framework default (3 turns)
    #
    # @return [Integer] Maximum number of conversation turns
    #
    # @example
    #   class MyAgent < AiAgentDsl::Agents::Base
    #     include AiAgentDsl::AgentDsl
    #     max_turns 5
    #   end
    #
    #   agent.max_turns # => 5
    #
    def max_turns
      self.class.max_turns
    end

    # Get the configured tools for this agent
    #
    # This method returns an array of tool instances that have been configured
    # for the agent through the DSL. Tools are built lazily and cached after
    # the first access. Each tool is resolved through the tool registry and
    # instantiated with any provided options.
    #
    # @return [Array<Object>] Array of tool instances ready for use by the agent
    # @example
    #   class MyAgent < AiAgentDsl::Agents::Base
    #     include AiAgentDsl::AgentDsl
    #     uses_tool :web_search, limit: 10
    #     uses_tool :calculator
    #   end
    #
    #   agent = MyAgent.new(context: {}, processing_params: {})
    #   agent.tools # => [WebSearchTool, CalculatorTool]
    #
    def tools
      @tools ||= begin
        built_tools = build_tools_from_config

        # Debug log final tools being returned
        if defined?(Rails) && Rails.logger && Rails.env.development?
          Rails.logger.info "🎯 Final tools for #{self.class.name}:"
          built_tools.each_with_index do |tool, idx|
            Rails.logger.info "   Tool #{idx + 1}: #{tool.class.name}"
            next unless tool.respond_to?(:name) && tool.respond_to?(:parameters)

            Rails.logger.info "     Name: #{tool.name}"
            Rails.logger.info "     Parameters type: #{tool.parameters.class.name}"
            Rails.logger.info "     Parameters present: #{!tool.parameters.nil? && !tool.parameters.empty?}"
            if tool.parameters && tool.parameters[:properties]
              Rails.logger.info "     Properties: #{tool.parameters[:properties].keys}"
              Rails.logger.info "     Required: #{tool.parameters[:required]}"
            end
          end
        end

        built_tools
      end
    end

    # Build the system instructions for the agent
    #
    # This method constructs the system prompt that defines the agent's behavior,
    # role, and capabilities. It uses the configured prompt class to generate
    # context-aware instructions based on the agent's current context and
    # processing parameters.
    #
    # The method enforces strict prompt class requirements and validates that
    # the prompt class implements the required system and user methods before
    # rendering the system prompt.
    #
    # @return [String] The system instructions for the AI agent
    # @raise [AiAgentDsl::Error] If no prompt class is configured or methods are missing
    #
    # @example
    #   agent = MyAgent.new(context: { company: "Acme Corp" }, processing_params: {})
    #   instructions = agent.build_instructions
    #   # => "You are an AI assistant analyzing Acme Corp..."
    #
    def build_instructions
      # Strict requirement: prompt class must be configured
      unless prompt_class_configured?
        raise AiAgentDsl::Error, "No prompt class configured for #{self.class.name}. " \
                                 "Either set 'prompt_class' explicitly or create #{expected_prompt_class_name}"
      end

      # Validate that the prompt instance has required methods
      validate_prompt_methods!

      prompt_instance.render(:system)
    end

    # Build the user prompt for the agent
    #
    # This method constructs the user prompt that contains the specific request
    # or task for the AI agent to perform. It uses the configured prompt class
    # to generate context-aware user prompts based on the agent's current
    # context and processing parameters.
    #
    # Like build_instructions, this method enforces strict prompt class
    # requirements and validates the prompt implementation before rendering.
    #
    # @return [String] The user prompt for the AI agent
    # @raise [AiAgentDsl::Error] If no prompt class is configured or methods are missing
    #
    # @example
    #   agent = MyAgent.new(
    #     context: { document: { name: "report.pdf" } },
    #     processing_params: { analysis_type: "financial" }
    #   )
    #   user_prompt = agent.build_user_prompt
    #   # => "Please analyze report.pdf using financial analysis..."
    #
    def build_user_prompt
      # Strict requirement: prompt class must be configured
      unless prompt_class_configured?
        raise AiAgentDsl::Error, "No prompt class configured for #{self.class.name}. " \
                                 "Either set 'prompt_class' explicitly or create #{expected_prompt_class_name}"
      end

      # Validate that the prompt instance has required methods
      validate_prompt_methods!

      prompt_instance.render(:user)
    end

    def prompt_class_configured?
      self.class._prompt_config[:class].present? || default_prompt_class.present?
    end

    # Get the prompt instance for this agent
    #
    # This method returns a configured instance of the prompt class that will
    # be used to generate system and user prompts for the agent. The prompt
    # instance is built with the agent's current context and processing parameters
    # and is cached after first access for performance.
    #
    # The prompt instance handles variable contracts, context mapping, and
    # template rendering to produce the final prompts that guide the AI's behavior.
    #
    # @return [AiAgentDsl::Prompts::Base] The configured prompt instance
    # @raise [AiAgentDsl::Error] If prompt class validation fails
    #
    # @example
    #   agent = MyAgent.new(
    #     context: { company: "Acme Corp" },
    #     processing_params: { analysis_depth: "deep" }
    #   )
    #   prompt = agent.prompt_instance
    #   prompt.system # => "You are analyzing Acme Corp with deep analysis..."
    #
    def prompt_instance
      @prompt_instance ||= build_prompt_instance
    end

    # Attempt to infer the prompt class based on naming conventions
    #
    # This method uses naming convention patterns to automatically discover
    # the appropriate prompt class for an agent. It transforms the agent's
    # class name from the Agents namespace to the Prompts namespace.
    #
    # Supported patterns:
    # - AiAgentDsl::Agents::MyAgent -> AiAgentDsl::Prompts::MyAgent
    # - CustomModule::Agents::MyAgent -> CustomModule::Prompts::MyAgent
    # - Nested namespaces are preserved
    #
    # @return [Class, nil] The inferred prompt class, or nil if not found
    #
    # @example
    #   class AiAgentDsl::Agents::Company::Discovery < Base
    #     # Will try to find AiAgentDsl::Prompts::Company::Discovery
    #   end
    #
    def default_prompt_class
      @default_prompt_class ||= begin
        # Convert agent class name to prompt class name
        # E.g., AiAgentDsl::Agents::Product::MarketResearch -> AiAgentDsl::Prompts::Product::MarketResearch
        # E.g., Ai::Agents::Product::MarketResearch -> Ai::Prompts::Product::MarketResearch
        agent_class_name = self.class.name

        # Support both AiAgentDsl::Agents:: and any ::Agents:: namespace
        if agent_class_name.start_with?("AiAgentDsl::Agents::")
          prompt_class_name = agent_class_name.sub("AiAgentDsl::Agents::", "AiAgentDsl::Prompts::")
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

    # Build the JSON schema for the agent's response format
    #
    # This method constructs the JSON schema that defines the expected structure
    # of the agent's response. It uses the schema configuration defined through
    # the DSL's schema block, or returns a basic empty schema if none is configured.
    #
    # The schema is used by OpenAI's structured output feature to ensure the
    # agent returns properly formatted JSON responses that match the expected
    # structure. All schemas include additionalProperties: false for OpenAI's
    # strict mode compliance.
    #
    # @return [Hash] JSON schema hash defining the response structure
    #
    # @example With configured schema
    #   class MyAgent < AiAgentDsl::Agents::Base
    #     include AiAgentDsl::AgentDsl
    #     schema do
    #       field :name, type: :string, required: true
    #       field :score, type: :integer, range: 0..100
    #     end
    #   end
    #
    #   agent.build_schema
    #   # => {
    #   #   type: "object",
    #   #   properties: {
    #   #     name: { type: "string" },
    #   #     score: { type: "integer", minimum: 0, maximum: 100 }
    #   #   },
    #   #   required: ["name"],
    #   #   additionalProperties: false
    #   # }
    #
    def build_schema
      agent_schema = self.class._schema_config
      prompt_schema = get_prompt_schema

      # Check for schema conflicts - only one source allowed
      if !agent_schema.empty? && !prompt_schema.empty?
        raise ArgumentError, "Schema conflict: Both agent class (#{self.class.name}) and prompt class " \
                             "(#{self.class._prompt_config[:class]&.name}) define schemas. " \
                             "Only one schema definition is allowed per agent."
      end

      # Use prompt schema if available, otherwise agent schema
      if !prompt_schema.empty?
        prompt_schema
      elsif !agent_schema.empty?
        agent_schema
      else
        # Check if unstructured output is requested
        if self.class._agent_config[:output_format] == :unstructured
          # Return nil to indicate no schema should be used
          return
        end

        # Return a basic schema if none is defined
        # Note: OpenAI strict mode requires additionalProperties: false
        {
          type:                 "object",
          properties:           {},
          additionalProperties: false
        }
      end
    end

    # Get the configured handoff agents for multi-agent workflows
    #
    # This method returns an array of OpenAI agent instances that this agent can
    # hand off execution to as part of a multi-agent workflow. Handoff agents
    # are built lazily and cached after the first access. Each handoff agent
    # starts as a DSL agent instance with the same context and processing
    # parameters as the current agent, then is converted to an OpenAI agent
    # instance for the handoff system.
    #
    # @return [Array<OpenAIAgents::Agent>] Array of OpenAI agent instances for handoffs
    #
    # @example
    #   class OrchestratorAgent < AiAgentDsl::Agents::Base
    #     include AiAgentDsl::AgentDsl
    #
    #     handoff_to ResearchAgent
    #     handoff_to AnalysisAgent
    #   end
    #
    #   orchestrator = OrchestratorAgent.new(context: ctx, processing_params: params)
    #   orchestrator.handoffs # => [OpenAIAgents::Agent, OpenAIAgents::Agent]
    #
    def handoffs
      @handoffs ||= build_handoffs_from_config
    end

    private

    # Get schema from the prompt class if available
    def get_prompt_schema
      prompt_class = self.class._prompt_config[:class]
      return {} unless prompt_class

      if prompt_class.respond_to?(:get_schema)
        prompt_class.get_schema
      else
        {}
      end
    end

    def expected_prompt_class_name
      # Convert agent class name to expected prompt class name
      # E.g., AiAgentDsl::Agents::MyAgent -> AiAgentDsl::Prompts::MyAgent
      # E.g., Ai::Agents::MyAgent -> Ai::Prompts::MyAgent
      agent_class_name = self.class.name

      if agent_class_name.start_with?("AiAgentDsl::Agents::")
        agent_class_name.sub("AiAgentDsl::Agents::", "AiAgentDsl::Prompts::")
      elsif agent_class_name.include?("::Agents::")
        agent_class_name.sub("::Agents::", "::Prompts::")
      else
        # Fallback: just append expected class name
        "#{agent_class_name}Prompt"
      end
    end

    def validate_prompt_methods!
      unless prompt_instance.respond_to?(:system)
        raise AiAgentDsl::Error, "Prompt class #{prompt_instance.class.name} must implement 'system' method"
      end

      unless prompt_instance.respond_to?(:user)
        raise AiAgentDsl::Error, "Prompt class #{prompt_instance.class.name} must implement 'user' method"
      end

      # Validate that the methods can actually be called without arguments for render
      unless prompt_instance.method(:system).arity <= 0
        raise AiAgentDsl::Error,
          "Prompt class #{prompt_instance.class.name} 'system' method must accept zero arguments or have default parameters"
      end

      unless prompt_instance.method(:user).arity <= 0
        raise AiAgentDsl::Error,
          "Prompt class #{prompt_instance.class.name} 'user' method must accept zero arguments or have default parameters"
      end
    end

    def build_tools_from_config
      self.class._tools_config.map do |tool_config|
        tool_instance = create_tool_instance(tool_config[:name], tool_config[:options])

        # Convert to OpenAI function tool format
        convert_to_openai_tool(tool_instance)
      end.compact
    end

    def create_tool_instance(tool_name, options)
      # First check the registry
      if AiAgentDsl::ToolRegistry.registered?(tool_name)
        tool_class = AiAgentDsl::ToolRegistry.get(tool_name)
        return tool_class.new(options)
      end

      # Fall back to resolving by class name
      tool_class = resolve_tool_class(tool_name)
      tool_class.new(options)
    end

    def convert_to_openai_tool(tool_instance)
      # If tool has an openai_tool method, use it
      return tool_instance.openai_tool if tool_instance.respond_to?(:openai_tool)

      # If tool uses DSL, create OpenAI function tool
      if tool_instance.respond_to?(:tool_definition)
        tool_def = tool_instance.tool_definition
        tool_name = tool_def[:function]&.[](:name) || tool_def[:name] || tool_instance.tool_name

        # Extract parameters from the correct location based on the tool definition structure
        tool_description = tool_def[:function]&.[](:description) || tool_def[:description] || "A function tool"
        tool_parameters = tool_def[:function]&.[](:parameters) || tool_def[:parameters] || {}

        # Debug log the tool definition we got from DSL
        if defined?(Rails) && Rails.logger
          Rails.logger.debug "📋 Tool definition from DSL for #{tool_name}:"
          Rails.logger.debug "   Full definition: #{tool_def.inspect}"
        end

        # Create a wrapper proc that calls the tool's method
        # First check for a method matching the tool name
        method_to_call = if tool_name && tool_instance.respond_to?(tool_name.to_sym)
                           tool_name.to_sym
                         elsif tool_instance.respond_to?(:execute_tool)
                           # Fallback to execute_tool if using DSL
                           :execute_tool
                         elsif tool_instance.respond_to?(:call)
                           # Some tools might use call
                           :call
                         else
                           # Try to find any method that might be the main execution method
                           # by looking for common patterns
                           possible_methods = [:execute, :run, :perform, :search, :fetch]
                           possible_methods.find { |m| tool_instance.respond_to?(m) }
                         end

        if method_to_call
          tool_proc = proc do |**params|
            # Ensure we pass keyword arguments properly
            if tool_instance.method(method_to_call).parameters.any? { |type, _| [:keyreq, :key].include?(type) }
              tool_instance.send(method_to_call, **params)
            else
              # Some methods might expect a single hash argument
              tool_instance.send(method_to_call, params)
            end
          end

          # Create OpenAI function tool if the class is available
          if defined?(::OpenAIAgents::FunctionTool)
            # Debug log the tool definition with enhanced schema inspection
            if defined?(Rails) && Rails.logger
              Rails.logger.debug "🛠️ Creating OpenAI tool: #{tool_name}"
              Rails.logger.debug "📋 Tool definition: #{tool_def.inspect}"
              Rails.logger.debug "📝 Parameters schema: #{tool_parameters.inspect}"

              # Check if parameters are correctly formatted
              if tool_parameters.nil? || tool_parameters.empty?
                Rails.logger.warn "⚠️ WARNING: Tool #{tool_name} has no parameters defined!"
              elsif !tool_parameters.is_a?(Hash)
                Rails.logger.warn "⚠️ WARNING: Tool #{tool_name} parameters are not a Hash: #{tool_parameters.class}"
              else
                Rails.logger.debug "✅ Parameters schema looks valid: type=#{tool_parameters[:type]}, properties=#{tool_parameters[:properties]&.keys}"
                
                # Enhanced logging for array parameters to debug "items" property
                if tool_parameters[:properties]
                  tool_parameters[:properties].each do |prop_name, prop_def|
                    if prop_def[:type] == "array"
                      Rails.logger.debug "🔍 ARRAY PROPERTY DEBUG for #{prop_name}:"
                      Rails.logger.debug "    Full property definition: #{prop_def.inspect}"
                      Rails.logger.debug "    Has items property: #{prop_def.key?(:items)}"
                      Rails.logger.debug "    Items value: #{prop_def[:items].inspect}" if prop_def[:items]
                      if prop_def[:items].nil?
                        Rails.logger.error "🚨 FOUND THE BUG! Array property '#{prop_name}' has nil items - this will cause OpenAI API error!"
                      end
                    end
                  end
                end
              end
            end

            # Create the OpenAI function tool
            openai_tool = ::OpenAIAgents::FunctionTool.new(
              tool_proc,
              name:        tool_name,
              description: tool_description,
              parameters:  tool_parameters
            )
            
            # Log the final tool that will be sent to OpenAI
            if defined?(Rails) && Rails.logger
              Rails.logger.debug "📤 Final OpenAI tool created for #{tool_name}:"
              if openai_tool.respond_to?(:definition)
                Rails.logger.debug "    Tool definition: #{openai_tool.definition.inspect}"
              elsif openai_tool.respond_to?(:to_hash)
                Rails.logger.debug "    Tool hash: #{openai_tool.to_hash.inspect}"
              else
                Rails.logger.debug "    Tool object: #{openai_tool.inspect}"
              end
            end
            
            return openai_tool
          end
        elsif defined?(Rails) && Rails.logger
          # Log warning if no executable method found
          Rails.logger.warn "No executable method found for tool: #{tool_name}"
          Rails.logger.warn "Available methods: #{tool_instance.methods(false).sort}"
        end
      end

      # Return the tool instance as-is
      tool_instance
    end

    # Build handoff agents from DSL configuration
    #
    # This method creates OpenAI Agent instances for each configured handoff agent.
    # It maintains the distinction between DSL agents (configuration) and OpenAI
    # agents (execution) by creating DSL agents first, then converting them to
    # OpenAI agents for the handoff system.
    #
    # @return [Array<OpenAIAgents::Agent>] Array of OpenAI agent instances for handoffs
    # @api private
    #
    def build_handoffs_from_config
      handoff_agent_configs = self.class._agent_config[:handoff_agents] || []
      handoff_agent_configs.map do |handoff_config|
        # Handle both old format (just class) and new format (hash with options)
        if handoff_config.is_a?(Hash)
          handoff_agent_class = handoff_config[:agent]
          options = handoff_config[:options] || {}
          # Merge context and processing_params with any additional options
          merged_context = @context.merge(options[:context] || {})
          merged_params = @processing_params.merge(options[:processing_params] || {})
          dsl_agent_instance = handoff_agent_class.new(context: merged_context, processing_params: merged_params)
        else
          # Legacy format - just the agent class
          handoff_agent_class = handoff_config
          dsl_agent_instance = handoff_agent_class.new(context: @context, processing_params: @processing_params)
        end

        # Convert DSL agent instance to OpenAI agent instance
        # This is pure configuration - we're just setting up the OpenAI agents
        # The OpenAI runner will handle everything including handoffs natively
        if dsl_agent_instance.respond_to?(:create_agent_with_context)
          openai_agent = dsl_agent_instance.create_agent_with_context(dsl_agent_instance.instance_variable_get(:@context))

          # Store a reference to the DSL agent for potential context sharing
          openai_agent.define_singleton_method(:dsl_agent) { dsl_agent_instance }

          openai_agent
        else
          # Fallback for legacy compatibility
          dsl_agent_instance.respond_to?(:create_agent) ? dsl_agent_instance.create_agent : dsl_agent_instance
        end
      end
    end

    def resolve_tool_class(tool_name)
      # Map common tool names to their actual classes
      tool_mappings = {
        tavily_search:      "TavilySearch",
        tavily_page_fetch:  "TavilyPageFetch",
        web_search:         "WebSearch",
        fetch_page_content: "TavilyPageFetch"
      }

      # Get the mapped name or use the original
      mapped_name = tool_mappings[tool_name.to_sym] || tool_name.to_s.camelize

      # Try multiple namespaces in order of preference
      candidates = [
        # First try the gem's namespace
        "AiAgentDsl::Tools::#{mapped_name}",
        # Then try the application's namespace (for backward compatibility)
        "Ai::Tools::#{mapped_name}",
        # Try with original name too
        "Ai::Tools::#{tool_name.to_s.camelize}",
        # Finally try global namespace
        mapped_name
      ]

      candidates.each do |class_name|
        return class_name.constantize
      rescue NameError
        next
      end

      raise "Unknown tool: #{tool_name}. Tried: #{candidates.join(', ')}"
    end

    def build_prompt_instance
      prompt_class = self.class._prompt_config[:class] || default_prompt_class
      return unless prompt_class

      # Build core context for prompt class - merge context variables directly
      prompt_context = @context.to_h.merge({
        processing_params: @processing_params,
        agent_name:        agent_name,
        context_variables: @context
      })

      prompt_class.new(**prompt_context)
    end
  end

  # Helper class for building JSON schemas
  class SchemaBuilder
    def initialize
      @schema = {
        type:                 "object",
        properties:           {},
        required:             [],
        additionalProperties: false
      }
    end

    # Define a field in the JSON schema
    #
    # This method adds a field definition to the JSON schema being built. It supports
    # various field types including primitives (string, integer, boolean) and complex
    # types (object, array) with nested structures. The method handles OpenAI's strict
    # mode requirements automatically.
    #
    # @param name [Symbol] The field name
    # @param type [Symbol] The field type (:string, :integer, :boolean, :object, :array, etc.)
    # @param required [Boolean] Whether the field is required (default: false)
    # @param options [Hash] Additional field options (range, enum, description, etc.)
    # @param block [Proc] Block for defining nested structure (objects and arrays)
    #
    # @example Simple field types
    #   field :name, type: :string, required: true
    #   field :age, type: :integer, range: 0..120
    #   field :status, type: :string, enum: ["active", "inactive"]
    #
    # @example Nested object
    #   field :address, type: :object do
    #     field :street, type: :string, required: true
    #     field :city, type: :string, required: true
    #     field :zip_code, type: :string
    #   end
    #
    # @example Array of objects
    #   field :contacts, type: :array do
    #     field :name, type: :string, required: true
    #     field :email, type: :string
    #   end
    #
    def field(name, type:, required: false, **options, &block)
      field_schema = build_field_schema(type, options)

      if block_given?
        case type
        when :object
          nested_builder = SchemaBuilder.new
          nested_builder.instance_eval(&block)
          nested_schema = nested_builder.to_hash.except(:type)
          # Ensure nested objects have additionalProperties: false for OpenAI strict mode
          nested_schema[:additionalProperties] = false unless nested_schema.key?(:additionalProperties)
          field_schema.merge!(nested_schema)
        when :array
          if options[:items_type]
            field_schema[:items] = build_field_schema(options[:items_type], options)
          else
            # Array of objects
            nested_builder = SchemaBuilder.new
            nested_builder.instance_eval(&block)
            nested_schema = nested_builder.to_hash
            # Ensure nested objects in arrays have additionalProperties: false for OpenAI strict mode
            nested_schema[:additionalProperties] = false unless nested_schema.key?(:additionalProperties)
            field_schema[:items] = nested_schema
          end
        end
      end

      @schema[:properties][name] = field_schema
      @schema[:required] << name if required
    end

    # Convert the schema builder to a hash representation
    #
    # This method returns the complete JSON schema as a hash that can be used
    # by OpenAI's structured output feature. The returned hash includes all
    # defined fields, their types, constraints, and nested structures.
    #
    # The schema automatically includes `additionalProperties: false` to comply
    # with OpenAI's strict mode requirements.
    #
    # @return [Hash] Complete JSON schema hash
    #
    # @example
    #   builder = SchemaBuilder.new
    #   builder.field :name, type: :string, required: true
    #   builder.field :age, type: :integer
    #   schema = builder.to_hash
    #   # => {
    #   #   type: "object",
    #   #   properties: {
    #   #     name: { type: "string" },
    #   #     age: { type: "integer" }
    #   #   },
    #   #   required: ["name"],
    #   #   additionalProperties: false
    #   # }
    #
    def to_hash
      @schema
    end

    private

    def build_field_schema(type, options)
      schema = { type: type.to_s }

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
        schema[:items] = { type: options[:items_type].to_s } if options[:items_type] && !block_given?
      end

      schema[:description] = options[:description] if options[:description]
      schema[:default] = options[:default] if options.key?(:default)
      schema
    end
  end

  # Helper class for building workflow sequences with DSL
  class WorkflowBuilder
    attr_reader :agents

    def initialize
      @agents = []
    end

    # Generic workflow methods for building agent sequences

    # Generic step method
    def step(agent_class, _description = nil)
      @agents << agent_class
    end

    # Add a workflow step (alias for step)
    #
    # This method provides a more readable way to chain workflow steps by using
    # "then_step" syntax. It's functionally identical to the step method but
    # provides better readability in workflow definitions where you want to
    # emphasize the sequential nature of the workflow.
    #
    # @param agent_class [Class] The agent class to add as a workflow step
    # @param description [String, nil] Optional description of what this step does
    # @return [WorkflowBuilder] Returns self for method chaining
    #
    # @example
    #   workflow do
    #     step DataCollectionAgent, "Gather initial data"
    #     then_step ProcessingAgent, "Process and clean data"
    #     then_step AnalysisAgent, "Perform analysis"
    #   end
    #
    def then_step(agent_class, description = nil)
      step(agent_class, description)
    end

    # Allow direct agent specification
    def agent(agent_class)
      @agents << agent_class
    end

    # Add an agent to the workflow sequence (alias for agent)
    #
    # This method provides a more readable way to chain agents in a workflow
    # by using "then_agent" syntax. It's functionally identical to the agent
    # method but provides better readability in workflow definitions.
    #
    # @param agent_class [Class] The agent class to add to the workflow
    # @return [WorkflowBuilder] Returns self for method chaining
    #
    # @example
    #   workflow do
    #     step ResearchAgent
    #     then_agent AnalysisAgent
    #     then_agent ReportAgent
    #   end
    #
    def then_agent(agent_class)
      agent(agent_class)
    end

    # Conditional steps
    def step_if(condition, agent_class)
      @agents << agent_class if condition
    end

    # Conditionally add a workflow step (alias for step_if)
    #
    # This method provides a more readable way to conditionally add workflow
    # steps using "then_step_if" syntax. It's functionally identical to step_if
    # but provides better readability in workflow definitions where you want to
    # emphasize the conditional and sequential nature.
    #
    # @param condition [Boolean] Condition that must be true to add the step
    # @param agent_class [Class] The agent class to add if condition is true
    # @return [WorkflowBuilder] Returns self for method chaining
    #
    # @example
    #   workflow do
    #     step BasicAnalysisAgent
    #     then_step_if detailed_analysis_requested?, DetailedAnalysisAgent
    #     then_step_if compliance_check_needed?, ComplianceAgent
    #     step ReportAgent
    #   end
    #
    def then_step_if(condition, agent_class)
      step_if(condition, agent_class)
    end

    # Handle dynamic method calls for workflow steps
    def method_missing(_method_name, agent_class = nil, *_args)
      # For any unrecognized method, treat it as a workflow step
      @agents << agent_class if agent_class
      self
    end

    def respond_to_missing?(_method_name, _include_private = false)
      true
    end
  end
end
