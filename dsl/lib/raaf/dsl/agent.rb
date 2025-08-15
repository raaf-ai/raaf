# frozen_string_literal: true

require "raaf-core"
require "active_support/concern"
require "active_support/core_ext/object/blank"
require_relative "config/config"
require_relative "core/context_variables"
# AgentDsl and AgentHooks functionality consolidated into Agent class
require_relative "data_merger"
require_relative "pipeline"

module RAAF
  module DSL
    # Unified Agent class for the RAAF DSL framework
    #
    # This class provides a complete agent implementation with consolidated DSL functionality:
    # - Declarative agent configuration
    # - Prompt class support with validation
    # - Agent hooks for lifecycle events  
    # - Built-in retry and circuit breaker patterns
    # - Schema building and context management
    #
    # @example Basic agent with static instructions
    #   class SimpleAgent < RAAF::DSL::Agent
    #     agent_name "SimpleAgent"
    #     static_instructions "You are a helpful assistant"
    #   end
    #
    # @example Agent with prompt class
    #   class MarketAnalysis < RAAF::DSL::Agent
    #     agent_name "MarketAnalysisAgent"
    #     prompt_class MarketAnalysisPrompt
    #     
    #     on_start { |agent| puts "Starting analysis..." }
    #     on_end :log_completion
    #   end
    #
    class Agent
      include RAAF::Logger

      # Configuration DSL methods - consolidated from AgentDsl and AgentHooks
      class << self
        # Class-specific configuration storage for thread safety
        def _agent_config
          Thread.current["raaf_dsl_agent_config_#{object_id}"] ||= {}
        end

        def _agent_config=(value)
          Thread.current["raaf_dsl_agent_config_#{object_id}"] = value
        end

        # Control auto-context behavior (default: true)
        def auto_context(enabled = true)
          _agent_config[:auto_context] = enabled
        end
        
        # Check if auto-context is enabled (default: true)
        def auto_context?
          _agent_config[:auto_context] != false
        end
        
        # Configuration for context building rules
        def context(options = {}, &block)
          if block_given?
            config = ContextConfig.new
            config.instance_eval(&block)
            _agent_config[:context_rules] = config.to_h
          else
            _agent_config[:context_rules] = options
          end
        end

        def _tools_config
          Thread.current["raaf_dsl_tools_config_#{object_id}"] ||= []
        end

        def _tools_config=(value)
          Thread.current["raaf_dsl_tools_config_#{object_id}"] = value
        end

        def _schema_config
          Thread.current["raaf_dsl_schema_config_#{object_id}"] ||= {}
        end

        def _schema_config=(value)
          Thread.current["raaf_dsl_schema_config_#{object_id}"] = value
        end

        def _prompt_config
          Thread.current["raaf_dsl_prompt_config_#{object_id}"] ||= {}
        end

        def _prompt_config=(value)
          Thread.current["raaf_dsl_prompt_config_#{object_id}"] = value
        end

        def _context_reader_config
          Thread.current["raaf_dsl_context_reader_config_#{object_id}"] ||= {}
        end

        def _context_reader_config=(value)
          Thread.current["raaf_dsl_context_reader_config_#{object_id}"] = value
        end

        def _auto_discovery_config
          Thread.current["raaf_dsl_auto_discovery_config_#{object_id}"] ||= {}
        end

        def _auto_discovery_config=(value)
          Thread.current["raaf_dsl_auto_discovery_config_#{object_id}"] = value
        end

        # Ensure each subclass gets its own configuration
        def inherited(subclass)
          super
          subclass._agent_config = {}
          subclass._tools_config = []
          subclass._schema_config = {}
          subclass._prompt_config = {}
          subclass._context_reader_config = {}
          
          # Enable auto-transform by default with standard patterns
          subclass._auto_discovery_config = {
            patterns: %w[
              process_*_from_data
              build_*_metadata
              extract_*_from_data
              compute_*
            ],
            exclude: [],
            enabled: true
          }
          
          # Initialize hooks for subclass
          hooks = {}
          HOOK_TYPES.each { |hook_type| hooks[hook_type] = [] }
          subclass._agent_hooks = hooks
          
          # Schedule auto-discovery to run after class body is evaluated
          TracePoint.new(:end) do |tp|
            if tp.self == subclass
              subclass.discover_computed_methods
              tp.disable
            end
          end.enable
        end

        # Core DSL methods from AgentDsl
        def agent_name(name = nil)
          if name
            _agent_config[:name] = name
          else
            _agent_config[:name] || inferred_agent_name
          end
        end

        def model(model_name = nil)
          if model_name
            _agent_config[:model] = model_name
          else
            _agent_config[:model] || "gpt-4o"
          end
        end

        def max_turns(turns = nil)
          if turns
            _agent_config[:max_turns] = turns
          else
            _agent_config[:max_turns] || 5
          end
        end

        def description(desc = nil)
          if desc
            _agent_config[:description] = desc
          else
            _agent_config[:description]
          end
        end

        def prompt_class(klass = nil)
          if klass
            _prompt_config[:class] = klass
          else
            _prompt_config[:class]
          end
        end

        def static_instructions(instructions = nil)
          if instructions
            _prompt_config[:static_instructions] = instructions
          else
            _prompt_config[:static_instructions]
          end
        end

        def instruction_template(template = nil)
          if template
            _prompt_config[:instruction_template] = template
          else
            _prompt_config[:instruction_template]
          end
        end

        # Tool configuration DSL methods (consolidated from AgentDsl)
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

        # Agent Hooks functionality (consolidated from AgentHooks)
        HOOK_TYPES = %i[
          on_start
          on_end
          on_handoff
          on_tool_start
          on_tool_end
          on_error
        ].freeze

        def _agent_hooks
          Thread.current["raaf_dsl_agent_hooks_#{object_id}"] ||= begin
            hooks = {}
            HOOK_TYPES.each { |hook_type| hooks[hook_type] = [] }
            hooks
          end
        end

        def _agent_hooks=(value)
          Thread.current["raaf_dsl_agent_hooks_#{object_id}"] = value
        end

        # Hook registration methods
        def on_start(method_name = nil, &block)
          register_agent_hook(:on_start, method_name, &block)
        end

        def on_end(method_name = nil, &block)
          register_agent_hook(:on_end, method_name, &block)
        end

        def on_handoff(method_name = nil, &block)
          register_agent_hook(:on_handoff, method_name, &block)
        end

        def on_tool_start(method_name = nil, &block)
          register_agent_hook(:on_tool_start, method_name, &block)
        end

        def on_tool_end(method_name = nil, &block)
          register_agent_hook(:on_tool_end, method_name, &block)
        end

        def on_error(method_name = nil, &block)
          register_agent_hook(:on_error, method_name, &block)
        end

        # Hook configuration methods
        def agent_hooks_config
          config = {}
          HOOK_TYPES.each do |hook_type|
            config[hook_type] = _agent_hooks[hook_type].dup if _agent_hooks[hook_type]&.any?
          end
          config
        end

        def get_agent_hooks(hook_type)
          _agent_hooks[hook_type] || []
        end

        def clear_agent_hooks!
          HOOK_TYPES.each do |hook_type|
            _agent_hooks[hook_type] = []
          end
        end

        private

        def inferred_agent_name
          name.to_s
              .split("::")
              .last
              .gsub(/Agent$/, "")
              .gsub(/([a-z\d])([A-Z])/, '\1_\2')
              .downcase
        end

        def register_agent_hook(hook_type, method_name = nil, &block)
          unless HOOK_TYPES.include?(hook_type)
            raise ArgumentError, "Invalid hook type: #{hook_type}. Must be one of: #{HOOK_TYPES.join(', ')}"
          end

          raise ArgumentError, "Either method_name or block must be provided" if method_name.nil? && block.nil?
          raise ArgumentError, "Cannot provide both method_name and block" if method_name && block

          hook = method_name || block
          _agent_hooks[hook_type] ||= []
          _agent_hooks[hook_type] << hook
        end

        # Additional configuration methods
        def temperature(temp)
          _agent_config[:temperature] = temp
        end

        def schema(&block)
          self._schema_definition = SchemaBuilder.new(&block).build if block_given?
          self._schema_definition
        end


        # Define user prompt
        def user_prompt(prompt = nil, &block)
          if block_given?
            self._user_prompt_block = block
          else
            self._user_prompt_block = ->(_) { prompt }
          end
        end

        # Configure retry behavior
        def retry_on(error_type, max_attempts: 3, backoff: :linear, delay: 1)
          self._retry_config ||= {}
          self._retry_config[error_type] = {
            max_attempts: max_attempts,
            backoff: backoff,
            delay: delay
          }
        end

        # Configure circuit breaker
        def circuit_breaker(threshold: 5, timeout: 60, reset_timeout: 300)
          self._circuit_breaker_config = {
            threshold: threshold,
            timeout: timeout,
            reset_timeout: reset_timeout
          }
        end


        # Enhanced context reader DSL - generates helper methods for context access
        # with support for validation, defaults, and transformation
        # Similar to attr_reader but for RAAF context variables
        #
        # @param keys [Array<Symbol>] Context keys to create helper methods for
        # @param options [Hash] Optional validation and default options
        #
        # @example Basic usage
        #   class MyAgent < RAAF::DSL::Agent
        #     context_reader :product, :company, :analysis_depth
        #   end
        #
        # @example With validation and defaults
        #   class MyAgent < RAAF::DSL::Agent
        #     context_reader :product, required: true, type: Product
        #     context_reader :analysis_depth, default: "standard", validate: ["standard", "deep", "quick"]
        #     context_reader :max_results, default: 10, type: Integer, validate: ->(v) { v > 0 && v <= 100 }
        #     context_reader :company, transform: ->(v) { v&.name&.downcase }
        #   end
        #
        def context_reader(*keys, **options)
          # Split keys and per-key options
          if keys.size == 1 && options.any?
            # Single key with options
            key = keys.first
            define_enhanced_context_reader(key, options)
          else
            # Multiple keys without options
            keys.each do |key|
              define_simple_context_reader(key)
            end
          end
        end

        private

        def define_simple_context_reader(key)
          define_method(key) do
            context.get(key)
          end
          private key
        end

        def define_enhanced_context_reader(key, options)
          # Store config for this key (only required is supported)
          self._context_reader_config ||= {}
          self._context_reader_config[key] = options.slice(:required)

          define_method(key) do
            value = context.get(key)
            
            # Validate required
            if options[:required] && value.nil?
              raise ArgumentError, "Context key '#{key}' is required but missing"
            end
            
            value
          end
          private key
        end


        # Result transformation DSL - defines how to transform AI responses
        # into structured, validated data formats
        #
        # @example Basic field mapping
        #   class MarketAnalysisAgent < RAAF::DSL::Agent
        #     result_transform do
        #       field :markets, from: "discovered_markets", type: :array
        #       field :confidence, from: "analysis_confidence", type: :integer, range: 0..100
        #       field :summary, default: "No summary available"
        #     end
        #   end
        #
        # @example Advanced transformations
        #   class CompanyEnrichmentAgent < RAAF::DSL::Agent
        #     result_transform do
        #       field :companies, type: :array, transform: ->(data) {
        #         data.map { |c| normalize_company_data(c) }
        #       }
        #       field :metadata, computed: :build_enrichment_metadata
        #       field :timestamp, default: -> { Time.current.iso8601 }
        #     end
        #   end
        #
        def result_transform(&block)
          self._result_transformations = ResultTransformBuilder.new(&block).build
        end

        # Note: log_events and track_metrics DSL methods were removed as they were not implemented.
        # Use Rails.logger or RAAF.logger directly for logging needs.

        # Conditional execution DSL - defines when agents should run
        # 
        # @example Simple conditions
        #   class EnrichmentAgent < RAAF::DSL::Agent
        #     run_if do
        #       context_has :companies
        #       context_value :analysis_depth, equals: "deep"
        #       previous_agent_succeeded
        #     end
        #   end
        #
        # @example Complex conditions
        #   class StakeholderAgent < RAAF::DSL::Agent
        #     run_if do
        #       any_of do
        #         context_value :company_size, greater_than: 100
        #         context_has_any :decision_makers, :influencers
        #       end
        #       
        #       none_of do
        #         context_value :industry, equals: "government"
        #         previous_agent_failed
        #       end
        #     end
        #   end
        #
        def run_if(&block)
          self._execution_conditions = ExecutionConditions.new(&block)
        end

        def run_unless(&block)
          self._execution_conditions = ExecutionConditions.new(negate: true, &block)
        end

        # Auto-discovery for computed field methods
        # Scans for methods matching naming patterns and automatically registers them
        #
        # @example Automatic discovery
        #   class EnrichmentAgent < RAAF::DSL::Agent
        #     enable_auto_discovery patterns: %w[process_* build_* compute_*]
        #     
        #     private
        #     
        #     # These methods are automatically discovered and registered
        #     def process_companies_from_data(data)
        #       # Processing logic
        #     end
        #     
        #     def build_enrichment_metadata(data)
        #       # Metadata building logic
        #     end
        #   end
        #
        # Auto-transform configuration for result transformation methods
        # Uses Convention Over Configuration - enabled by default with standard patterns
        #
        # Default patterns (automatically discovered):
        #   - process_*_from_data  : Process raw AI data into structured format
        #   - build_*_metadata     : Build metadata for results
        #   - extract_*_from_data  : Extract specific data from AI response
        #   - compute_*            : Compute derived values
        #
        # @example Using default auto-transform (no configuration needed!)
        #   class MyAgent < RAAF::DSL::Agent
        #     # Auto-transform is ON by default - these methods will be auto-discovered:
        #     
        #     def process_companies_from_data(data)
        #       # Automatically used for field :companies, computed: :process_companies_from_data
        #     end
        #     
        #     def build_search_metadata(data)
        #       # Automatically used for field :search_metadata, computed: :build_search_metadata
        #     end
        #   end
        #
        # @example Disabling auto-transform
        #   class MyAgent < RAAF::DSL::Agent
        #     auto_transform :off
        #   end
        #
        # @example Custom patterns
        #   class MyAgent < RAAF::DSL::Agent
        #     auto_transform patterns: %w[parse_* format_*]
        #   end
        #
        def auto_transform(config = :on, patterns: nil, exclude: [])
          if config == :off
            self._auto_discovery_config = { enabled: false }
          else
            # Use provided patterns or default convention patterns
            transform_patterns = patterns || %w[
              process_*_from_data
              build_*_metadata
              extract_*_from_data
              compute_*
            ]
            
            self._auto_discovery_config = {
              patterns: transform_patterns,
              exclude: exclude,
              enabled: true
            }
            
            # Trigger discovery when class is loaded
            discover_computed_methods
          end
        end
        
        # Legacy method for backward compatibility
        def enable_auto_discovery(patterns: %w[process_*_from_data build_*_metadata compute_*], exclude: [])
          auto_transform(:on, patterns: patterns, exclude: exclude)
        end

        # Manual computed method registration
        def computed_method(method_name, field_name = nil)
          self._computed_methods ||= {}
          field_name ||= method_name.to_s.gsub(/^(process_|build_|compute_)/, '').gsub(/_from_data$/, '')
          self._computed_methods[field_name.to_sym] = method_name.to_sym
        end

        protected

        def discover_computed_methods
          # Auto-transform is enabled by default
          return if _auto_discovery_config&.dig(:enabled) == false
          
          self._computed_methods ||= {}
          # Use configured patterns or default convention patterns
          patterns = _auto_discovery_config&.dig(:patterns) || %w[
            process_*_from_data
            build_*_metadata
            extract_*_from_data
            compute_*
          ]
          exclude = _auto_discovery_config&.dig(:exclude) || []
          
          # Get all instance methods including private ones
          all_methods = instance_methods(false) + private_instance_methods(false)
          
          patterns.each do |pattern|
            # Convert glob pattern to regex
            regex = pattern_to_regex(pattern)
            
            matching_methods = all_methods.select do |method_name|
              method_str = method_name.to_s
              method_str.match?(regex) && !exclude.include?(method_name)
            end
            
            matching_methods.each do |method_name|
              field_name = derive_field_name_from_method(method_name.to_s)
              self._computed_methods[field_name.to_sym] = method_name.to_sym
            end
          end
          
          if _auto_discovery_config[:debug] || (defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.development?)
            puts "🔍 [#{self.name}] Auto-discovered #{_computed_methods.size} computed methods: #{_computed_methods.keys.join(', ')}"
          end
        end

        private

        def pattern_to_regex(pattern)
          # Convert glob pattern to regex
          regex_string = pattern.gsub('*', '.*')
          /^#{regex_string}$/
        end

        def derive_field_name_from_method(method_name)
          # Apply common transformations to derive field names
          field_name = method_name.dup
          
          # Remove common prefixes
          field_name = field_name.gsub(/^(process_|build_|compute_|calculate_|generate_)/, '')
          
          # Remove common suffixes
          field_name = field_name.gsub(/(_from_data|_metadata|_result)$/, '')
          
          # Handle special cases
          case field_name
          when /^(.+)_companies$/
            $1 + '_companies'
          when /^(.+)_analysis$/
            $1 + '_analysis'
          else
            field_name
          end
        end

        # ContextConfig class for the context DSL
        class ContextConfig
          def initialize
            @rules = {}
          end
          
          def requires(*keys)
            @rules[:required] ||= []
            @rules[:required].concat(keys)
          end
          
          def exclude(*keys)
            @rules[:exclude] ||= []
            @rules[:exclude].concat(keys)
          end
          
          def include(*keys)
            @rules[:include] ||= []
            @rules[:include].concat(keys)
          end
          
          def validate(key, type: nil, with: nil)
            @rules[:validations] ||= {}
            @rules[:validations][key] = { type: type, proc: with }
          end
          
          def default(key, value)
            @rules[:defaults] ||= {}
            @rules[:defaults][key.to_sym] = value
          end
          
          def to_h
            @rules
          end
        end

      end # End of class << self

      # Additional class attributes for agent functionality
      class << self
        attr_accessor :_required_context_keys, :_validation_rules, :_schema_definition, :_user_prompt_block,
                     :_retry_config, :_circuit_breaker_config, :_result_transformations,
                     :_computed_methods, :_execution_conditions
      end

      # Instance attributes
      attr_reader :context, :processing_params, :debug_enabled

      # Initialize a new agent instance
      #
      # @param context [ContextVariables, Hash, nil] Context for all agent data
      # @param processing_params [Hash] Parameters that control how the agent processes content  
      # @param debug [Boolean, nil] Enable debug logging for this agent instance
      # @param kwargs [Hash] Arbitrary keyword arguments that become context when auto-context is enabled
      def initialize(context: nil, processing_params: {}, debug: nil, **kwargs)
        @debug_enabled = debug || (defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.development?) || false
        @processing_params = processing_params
        @circuit_breaker_state = :closed
        @circuit_breaker_failures = 0
        @circuit_breaker_last_failure = nil
        
        # If context provided explicitly, use it (backward compatible)
        if context
          @context = build_context_from_param(context, @debug_enabled)
        elsif self.class.auto_context?
          # Auto-build from kwargs
          @context = build_auto_context(kwargs, @debug_enabled)
        else
          # Auto-context disabled, empty context
          @context = RAAF::DSL::ContextVariables.new({}, debug: @debug_enabled)
        end
        
        validate_context!
        setup_agent_configuration
        setup_logging_and_metrics
        
        if @debug_enabled
          log_debug("Agent initialized",
                    agent_class: self.class.name,
                    context_size: @context.size,
                    context_keys: @context.keys.inspect,
                    auto_context: self.class.auto_context?,
                    category: :context)
        end
      end

      # Clean API methods for context access
      def get(key, default = nil)
        @context.get(key, default)
      end
      
      def set(key, value)
        @context = @context.set(key, value)
        value
      end
      
      def update(**values)
        @context = @context.update(values)
        self
      end
      
      def has?(key)
        @context.has?(key)
      end
      
      def context_keys
        @context.keys
      end
      
      # Run the agent with optional smart features (retry, circuit breaker, etc.)
      # 
      # @param context [ContextVariables, Hash, nil] Context to use (overrides instance context)
      # @param input_context_variables [ContextVariables, Hash, nil] Alternative parameter name for context
      # @param stop_checker [Proc] Optional stop checker for execution control
      # @param skip_retries [Boolean] Skip retry/circuit breaker logic (default: false)
      # @return [Hash] Result from agent execution
      def run(context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false, previous_result: nil)
        # Check execution conditions first
        if self.class._execution_conditions
          resolved_context = resolve_run_context(context || input_context_variables)
          unless should_execute?(resolved_context, previous_result)
            log_info "⏭️ [#{self.class.name}] Skipping execution due to conditions not met"
            return {
              success: true,
              skipped: true,
              reason: "Execution conditions not met",
              workflow_status: "skipped"
            }
          end
        end

        # Check if we should use smart features
        if skip_retries || !has_smart_features?
          # Direct execution without retries/circuit breaker
          direct_run(context: context, input_context_variables: input_context_variables, stop_checker: stop_checker)
        else
          # Smart execution with retries and circuit breaker
          agent_name = self.class._agent_config&.dig(:name) || self.class.name
          log_info "🤖 [#{agent_name}] Starting execution"

          begin
            # Check circuit breaker
            check_circuit_breaker!
            
            # Execute with retry logic
            result = execute_with_retry do
              raaf_result = direct_run(context: context, input_context_variables: input_context_variables, stop_checker: stop_checker)
              process_raaf_result(raaf_result)
            end

            # Reset circuit breaker on success
            reset_circuit_breaker!
            
            log_info "✅ [#{agent_name}] Execution completed successfully"
            result

          rescue => e
            handle_smart_error(e)
          end
        end
      end
      
      # Create the underlying RAAF::Agent instance
      def create_agent
        log_debug("Creating RAAF agent instance",
                  agent_name: agent_name,
                  model: model_name,
                  max_turns: max_turns,
                  tools_count: tools.length,
                  handoffs_count: handoffs.length)

        create_openai_agent_instance
      end

      # RAAF DSL method - build system instructions using resolver system
      def build_instructions
        prompt_spec = determine_prompt_spec
        log_debug "Building system instructions", prompt_spec: prompt_spec, agent_class: self.class.name
        
        if prompt_spec
          begin
            resolved_prompt = DSL.prompt_resolvers.resolve(prompt_spec, @context.to_h)
            log_debug "Resolver result", resolved: !!resolved_prompt, resolvers_count: DSL.prompt_resolvers.resolvers.count
            if resolved_prompt
              system_message = resolved_prompt.messages.find { |m| m[:role] == "system" }
              log_debug "System message found", found: !!system_message
              return system_message[:content] if system_message
            end
          rescue StandardError => e
            # Re-raise prompt resolution errors with agent context, preserving original error type and stack trace
            raise e.class, "Agent #{self.class.name} failed to build system prompt: #{e.message}", e.backtrace
          end
        end
        
        raise RAAF::DSL::Error, "No system prompt resolved for #{self.class.name}. " \
                                "Check prompt class configuration or ensure prompt files exist."
      end

      # RAAF DSL method - build user prompt using resolver system
      def build_user_prompt
        prompt_spec = determine_prompt_spec
        
        if prompt_spec
          begin
            resolved_prompt = DSL.prompt_resolvers.resolve(prompt_spec, @context.to_h)
            if resolved_prompt
              user_message = resolved_prompt.messages.find { |m| m[:role] == "user" }
              return user_message[:content] if user_message
            end
          rescue StandardError => e
            # Re-raise prompt resolution errors with agent context, preserving original error type and stack trace
            raise e.class, "Agent #{self.class.name} failed to build user prompt: #{e.message}", e.backtrace
          end
        end
        
        raise RAAF::DSL::Error, "No user prompt resolved for #{self.class.name}. " \
                                "Check prompt class configuration or ensure prompt files exist."
      end

      protected

      # Determine the prompt specification to resolve
      # Can be a prompt class, file name, or other spec that resolvers can handle
      def determine_prompt_spec
        # Check for configured prompt class first
        if self.class._prompt_config[:class]
          log_debug "Found configured prompt class", class: self.class._prompt_config[:class]
          return self.class._prompt_config[:class]
        end
        
        # Try to infer prompt class by convention (e.g., Ai::Agents::MyAgent -> Ai::Prompts::MyAgent)
        inferred_prompt_class = infer_prompt_class_name
        if inferred_prompt_class
          log_debug "Trying inferred prompt class", class: inferred_prompt_class.name
          return inferred_prompt_class
        end
        
        # Try to infer from agent name (e.g., MyAgent -> "my_agent.md")
        agent_name_file = agent_name.underscore
        log_debug "Trying to infer prompt from agent name", agent_name: agent_name_file
        return agent_name_file if agent_name_file
        
        log_debug "No prompt spec found for agent", agent_class: self.class.name
        nil
      end

      # Infer prompt class name by convention
      # Transforms Ai::Agents::Category::AgentName to Ai::Prompts::Category::AgentName
      def infer_prompt_class_name
        agent_class_name = self.class.name
        
        # Replace "Agents" with "Prompts" in the module path
        prompt_class_name = agent_class_name.gsub(/::Agents::/, "::Prompts::")
        
        log_debug "Inferring prompt class", 
                  agent_class: agent_class_name, 
                  inferred_prompt_class: prompt_class_name
        
        # Try to constantize the inferred class name
        begin
          prompt_class_name.constantize
        rescue NameError => e
          log_debug "Inferred prompt class not found", 
                    class: prompt_class_name, 
                    error: e.message
          nil
        end
      end

      # Supporting methods for prompt handling (from AgentDsl) - called by public methods
      def prompt_class_configured?
        self.class._prompt_config[:class].present? || default_prompt_class.present?
      end

      def prompt_instance
        @prompt_instance ||= build_prompt_instance
      end

      private

      def default_prompt_class
        @default_prompt_class ||= begin
          # Convert agent class name to prompt class name
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

      def build_templated_instructions
        template = self.class.instruction_template
        return template unless template.include?("{{")
        
        # Simple variable substitution
        result = template.dup
        @context.to_h.each do |key, value|
          result.gsub!("{{#{key}}}", value.to_s)
        end
        result
      end

      def agent_name
        self.class._agent_config[:name] || self.class.name.split("::").last
      end

      public

      # Agent Hooks instance method (consolidated from AgentHooks)
      def combined_hooks_config
        # For now, just return agent-specific hooks
        # Global hooks integration would be handled elsewhere if needed
        agent_config = self.class.agent_hooks_config
        agent_config.empty? ? nil : agent_config
      end

      # RAAF DSL method - build response schema
      def build_schema
        self.class._schema_definition || default_schema
      end


      # Agent configuration methods
      def agent_name
        self.class._agent_config&.dig(:name) || self.class.name.demodulize
      end

      def model_name
        self.class._agent_config&.dig(:model) || 
          RAAF::DSL::Config.model_for(agent_name) || 
          "gpt-4o"
      end

      def max_turns
        self.class._agent_config&.dig(:max_turns) || 
          RAAF::DSL::Config.max_turns_for(agent_name) || 
          3
      end

      def instructions
        build_instructions
      end

      def name
        agent_name
      end

      def tools
        @tools ||= begin
          tool_list = build_tools_from_config
          # Convert DSL tools to FunctionTool instances for RAAF compatibility
          tool_list.map { |tool| convert_to_function_tool(tool) }.compact
        end
      end

      def tools?
        tools.any?
      end

      def response_format
        # Check if unstructured output is requested
        return if self.class._agent_config&.dig(:output_format) == :unstructured

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

      # Public context accessor for testing and prompt blocks
      attr_reader :context

      private
      
      # Build context from parameter (backward compatibility)
      def build_context_from_param(context_param, debug = nil)
        case context_param
        when RAAF::DSL::ContextVariables
          context_param
        when Hash
          RAAF::DSL::ContextVariables.new(context_param, debug: debug)
        else
          raise ArgumentError, "context must be ContextVariables instance or Hash"
        end
      end
      
      # Build context automatically from keyword arguments
      def build_auto_context(params, debug = nil)
        require_relative "core/context_builder"
        
        rules = self.class._agent_config[:context_rules] || {}
        builder = RAAF::DSL::ContextBuilder.new({}, debug: debug)
        
        # First pass: Add static params and defaults
        params.each do |key, value|
          # Apply exclusion rules
          next if rules[:exclude]&.include?(key)
          next if rules[:include]&.any? && !rules[:include].include?(key)
          
          # Check for custom preparation method
          if respond_to?("prepare_#{key}_for_context", true)
            value = send("prepare_#{key}_for_context", value)
          end
          
          builder.with(key, value)
        end
        
        # Apply default values for keys that weren't provided
        if rules[:defaults]
          rules[:defaults].each do |key, default_value|
            # Only set default if the key wasn't provided in params
            unless params.key?(key)
              builder.with(key, default_value)
            end
          end
        end
        
        # Make static context available to build_*_context methods
        @context = builder.current_context
        
        # Second pass: Add computed context values now that @context is available
        add_computed_context(builder)
        
        # Final build with all values
        builder.build
      end
      
      # Add computed context values from build_*_context methods
      def add_computed_context(builder)
        # Find all methods matching build_*_context pattern
        methods = self.class.instance_methods(false) + self.class.private_instance_methods(false)
        computed_methods = methods.grep(/^build_(.+)_context$/)
        
        computed_methods.each do |method|
          context_key = method.to_s.match(/^build_(.+)_context$/)[1].to_sym
          if respond_to?(method, true)
            value = send(method)
            builder.with(context_key, value)
          end
        end
      end
      
      # Check if agent has any smart features configured
      def has_smart_features?
        self.class._retry_config.present? || 
        self.class._circuit_breaker_config.present? ||
        self.class._required_context_keys.present? ||
        self.class._validation_rules.present?
      end
      
      # Direct execution without smart features (original run behavior)
      def direct_run(context: nil, input_context_variables: nil, stop_checker: nil)
        # Resolve context for this run
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
        log_error("Agent execution failed",
                  error_class: e.class.name,
                  error_message: e.message,
                  agent_name: agent_name)
        
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

      def validate_context!
        return unless self.class._required_context_keys

        missing_keys = self.class._required_context_keys.reject do |key|
          @context.has?(key)
        end

        if missing_keys.any?
          raise ArgumentError, "Required context keys missing: #{missing_keys.join(', ')}"
        end

        # Run validation rules
        validate_context_rules! if self.class._validation_rules
      end

      def validate_context_rules!
        self.class._validation_rules.each do |key, rules|
          value = @context.get(key)
          
          if rules[:presence] && value.nil?
            raise ArgumentError, "Context key '#{key}' is required but missing"
          end

          if rules[:presence].is_a?(Array) && value.respond_to?(:[])
            missing_attrs = rules[:presence].reject { |attr| value[attr].present? }
            if missing_attrs.any?
              raise ArgumentError, "Context key '#{key}' missing required attributes: #{missing_attrs.join(', ')}"
            end
          end

          if rules[:type] && value && !value.is_a?(rules[:type])
            raise ArgumentError, "Context key '#{key}' must be #{rules[:type]} but was #{value.class}"
          end
        end
      end

      def setup_agent_configuration
        # Configuration is already set at class level via DSL
        # No need to apply it again at instance level
      end

      def setup_logging_and_metrics
        # Note: log_events and track_metrics DSL methods were removed as they were not implemented.
      end


      # Check if agent should execute based on defined conditions
      def should_execute?(context, previous_result)
        return true unless self.class._execution_conditions
        
        self.class._execution_conditions.evaluate(context, previous_result)
      end

      def execute_with_retry(&block)
        attempts = 0
        max_attempts = 1  # Default no retry
        
        begin
          attempts += 1
          yield
        rescue => e
          retry_config = find_retry_config(e)
          
          if retry_config && attempts < retry_config[:max_attempts]
            delay = calculate_retry_delay(retry_config, attempts)
            
            log_warn "🔄 [#{self.class.name}] Retrying in #{delay}s (attempt #{attempts}/#{retry_config[:max_attempts]}): #{e.message}"
            
            sleep(delay)
            retry
          else
            raise
          end
        end
      end

      def find_retry_config(error)
        return nil unless self.class._retry_config

        self.class._retry_config.each do |error_type, config|
          case error_type
          when :rate_limit
            return config if error.message.include?("rate limit")
          when :timeout
            return config if error.is_a?(Timeout::Error)
          when :network
            return config if error.is_a?(Net::Error) || error.message.include?("connection")
          when Class
            return config if error.is_a?(error_type)
          end
        end
        
        nil
      end

      def calculate_retry_delay(config, attempt)
        base_delay = config[:delay] || 1
        
        case config[:backoff]
        when :exponential
          base_delay * (2 ** (attempt - 1))
        when :linear
          base_delay * attempt
        else
          base_delay
        end
      end

      def check_circuit_breaker!
        return unless self.class._circuit_breaker_config
        
        config = self.class._circuit_breaker_config
        
        if @circuit_breaker_state == :open
          if Time.current - @circuit_breaker_last_failure > config[:reset_timeout]
            @circuit_breaker_state = :half_open
            log_info "🔄 [#{self.class.name}] Circuit breaker transitioning to half-open"
          else
            raise CircuitBreakerOpenError, "Circuit breaker is open due to repeated failures"
          end
        end
      end

      def reset_circuit_breaker!
        return unless self.class._circuit_breaker_config
        
        @circuit_breaker_state = :closed
        @circuit_breaker_failures = 0
        @circuit_breaker_last_failure = nil
      end

      def record_circuit_breaker_failure!
        return unless self.class._circuit_breaker_config
        
        config = self.class._circuit_breaker_config
        @circuit_breaker_failures += 1
        @circuit_breaker_last_failure = Time.current
        
        if @circuit_breaker_failures >= config[:threshold]
          @circuit_breaker_state = :open
          log_error "🚫 [#{self.class.name}] Circuit breaker opened after #{@circuit_breaker_failures} failures"
        end
      end

      def process_raaf_result(raaf_result)
        # Handle different RAAF result formats automatically
        base_result = if raaf_result.is_a?(Hash) && raaf_result[:success] && raaf_result[:results]
          # New RAAF format
          extract_result_data(raaf_result[:results])
        elsif raaf_result.is_a?(Hash)
          # Direct hash result
          extract_hash_result(raaf_result)
        else
          # Unknown format
          log_warn "🤔 [#{self.class.name}] Unknown result format: #{raaf_result.class}"
          { success: true, data: raaf_result }
        end

        # Apply result transformations if configured
        if self.class._result_transformations
          apply_result_transformations(base_result)
        else
          base_result
        end
      end

      def extract_result_data(results)
        if results.respond_to?(:final_output) && results.final_output
          parse_ai_response(results.final_output)
        elsif results.respond_to?(:messages) && results.messages.any?
          parse_ai_response(results.messages.last[:content])
        elsif results.respond_to?(:data)
          results.data
        else
          log_warn "🤔 [#{self.class.name}] Could not extract result data"
          { success: false, error: "Could not extract result data" }
        end
      end

      def extract_hash_result(hash)
        # Try to find the actual data in various hash structures
        if hash.key?("results") || hash.key?(:results)
          hash["results"] || hash[:results]
        else
          hash
        end
      end

      def parse_ai_response(content)
        return content unless content.is_a?(String)
        
        begin
          parsed = JSON.parse(content)
          { success: true, data: parsed }
        rescue JSON::ParserError => e
          log_error "❌ [#{self.class.name}] JSON parsing failed: #{e.message}"
          { success: false, error: "Failed to parse AI response", raw_content: content }
        end
      end

      def handle_smart_error(error)
        agent_name = self.class._agent_config&.dig(:name) || self.class.name
        
        # Record circuit breaker failure
        record_circuit_breaker_failure!
        
        # Categorize and handle error
        if error.message.include?("rate limit")
          log_error "🚫 [#{agent_name}] Rate limit exceeded: #{error.message}"
          { success: false, error: "Rate limit exceeded. Please try again later.", error_type: "rate_limit" }
        elsif error.is_a?(CircuitBreakerOpenError)
          log_error "🚫 [#{agent_name}] Circuit breaker open: #{error.message}"
          { success: false, error: "Service temporarily unavailable", error_type: "circuit_breaker" }
        elsif error.is_a?(JSON::ParserError)
          log_error "❌ [#{agent_name}] JSON parsing error: #{error.message}"
          { success: false, error: "Failed to parse AI response", error_type: "json_error" }
        elsif error.is_a?(ArgumentError) && error.message.include?("context")
          log_error "❌ [#{agent_name}] Context validation error: #{error.message}"
          { success: false, error: error.message, error_type: "validation_error" }
        else
          log_error "❌ [#{agent_name}] Unexpected error: #{error.message}", stack_trace: error.backtrace.join("\n")
          { success: false, error: "Agent execution failed: #{error.message}", error_type: "unexpected_error" }
        end
      end

      def default_schema
        {
          type: "object",
          properties: {
            result: { type: "string", description: "The result of the analysis" }
          },
          required: ["result"],
          additionalProperties: false
        }
      end

      # Methods from Base class
      def create_openai_agent_instance
        # Build handoffs if configured
        handoff_agents = handoffs

        # Build base configuration
        agent_config = {
          name: agent_name,
          instructions: build_instructions,
          model: model_name,
          max_turns: max_turns
        }

        # Add response format if structured output is requested
        if (format = response_format)
          agent_config[:response_format] = format
        end

        # Add tools if configured
        if tools.any?
          agent_config[:tools] = tools
        end

        # Add handoffs if configured
        if handoff_agents.any?
          agent_config[:handoffs] = handoff_agents
        end

        # Create and return the RAAF agent
        RAAF::Agent.new(**agent_config)
      end

      def resolve_run_context(override_context)
        case override_context
        when RAAF::DSL::ContextVariables
          override_context
        when Hash
          # Merge override context with instance context
          merged_data = @context.to_h.merge(override_context)
          RAAF::DSL::ContextVariables.new(merged_data, debug: @debug_enabled)
        when nil
          @context
        else
          raise ArgumentError, "Context must be ContextVariables, Hash, or nil"
        end
      end

      def build_user_prompt_with_context(run_context)
        # Set context for prompt access
        original_context = @context
        @context = run_context

        # Build prompt
        prompt = build_user_prompt

        # Restore original context
        @context = original_context

        prompt
      end

      def transform_openai_result(run_result, run_context)
        # Extract final output from messages
        final_output = extract_final_output(run_result)

        # Build result in expected DSL format
        {
          workflow_status: "completed",
          success: true,
          results: run_result,
          final_output: final_output,
          context_variables: run_context,
          summary: build_result_summary(final_output)
        }
      end

      def extract_final_output(run_result)
        return nil unless run_result.respond_to?(:messages)

        # Find last assistant message
        last_assistant_message = run_result.messages.reverse.find { |m| m[:role] == "assistant" }
        return nil unless last_assistant_message

        content = last_assistant_message[:content]

        # Try to parse as JSON if it looks like JSON
        if content.is_a?(String) && (content.start_with?("{") || content.start_with?("["))
          begin
            JSON.parse(content)
          rescue JSON::ParserError
            content
          end
        else
          content
        end
      end

      def build_result_summary(final_output)
        case final_output
        when Hash
          "Completed with structured output"
        when Array
          "Completed with #{final_output.length} items"
        when String
          "Completed with text output"
        else
          "Completed"
        end
      end

      # Apply configured result transformations
      def apply_result_transformations(base_result)
        return base_result unless self.class._result_transformations

        transformations = self.class._result_transformations
        input_data = base_result[:data] || base_result

        transformed_result = {}
        metadata = {}

        transformations.each do |field_name, field_config|
          begin
            # Extract source value
            source_value = extract_field_value(input_data, field_config)

            # Apply transformations and validations
            transformed_value = transform_field_value(source_value, field_config)

            # Set result
            transformed_result[field_name] = transformed_value

            # Track metadata for debugging
            metadata[field_name] = {
              source: field_config[:from] || field_name,
              transformed: !field_config[:transform].nil?,
              computed: !field_config[:computed].nil?
            }

          rescue => e
            log_error "❌ [#{self.class.name}] Field transformation failed",
                     field: field_name,
                     error: e.message

            # Set field to nil or default if transformation fails
            transformed_result[field_name] = field_config[:default] || nil
            metadata[field_name] = { error: e.message }
          end
        end

        # Return transformed result with original structure preserved
        {
          success: base_result[:success] != false,
          data: transformed_result,
          transformation_metadata: metadata,
          original_data: input_data
        }
      end

      def extract_field_value(input_data, field_config)
        # Determine source field name
        source_key = field_config[:from] || field_config[:field_name]

        # Handle computed fields
        if field_config[:computed]
          method_name = field_config[:computed]
          if respond_to?(method_name, true)
            send(method_name, input_data)
          else
            log_warn "🤔 [#{self.class.name}] Computed method '#{method_name}' not found"
            nil
          end
        elsif self.class._computed_methods && self.class._computed_methods[source_key]
          # Use auto-discovered computed method
          method_name = self.class._computed_methods[source_key]
          if respond_to?(method_name, true)
            send(method_name, input_data)
          else
            log_warn "🤔 [#{self.class.name}] Auto-discovered computed method '#{method_name}' not found"
            nil
          end
        else
          # Extract from input data (supports both string and symbol keys)
          case input_data
          when Hash
            input_data[source_key] || input_data[source_key.to_s] || input_data[source_key.to_sym]
          else
            nil
          end
        end
      end

      def transform_field_value(source_value, field_config)
        value = source_value

        # Apply default if value is nil
        if value.nil? && field_config[:default]
          value = case field_config[:default]
                  when Proc
                    field_config[:default].call
                  else
                    field_config[:default]
                  end
        end

        # Type validation
        if value && field_config[:type] && !valid_type?(value, field_config[:type])
          raise ArgumentError, "Field must be #{field_config[:type]} but was #{value.class}"
        end

        # Range validation
        if value && field_config[:range] && !field_config[:range].include?(value)
          raise ArgumentError, "Field value #{value} not in range #{field_config[:range]}"
        end

        # Custom transformation
        if value && field_config[:transform]
          value = field_config[:transform].call(value)
        end

        value
      end

      def valid_type?(value, type)
        case type
        when :array
          value.is_a?(Array)
        when :hash, :object
          value.is_a?(Hash)
        when :string
          value.is_a?(String)
        when :integer
          value.is_a?(Integer)
        when :float, :number
          value.is_a?(Numeric)
        when :boolean
          value.is_a?(TrueClass) || value.is_a?(FalseClass)
        when Class
          value.is_a?(type)
        else
          true
        end
      end

      # Tool building methods (consolidated from AgentDsl)
      def build_tools_from_config
        self.class._tools_config.map do |tool_config|
          create_tool_instance(tool_config[:name], tool_config[:options])
        end.compact
      end

      def create_tool_instance(tool_name, options)
        tool_class = resolve_tool_class(tool_name)
        return nil unless tool_class
        
        tool_class.new(options)
      rescue => e
        log_error("Failed to create tool instance for #{tool_name}: #{e.message}")
        nil
      end

      def resolve_tool_class(tool_name)
        # Convert tool name to class name (e.g., :web_search -> RAAF::DSL::Tools::WebSearch)
        class_name = tool_name.to_s.split('_').map(&:capitalize).join
        
        # Try RAAF::DSL::Tools namespace first
        if defined?("RAAF::DSL::Tools::#{class_name}")
          "RAAF::DSL::Tools::#{class_name}".constantize
        else
          # Fallback: assume it's a custom tool class
          tool_name.to_s.classify.constantize
        end
      rescue NameError => e
        log_error("Tool class not found for #{tool_name}: #{e.message}")
        nil
      end

      def convert_to_function_tool(tool_instance)
        return nil unless tool_instance
        
        # If tool has a function_tool method, use it
        return tool_instance.function_tool if tool_instance.respond_to?(:function_tool)
        
        # If tool uses DSL, create RAAF function tool
        process_dsl_tool(tool_instance)
      end

      def process_dsl_tool(tool_instance)
        return tool_instance unless tool_instance.respond_to?(:tool_definition)

        tool_def = tool_instance.tool_definition
        tool_name = extract_tool_name(tool_def, tool_instance)
        tool_description = extract_tool_description(tool_def)
        tool_parameters = extract_tool_parameters(tool_def)

        method_to_call = find_executable_method(tool_name, tool_instance)
        return handle_no_executable_method(tool_name, tool_instance) unless method_to_call

        return tool_instance unless defined?(::RAAF::FunctionTool)

        tool_proc = create_tool_proc(tool_instance, method_to_call)
        validate_tool_parameters(tool_name, tool_parameters)
        create_raaf_function_tool(tool_name, tool_description, tool_parameters, tool_proc)
      end

      def extract_tool_name(tool_def, tool_instance)
        if tool_def.is_a?(Hash) && tool_def.dig(:function, :name)
          tool_def[:function][:name]
        elsif tool_instance.respond_to?(:tool_name)
          tool_instance.tool_name
        elsif tool_instance.respond_to?(:name)
          tool_instance.name
        else
          tool_instance.class.name.demodulize.underscore
        end
      end

      def extract_tool_description(tool_def)
        if tool_def.is_a?(Hash) && tool_def.dig(:function, :description)
          tool_def[:function][:description]
        else
          "Tool: #{extract_tool_name(tool_def, nil)}"
        end
      end

      def extract_tool_parameters(tool_def)
        if tool_def.is_a?(Hash) && tool_def.dig(:function, :parameters)
          tool_def[:function][:parameters]
        else
          { type: "object", properties: {}, required: [] }
        end
      end

      def find_executable_method(tool_name, tool_instance)
        # Look for execute method first, then tool name method
        if tool_instance.respond_to?(:execute)
          :execute
        elsif tool_instance.respond_to?(tool_name)
          tool_name.to_sym
        else
          nil
        end
      end

      def handle_no_executable_method(tool_name, tool_instance)
        log_error("Tool #{tool_name} has no executable method (execute or #{tool_name})")
        nil
      end

      def create_tool_proc(tool_instance, method_to_call)
        lambda do |**args|
          begin
            result = tool_instance.send(method_to_call, **args)
            result.is_a?(Hash) ? result : { result: result }
          rescue => e
            log_error("Tool execution failed: #{e.message}")
            { error: e.message }
          end
        end
      end

      def validate_tool_parameters(tool_name, parameters)
        unless parameters.is_a?(Hash) && parameters.key?(:type)
          log_warn("Tool #{tool_name} has invalid parameter schema")
        end
      end

      def create_raaf_function_tool(tool_name, description, parameters, tool_proc)
        RAAF::FunctionTool.new(
          name: tool_name,
          description: description,
          parameters: parameters,
          &tool_proc
        )
      end

      # Handoff building method (consolidated from AgentDsl)
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

      # Custom error classes
      class CircuitBreakerOpenError < StandardError; end

      # Schema builder for inline schema definitions
      class SchemaBuilder
        def initialize(&block)
          @schema = { type: "object", properties: {}, required: [], additionalProperties: false }
          instance_eval(&block) if block_given?
        end

        def build
          @schema
        end

        def field(name, type:, required: false, description: nil, **options, &block)
          field_schema = { type: type.to_s }
          field_schema[:description] = description if description
          
          # Handle type-specific options
          case type
          when :integer, :number
            field_schema[:minimum] = options[:min] if options[:min]
            field_schema[:maximum] = options[:max] if options[:max]
            if options[:range]
              field_schema[:minimum] = options[:range].min
              field_schema[:maximum] = options[:range].max
            end
          when :string
            field_schema[:minLength] = options[:min_length] if options[:min_length]
            field_schema[:maxLength] = options[:max_length] if options[:max_length]
            field_schema[:enum] = options[:enum] if options[:enum]
          when :array
            field_schema[:items] = { type: (options[:items_type] || :string).to_s }
            field_schema[:minItems] = options[:min_items] if options[:min_items]
            field_schema[:maxItems] = options[:max_items] if options[:max_items]
            if block_given?
              nested_builder = SchemaBuilder.new(&block)
              field_schema[:items] = nested_builder.build
            end
          when :object
            if block_given?
              nested_builder = SchemaBuilder.new(&block)
              field_schema = nested_builder.build
            end
          end

          @schema[:properties][name] = field_schema
          @schema[:required] << name.to_s if required
        end
      end

      # Result transformation builder for defining field mappings and transformations
      class ResultTransformBuilder
        def initialize(&block)
          @transformations = {}
          instance_eval(&block) if block_given?
        end

        def build
          @transformations
        end

        # Define a field transformation
        #
        # @param name [Symbol] Output field name
        # @param options [Hash] Transformation options
        # @option options [String, Symbol] :from Source field name (defaults to field name)
        # @option options [Symbol] :type Expected type for validation
        # @option options [Range] :range Valid range for numeric values
        # @option options [Proc] :transform Custom transformation lambda
        # @option options [Symbol] :computed Method name for computed fields
        # @option options [Object, Proc] :default Default value if source is nil
        #
        def field(name, **options)
          @transformations[name] = options.merge(field_name: name)
        end
      end

      # Note: LogEventBuilder and MetricsBuilder classes were removed as they were not implemented.

      # Note: LogEventProcessor and MetricsCollector classes were removed as they were not implemented.

      # Execution conditions for conditional agent execution
      class ExecutionConditions
        def initialize(negate: false, &block)
          @conditions = []
          @negate = negate
          instance_eval(&block) if block_given?
        end

        def evaluate(context, previous_result)
          result = @conditions.empty? || @conditions.all? { |condition| condition.call(context, previous_result) }
          @negate ? !result : result
        end

        # Context-based conditions
        def context_has(*keys)
          @conditions << ->(context, _) {
            keys.all? { |key| context.has?(key) && context.get(key) }
          }
        end

        def context_has_any(*keys)
          @conditions << ->(context, _) {
            keys.any? { |key| context.has?(key) && context.get(key) }
          }
        end

        def context_value(key, **comparisons)
          @conditions << ->(context, _) {
            value = context.get(key)
            return false unless value
            
            check_comparisons(value, comparisons)
          }
        end

        # Previous result conditions
        def previous_agent_succeeded
          @conditions << ->(_, previous_result) {
            previous_result && previous_result[:success] != false
          }
        end

        def previous_agent_failed
          @conditions << ->(_, previous_result) {
            previous_result && previous_result[:success] == false
          }
        end

        def previous_result_has(*keys)
          @conditions << ->(_, previous_result) {
            return false unless previous_result.is_a?(Hash)
            keys.all? { |key| previous_result.key?(key) && previous_result[key] }
          }
        end

        # Logical grouping
        def all_of(&block)
          sub_conditions = ExecutionConditions.new(&block)
          @conditions << ->(context, previous_result) {
            sub_conditions.evaluate(context, previous_result)
          }
        end

        def any_of(&block)
          sub_builder = ConditionBuilder.new
          sub_builder.instance_eval(&block)
          
          @conditions << ->(context, previous_result) {
            sub_builder.conditions.any? { |condition| condition.call(context, previous_result) }
          }
        end

        def none_of(&block)
          sub_builder = ConditionBuilder.new
          sub_builder.instance_eval(&block)
          
          @conditions << ->(context, previous_result) {
            sub_builder.conditions.none? { |condition| condition.call(context, previous_result) }
          }
        end

        # Custom condition
        def custom(&block)
          @conditions << block
        end

        private

        def check_comparisons(value, comparisons)
          comparisons.all? do |comparison, expected|
            case comparison
            when :equals, :eq
              value == expected
            when :not_equals, :ne
              value != expected
            when :greater_than, :gt
              value.respond_to?(:>) && value > expected
            when :greater_than_or_equal, :gte
              value.respond_to?(:>=) && value >= expected
            when :less_than, :lt
              value.respond_to?(:<) && value < expected
            when :less_than_or_equal, :lte
              value.respond_to?(:<=) && value <= expected
            when :includes
              value.respond_to?(:include?) && value.include?(expected)
            when :matches
              expected.is_a?(Regexp) && expected.match?(value.to_s)
            when :in
              expected.respond_to?(:include?) && expected.include?(value)
            else
              true
            end
          end
        end
      end

      # Helper class for building condition groups
      class ConditionBuilder
        attr_reader :conditions

        def initialize
          @conditions = []
        end

        def context_has(*keys)
          @conditions << ->(context, _) {
            keys.all? { |key| context.has?(key) && context.get(key) }
          }
        end

        def context_has_any(*keys)
          @conditions << ->(context, _) {
            keys.any? { |key| context.has?(key) && context.get(key) }
          }
        end

        def context_value(key, **comparisons)
          @conditions << ->(context, _) {
            value = context.get(key)
            return false unless value
            
            check_comparisons(value, comparisons)
          }
        end

        def previous_agent_succeeded
          @conditions << ->(_, previous_result) {
            previous_result && previous_result[:success] != false
          }
        end

        def previous_agent_failed
          @conditions << ->(_, previous_result) {
            previous_result && previous_result[:success] == false
          }
        end

        def custom(&block)
          @conditions << block
        end

        private

        def check_comparisons(value, comparisons)
          comparisons.all? do |comparison, expected|
            case comparison
            when :equals, :eq
              value == expected
            when :not_equals, :ne
              value != expected
            when :greater_than, :gt
              value.respond_to?(:>) && value > expected
            when :greater_than_or_equal, :gte
              value.respond_to?(:>=) && value >= expected
            when :less_than, :lt
              value.respond_to?(:<) && value < expected
            when :less_than_or_equal, :lte
              value.respond_to?(:<=) && value <= expected
            when :includes
              value.respond_to?(:include?) && value.include?(expected)
            when :matches
              expected.is_a?(Regexp) && expected.match?(value.to_s)
            when :in
              expected.respond_to?(:include?) && expected.include?(value)
            else
              true
            end
          end
        end
      end
    end
  end
end