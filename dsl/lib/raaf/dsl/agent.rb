# frozen_string_literal: true

require "raaf-core"
require "active_support/concern"
require_relative "config/config"
require_relative "core/context_variables"
require_relative "agents/agent_dsl"
require_relative "hooks/agent_hooks"

module RAAF
  module DSL
    # Unified Agent class for the RAAF DSL framework
    #
    # This class combines all the features from Base and SmartAgent into a single,
    # powerful agent implementation that provides:
    # - Declarative agent configuration with DSL
    # - Automatic retry logic with configurable strategies
    # - Circuit breaker pattern for fault tolerance
    # - Context validation and requirements
    # - Built-in error handling and categorization
    # - Automatic result parsing and extraction
    # - Schema building with inline DSL
    #
    # @example Simple agent definition
    #   class MarketAnalysis < RAAF::DSL::Agent
    #     agent_name "MarketAnalysisAgent"
    #     requires :product, :company
    #     
    #     schema do
    #       field :markets, type: :array, required: true do
    #         field :name, type: :string, required: true
    #         field :fit_score, type: :integer, range: 0..100
    #       end
    #     end
    #     
    #     system_prompt "You are a market analysis expert..."
    #     
    #     user_prompt do |ctx|
    #       "Analyze product: #{ctx.product.name} from #{ctx.company.name}"
    #     end
    #   end
    #
    # @example Advanced configuration
    #   class ComplexAgent < RAAF::DSL::Agent
    #     retry_on :rate_limit, max_attempts: 3, backoff: :exponential
    #     circuit_breaker threshold: 5, timeout: 60.seconds
    #     fallback_to :simplified_analysis, when: :context_too_large
    #   end
    #
    class Agent
      include RAAF::DSL::Agents::AgentDsl
      include RAAF::DSL::Hooks::AgentHooks
      include RAAF::Logger

      # Configuration DSL methods
      class << self
        attr_accessor :_agent_config, :_schema_definition, :_system_prompt_block, 
                     :_user_prompt_block, :_retry_config, :_circuit_breaker_config,
                     :_required_context_keys, :_validation_rules

        # Configure agent name
        def agent_name(name)
          self._agent_config ||= {}
          self._agent_config[:name] = name
        end

        # Configure model
        def model(model_name)
          self._agent_config ||= {}
          self._agent_config[:model] = model_name
        end

        # Configure max turns
        def max_turns(turns)
          self._agent_config ||= {}
          self._agent_config[:max_turns] = turns
        end

        # Configure temperature
        def temperature(temp)
          self._agent_config ||= {}
          self._agent_config[:temperature] = temp
        end

        # Declare required context keys
        def requires(*keys)
          self._required_context_keys ||= []
          self._required_context_keys.concat(keys.map(&:to_sym))
        end

        # Add validation rules
        def validates(key, **rules)
          self._validation_rules ||= {}
          self._validation_rules[key.to_sym] = rules
        end

        # Define inline schema
        def schema(&block)
          self._schema_definition = SchemaBuilder.new(&block).build
        end

        # Define system prompt
        def system_prompt(prompt = nil, &block)
          if block_given?
            self._system_prompt_block = block
          else
            self._system_prompt_block = ->(_) { prompt }
          end
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

        # Configure fallback strategy
        def fallback_to(method_name, when: nil)
          self._fallback_config = {
            method: method_name,
            condition: binding.local_variable_get(:when)
          }
        end

        # Inherit configuration from parent class
        def inherited(subclass)
          super
          
          # Copy configuration from parent
          subclass._agent_config = _agent_config&.dup
          subclass._required_context_keys = _required_context_keys&.dup
          subclass._validation_rules = _validation_rules&.dup
          subclass._retry_config = _retry_config&.dup
          subclass._circuit_breaker_config = _circuit_breaker_config&.dup
        end
      end

      # Instance attributes
      attr_reader :context, :processing_params, :debug_enabled

      # Initialize a new agent instance
      #
      # @param context [ContextVariables, Hash, nil] Unified context for all agent data
      # @param context_variables [ContextVariables, Hash, nil] Alternative parameter name for context (backward compatibility)
      # @param processing_params [Hash] Parameters that control how the agent processes content
      # @param debug [Boolean, nil] Enable debug logging for this agent instance
      def initialize(context: nil, context_variables: nil, processing_params: {}, debug: nil)
        @debug_enabled = debug || (defined?(::Rails) && ::Rails.env.development?) || false
        @processing_params = processing_params
        @circuit_breaker_state = :closed
        @circuit_breaker_failures = 0
        @circuit_breaker_last_failure = nil
        
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
        
        validate_context!
        setup_agent_configuration
        
        if @debug_enabled
          log_debug("Agent initialized",
                    agent_class: self.class.name,
                    context_size: @context.size,
                    context_keys: @context.keys.inspect,
                    category: :context)
        end
      end

      # Run the agent with optional smart features (retry, circuit breaker, etc.)
      # 
      # @param context [ContextVariables, Hash, nil] Context to use (overrides instance context)
      # @param input_context_variables [ContextVariables, Hash, nil] Alternative parameter name for context
      # @param stop_checker [Proc] Optional stop checker for execution control
      # @param skip_retries [Boolean] Skip retry/circuit breaker logic (default: false)
      # @return [Hash] Result from agent execution
      def run(context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false)
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
      
      # Backward compatibility - call now just delegates to run
      def call
        run
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

      # RAAF DSL method - build system instructions
      def build_instructions
        if self.class._system_prompt_block
          prompt_result = self.class._system_prompt_block.call(@context)
          if prompt_result.is_a?(String)
            prompt_result
          else
            log_error "System prompt block must return a String, got #{prompt_result.class}"
            "You are a helpful AI assistant."
          end
        else
          "You are a helpful AI assistant."
        end
      end

      # RAAF DSL method - build response schema
      def build_schema
        self.class._schema_definition || default_schema
      end

      # RAAF DSL method - build user prompt  
      def build_user_prompt
        if self.class._user_prompt_block
          prompt_result = self.class._user_prompt_block.call(@context)
          if prompt_result.is_a?(String)
            prompt_result
          else
            log_error "User prompt block must return a String, got #{prompt_result.class}"
            "Please help me with this task."
          end
        else
          "Please help me with this task."
        end
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

      protected

      private
      
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
        if raaf_result.is_a?(Hash) && raaf_result[:success] && raaf_result[:results]
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
            result: { type: "string", description: "The result of the analysis" },
            confidence: { type: "integer", minimum: 0, maximum: 100, description: "Confidence level" }
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
    end
  end
end