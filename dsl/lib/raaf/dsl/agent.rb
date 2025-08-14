# frozen_string_literal: true

require "raaf-core"
require "active_support/concern"
require_relative "config/config"
require_relative "core/context_variables"
require_relative "agents/agent_dsl"
require_relative "hooks/agent_hooks"
require_relative "data_merger"
require_relative "pipeline"

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
                     :_required_context_keys, :_validation_rules,
                     :_context_reader_config, :_result_transformations, :_log_events, 
                     :_metrics_config, :_auto_discovery_config, :_computed_methods, 
                     :_execution_conditions

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
            # Multiple keys without options (backward compatibility)
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
          # Store config for this key (only required and default are supported)
          self._context_reader_config ||= {}
          self._context_reader_config[key] = options.slice(:required, :default)

          define_method(key) do
            value = context.get(key)
            
            # Apply default if value is nil
            if value.nil? && options[:default]
              value = case options[:default]
                      when Proc
                        options[:default].call
                      else
                        options[:default]
                      end
            end
            
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

        # Logging and metrics DSL - defines structured logging and performance tracking
        # 
        # @example Basic logging configuration
        #   class AnalysisAgent < RAAF::DSL::Agent
        #     log_events do
        #       event :analysis_started, level: :info, message: "Starting analysis for {product}"
        #       event :results_processed, level: :debug, message: "Processed {count} results"
        #       event :analysis_failed, level: :error, message: "Analysis failed: {error}"
        #     end
        #   end
        #
        # @example Metrics tracking
        #   class EnrichmentAgent < RAAF::DSL::Agent
        #     track_metrics do
        #       counter :companies_processed, description: "Total companies processed"
        #       gauge :processing_time_seconds, description: "Time spent processing"
        #       histogram :response_size_bytes, buckets: [100, 1000, 10000]
        #     end
        #   end
        #
        def log_events(&block)
          self._log_events ||= {}
          builder = LogEventBuilder.new(self._log_events, &block)
          self._log_events = builder.build
        end

        def track_metrics(&block)
          self._metrics_config ||= {}
          builder = MetricsBuilder.new(self._metrics_config, &block)
          self._metrics_config = builder.build
        end

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
        def enable_auto_discovery(patterns: %w[process_*_from_data build_*_metadata compute_*], exclude: [])
          self._auto_discovery_config = {
            patterns: patterns,
            exclude: exclude,
            enabled: true
          }
          
          # Trigger discovery when class is loaded
          discover_computed_methods
        end

        # Manual computed method registration
        def computed_method(method_name, field_name = nil)
          self._computed_methods ||= {}
          field_name ||= method_name.to_s.gsub(/^(process_|build_|compute_)/, '').gsub(/_from_data$/, '')
          self._computed_methods[field_name.to_sym] = method_name.to_sym
        end

        private

        def discover_computed_methods
          return unless _auto_discovery_config&.dig(:enabled)
          
          self._computed_methods ||= {}
          patterns = _auto_discovery_config[:patterns] || []
          exclude = _auto_discovery_config[:exclude] || []
          
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

        # Inherit configuration from parent class
        def inherited(subclass)
          super
          
          # Copy configuration from parent
          subclass._agent_config = _agent_config&.dup
          subclass._required_context_keys = _required_context_keys&.dup
          subclass._validation_rules = _validation_rules&.dup
          subclass._retry_config = _retry_config&.dup
          subclass._circuit_breaker_config = _circuit_breaker_config&.dup
          subclass._context_reader_config = _context_reader_config&.dup
          subclass._result_transformations = _result_transformations&.dup
          subclass._log_events = _log_events&.dup
          subclass._metrics_config = _metrics_config&.dup
          subclass._auto_discovery_config = _auto_discovery_config&.dup
          subclass._computed_methods = _computed_methods&.dup
          subclass._execution_conditions = _execution_conditions&.dup
        end
      end

      # Instance attributes
      attr_reader :context, :processing_params, :debug_enabled, :metrics_collector

      # Initialize a new agent instance
      #
      # @param context [ContextVariables, Hash, nil] Unified context for all agent data
      # @param context_variables [ContextVariables, Hash, nil] Alternative parameter name for context (backward compatibility)
      # @param processing_params [Hash] Parameters that control how the agent processes content
      # @param debug [Boolean, nil] Enable debug logging for this agent instance
      def initialize(context: nil, context_variables: nil, processing_params: {}, debug: nil)
        @debug_enabled = debug || (defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.development?) || false
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
        setup_logging_and_metrics
        
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

      def setup_logging_and_metrics
        # Initialize metrics collector if metrics are configured
        if self.class._metrics_config.present?
          @metrics_collector = MetricsCollector.new(self.class._metrics_config)
        end
        
        # Initialize log event processor
        if self.class._log_events.present?
          @log_event_processor = LogEventProcessor.new(self.class._log_events)
        end
      end

      # Structured logging method with event-based configuration
      def log_event(event_name, **context_data)
        return unless @log_event_processor
        
        @log_event_processor.process_event(event_name, context_data.merge(
          agent: self.class.name,
          timestamp: Time.current.iso8601,
          context_size: @context.size
        ))
      end

      # Metrics tracking methods
      def increment_counter(metric_name, value = 1, **labels)
        return unless @metrics_collector
        @metrics_collector.increment_counter(metric_name, value, labels)
      end

      def set_gauge(metric_name, value, **labels)
        return unless @metrics_collector
        @metrics_collector.set_gauge(metric_name, value, labels)
      end

      def observe_histogram(metric_name, value, **labels)
        return unless @metrics_collector
        @metrics_collector.observe_histogram(metric_name, value, labels)
      end

      def track_execution_time(metric_name = :execution_time_seconds, **labels)
        start_time = Time.current
        result = yield
        execution_time = Time.current - start_time
        observe_histogram(metric_name, execution_time, labels)
        result
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

      # Log event builder for defining structured logging events
      class LogEventBuilder
        def initialize(existing_events = {}, &block)
          @events = existing_events.dup
          instance_eval(&block) if block_given?
        end

        def build
          @events
        end

        # Define a log event
        #
        # @param name [Symbol] Event name
        # @param options [Hash] Event configuration
        # @option options [Symbol] :level Log level (info, debug, warn, error)
        # @option options [String] :message Log message with {variable} interpolation
        # @option options [Hash] :metadata Additional structured metadata
        #
        def event(name, level: :info, message:, **metadata)
          @events[name] = {
            level: level,
            message: message,
            metadata: metadata
          }
        end
      end

      # Metrics builder for defining performance tracking metrics
      class MetricsBuilder
        def initialize(existing_metrics = {}, &block)
          @metrics = existing_metrics.dup
          instance_eval(&block) if block_given?
        end

        def build
          @metrics
        end

        # Define a counter metric (monotonically increasing)
        def counter(name, description: nil, **labels)
          @metrics[name] = {
            type: :counter,
            description: description,
            default_labels: labels
          }
        end

        # Define a gauge metric (can go up or down)
        def gauge(name, description: nil, **labels)
          @metrics[name] = {
            type: :gauge,
            description: description,
            default_labels: labels
          }
        end

        # Define a histogram metric (distribution of values)
        def histogram(name, description: nil, buckets: nil, **labels)
          @metrics[name] = {
            type: :histogram,
            description: description,
            buckets: buckets || [0.1, 0.5, 1.0, 2.0, 5.0, 10.0],
            default_labels: labels
          }
        end
      end

      # Log event processor that handles structured logging events
      class LogEventProcessor
        def initialize(events_config)
          @events_config = events_config
        end

        def process_event(event_name, context_data)
          event_config = @events_config[event_name]
          return unless event_config

          # Interpolate message with context data
          message = interpolate_message(event_config[:message], context_data)
          
          # Build structured log entry
          log_entry = {
            level: event_config[:level],
            message: message,
            event: event_name,
            metadata: event_config[:metadata].merge(context_data)
          }

          # Send to appropriate logger based on level
          case event_config[:level]
          when :debug
            log_debug(message, log_entry[:metadata])
          when :info
            log_info(message)
          when :warn
            log_warn(message)
          when :error
            log_error(message, log_entry[:metadata])
          end
        end

        private

        def interpolate_message(template, context_data)
          result = template.dup
          context_data.each do |key, value|
            result.gsub!("{#{key}}", value.to_s)
          end
          result
        end

        def log_debug(message, metadata = {})
          return unless respond_to?(:log_debug, true)
          log_debug(message, **metadata)
        end

        def log_info(message)
          if defined?(RAAF) && RAAF.respond_to?(:logger)
            RAAF.logger.info(message)
          elsif defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
            ::Rails.logger.info(message)
          else
            puts "[INFO] #{message}"
          end
        end

        def log_warn(message)
          if defined?(RAAF) && RAAF.respond_to?(:logger)
            RAAF.logger.warn(message)
          elsif defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
            ::Rails.logger.warn(message)
          else
            puts "[WARN] #{message}"
          end
        end

        def log_error(message, metadata = {})
          if defined?(RAAF) && RAAF.respond_to?(:logger)
            RAAF.logger.error(message)
          elif defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
            ::Rails.logger.error(message)
          else
            puts "[ERROR] #{message}"
          end
        end
      end

      # Metrics collector that handles performance metric collection
      class MetricsCollector
        def initialize(metrics_config)
          @metrics_config = metrics_config
          @counters = {}
          @gauges = {}
          @histograms = {}
        end

        def increment_counter(metric_name, value = 1, labels = {})
          metric_config = @metrics_config[metric_name]
          return unless metric_config && metric_config[:type] == :counter

          key = build_metric_key(metric_name, labels, metric_config[:default_labels])
          @counters[key] = (@counters[key] || 0) + value

          # Emit metric (could integrate with Prometheus, DataDog, etc.)
          emit_counter_metric(key, @counters[key], metric_config)
        end

        def set_gauge(metric_name, value, labels = {})
          metric_config = @metrics_config[metric_name]
          return unless metric_config && metric_config[:type] == :gauge

          key = build_metric_key(metric_name, labels, metric_config[:default_labels])
          @gauges[key] = value

          # Emit metric
          emit_gauge_metric(key, value, metric_config)
        end

        def observe_histogram(metric_name, value, labels = {})
          metric_config = @metrics_config[metric_name]
          return unless metric_config && metric_config[:type] == :histogram

          key = build_metric_key(metric_name, labels, metric_config[:default_labels])
          @histograms[key] ||= []
          @histograms[key] << value

          # Emit metric
          emit_histogram_metric(key, value, metric_config)
        end

        private

        def build_metric_key(metric_name, labels, default_labels)
          all_labels = (default_labels || {}).merge(labels || {})
          label_string = all_labels.map { |k, v| "#{k}=#{v}" }.join(",")
          "#{metric_name}#{label_string.empty? ? '' : "{#{label_string}}"}"
        end

        def emit_counter_metric(key, value, config)
          # Simple console output - could be replaced with actual metrics backend
          puts "[METRIC] Counter #{key} = #{value} (#{config[:description]})"
        end

        def emit_gauge_metric(key, value, config)
          puts "[METRIC] Gauge #{key} = #{value} (#{config[:description]})"
        end

        def emit_histogram_metric(key, value, config)
          puts "[METRIC] Histogram #{key} observed #{value} (#{config[:description]})"
        end
      end

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