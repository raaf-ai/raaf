# frozen_string_literal: true

module RAAF
  module DSL
    module Agents
      # SmartAgent is an advanced base class that eliminates 80-90% of agent boilerplate
      #
      # This class provides intelligent defaults, automatic result processing, built-in error
      # handling, and declarative configuration to make AI agent development incredibly simple.
      #
      # @example Simple agent definition
      #   class MarketAnalysis < RAAF::DSL::SmartAgent
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
      #   class ComplexAgent < RAAF::DSL::SmartAgent
      #     retry_on :rate_limit, max_attempts: 3, backoff: :exponential
      #     circuit_breaker threshold: 5, timeout: 60.seconds
      #     fallback_to :simplified_analysis, when: :context_too_large
      #   end
      #
      class SmartAgent
        include RAAF::DSL::Agents::AgentDsl
        include RAAF::DSL::Hooks::AgentHooks

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
              self._system_prompt_block = -> { prompt }
            end
          end

          # Define user prompt
          def user_prompt(prompt = nil, &block)
            if block_given?
              self._user_prompt_block = block
            else
              self._user_prompt_block = -> { prompt }
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

        # Instance methods
        def initialize(context:)
          @context = context.is_a?(Hash) ? ContextVariables.new(context) : context
          @circuit_breaker_state = :closed
          @circuit_breaker_failures = 0
          @circuit_breaker_last_failure = nil
          
          validate_context!
          setup_agent_configuration
          
          super(context: @context)
        end

        # Main execution method - handles all the complexity automatically
        def call
          agent_name = self.class._agent_config&.dig(:name) || self.class.name
          RAAF::Logging.info "🤖 [#{agent_name}] Starting execution"

          begin
            # Check circuit breaker
            check_circuit_breaker!
            
            # Execute with retry logic
            result = execute_with_retry do
              raaf_result = run  # Call inherited RAAF run method
              process_raaf_result(raaf_result)
            end

            # Reset circuit breaker on success
            reset_circuit_breaker!
            
            RAAF::Logging.info "✅ [#{agent_name}] Execution completed successfully"
            result

          rescue => e
            handle_smart_error(e)
          end
        end

        # RAAF DSL method - build system instructions
        def build_instructions
          if self.class._system_prompt_block
            prompt_result = self.class._system_prompt_block.call(@context)
            if prompt_result.is_a?(String)
              prompt_result
            else
              RAAF::Logging.error "System prompt block must return a String, got #{prompt_result.class}"
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
              RAAF::Logging.error "User prompt block must return a String, got #{prompt_result.class}"
              "Please help me with this task."
            end
          else
            "Please help me with this task."
          end
        end

        protected

        # Context accessor for prompt blocks
        attr_reader :context

        private

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
          config = self.class._agent_config || {}
          
          # Apply configuration if methods exist (from AgentDsl)
          if respond_to?(:agent_name) && config[:name]
            agent_name config[:name]
          end
          
          if respond_to?(:model) && config[:model]
            model config[:model]
          end
          
          if respond_to?(:max_turns) && config[:max_turns]
            max_turns config[:max_turns]
          end
          
          if respond_to?(:temperature) && config[:temperature]
            temperature config[:temperature]
          end
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
              
              RAAF::Logging.warn "🔄 [#{self.class.name}] Retrying in #{delay}s (attempt #{attempts}/#{retry_config[:max_attempts]}): #{e.message}"
              
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
              RAAF::Logging.info "🔄 [#{self.class.name}] Circuit breaker transitioning to half-open"
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
            RAAF::Logging.error "🚫 [#{self.class.name}] Circuit breaker opened after #{@circuit_breaker_failures} failures"
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
            RAAF::Logging.warn "🤔 [#{self.class.name}] Unknown result format: #{raaf_result.class}"
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
            RAAF::Logging.warn "🤔 [#{self.class.name}] Could not extract result data"
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
            RAAF::Logging.error "❌ [#{self.class.name}] JSON parsing failed: #{e.message}"
            { success: false, error: "Failed to parse AI response", raw_content: content }
          end
        end

        def handle_smart_error(error)
          agent_name = self.class._agent_config&.dig(:name) || self.class.name
          
          # Record circuit breaker failure
          record_circuit_breaker_failure!
          
          # Categorize and handle error
          if error.message.include?("rate limit")
            RAAF::Logging.error "🚫 [#{agent_name}] Rate limit exceeded: #{error.message}"
            { success: false, error: "Rate limit exceeded. Please try again later.", error_type: "rate_limit" }
          elsif error.is_a?(CircuitBreakerOpenError)
            RAAF::Logging.error "🚫 [#{agent_name}] Circuit breaker open: #{error.message}"
            { success: false, error: "Service temporarily unavailable", error_type: "circuit_breaker" }
          elsif error.is_a?(JSON::ParserError)
            RAAF::Logging.error "❌ [#{agent_name}] JSON parsing error: #{error.message}"
            { success: false, error: "Failed to parse AI response", error_type: "json_error" }
          elsif error.is_a?(ArgumentError) && error.message.include?("context")
            RAAF::Logging.error "❌ [#{agent_name}] Context validation error: #{error.message}"
            { success: false, error: error.message, error_type: "validation_error" }
          else
            RAAF::Logging.error "❌ [#{agent_name}] Unexpected error: #{error.message}"
            RAAF::Logging.error error.backtrace.join("\n")
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
            @schema[:required] << name if required
          end
        end
      end
    end
  end
end