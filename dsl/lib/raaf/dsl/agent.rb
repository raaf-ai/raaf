# frozen_string_literal: true

require "raaf-core"
require "active_support/concern"
require "active_support/core_ext/object/blank"
require "timeout"
require_relative "config/config"
require_relative "core/context_variables"
require_relative "context_access"
require_relative "context_configuration"
# JsonRepair and SchemaValidator are now loaded automatically via raaf-core
# No need for explicit requires since raaf-core is already loaded in raaf-dsl.rb
require_relative "pipelineable"
# AgentDsl and AgentHooks functionality consolidated into Agent class
require_relative "data_merger"
# Note: Old AgentPipeline class removed - use RAAF::Pipeline from pipeline_dsl/pipeline.rb
require_relative "hooks/hook_context"
require_relative "hooks/agent_hooks"
require_relative "auto_merge"
require_relative "incremental_processing"
require_relative "incremental_processor"
require_relative "agent_tool_integration"
require_relative "agent_streaming_methods"

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
      include RAAF::DSL::ContextAccess
      include RAAF::DSL::ContextConfiguration
      include RAAF::DSL::Pipelineable
      include RAAF::DSL::Hooks::HookContext
      include RAAF::DSL::Hooks::AgentHooks
      include RAAF::DSL::AutoMerge
      include RAAF::DSL::IncrementalProcessing
      include RAAF::DSL::AgentToolIntegration
      include RAAF::DSL::AgentStreamingMethods

      # Configuration DSL methods - consolidated from AgentDsl and AgentHooks
      class << self

        def _tools_config
          # Use Concurrent::Array for thread-safe array operations
          # This ensures configuration persists across threads (e.g., in background jobs)
          # and prevents race conditions during tool registration
          # FIXED: Previously used Thread.current with object_id which failed in job threads
          @_tools_config ||= Concurrent::Array.new
        end

        def _tools_config=(value)
          # Accept regular arrays and convert to Concurrent::Array
          @_tools_config = value.is_a?(Concurrent::Array) ? value : Concurrent::Array.new(value)
        end

        def _schema_config
          # Use Concurrent::Hash for thread-safe hash operations
          # This ensures configuration persists across threads
          @_schema_config ||= Concurrent::Hash.new
        end

        def _schema_config=(value)
          # Accept regular hashes and convert to Concurrent::Hash
          @_schema_config = value.is_a?(Concurrent::Hash) ? value : Concurrent::Hash.new(value)
        end

        def _prompt_config
          # Use Concurrent::Hash for thread-safe hash operations
          # This ensures configuration persists across threads
          @_prompt_config ||= Concurrent::Hash.new
        end

        def _prompt_config=(value)
          # Accept regular hashes and convert to Concurrent::Hash
          @_prompt_config = value.is_a?(Concurrent::Hash) ? value : Concurrent::Hash.new(value)
        end


        def _auto_discovery_config
          # Use Concurrent::Hash for thread-safe hash operations
          # This ensures configuration persists across threads
          @_auto_discovery_config ||= Concurrent::Hash.new
        end

        def _auto_discovery_config=(value)
          # Accept regular hashes and convert to Concurrent::Hash
          @_auto_discovery_config = value.is_a?(Concurrent::Hash) ? value : Concurrent::Hash.new(value)
        end

        # Tool execution configuration for interceptor conveniences
        # Temporarily disabled - ToolExecutionConfig removed
        # def tool_execution_config
        #   Thread.current["raaf_dsl_tool_execution_config_#{object_id}"] ||= ToolExecutionConfig::DEFAULTS.dup.freeze
        # end
        #
        # def tool_execution_config=(value)
        #   Thread.current["raaf_dsl_tool_execution_config_#{object_id}"] = value.freeze
        # end

        # Ensure each subclass gets its own configuration
        def inherited(subclass)
          super
          subclass._context_config = Concurrent::Hash.new
          subclass._tools_config = Concurrent::Array.new
          subclass._schema_config = Concurrent::Hash.new
          subclass._prompt_config = Concurrent::Hash.new

          # Copy retry configuration from parent class
          subclass._retry_config = _retry_config&.dup || {}
          subclass._circuit_breaker_config = _circuit_breaker_config&.dup
          subclass._required_context_keys = _required_context_keys&.dup || []
          subclass._validation_rules = _validation_rules&.dup || {}

          # Register automatic trace flushing for all agents
          # This ensures RAAF traces are persisted after every agent execution
          subclass.on_end do |**|
            auto_flush_raaf_traces
          end
          subclass._result_transformations = _result_transformations&.dup || {}
          subclass._execution_conditions = _execution_conditions&.dup

          # Enable auto-transform by default with standard patterns
          subclass._auto_discovery_config = Concurrent::Hash.new({
            patterns: %w[
              process_*_from_data
              build_*_metadata
              extract_*_from_data
            ],
            exclude: [],
            enabled: true
          })

          # Initialize hooks for subclass
          hooks = {}
          HOOK_TYPES.each { |hook_type| hooks[hook_type] = [] }
          subclass._agent_hooks = hooks

          # Copy tool execution configuration from parent class
          # Temporarily disabled - ToolExecutionConfig removed
          # subclass.tool_execution_config = tool_execution_config.dup
        end

        # Core DSL methods from AgentDsl
        def agent_name(name = nil)
          if name
            _context_config[:name] = name
          else
            _context_config[:name] || inferred_agent_name
          end
        end

        def model(model_name = nil)
          if model_name
            _context_config[:model] = model_name
          else
            _context_config[:model] || "gpt-4o"
          end
        end


        def max_turns(turns = nil)
          if turns
            _context_config[:max_turns] = turns
          else
            _context_config[:max_turns] || 5
          end
        end

        def max_tokens(tokens = nil)
          if tokens
            _context_config[:max_tokens] = tokens
          else
            _context_config[:max_tokens]
          end
        end

        # Configure reasoning effort level for reasoning-capable models (GPT-5, o1-preview, o1-mini)
        #
        # @param effort [String, Symbol, nil] Reasoning effort level
        # @return [String, nil] Current reasoning effort setting when called without parameters
        #
        # @example Set reasoning effort to minimal (GPT-5 only)
        #   class CostAwareAgent < RAAF::DSL::Agent
        #     model "gpt-5"
        #     reasoning_effort "minimal"  # Lowest cost, fastest
        #   end
        #
        # @example Set reasoning effort to high for complex tasks
        #   class DeepThinkerAgent < RAAF::DSL::Agent
        #     model "gpt-5"
        #     reasoning_effort "high"  # Most thorough, highest cost
        #   end
        #
        # @example Use symbol notation
        #   class MediumReasoningAgent < RAAF::DSL::Agent
        #     model "o1-preview"
        #     reasoning_effort :medium  # Default level
        #   end
        #
        # @note Available levels:
        #   - "minimal" - Least reasoning, lowest cost (~1-2x tokens) - GPT-5 only
        #   - "low" - Basic reasoning (~2-3x tokens)
        #   - "medium" - Standard reasoning depth (~3-4x tokens) - Default
        #   - "high" - Deep reasoning, highest cost (~4-5x tokens)
        #
        # @note Cost implications:
        #   - Reasoning tokens are ~4x more expensive than regular tokens
        #   - "minimal" can reduce reasoning tokens by 60-80% vs "high"
        #   - Use lower effort levels for simple tasks to control costs
        #
        def reasoning_effort(effort = nil)
          if effort
            _context_config[:reasoning_effort] = effort.to_s
          else
            _context_config[:reasoning_effort]
          end
        end

        def description(desc = nil)
          if desc
            _context_config[:description] = desc
          else
            _context_config[:description]
          end
        end

        # Configure which provider to use for this agent
        #
        # @param provider_name [Symbol, String, nil] Short name of the provider
        # @return [Symbol, nil] Current provider setting when called without parameters
        #
        # @example Explicit provider specification
        #   class ClaudeAgent < RAAF::DSL::Agent
        #     model "claude-3-5-sonnet-20241022"
        #     provider :anthropic
        #   end
        #
        # @example Auto-detection (default)
        #   class GPTAgent < RAAF::DSL::Agent
        #     model "gpt-4o"
        #     # Provider auto-detected as :openai (ResponsesProvider)
        #   end
        #
        def provider(provider_name = nil)
          if provider_name
            _context_config[:provider] = provider_name.to_sym
          else
            _context_config[:provider]
          end
        end

        # Configure provider-specific options
        #
        # @param options [Hash] Options to pass to provider constructor
        # @return [Hash] Current provider options when called without parameters
        #
        # @example Configure provider options
        #   class ClaudeAgent < RAAF::DSL::Agent
        #     provider :anthropic
        #     provider_options api_key: ENV['CUSTOM_ANTHROPIC_KEY'], max_tokens: 4000
        #   end
        #
        def provider_options(**options)
          if options.any?
            _context_config[:provider_options] = options
          else
            _context_config[:provider_options] || {}
          end
        end

        # Enable or disable automatic provider detection from model name
        #
        # @param enabled [Boolean, nil] Whether to enable auto-detection
        # @return [Boolean] Current auto-detection setting when called without parameters
        #
        # @example Disable auto-detection
        #   class MyAgent < RAAF::DSL::Agent
        #     model "gpt-4o"
        #     auto_detect_provider false
        #     # Will use Runner's default provider instead
        #   end
        #
        def auto_detect_provider(enabled = nil)
          if enabled.nil?
            _context_config.fetch(:auto_detect_provider, true)
          else
            _context_config[:auto_detect_provider] = enabled
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

        # Configure whether this agent should use AutoMerge functionality
        # AutoMerge intelligently merges AI agent results with existing pipeline context
        # using strategies like by_id merging for arrays, deep merge for hashes, etc.
        #
        # @param enabled [Boolean] Enable or disable AutoMerge (default: true)
        # @return [Boolean] Current AutoMerge setting when called without parameters
        #
        # @example Enable AutoMerge (default behavior)
        #   class Market::Scoring < ApplicationAgent
        #     auto_merge true  # Can be omitted since true is default
        #   end
        #
        # @example Disable AutoMerge for agents that create new data
        #   class Market::Analysis < ApplicationAgent
        #     auto_merge false  # Creates new markets, no merging needed
        #   end
        def auto_merge(enabled = nil)
          if enabled.nil?
            # Getter: return current setting, default to true if never set
            _context_config.fetch(:auto_merge, true)
          else
            # Setter: store the setting
            _context_config[:auto_merge] = enabled
          end
        end

        # Check if AutoMerge is enabled for this agent class
        # @return [Boolean] true if AutoMerge should be used (default: true)
        def auto_merge_enabled?
          auto_merge
        end


        # Agent Hooks functionality (consolidated from AgentHooks)
        HOOK_TYPES = %i[
          on_start
          on_end
          on_handoff
          on_tool_start
          on_tool_end
          on_error
          on_context_built
          on_validation_failed
          on_result_ready
          on_prompt_generated
          on_tokens_counted
          on_circuit_breaker_open
          on_circuit_breaker_closed
          on_retry_attempt
          on_execution_slow
          on_pipeline_stage_complete
          before_execute
          after_execute
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

        # DSL-LEVEL HOOKS (Tier 1: Essential)

        def on_context_built(method_name = nil, &block)
          register_agent_hook(:on_context_built, method_name, &block)
        end

        def on_validation_failed(method_name = nil, &block)
          register_agent_hook(:on_validation_failed, method_name, &block)
        end

        def on_result_ready(method_name = nil, &block)
          register_agent_hook(:on_result_ready, method_name, &block)
        end

        # DSL-LEVEL HOOKS (Tier 2: High-Value Development)

        def on_prompt_generated(method_name = nil, &block)
          register_agent_hook(:on_prompt_generated, method_name, &block)
        end

        def on_tokens_counted(method_name = nil, &block)
          register_agent_hook(:on_tokens_counted, method_name, &block)
        end

        def on_circuit_breaker_open(method_name = nil, &block)
          register_agent_hook(:on_circuit_breaker_open, method_name, &block)
        end

        def on_circuit_breaker_closed(method_name = nil, &block)
          register_agent_hook(:on_circuit_breaker_closed, method_name, &block)
        end

        # DSL-LEVEL HOOKS (Tier 3: Specialized Operations)

        def on_retry_attempt(method_name = nil, &block)
          register_agent_hook(:on_retry_attempt, method_name, &block)
        end

        def on_execution_slow(method_name = nil, &block)
          register_agent_hook(:on_execution_slow, method_name, &block)
        end

        def on_pipeline_stage_complete(method_name = nil, &block)
          register_agent_hook(:on_pipeline_stage_complete, method_name, &block)
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
          _context_config[:temperature] = temp
        end

        # Nucleus sampling parameter (0.0 to 1.0)
        # Controls diversity via nucleus sampling. 0.0 is deterministic, 1.0 is maximum diversity.
        def top_p(value)
          _context_config[:top_p] = value
        end

        # Reduce repetition (-2.0 to 2.0)
        # Positive values penalize tokens that have already appeared
        def frequency_penalty(value)
          _context_config[:frequency_penalty] = value
        end

        # Encourage new topics (-2.0 to 2.0)
        # Positive values encourage the model to talk about new topics
        def presence_penalty(value)
          _context_config[:presence_penalty] = value
        end

        # Stop sequences (string or array of strings)
        # The model will stop generating when it encounters these sequences
        def stop(sequences)
          _context_config[:stop] = sequences
        end

        # User identifier for tracking and abuse monitoring
        def user(identifier)
          _context_config[:user] = identifier
        end

        # Enable or disable parallel tool execution
        def parallel_tool_calls(enabled)
          _context_config[:parallel_tool_calls] = enabled
        end

        # Set or get execution timeout for this agent
        #
        # @param seconds [Integer, nil] Timeout in seconds
        # @return [Integer, nil] The execution timeout value
        def execution_timeout(seconds = nil)
          if seconds
            _context_config[:execution_timeout] = seconds
          else
            _context_config[:execution_timeout]
          end
        end

        # Set or get HTTP timeout for OpenAI API calls
        #
        # @param seconds [Integer, nil] HTTP timeout in seconds
        # @return [Integer, nil] The HTTP timeout value
        def http_timeout(seconds = nil)
          if seconds
            _context_config[:http_timeout] = seconds
          else
            _context_config[:http_timeout]
          end
        end

        # Set or get general timeout for this agent (used by pipeline wrappers)
        #
        # @param seconds [Integer, nil] Timeout in seconds
        # @return [Integer, nil] The timeout value
        def timeout(seconds = nil)
          if seconds
            _context_config[:timeout] = seconds
          else
            _context_config[:timeout]
          end
        end

        public  # Make tool_execution public (needed for DSL usage)

        # Configure tool execution interceptor conveniences
        #
        # This DSL method allows configuring validation, logging, metadata injection,
        # and other convenience features for tool execution.
        #
        # @yield Block for configuring tool execution features
        #
        # @example Disable validation
        #   class MyAgent < RAAF::DSL::Agent
        #     tool_execution do
        #       enable_validation false
        #     end
        #   end
        #
        # @example Configure multiple options
        #   class MyAgent < RAAF::DSL::Agent
        #     tool_execution do
        #       enable_validation true
        #       enable_logging true
        #       enable_metadata false
        #       truncate_logs 200
        #     end
        #   end
        #
        # Temporarily disabled - ToolExecutionConfig removed
        # def tool_execution(&block)
        #   config = ToolExecutionConfig.new(tool_execution_config.dup)
        #   config.instance_eval(&block) if block
        #   self.tool_execution_config = config.to_h
        # end

        private  # Make methods after tool_execution private again

        # Set or get retry count for this agent (used by pipeline wrappers)
        #
        # @param count [Integer, nil] Number of retry attempts
        # @return [Integer, nil] The retry count value
        def retry(count = nil)
          if count
            _context_config[:retry] = count
          else
            _context_config[:retry]
          end
        end

        def schema(model: nil, &block)
          # Always use the modern SchemaBuilder that supports model introspection
          builder = RAAF::DSL::SchemaBuilder.new(model: model)
          builder.instance_eval(&block) if block_given?
          self._schema_definition = {
            schema: builder.to_schema,
            config: { mode: :strict, repair_attempts: 0, allow_extra: false }
          }
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

        public  # Make continuation methods public


        # Enable automatic continuation support for this agent
        #
        # Configures the agent to automatically handle continuations
        # for large outputs that require multiple calls to complete.
        #
        # @param options [Hash] Configuration options for continuation
        # @option options [Integer] :max_attempts (10) Maximum continuation attempts (1-50)
        # @option options [Symbol] :output_format (:auto) Format for structured output (:csv, :markdown, :json, :auto)
        # @option options [Symbol] :on_failure (:return_partial) Behavior on failure (:return_partial, :raise_error)
        #
        # @raise [RAAF::InvalidConfigurationError] If configuration is invalid
        #
        # @example Basic usage with defaults
        #   class MyAgent < RAAF::DSL::Agent
        #     enable_continuation
        #   end
        #
        # @example Custom configuration
        #   class MyAgent < RAAF::DSL::Agent
        #     enable_continuation(
        #       max_attempts: 20,
        #       output_format: :csv,
        #       on_failure: :raise_error
        #     )
        #   end
        #
        # @return [Class] Returns the class for method chaining
        def enable_continuation(options = {})
          # Ensure continuation module is loaded
          require_relative '../continuation/config'

          # Create and validate configuration
          config = RAAF::Continuation::Config.new(options)
          config.validate!

          # Store configuration as a hash
          @continuation_config = config.to_h

          # Return class for chaining
          self
        end

        # Get the continuation configuration
        #
        # @return [Hash, nil] Continuation configuration hash or nil if not enabled
        def _continuation_config
          @continuation_config
        end

        # Check if continuation is enabled for this agent
        #
        # @return [Boolean] true if continuation is enabled, false otherwise
        def continuation_enabled?
          !@continuation_config.nil?
        end

        # DSL convenience methods for continuation output formats
        # These provide a shorthand syntax for enabling continuation with specific formats
        #
        # @example Enable continuation with CSV output format
        #   class MyAgent < RAAF::DSL::Agent
        #     output_csv  # Equivalent to: enable_continuation(output_format: :csv)
        #   end
        #
        # @example Enable continuation with markdown output format
        #   class MyAgent < RAAF::DSL::Agent
        #     output_markdown  # Equivalent to: enable_continuation(output_format: :markdown)
        #   end
        #
        # @example Enable continuation with JSON output format
        #   class MyAgent < RAAF::DSL::Agent
        #     output_json  # Equivalent to: enable_continuation(output_format: :json)
        #   end
        #
        # @return [Class] Returns the class for method chaining

        # Enable continuation with CSV output format
        #
        # Convenience method that enables continuation with CSV output format
        # and returns the class for method chaining.
        #
        def output_csv
          enable_continuation(output_format: :csv)
        end

        # Enable continuation with Markdown output format
        #
        # Convenience method that enables continuation with Markdown output format
        # and returns the class for method chaining.
        #
        def output_markdown
          enable_continuation(output_format: :markdown)
        end

        # Enable continuation with JSON output format
        #
        # Convenience method that enables continuation with JSON output format
        # and returns the class for method chaining.
        #
        def output_json
          enable_continuation(output_format: :json)
        end

        # Get the model configuration
        #
        # @return [String, nil] The model name or nil
        def _model
          _context_config[:model]
        end

        # Get the temperature configuration
        #
        # @return [Float, nil] The temperature value or nil
        def _temperature
          _context_config[:temperature]
        end

        # Get the max_turns configuration
        #
        # @return [Integer, nil] The max turns value or nil
        def _max_turns
          _context_config[:max_turns]
        end

        private  # Restore private visibility

        # Context DSL method - bridges between new ContextConfiguration and legacy _required_context_keys
        def context(options = {}, &block)
          if block_given?
            # Call the ContextConfiguration method
            super(options, &block)

            # Bridge to legacy _required_context_keys for backward compatibility with inheritance
            if _context_config[:context_rules] && _context_config[:context_rules][:required]
              # Merge with parent's required keys rather than overriding
              parent_keys = self._required_context_keys || []
              new_keys = _context_config[:context_rules][:required] || []
              self._required_context_keys = (parent_keys + new_keys).uniq
            end
          else
            super(options)
          end
        end

        # Context validation DSL method
        def validates_context(key, type: nil, presence: nil, format: nil)
          self._validation_rules ||= {}
          self._validation_rules[key.to_sym] = {
            type: type,
            presence: presence,
            format: format
          }.compact
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
        # Default patterns (automatically discovered for result processing):
        #   - process_*_from_data  : Process raw AI data into structured format
        #   - build_*_metadata     : Build metadata for results
        #   - extract_*_from_data  : Extract specific data from AI response
        #
        # @example Using default auto-transform (result processing only)
        #   class MyAgent < RAAF::DSL::Agent
        #     # Auto-transform is ON by default for result processing methods:
        #     
        #     def process_companies_from_data(data)
        #       # Used in result_transform field declarations
        #     end
        #     
        #     def build_search_metadata(data)
        #       # Used in result_transform field declarations
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
            ]
            
            self._auto_discovery_config = {
              patterns: transform_patterns,
              exclude: exclude,
              enabled: true
            }
          end
        end
        
        # Legacy method for backward compatibility
        def enable_auto_discovery(patterns: %w[process_*_from_data build_*_metadata], exclude: [])
          auto_transform(:on, patterns: patterns, exclude: exclude)
        end


        protected

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
          
          # New DSL methods
          def required(*fields)
            @rules[:required] ||= []
            @rules[:required].concat(fields.map(&:to_sym))
          end
          
          def optional(**fields_with_defaults)
            @rules[:optional] ||= {}
            fields_with_defaults.each do |field, default_value|
              @rules[:optional][field.to_sym] = default_value
            end
          end
          
          def output(*fields)
            @rules[:output] ||= []
            @rules[:output].concat(fields.map(&:to_sym))
          end
          
          def computed(field_name, method_name = nil)
            @rules[:computed] ||= {}
            method_name ||= "compute_#{field_name}".to_sym
            @rules[:computed][field_name.to_sym] = method_name.to_sym
          end
          
          # Keep existing methods for backward compatibility and other functionality
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
          
          def to_h
            @rules
          end
        end

      end # End of class << self

      # Additional class attributes for agent functionality
      class << self
        attr_accessor :_required_context_keys, :_validation_rules, :_schema_definition, :_user_prompt_block,
                     :_retry_config, :_circuit_breaker_config, :_result_transformations,
                     :_execution_conditions
      end

      # Instance attributes
      attr_reader :context, :processing_params, :debug_enabled

      # Initialize a new agent instance
      #
      # @param context [ContextVariables, Hash, nil] Context for all agent data
      # @param processing_params [Hash] Parameters that control how the agent processes content
      # @param debug [Boolean, nil] Enable debug logging for this agent instance
      # @param validation_mode [Boolean] Skip execution conditions during validation (internal use)
      # @param parent_component [Object, nil] Optional parent component for span hierarchy
      # @param kwargs [Hash] Arbitrary keyword arguments that become context when auto-context is enabled
      def initialize(context: nil, processing_params: {}, debug: nil, validation_mode: false, parent_component: nil, **kwargs)
        @debug_enabled = debug || (defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.development?) || false
        @processing_params = processing_params
        @validation_mode = validation_mode
        @circuit_breaker_state = :closed
        @circuit_breaker_failures = 0
        @circuit_breaker_last_failure = nil
        @pipeline_schema = nil  # Will be set by pipeline if agent is part of one
        @parent_component = parent_component

        # Log parent_component status for tracing hierarchy
        if @parent_component
          log_debug "Received parent_component: #{@parent_component.class.name}"
        end

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

        # Setup provider instance if configured
        @provider = setup_provider

        # LAZY LOADING: Resolve tools during initialization
        @resolved_tools = {}
        resolve_all_tools!

        validate_context!
        # setup_context_configuration  # REMOVED: Empty method causing method_missing conflicts
        # setup_logging_and_metrics    # REMOVED: Empty method causing method_missing conflicts

        if @debug_enabled
          log_debug("Agent initialized",
                    agent_class: self.class.name,
                    context_size: @context.size,
                    context_keys: @context.keys.inspect,
                    auto_context: self.class.auto_context?,
                    provider: @provider ? @provider.class.name : "none",
                    category: :context)
        end
      end
      
      # Inject pipeline schema from pipeline (called by pipeline execution)
      def inject_pipeline_schema(schema_block)
        @pipeline_schema = schema_block
      end

      # Context access through dynamic methods - update/set methods removed
      
      def has?(key)
        @context.has?(key)
      end
      
      def context_keys
        @context.keys
      end
      

      # Instance-level convenience methods for accessing continuation metadata
      # These methods provide easy access to continuation status and metadata from runner results
      #
      # @example Check if agent result was continued
      #   agent = MyAgent.new
      #   result = agent.run
      #   puts agent.was_continued?  # => true if result was continued
      #
      # @example Get continuation metadata
      #   agent = MyAgent.new
      #   result = agent.run
      #   metadata = agent.continuation_metadata
      #   puts metadata[:continuation_count]  # => Number of continuation attempts
      #

      # Store the last runner result for accessing continuation metadata
      attr_accessor :runner_result

      # Check if continuation is enabled for this agent
      #
      # @return [Boolean] true if continuation is enabled, false otherwise
      def continuation_enabled?
        self.class.continuation_enabled?
      end

      # Get continuation metadata from the last run
      #
      # @return [Hash] Metadata hash containing continuation details
      def continuation_metadata
        runner_result&.dig(:_continuation_metadata) || {}
      end

      # Check if the last run was a continuation
      #
      # @return [Boolean] true if the last run was a continuation attempt
      def was_continued?
        continuation_metadata[:was_continued] == true
      end

      # Get the number of continuation attempts from the last run
      #
      # @return [Integer] Number of continuation attempts (0 if not continued)
      def continuation_count
        continuation_metadata[:continuation_count] || 0
      end

      # Run the agent with optional smart features (retry, circuit breaker, etc.)
      # Override run to integrate incremental processing
      #
      # When an agent has incremental_processing configured, this method:
      # 1. Detects the input field (marked with incremental: true in context)
      # 2. Detects the output field (first array field in schema)
      # 3. Initializes IncrementalProcessor with agent and config
      # 4. Processes data with skip/load/persist logic
      # 5. Returns results merged with context
      #
      # For agents without incremental processing, this delegates to the standard execution path.
      #
      # @param context [ContextVariables, Hash, nil] Context to use (overrides instance context)
      # @param input_context_variables [ContextVariables, Hash, nil] Alternative parameter name for context
      # @param stop_checker [Proc] Optional stop checker for execution control
      # @param skip_retries [Boolean] Skip retry/circuit breaker logic (default: false)
      # @return [Hash] Result from agent execution
      def run(context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false, previous_result: nil)
        # Check if incremental processing is configured
        if incremental_processing?
          run_with_incremental_processing(context: context, input_context_variables: input_context_variables, stop_checker: stop_checker, skip_retries: skip_retries, previous_result: previous_result)
        else
          # Standard execution path
          run_standard(context: context, input_context_variables: input_context_variables, stop_checker: stop_checker, skip_retries: skip_retries, previous_result: previous_result)
        end
      end

      # Standard run execution (original behavior)
      #
      # @param context [ContextVariables, Hash, nil] Context to use (overrides instance context)
      # @param input_context_variables [ContextVariables, Hash, nil] Alternative parameter name for context
      # @param stop_checker [Proc] Optional stop checker for execution control
      # @param skip_retries [Boolean] Skip retry/circuit breaker logic (default: false)
      # @return [Hash] Result from agent execution
      def run_standard(context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false, previous_result: nil)
        # Check if execution timeout is configured
        execution_timeout = self.class._context_config[:execution_timeout]

        if execution_timeout
          run_with_timeout(execution_timeout, context: context, input_context_variables: input_context_variables, stop_checker: stop_checker, skip_retries: skip_retries, previous_result: previous_result)
        else
          run_without_timeout(context: context, input_context_variables: input_context_variables, stop_checker: stop_checker, skip_retries: skip_retries, previous_result: previous_result)
        end
      end

      # Backward compatibility alias for run method
      def call(context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false, previous_result: nil)
        run(context: context, input_context_variables: input_context_variables, stop_checker: stop_checker, skip_retries: skip_retries, previous_result: previous_result)
      end

      # Public accessor for provider instance
      #
      # @return [Object, nil] The provider instance if configured
      #
      def provider
        @provider
      end

      # Execute agent with incremental processing logic
      #
      # This method:
      # 1. Auto-detects input/output fields
      # 2. Initializes IncrementalProcessor
      # 3. Processes data with skip/load/persist logic
      # 4. Merges results back into context
      #
      # @return [Hash] Results with processed and skipped items merged
      def run_with_incremental_processing(context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false, previous_result: nil)
        log_info "🔄 [#{self.class.name}] Running with incremental processing"

        # Auto-detect input field (marked with incremental: true in context)
        input_field = detect_incremental_input_field
        raise ArgumentError, "No incremental input field found in context" unless input_field

        # Auto-detect output field (first array field in schema)
        output_field = detect_output_field
        raise ArgumentError, "No array output field found in schema" unless output_field

        log_info "📥 [#{self.class.name}] Input field: #{input_field}"
        log_info "📤 [#{self.class.name}] Output field: #{output_field}"

        # Get input data from context
        input_data = @context[input_field]
        raise ArgumentError, "Input field #{input_field} not found in context" unless input_data

        # Initialize processor
        processor = RAAF::DSL::IncrementalProcessor.new(self, incremental_config)

        # Process with skip/load/persist logic
        # The block processes non-skipped items through the normal agent flow
        processed_results = processor.process(input_data, @context) do |items_to_process, ctx|
          # Create temporary context with items to process
          temp_context = ctx.dup
          temp_context[input_field] = items_to_process

          # Run normal agent processing on non-skipped items only
          agent_result = run_agent_on_batch(items_to_process, temp_context, context: context, input_context_variables: input_context_variables, stop_checker: stop_checker, skip_retries: skip_retries, previous_result: previous_result)

          # Extract results from agent response
          agent_result[output_field] || []
        end

        log_info "✅ [#{self.class.name}] Incremental processing complete: #{processed_results.count} total items"

        # Return results in standard format
        {
          success: true,
          output_field => processed_results
        }
      end

      # Run the agent on a batch of items
      #
      # This method executes the normal agent flow (calling the LLM) for the
      # provided batch of items. It's called by the incremental processor for
      # non-skipped items only.
      #
      # @param items [Array<Hash>] Items to process
      # @param ctx [Hash] Context for processing
      # @return [Hash] Agent results
      def run_agent_on_batch(items, ctx, context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false, previous_result: nil)
        # Temporarily set context for this batch
        original_context = @context
        @context = ctx

        # Execute normal agent flow (standard run method)
        result = run_standard(context: context, input_context_variables: input_context_variables, stop_checker: stop_checker, skip_retries: skip_retries, previous_result: previous_result)

        # Restore original context
        @context = original_context

        result
      end

      # Detect which context field is marked for incremental processing
      #
      # Uses the explicitly declared incremental_input_field from the agent class.
      # Agents must declare this using `incremental_input_field :field_name` DSL.
      #
      # @return [Symbol, nil] The incremental input field name or nil if not declared
      # @raise [ArgumentError] if incremental processing is configured but field not declared
      def detect_incremental_input_field
        field = self.class._incremental_input_field

        if field.nil? && incremental_processing?
          raise ArgumentError, "#{self.class.name} has incremental_processing configured but no incremental_input_field declared. Add 'incremental_input_field :field_name' to your agent class."
        end

        field
      end

      # Detect the output field from schema
      #
      # Uses the explicitly declared incremental_output_field from the agent class.
      # Agents must declare this using `incremental_output_field :field_name` DSL.
      #
      # @return [Symbol, nil] The output field name or nil if not declared
      # @raise [ArgumentError] if incremental processing is configured but field not declared
      def detect_output_field
        field = self.class._incremental_output_field

        if field.nil? && incremental_processing?
          raise ArgumentError, "#{self.class.name} has incremental_processing configured but no incremental_output_field declared. Add 'incremental_output_field :field_name' to your agent class."
        end

        field
      end

      def handle_smart_error(error)
        agent_name = self.class._context_config&.dig(:name) || self.class.name

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
        elsif error.is_a?(RAAF::DSL::SchemaError) || error.is_a?(RAAF::DSL::ValidationError)
          log_error "❌ [#{agent_name}] Schema validation error: #{error.message}"

          # Fire DSL hook: on_validation_failed
          fire_dsl_hook(:on_validation_failed, {
            error: error.message,
            error_type: error.is_a?(RAAF::DSL::SchemaError) ? "schema_validation" : "data_validation",
            field: error.respond_to?(:field) ? error.field : nil,
            value: error.respond_to?(:value) ? error.value : nil,
            expected_type: error.respond_to?(:expected_type) ? error.expected_type : nil
          })

          { success: false, error: error.message, error_type: "validation_error" }
        elsif error.is_a?(ArgumentError) && error.message.include?("context")
          log_error "❌ [#{agent_name}] Context validation error: #{error.message}"

          # Fire DSL hook: on_validation_failed
          fire_dsl_hook(:on_validation_failed, {
            error: error.message,
            error_type: "context_validation"
          })

          { success: false, error: error.message, error_type: "validation_error" }
        else
          log_error "❌ [#{agent_name}] Unexpected error: #{error.message}", stack_trace: error.backtrace.join("
")
          { success: false, error: "Agent execution failed: #{error.message}", error_type: "unexpected_error" }
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

        # Preserve metadata from the original raaf_result (e.g., search_results from Perplexity)
        if raaf_result.is_a?(Hash) && raaf_result.key?(:metadata)
          base_result[:metadata] = raaf_result[:metadata]
          log_debug "🔍 [#{self.class.name}::process_raaf_result] Preserved metadata: #{raaf_result[:metadata].keys.inspect}"
        end

        # Apply result transformations if configured, or auto-generate them for output fields
        final_result = if self.class._result_transformations
          apply_result_transformations(base_result)
        else
          # Automatically extract output fields if they are declared but no transformations exist
          generate_auto_transformations_for_output_fields(base_result)
        end

        # Fire DSL hook: on_result_ready - After all transformations complete
        fire_dsl_hook(:on_result_ready, {
          raw_result: base_result,
          processed_result: final_result
        })

        final_result
      end

      private

      # Resolve all tools with deferred resolution
      #
      # This method is called during agent initialization to resolve tool identifiers
      # that were stored at class definition time. This implements lazy loading to
      # avoid Rails eager loading issues.
      #
      # @return [void]
      def resolve_all_tools!
        return unless self.class.respond_to?(:_tools_config)

        self.class._tools_config.each do |tool_config|
          # Skip if already resolved or not deferred
          next unless tool_config[:resolution_deferred]
          next if tool_config[:tool_class]

          identifier = tool_config[:tool_identifier] || tool_config[:identifier]

          begin
            # Resolve using ToolRegistry
            tool_class = RAAF::ToolRegistry.resolve(identifier)

            unless tool_class
              # Enhanced error with DidYouMean suggestions
              result = RAAF::ToolRegistry.resolve_with_details(identifier)

              error_message = "Failed to resolve tool '#{identifier}' for agent '#{self.class.name}'
"
              error_message += "Searched namespaces: #{result[:searched_namespaces].join(', ')}
"

              if result[:suggestions].any?
                error_message += "Did you mean? #{result[:suggestions].join(', ')}"
              end

              raise ArgumentError, error_message
            end

            # Store resolved class and cache in instance
            tool_config[:tool_class] = tool_class
            @resolved_tools[identifier] = tool_class

            # Log successful resolution in debug mode
            if @debug_enabled
              log_debug("Tool resolved",
                       identifier: identifier,
                       tool_class: tool_class.name,
                       category: :tools)
            end

          rescue StandardError => e
            RAAF.logger.error "❌ [Agent] Failed to resolve tool '#{identifier}': #{e.message}"
            raise
          end
        end
      end

      # Fire a DSL-level hook with error handling
      #
      # DSL hooks fire during DSL processing (after context building, validation, transformations)
      # while core hooks fire during RAAF agent execution. This separation ensures hooks
      # receive appropriate data for their execution context.
      #
      # @param hook_name [Symbol] The name of the hook to fire
      # @param hook_data [Hash] Data to pass to the hook (automatically converted to HashWithIndifferentAccess)
      # @return [void]
      def fire_dsl_hook(hook_name, hook_data = {})
        return unless self.class.respond_to?(:_agent_hooks) && self.class._agent_hooks[hook_name]

        # Build comprehensive data with standard parameters
        comprehensive_data = {
          # Standard parameters (always present)
          context: @context || RAAF::DSL::ContextVariables.new,
          agent: self,
          timestamp: Time.now,

          # Hook-specific data
          **hook_data
        }

        # Ensure HashWithIndifferentAccess for flexible key access
        normalized_data = ActiveSupport::HashWithIndifferentAccess.new(comprehensive_data)

        # Convert to symbol keys for keyword arguments (use deep to handle nested hashes)
        # HashWithIndifferentAccess uses string keys internally, but keyword arguments need symbols
        # deep_symbolize_keys recursively converts all nested hash keys to symbols
        symbol_keyed_data = normalized_data.deep_symbolize_keys

        # Execute each registered hook for this type
        self.class._agent_hooks[hook_name].each do |hook|
          begin
            if hook.is_a?(Proc)
              # Use instance_exec to execute block in agent's context with keyword arguments
              # This allows hook blocks to use clean keyword syntax: |param1:, param2:, **|
              instance_exec(**symbol_keyed_data, &hook)
            elsif hook.is_a?(Symbol)
              # Call method with keyword arguments
              send(hook, **symbol_keyed_data)
            end
          rescue StandardError => e
            # Enhanced error logging with hook context
            log_error "❌ [#{self.class.name}] Hook #{hook_name} failed: #{e.message}"
            log_debug "Hook data", data: normalized_data.except(:context, :agent)
            log_debug "Error details", error: e.class.name, backtrace: e.backtrace.first(5)
          end
        end
      end

      # Calculate estimated cost based on token usage and model
      #
      # @param usage [Hash] Token usage data with :input_tokens and :output_tokens
      # @param model [String] Model identifier (e.g., "gpt-4o", "claude-3-5-sonnet")
      # @return [Float] Estimated cost in USD
      def calculate_estimated_cost(usage, model)
        input_tokens = (usage[:input_tokens] || usage["input_tokens"] || 0).to_f
        output_tokens = (usage[:output_tokens] || usage["output_tokens"] || 0).to_f

        # Pricing per 1M tokens (approximate, as of 2025)
        pricing = case model.to_s.downcase
        when /gpt-4o-mini/
          { input: 0.15, output: 0.60 }
        when /gpt-4o/
          { input: 2.50, output: 10.00 }
        when /gpt-4-turbo/, /gpt-4-1106/
          { input: 10.00, output: 30.00 }
        when /gpt-4/, /gpt-4-0613/
          { input: 30.00, output: 60.00 }
        when /gpt-3.5-turbo/
          { input: 0.50, output: 1.50 }
        when /claude-3-5-sonnet/,  /claude-3\.5-sonnet/
          { input: 3.00, output: 15.00 }
        when /claude-3-sonnet/, /claude-3-opus/
          { input: 3.00, output: 15.00 }
        when /claude-3-haiku/
          { input: 0.25, output: 1.25 }
        else
          # Default pricing for unknown models
          { input: 1.00, output: 2.00 }
        end

        input_cost = (input_tokens / 1_000_000.0) * pricing[:input]
        output_cost = (output_tokens / 1_000_000.0) * pricing[:output]

        (input_cost + output_cost).round(6)
      end

      def run_with_timeout(timeout_seconds, context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false, previous_result: nil)
        agent_name = self.class._context_config&.dig(:name) || self.class.name
        log_info "⏰ [#{agent_name}] Starting execution with #{timeout_seconds}s timeout"
        
        begin
          Timeout.timeout(timeout_seconds) do
            run_without_timeout(context: context, input_context_variables: input_context_variables, stop_checker: stop_checker, skip_retries: skip_retries, previous_result: previous_result)
          end
        rescue Timeout::Error => e
          log_error "⏰ [#{agent_name}] Execution timed out after #{timeout_seconds} seconds"
          {
            workflow_status: "timeout",
            success: false,
            error: "Agent execution timed out after #{timeout_seconds} seconds",
            error_type: "execution_timeout",
            timeout_seconds: timeout_seconds
          }
        end
      end

      def run_without_timeout(context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false, previous_result: nil)
        # Validate prompt context early if configured
        if self.class._context_config[:validate_prompt_context] != false
          validate_prompt_context!
        end
        
        # Validate computed fields early to catch context reference errors
        validate_computed_fields!
        
        # Check execution conditions first
        if self.class._execution_conditions
          resolved_context = resolve_run_context(context || input_context_variables)
          unless should_execute?(resolved_context, previous_result)
            log_info "⏭️ [#{self.class.name}] Skipping execution due to conditions not met"

            # Create a span for the skipped agent to make it visible in traces
            skip_result = {
              success: true,
              skipped: true,
              reason: "Execution conditions not met",
              workflow_status: "skipped"
            }

            return create_skipped_span("execution_conditions_not_met", skip_result, resolved_context)
          end
        end

        # Check if we should use smart features
        agent_name = self.class._context_config&.dig(:name) || self.class.name
        has_smart = has_smart_features?
        log_debug "🔍 [#{agent_name}] Smart features check: skip_retries=#{skip_retries}, has_smart_features=#{has_smart}"
        log_debug "🔍 [#{agent_name}] Retry config present: #{self.class._retry_config.present?}"
        log_debug "🔍 [#{agent_name}] Retry config keys: #{self.class._retry_config&.keys&.inspect}"

        if skip_retries || !has_smart_features?
          log_debug "🔍 [#{agent_name}] Using direct execution (no smart features)"
          # Direct execution without retries/circuit breaker, but still apply transformations
          raaf_result = direct_run(context: context, input_context_variables: input_context_variables, stop_checker: stop_checker)
          process_raaf_result(raaf_result)
        else
          log_debug "🔍 [#{agent_name}] Using smart execution with retries"
          # Smart execution with retries and circuit breaker
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
      
      # Validate prompt context requirements using dry-run
      def validate_prompt_context!
        prompt_spec = determine_prompt_spec
        return true unless prompt_spec

        begin
          # Try to create prompt instance for validation
          prompt_instance = case prompt_spec
                           when Class
                             # Pass context as keyword arguments with optional defaults merged
                             context_hash = @context.respond_to?(:to_h) ? @context.to_h : @context
                             context_with_defaults = merge_optional_defaults(context_hash)
                             prompt_spec.new(**context_with_defaults)
                           when String, Symbol
                             # Try to resolve and instantiate with optional defaults merged
                             klass = Object.const_get(prompt_spec.to_s)
                             context_hash = @context.respond_to?(:to_h) ? @context.to_h : @context
                             context_with_defaults = merge_optional_defaults(context_hash)
                             klass.new(**context_with_defaults)
                           else
                             prompt_spec
                           end
          
          # Run dry validation if available
          if prompt_instance.respond_to?(:dry_run_validation!)
            prompt_instance.dry_run_validation!
          end
          
          # NEW: Validate prompt methods can be called without context errors
          validate_prompt_methods!(prompt_instance)
          
          true
          
        rescue RAAF::DSL::Error => e
          # Re-raise validation errors with agent context
          raise RAAF::DSL::Error,
            "Prompt validation failed for agent #{self.class.name}:
#{e.message}"
        rescue StandardError => e
          # Log but don't fail on other errors (like missing prompt class)
          log_debug "Could not validate prompt context", error: e.message
          true
        end
      end

      # Validate that prompt methods (system, user) can be called without context errors
      #
      # This performs dry-run validation of prompt methods to catch undefined variable
      # references early, before expensive AI operations.
      #
      # @param prompt_instance [Object] The instantiated prompt object to validate
      # @return [Boolean] true if validation passes
      # @raise [RAAF::DSL::Error] if validation fails
      def validate_prompt_methods!(prompt_instance)
        return true unless prompt_instance
        
        # Validate system prompt method
        if prompt_instance.respond_to?(:system)
          begin
            prompt_instance.system
          rescue NameError => e
            if e.message.include?("undefined variable") || e.message.include?("undefined local variable or method")
              handle_prompt_validation_error("system", e, prompt_instance.class.name)
            else
              # Re-raise other NameErrors as they might be legitimate method issues
              raise
            end
          rescue StandardError => e
            # Log but don't fail on other errors during dry-run (e.g., nil method calls)
            log_debug "Prompt system method dry-run warning: #{e.class.name}: #{e.message}"
          end
        end
        
        # Validate user prompt method
        if prompt_instance.respond_to?(:user)
          begin
            prompt_instance.user
          rescue NameError => e
            if e.message.include?("undefined variable") || e.message.include?("undefined local variable or method")
              handle_prompt_validation_error("user", e, prompt_instance.class.name)
            else
              # Re-raise other NameErrors as they might be legitimate method issues
              raise
            end
          rescue StandardError => e
            # Log but don't fail on other errors during dry-run
            log_debug "Prompt user method dry-run warning: #{e.class.name}: #{e.message}"
          end
        end
        
        true
      end

      # Handle prompt validation errors with clear, actionable messages
      #
      # @param method_name [String] The prompt method that failed ("system" or "user")
      # @param error [NameError] The original error
      # @param prompt_class_name [String] Name of the prompt class
      # @raise [RAAF::DSL::Error] Formatted validation error
      def handle_prompt_validation_error(method_name, error, prompt_class_name)
        # Extract the problematic variable name
        variable_match = error.message.match(/`([^']+)'/)
        problem_var = variable_match ? variable_match[1] : "unknown"

        # Get available context for helpful error message
        available_context = if @context.respond_to?(:keys)
                             @context.keys
                           elsif @context.respond_to?(:to_h)
                             @context.to_h.keys
                           else
                             ["context object: #{@context.class.name}"]
                           end

        raise RAAF::DSL::Error,
          "Failed to validate #{method_name} prompt method in #{prompt_class_name}: " \
          "references undefined variable '#{problem_var}'. " \
          "Available context variables: #{available_context.join(', ')}. " \
          "This usually indicates an error in the prompt's #{method_name} method or missing required context."
      end

      # Merge optional context defaults into provided context
      #
      # This ensures that prompt validation uses the same context that execution will use,
      # by merging in optional field defaults from the agent's context definition.
      #
      # @param context_hash [Hash] The current runtime context
      # @return [Hash] Context with optional defaults merged in
      def merge_optional_defaults(context_hash)
        # Get context rules from agent class configuration
        rules = self.class._context_config[:context_rules] || {}
        return context_hash unless rules[:optional]

        # Create a copy to avoid mutating original
        merged = context_hash.dup

        # Add default values for optional fields that aren't present
        rules[:optional].each do |key, default_value|
          # Check both symbol and string keys (indifferent access)
          unless merged.key?(key) || merged.key?(key.to_s)
            merged[key] = default_value.is_a?(Proc) ? default_value.call : default_value
          end
        end

        merged
      end

      # Validate computed fields in result_transform blocks before execution
      #
      # This method performs a dry-run of all computed field methods to catch
      # context variable reference errors early, before expensive AI API calls.
      #
      # @return [Boolean] true if validation passes
      # @raise [RAAF::DSL::Error] if validation fails
      def validate_computed_fields!
        return true unless self.class._result_transformations
        
        transformations = self.class._result_transformations
        precheck_data = { "test" => "value", :test => :value }
        
        transformations.each do |field_name, field_config|
          next unless field_config[:computed]
          
          method_name = field_config[:computed]
          next unless respond_to?(method_name, true)

          begin
            # Attempt dry-run with mock data
            send(method_name, precheck_data)
            
          rescue NameError => e
            if e.message.include?("undefined variable") || e.message.include?("undefined local variable or method")
              # Extract the problematic variable name
              variable_match = e.message.match(/`([^']+)'/)
              problem_var = variable_match ? variable_match[1] : "unknown"
              
              # Get available context for helpful error message
              available_context = if @context.respond_to?(:keys)
                                   @context.keys
                                 elsif @context.respond_to?(:to_h)
                                   @context.to_h.keys
                                 else
                                   ["context object: #{@context.class.name}"]
                                 end
              
              raise RAAF::DSL::Error,
                "Computed field '#{field_name}' (method: #{method_name}) references undefined variable '#{problem_var}'. " \
                "Available context variables: #{available_context.join(', ')}"
            else
              # Re-raise other NameErrors as they might be legitimate method issues
              raise
            end
            
          rescue StandardError => e
            # Log but don't fail on other errors during dry-run
            # These might be legitimate errors that only occur with real data
            log_debug "Computed field '#{field_name}' dry-run warning: #{e.class.name}: #{e.message}"
          end
        end
        
        true
      end

      # Class method to validate with specific context (for pipeline validation)
      def self.validate_with_context(context)
        agent = new(**context)
        agent.validate_prompt_context!
      end
      
      public
      
      # Validate this agent for pipeline use (implements Pipelineable interface)
      #
      # Agents validate both their required context fields and their prompt context.
      # This provides comprehensive validation for pipeline compatibility.
      #
      # @param context [Hash] Context to validate against  
      # @return [Boolean] true if validation passes
      # @raise [RAAF::DSL::Error] if validation fails
      def validate_for_pipeline(context)
        # First validate basic required context fields (from Pipelineable)
        validate_required_context_fields(context)
        
        # Then validate prompt-specific context if this agent has prompts
        if self.class._context_config[:validate_prompt_context] != false
          validate_prompt_context!
        end
        
        true
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
        base_instructions = build_base_instructions
        
        # Append schema instructions if in tolerant or partial mode
        schema_def = build_schema
        if schema_def && schema_def.is_a?(Hash) && schema_def[:config]
          validation_mode = schema_def[:config][:mode]
          if [:tolerant, :partial].include?(validation_mode)
            schema_instructions = build_schema_instructions(schema_def)
            return "#{base_instructions}

#{schema_instructions}"
          end
        end
        
        base_instructions
      end

      # Build base system instructions (original logic)
      def build_base_instructions
        # First check for DSL-configured static instructions
        if self.class._prompt_config[:static_instructions]
          log_debug "Using static instructions from DSL"
          return self.class._prompt_config[:static_instructions]
        end

        # Then check for instruction template with context
        if self.class._prompt_config[:instruction_template]
          log_debug "Using instruction template from DSL"
          # TODO: Implement template interpolation with context
          return self.class._prompt_config[:instruction_template]
        end

        # Fall back to prompt resolver system
        prompt_spec = determine_prompt_spec
        log_debug "Building system instructions", prompt_spec: prompt_spec, agent_class: self.class.name

        error_message = "No system prompt resolved for #{self.class.name}. "

        if prompt_spec.nil?
          error_message += "No prompt class configured and could not infer one. " \
                          "Expected to find prompt class at: #{infer_prompt_class_name_string}"
        else
          log_debug "Found prompt spec", spec_class: prompt_spec.class.name, spec_value: prompt_spec.inspect

          resolved_prompt = DSL.prompt_resolvers.resolve(prompt_spec, @context.to_h)
          log_debug "Resolver result", resolved: !!resolved_prompt, resolvers_count: DSL.prompt_resolvers.resolvers.count

          if resolved_prompt
            system_message = resolved_prompt.messages.find { |m| m[:role] == "system" }
            log_debug "System message found", found: !!system_message
            if system_message
              return system_message[:content]
            else
              error_message += "Prompt was resolved but no system message found. " \
                              "Check your prompt class has a 'system' method that returns content."
            end
          else
            error_message += "No resolver could handle the prompt specification. " \
                            "Tried: #{DSL.prompt_resolvers.resolvers.map(&:name).join(', ')}. " \
                            "Check prompt class exists and context variables are valid."
          end
        end
        
        raise RAAF::DSL::Error, error_message
      end

      # Build schema guidance instructions for tolerant/partial validation modes
      def build_schema_instructions(schema_def)
        schema = schema_def[:schema]
        config = schema_def[:config]
        required = schema[:required] || []
        properties = schema[:properties] || {}
        
        instructions = "
## Response Format Requirements

"
        instructions += "You must return your response as valid JSON matching this structure:

"
        instructions += "```json
{
"
        
        properties.each do |name, field_config|
          req_marker = required.include?(name.to_s) ? " (REQUIRED)" : " (optional)"
          type_str = field_config[:type] || "any"
          
          # Add enum information if available
          if field_config[:enum]
            type_str += " (one of: #{field_config[:enum].join(', ')})"
          end
          
          # Add default value information
          if field_config[:default]
            default_str = field_config[:default].is_a?(String) ? "\"#{field_config[:default]}\"" : field_config[:default]
            type_str += " (default: #{default_str})"
          end
          
          instructions += "  \"#{name}\": <#{type_str}>#{req_marker}"
          instructions += field_config[:description] ? " // #{field_config[:description]}" : ""
          instructions += ",
"
        end
        
        instructions = instructions.chomp(",
") + "
"
        instructions += "}
```

"
        
        # Add validation-specific guidance
        case config[:mode]
        when :tolerant
          instructions += "**Validation Mode: Tolerant**
"
          instructions += "- REQUIRED fields must always be present and valid
"
          instructions += "- Optional fields should be included when relevant
"
          instructions += "- If you cannot determine a required field value, use a reasonable default
"
          instructions += "- Additional fields are allowed if they provide value
"
        when :partial
          instructions += "**Validation Mode: Partial**
"
          instructions += "- Include any fields you can determine
"
          instructions += "- Skip fields you cannot confidently populate
"
          instructions += "- Focus on providing accurate data for the fields you do include
"
        end
        
        instructions += "
**Important:** Ensure your response is valid JSON that can be parsed. " \
                       "If you're unsure about a field value, it's better to omit optional fields " \
                       "than to include invalid data."
        
        instructions
      end

      # RAAF DSL method - build user prompt using resolver system
      def build_user_prompt
        # First check for DSL-configured user prompt block
        if self.class._user_prompt_block
          log_debug "Using user prompt block from DSL"
          begin
            return self.class._user_prompt_block.call(@context)
          rescue StandardError => e
            raise RAAF::DSL::Error, "Failed to execute user prompt block for #{self.class.name}: #{e.message}"
          end
        end

        # Fall back to prompt resolver system
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
        
        # Ensure resolvers are initialized before trying to resolve prompts
        DSL.ensure_prompt_resolvers_initialized!
        
        # Try to infer prompt class by convention (e.g., Ai::Agents::MyAgent -> Ai::Prompts::MyAgent)
        inferred_prompt_class = infer_prompt_class_name
        if inferred_prompt_class
          log_debug "Trying inferred prompt class", class: inferred_prompt_class.name
          return inferred_prompt_class
        end
        
        # Try multiple naming conventions for prompt class inference
        alternative_prompt_class = try_alternative_prompt_conventions
        if alternative_prompt_class
          log_debug "Found alternative prompt class", class: alternative_prompt_class.name
          return alternative_prompt_class
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

        # Return nil if class name is not available (e.g., anonymous classes in tests)
        return nil if agent_class_name.nil?

        # Replace "Agents" with "Prompts" in the module path
        prompt_class_name = agent_class_name.gsub(/::Agents::/, "::Prompts::")
        
        log_debug "Inferring prompt class", 
                  agent_class: agent_class_name, 
                  inferred_prompt_class: prompt_class_name
        
        # In Rails environments, use constantize directly which handles autoloading
        # In non-Rails environments, fall back to the original behavior
        begin
          if defined?(Rails) && Rails.respond_to?(:application)
            # Rails environment - use constantize which handles autoloading properly
            prompt_class_name.constantize
          else
            # Non-Rails environment - use original logic
            if Object.const_defined?(prompt_class_name)
              prompt_class_name.constantize
            else
              log_debug "Inferred prompt class not found", 
                        class: prompt_class_name, 
                        error: "Class does not exist"
              nil
            end
          end
        rescue NameError => e
          # Class doesn't exist - this is expected when no prompt class is defined
          log_debug "Inferred prompt class not found", 
                    class: prompt_class_name, 
                    error: e.message
          nil
        rescue StandardError => e
          # This is a real error in the class definition (like missing methods, syntax errors, etc.)
          # Re-raise it so the user can see what's wrong
          # TODO: Consider more defensive error re-raising pattern - e.class constructor might not accept this format
          raise e.class, "Error loading prompt class #{prompt_class_name}: #{e.message}", e.backtrace
        end
      end
      
      def infer_prompt_class_name_string
        agent_class_name = self.class.name
        return nil if agent_class_name.nil?
        agent_class_name.gsub(/::Agents::/, "::Prompts::")
      end

      # Try alternative prompt naming conventions for better auto-discovery
      # This helps in cases where the standard convention doesn't work
      def try_alternative_prompt_conventions
        agent_class_name = self.class.name

        # Return nil if class name is not available (e.g., anonymous classes in tests)
        return nil if agent_class_name.nil?

        # Extract the final class name (e.g., "Analysis" from "Ai::Agents::Market::Analysis")
        final_class_name = agent_class_name.split("::").last
        
        alternative_patterns = [
          # Pattern: Same namespace as agent but under Prompts
          # Ai::Agents::Market::Analysis -> Ai::Prompts::Market::Analysis
          agent_class_name.gsub(/::Agents::/, "::Prompts::"),
          
          # Pattern: Directly under Ai::Prompts with category
          # Ai::Agents::Market::Analysis -> Ai::Prompts::MarketAnalysis  
          "Ai::Prompts::#{agent_class_name.split('::')[2..-1].join}",
          
          # Pattern: Under parent module's prompts
          # Ai::Agents::Market::Analysis -> Ai::Agents::Market::Prompts::Analysis
          agent_class_name.gsub(/::([^:]+)$/, "::Prompts::\\1"),
        ]
        
        alternative_patterns.each do |pattern|
          log_debug "Trying alternative prompt pattern", pattern: pattern
          
          begin
            if defined?(Rails) && Rails.respond_to?(:application)
              # Use Rails constantize for proper autoloading/eager loading
              prompt_class = pattern.constantize
              if prompt_class.is_a?(Class)
                log_debug "Found alternative prompt class", class: prompt_class.name
                return prompt_class
              end
            else
              # Non-Rails environment
              if Object.const_defined?(pattern)
                prompt_class = pattern.constantize
                if prompt_class.is_a?(Class)
                  log_debug "Found alternative prompt class", class: prompt_class.name  
                  return prompt_class
                end
              end
            end
          rescue NameError => e
            log_debug "Alternative pattern failed", pattern: pattern, error: e.message
            # Continue to next pattern
          rescue StandardError => e
            log_debug "Unexpected error trying alternative pattern", pattern: pattern, error: e.message
            # Continue to next pattern
          end
        end
        
        log_debug "No alternative prompt patterns found", agent_class: agent_class_name
        nil
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
        self.class._context_config[:name] || self.class.name.split("::").last
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
        log_debug("Building schema", category: :agents, agent_class: self.class.name)
        log_debug("Pipeline schema present?", category: :agents, present: @pipeline_schema.present?)
        
        # First check if pipeline schema is available
        if @pipeline_schema
          log_debug("Using schema from pipeline", category: :agents, agent_class: self.class.name)
          
          schema_result = @pipeline_schema.call
          log_debug("Pipeline schema structure", category: :agents, 
                    structure: schema_result.inspect[0..800])
          if schema_result.is_a?(Hash) && schema_result[:config]
            log_debug("Validation mode", category: :agents, mode: schema_result[:config][:mode])
          end
          if schema_result.is_a?(Hash) && schema_result[:schema] && schema_result[:schema][:properties]
            log_debug("Schema properties", category: :agents, 
                      properties: schema_result[:schema][:properties].keys.inspect)
          end
          
          return schema_result
        end
        
        # Next check if agent has directly defined schema
        if self.class._schema_definition
          log_debug("Using agent-defined schema", category: :agents, agent_class: self.class.name)
          return self.class._schema_definition
        end
        
        # Check if prompt class has a schema
        prompt_spec = determine_prompt_spec
        if prompt_spec && prompt_spec.respond_to?(:has_schema?) && prompt_spec.has_schema?
          log_debug("Using schema from prompt class", category: :agents, prompt_class: prompt_spec.name)
          return prompt_spec.get_schema
        end
        
        # Fall back to default schema
        log_debug("Using default schema", category: :agents, agent_class: self.class.name)
        default_schema
      end


      # Agent configuration methods
      def agent_name
        self.class._context_config&.dig(:name) || self.class.name.demodulize
      end

      def model_name
        self.class._context_config&.dig(:model) || 
          RAAF::DSL::Config.model_for(agent_name) || 
          "gpt-4o"
      end

      def max_turns
        self.class._context_config&.dig(:max_turns) ||
          RAAF::DSL::Config.max_turns_for(agent_name) ||
          3
      end

      def max_tokens
        self.class._context_config&.dig(:max_tokens) ||
          RAAF::DSL::Config.max_tokens_for(agent_name) ||
          nil  # No default - let provider use its default
      end

      # Instance accessor for temperature (randomness control)
      def temperature
        self.class._context_config&.dig(:temperature) ||
          RAAF::DSL::Config.temperature_for(agent_name) ||
          nil  # No default - let provider use its default
      end

      # Instance accessor for top_p (nucleus sampling)
      def top_p
        self.class._context_config&.dig(:top_p) || nil
      end

      # Instance accessor for frequency_penalty (reduce repetition)
      def frequency_penalty
        self.class._context_config&.dig(:frequency_penalty) || nil
      end

      # Instance accessor for presence_penalty (encourage new topics)
      def presence_penalty
        self.class._context_config&.dig(:presence_penalty) || nil
      end

      # Instance accessor for stop sequences
      def stop
        self.class._context_config&.dig(:stop) || nil
      end

      # Instance accessor for user identifier
      def user
        self.class._context_config&.dig(:user) || nil
      end

      # Instance accessor for parallel_tool_calls setting
      def parallel_tool_calls
        self.class._context_config&.dig(:parallel_tool_calls) || nil
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
          converted = tool_list.map { |tool| convert_to_function_tool(tool) }.compact
          converted
        end

        @tools
      end

      def tools?
        tools.any?
      end

      # Execute a tool with DSL conveniences (validation, logging, metadata)
      #
      # This method adds validation, logging, and metadata to tool executions
      # for raw core tools, while bypassing already-wrapped DSL tools to avoid
      # double-processing.
      #
      # @param tool_name [String] The name of the tool to execute
      # @param kwargs [Hash] Arguments to pass to the tool
      # @return [Hash] Tool execution result, potentially enhanced with metadata
      def execute_tool(tool_name, **kwargs)
        # Find the tool instance
        tool = tools.find { |t| t.name == tool_name }
        raise RAAF::ToolError, "Tool '#{tool_name}' not found" unless tool

        # If tool execution interception is disabled or tool is wrapped, execute directly
        unless should_intercept_tool?(tool)
          return begin
            tool.call(**kwargs)
          rescue StandardError => e
            raise RAAF::ToolError, "Tool execution failed: #{e.message}"
          end
        end

        # PRE-EXECUTION: Validation and logging
        perform_pre_execution(tool, kwargs)
        start_time = Time.now

        # EXECUTE: Call the tool directly
        result = begin
          tool.call(**kwargs)
        rescue StandardError => e
          raise RAAF::ToolError, "Tool execution failed: #{e.message}"
        end

        # POST-EXECUTION: Logging and metadata
        duration_ms = ((Time.now - start_time) * 1000).round(2)
        perform_post_execution(tool, result, duration_ms)

        result
      rescue StandardError => e
        handle_tool_error(tool, e)
        raise
      end

      def response_format
        log_debug("Building response format", category: :agents, agent_name: agent_name)
        
        # Check if unstructured output is requested
        if self.class._context_config&.dig(:output_format) == :unstructured
          log_debug("Unstructured output requested, returning nil", category: :agents)
          return
        end

        # Check if schema is nil (indicating unstructured output)
        schema_def = build_schema
        if schema_def.nil?
          log_debug("Schema is nil, returning nil response format", category: :agents)
          return
        end

        # Extract validation mode from schema definition
        validation_mode = schema_def.is_a?(Hash) && schema_def[:config] ? 
                         schema_def[:config][:mode] : :strict
        
        log_debug("Schema validation mode", category: :agents, mode: validation_mode)
        log_debug("Using structured output?", category: :agents, 
                  structured: validation_mode == :strict)
        
        # In tolerant/partial mode, don't use OpenAI response_format
        # Let the agent return flexible JSON and validate on our side
        if [:tolerant, :partial].include?(validation_mode)
          log_debug("Tolerant/partial mode - not using OpenAI structured output", category: :agents)
          return nil
        end
        
        # Strict mode uses OpenAI response_format (backward compatible)
        schema_data = schema_def.is_a?(Hash) && schema_def[:schema] ?
                     schema_def[:schema] : schema_def

        # Process schema through StrictSchema for OpenAI strict mode compliance
        if validation_mode == :strict && schema_data
          schema_data = RAAF::StrictSchema.ensure_strict_json_schema(schema_data)
        end

        if schema_data
          log_debug("Schema being sent to OpenAI", category: :agents,
                    schema: schema_data.inspect[0..500])
        end
        
        response_format_obj = {
          type: "json_schema",
          json_schema: {
            name: schema_name,
            strict: true,
            schema: schema_data
          }
        }
        
        log_debug("Final response_format object created", category: :agents)
        response_format_obj
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

      # Context access now handled by RAAF::DSL::ContextAccess module

      # Context update methods removed - use natural assignment syntax: field = value

      # Context validation method - needs to be public for pipeline validation
      def validate_context!
        # Validate required context keys from the _required_context_keys class method
        if self.class._required_context_keys
          missing_keys = self.class._required_context_keys.reject do |key|
            @context.has?(key)
          end

          if missing_keys.any?
            raise ArgumentError, "Required context keys missing: #{missing_keys.join(', ')}"
          end
        end
      end

      # Find retry configuration for a given error
      #
      # @param error [StandardError] The error to find configuration for
      # @return [Hash, nil] The retry configuration or nil if not retryable
      def find_retry_config(error)
        return nil unless self.class._retry_config

        log_debug "🔍 [#{self.class.name}] Finding retry config for error: #{error.class.name} - #{error.message}"
        log_debug "🔍 [#{self.class.name}] Available retry configs: #{self.class._retry_config.keys.inspect}"

        self.class._retry_config.each do |error_type, config|
          log_debug "🔍 [#{self.class.name}] Checking error_type: #{error_type} (#{error_type.class.name})"
          case error_type
          when :rate_limit
            if error.message.include?("rate limit")
              log_debug "✅ [#{self.class.name}] Matched :rate_limit"
              return config
            end
          when :timeout
            if error.is_a?(Timeout::Error)
              log_debug "✅ [#{self.class.name}] Matched :timeout"
              return config
            end
          when :network
            network_match = false
            begin
              network_match = defined?(Net::Error) && error.is_a?(Net::Error)
            rescue NameError
              # Net::Error class not available in this environment
              network_match = false
            end
            if network_match || error.message.include?("connection") || error.message.include?("503")
              log_debug "✅ [#{self.class.name}] Matched :network"
              return config
            end
          when Class
            log_debug "🔍 [#{self.class.name}] Checking Class match: #{error_type.name} vs #{error.class.name}"
            if error.is_a?(error_type)
              log_debug "✅ [#{self.class.name}] Matched Class: #{error_type.name}"
              return config
            end
          end
        end

        log_debug "❌ [#{self.class.name}] No retry config found for error: #{error.class.name}"
        nil
      end

      # Calculate retry delay based on configuration and attempt number
      #
      # @param config [Hash] The retry configuration
      # @param attempt [Integer] The current attempt number
      # @return [Numeric] The delay in seconds
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

      # Execute agent without tracing (fallback)
      def execute(context, input_context_variables, stop_checker)
        # Resolve context for this run
        run_context = resolve_run_context(context || input_context_variables)

        # Ensure @context is set for hook access
        @context = run_context

        # Fire DSL hook: on_context_built - After context assembly, before AI call
        fire_dsl_hook(:on_context_built, {})

        # Create OpenAI agent with DSL configuration
        openai_agent = create_agent

        # Build user prompt with context if available
        user_prompt = build_user_prompt_with_context(run_context)

        # Fire DSL hook: on_prompt_generated - After prompts are generated
        fire_dsl_hook(:on_prompt_generated, {
          system_prompt: openai_agent.instructions,
          user_prompt: user_prompt
        })

        log_debug "Executing agent #{self.class.name} with prompt length: #{user_prompt.to_s.length}"

        # Create RAAF runner and delegate execution
        runner_params = { agent: openai_agent }
        runner_params[:provider] = @provider if @provider  # Pass agent's provider if configured
        runner_params[:stop_checker] = stop_checker if stop_checker
        runner_params[:http_timeout] = self.class._context_config[:http_timeout] if self.class._context_config[:http_timeout]
        runner_params[:parent_component] = @parent_component if @parent_component

        runner = RAAF::Runner.new(**runner_params)

        # Pure delegation to raaf-ruby
        log_debug "Calling RAAF runner for #{self.class.name}"
        run_result = runner.run(user_prompt, context: run_context)

        # Generic response logging
        log_debug "Received AI response for #{agent_name}"

        # Fire DSL hook: on_tokens_counted - After token counting
        if run_result.respond_to?(:usage) && run_result.usage
          usage = run_result.usage
          fire_dsl_hook(:on_tokens_counted, {
            input_tokens: usage[:input_tokens] || usage["input_tokens"],
            output_tokens: usage[:output_tokens] || usage["output_tokens"],
            total_tokens: usage[:total_tokens] || usage["total_tokens"],
            estimated_cost: calculate_estimated_cost(usage, openai_agent.model),
            model: openai_agent.model
          })
        end

        # Transform result to expected DSL format
        base_result = transform_ai_result(run_result, run_context)

        # Return base_result WITHOUT applying transformations
        # Transformations will be applied by process_raaf_result() to avoid double execution
        base_result
      end

      # Resolve context for run execution
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

      # Build user prompt with context
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

      # Transform AI result to expected DSL format
      def transform_ai_result(run_result, run_context)
        # Extract parsed output from messages (works for any AI provider)
        parsed_output = extract_final_output(run_result)

        # Build result in expected DSL format
        {
          workflow_status: "completed",
          success: true,
          message: parsed_output || {},
          parsed_output: parsed_output,
          context_variables: run_context,
          raw_response: run_result,
          agent_class: self.class.name,
          agent_name: agent_name,
          execution_metadata: {
            executed_at: Time.current,
            execution_time: nil
          }
        }
      end

      # Apply result transformations if configured
      def apply_result_transformations(base_result)
        return base_result unless self.class._result_transformations

        transformations = self.class._result_transformations
        transformed_result = base_result.dup
        transformations.each do |field, transformation|
          begin
            if transformation.respond_to?(:call)
              transformed_result[field] = transformation.call(base_result)
            end
          rescue => e
            # Continue with other transformations
          end
        end

        transformed_result
      end

      # Generate automatic transformations for output fields
      def generate_auto_transformations_for_output_fields(base_result)
        return base_result unless self.class.respond_to?(:provided_fields)

        output_fields = self.class.provided_fields
        return base_result if output_fields.nil? || output_fields.empty?

        source_data = base_result[:parsed_output] || base_result[:data] || base_result
        return base_result unless source_data.respond_to?(:[])

        output_fields.each do |field_name|
          field_data = source_data[field_name] ||
                      source_data[field_name.to_s] ||
                      source_data[field_name.to_sym]

          if field_data
            base_result[field_name] = field_data
          end
        end

        base_result
      end


      # Convert tool instance to function tool
      def convert_to_function_tool(tool_instance)
        return nil unless tool_instance

        # If already a FunctionTool (from core tool wrapping), return as-is
        return tool_instance if tool_instance.is_a?(RAAF::FunctionTool)

        # If tool has a function_tool method, use it
        return tool_instance.function_tool if tool_instance.respond_to?(:function_tool)

        # If tool uses DSL, create RAAF function tool
        result = process_dsl_tool(tool_instance)
        return result if result.present?

        # If tool has a call method, it's a core tool - wrap it in FunctionTool
        if tool_instance.respond_to?(:call)
          # Try to get function tool parameters and description from class methods
          klass = tool_instance.class
          params = if klass.respond_to?(:function_tool_parameters)
            klass.function_tool_parameters
          else
            # Default: infer from call method signature
            {}
          end
          desc = if klass.respond_to?(:function_tool_description)
            klass.function_tool_description
          else
            "Tool: #{klass.name}"
          end

          ft = RAAF::FunctionTool.new(
            tool_instance.method(:call),
            name: tool_instance.class.name.split("::").last.downcase,
            description: desc,
            parameters: params
          )
          return ft
        end

        nil
      end

      # Process DSL tool and convert to RAAF function tool
      def process_dsl_tool(tool_instance)
        return nil unless tool_instance.respond_to?(:tool_configuration)

        config = tool_instance.tool_configuration

        # Create RAAF function tool from DSL tool configuration
        # Extract the function definition from the configuration
        function_def = config.is_a?(Hash) && config[:function] ? config[:function] : config

        RAAF::FunctionTool.new(
          tool_instance,
          name: function_def.dig(:name) || tool_instance.tool_name,
          description: function_def.dig(:description) || tool_instance.description,
          parameters: function_def.dig(:parameters)
        )
      end

      # Direct execution without smart features
      def direct_run(context: nil, input_context_variables: nil, stop_checker: nil)
        # DSL agents delegate directly to core agents which handle tracing
        execute(context, input_context_variables, stop_checker)
      end

      # === Tool Execution Configuration Query Methods ===
      # These methods are public to allow external access to configuration

      # Check if parameter validation is enabled
      #
      # @return [Boolean] true if validation is enabled
      # Temporarily disabled - ToolExecutionConfig removed
      def validation_enabled?
        true  # Default to enabled
        # self.class.tool_execution_config[:enable_validation]
      end

      # Check if execution logging is enabled
      #
      # @return [Boolean] true if logging is enabled
      # Temporarily disabled - ToolExecutionConfig removed
      def logging_enabled?
        true  # Default to enabled
        # self.class.tool_execution_config[:enable_logging]
      end

      # Check if metadata injection is enabled
      #
      # @return [Boolean] true if metadata is enabled
      # Temporarily disabled - ToolExecutionConfig removed
      def metadata_enabled?
        true  # Default to enabled
        # self.class.tool_execution_config[:enable_metadata]
      end

      # Check if argument logging is enabled
      #
      # @return [Boolean] true if argument logging is enabled
      # Temporarily disabled - ToolExecutionConfig removed
      def log_arguments?
        true  # Default to enabled
        # self.class.tool_execution_config[:log_arguments]
      end

      # Get the truncation length for log values
      #
      # @return [Integer] Truncation length for logs
      # Temporarily disabled - ToolExecutionConfig removed
      def truncate_logs_at
        100  # Default value
        # self.class.tool_execution_config[:truncate_logs]
      end

      private

      # === Tool Execution Interceptor Helper Methods ===

      # Determine if we should intercept this tool execution
      #
      # @param tool [Object] The tool instance
      # @return [Boolean] true if interception should occur
      def should_intercept_tool?(tool)
        return false unless tool

        # Don't double-intercept DSL tools that already have conveniences
        if tool.respond_to?(:dsl_wrapped?) && tool.dsl_wrapped?
          return false
        end

        # Check if tool execution features are enabled
        tool_execution_enabled?
      end

      # Check if tool execution interception is enabled via configuration
      #
      # @return [Boolean] true if any interception feature is enabled
      def tool_execution_enabled?
        validation_enabled? || logging_enabled? || metadata_enabled?
      end

      # Pre-execution phase: validation and logging
      #
      # @param tool [Object] The tool being executed
      # @param arguments [Hash] Arguments passed to the tool
      def perform_pre_execution(tool, arguments)
        # Validate parameters if enabled (from ToolValidation module)
        validate_tool_arguments(tool, arguments) if validation_enabled?

        # Logging from ToolLogging module
        log_tool_start(tool, arguments) if logging_enabled?
      end

      # Post-execution phase: logging and metadata
      #
      # @param tool [Object] The tool that was executed
      # @param result [Hash] The tool execution result
      # @param duration_ms [Float] Execution duration in milliseconds
      def perform_post_execution(tool, result, duration_ms)
        # Logging from ToolLogging module
        log_tool_end(tool, result, duration_ms) if logging_enabled?

        # Metadata injection from ToolMetadata module
        # Only inject metadata for Hash results when metadata is enabled
        if metadata_enabled? && result.is_a?(Hash)
          inject_metadata!(result, tool, duration_ms)
        end
      end

      # Handle tool execution errors
      #
      # @param tool [Object] The tool that raised an error
      # @param error [StandardError] The error that occurred
      def handle_tool_error(tool, error)
        # Error logging from ToolLogging module
        log_tool_error(tool, error) if logging_enabled?
      end

      # Extract tool name from various tool types
      #
      # @param tool [Object] The tool instance
      # @return [String] The tool's name
      def extract_tool_name(tool)
        if tool.respond_to?(:tool_name)
          tool.tool_name
        elsif tool.respond_to?(:name)
          tool.name
        elsif tool.is_a?(RAAF::FunctionTool)
          # FunctionTool stores name as instance variable
          tool.instance_variable_get(:@name) || "unknown_tool"
        else
          tool.class.name.split("::").last.underscore
        end
      end

      # === End Tool Execution Interceptor Helper Methods ===

      # Build context from parameter (backward compatibility)
      def build_context_from_param(context_param, debug = nil)
        # Only accept ContextVariables instances
        base_context = case context_param
        when RAAF::DSL::ContextVariables
          context_param.to_h
        else
          raise ArgumentError, "context must be RAAF::DSL::ContextVariables instance. Use RAAF::DSL::ContextVariables.new(your_hash) instead of passing raw hash."
        end
        
        # Apply agent's context defaults if they don't exist in provided context
        if self.class._context_config && self.class._context_config[:context_rules] && self.class._context_config[:context_rules][:defaults]
          defaults = self.class._context_config[:context_rules][:defaults]
          defaults.each do |key, value|
            base_context[key] ||= value.is_a?(Proc) ? value.call : value
          end
        end
        
        final_context = RAAF::DSL::ContextVariables.new(base_context, debug: debug)
        @context = final_context
        
        # NEW: Create dynamic methods for all context variables
        define_context_accessors(final_context.keys)
        
        final_context
      end
      
      # Build context automatically from keyword arguments
      def build_auto_context(params, debug = nil)
        require_relative "core/context_builder"
        
        log_debug "Building auto context for #{self.class.name}"
        
        rules = self.class._context_config[:context_rules] || {}
        builder = RAAF::DSL::ContextBuilder.new({}, debug: debug)
        
        # Ensure params has indifferent access for key checking throughout this method
        params_with_indifferent_access = params.is_a?(ActiveSupport::HashWithIndifferentAccess) ? 
                                          params : 
                                          params.with_indifferent_access
        
        # Validate required fields are provided
        if rules[:required]
          missing_required = rules[:required].select { |field| !params_with_indifferent_access.key?(field) }
          if missing_required.any?
            raise ArgumentError, "Missing required context fields: #{missing_required.inspect}"
          end
        end
        
        # Add provided parameters (with exclusion/inclusion rules for backward compatibility)
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
        
        # Add optional fields with defaults (new DSL)
        if rules[:optional]
          rules[:optional].each do |key, default_value|
            # Only set default if the key wasn't provided in params
            unless params_with_indifferent_access.key?(key)
              builder.with(key, default_value.is_a?(Proc) ? default_value.call : default_value)
            end
          end
        end
        
        # Add output fields as nil (new DSL)
        if rules[:output]
          rules[:output].each do |key|
            # Initialize output fields as nil to prevent NameError on access during agent execution
            # BUT only if not already provided in params to avoid overwriting existing data from pipeline context
            builder.with(key, nil) unless params_with_indifferent_access.key?(key)
          end
        end
        
        # Apply legacy default values for backward compatibility
        if rules[:defaults]
          rules[:defaults].each do |key, default_value|
            # Only set default if the key wasn't provided in params
            unless params_with_indifferent_access.key?(key)
              builder.with(key, default_value.is_a?(Proc) ? default_value.call : default_value)
            end
          end
        end
        
        # Make static context available to computed methods
        @context = builder.current_context
        
        # Add computed context values from build_*_context methods (legacy)
        add_computed_context(builder)
        
        # Add computed fields (new DSL) - after basic context is available
        if rules[:computed]
          rules[:computed].each do |field_name, method_name|
            # Only compute if the method exists on the agent
            if respond_to?(method_name, true)
              computed_value = send(method_name)
              builder.with(field_name, computed_value)
            else
              # Initialize as nil to prevent NameError, but log a warning
              builder.with(field_name, nil)
              log_warn "🤔 [#{self.class.name}] Computed method '#{method_name}' not found for field '#{field_name}'"
            end
          end
        end
        
        # Final build with all values
        final_context = builder.build
        @context = final_context
        
        log_debug "Final context built for #{self.class.name} with #{final_context.keys.size} keys"
        
        # NEW: Create dynamic methods for all context variables
        define_context_accessors(final_context.keys)
        
        final_context
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
      
      # Define dynamic getter and setter methods for context variables
      # This enables natural Ruby assignment syntax: results = value
      def define_context_accessors(context_keys)
        context_keys.each do |key|
          # Skip creating singleton accessor if instance method already exists
          # This prevents shadowing real methods like 'provider', 'agent_name', etc.
          if self.class.method_defined?(key) || self.class.private_method_defined?(key)
            next
          end

          # Remove any existing methods to avoid warnings (check if method exists first)
          begin
            singleton_class.remove_method(key) if singleton_class.method_defined?(key)
          rescue NameError
            # Method doesn't exist, which is fine
          end

          begin
            singleton_class.remove_method("#{key}=") if singleton_class.method_defined?("#{key}=")
          rescue NameError
            # Method doesn't exist, which is fine
          end

          # Define getter method
          define_singleton_method(key) do
            @context.get(key)
          end

          # Define setter method
          define_singleton_method("#{key}=") do |value|
            @context = @context.set(key, value)
            value
          end
        end

        # Track what we've defined for debugging
        @defined_context_keys = context_keys
      end
      
      # Setup provider instance based on agent configuration
      #
      # @return [Object, nil] Provider instance or nil if not configured
      #
      def setup_provider
        # Check if auto-detection is enabled (default: true)
        auto_detect = self.class.auto_detect_provider

        # Get explicit provider from configuration
        provider_name = self.class.provider

        # If no explicit provider and auto-detection enabled, detect from model
        if provider_name.nil? && auto_detect
          model_name = self.class.model
          provider_name = RAAF::ProviderRegistry.detect(model_name) if model_name

          if @debug_enabled && provider_name
            log_debug("Auto-detected provider",
                      model: model_name,
                      provider: provider_name,
                      category: :provider)
          end
        end

        # If we have a provider name, create the instance
        if provider_name
          provider_opts = self.class.provider_options

          begin
            RAAF::ProviderRegistry.create(provider_name, **provider_opts)
          rescue => e
            log_error("Failed to create provider",
                      provider: provider_name,
                      error: e.message,
                      category: :provider)
            nil
          end
        else
          nil  # No provider configured
        end
      end

      # Check if agent has any smart features configured
      def has_smart_features?
        self.class._retry_config.present? ||
        self.class._circuit_breaker_config.present? ||
        self.class._required_context_keys.present? ||
        self.class._validation_rules.present?
      end
      



      # Capture initial dialog state
      def capture_initial_dialog_state(span, run_context)
        # Capture context size and keys
        span.set_attribute("dialog.context_size", run_context.respond_to?(:size) ? run_context.size : run_context.keys.length)
        span.set_attribute("dialog.context_keys", run_context.respond_to?(:keys) ? run_context.keys : run_context.keys)

        # Redact sensitive context data
        safe_context = redact_sensitive_dialog_data(run_context.respond_to?(:to_h) ? run_context.to_h : run_context)
        span.set_attribute("dialog.initial_context", safe_context)
      end

      # Capture dialog components (prompts, instructions)
      def capture_dialog_components(span, openai_agent, user_prompt, run_context)
        # System prompt (instructions)
        system_prompt = openai_agent.instructions
        if system_prompt
          safe_system_prompt = redact_sensitive_content(system_prompt)
          span.set_attribute("dialog.system_prompt", safe_system_prompt)
          span.set_attribute("dialog.system_prompt_length", system_prompt.length)
        end

        # User prompt
        if user_prompt
          safe_user_prompt = redact_sensitive_content(user_prompt.to_s)
          span.set_attribute("dialog.user_prompt", safe_user_prompt)
          span.set_attribute("dialog.user_prompt_length", user_prompt.to_s.length)
        end

        # Prompt class info
        if self.class.prompt_class
          span.set_attribute("dialog.prompt_class", self.class.prompt_class.name)
        end
      end

      # Capture final dialog state from LLM execution
      def capture_final_dialog_state(span, run_result)
        if run_result.respond_to?(:messages) && run_result.messages
          # Capture conversation messages
          messages = run_result.messages.map do |msg|
            {
              role: msg[:role],
              content: redact_sensitive_content(msg[:content] || ""),
              timestamp: msg[:timestamp] || Time.now.utc.iso8601
            }
          end
          span.set_attribute("dialog.messages", messages)
          span.set_attribute("dialog.message_count", messages.length)

          # Tool calls if present
          tool_calls = extract_tool_calls_from_messages(messages)
          if tool_calls.any?
            span.set_attribute("dialog.tool_calls", tool_calls)
            span.set_attribute("dialog.tool_call_count", tool_calls.length)
          end
        end

        # Token usage
        if run_result.respond_to?(:usage) && run_result.usage
          usage = run_result.usage
          span.set_attribute("dialog.total_tokens", {
            prompt_tokens: usage[:prompt_tokens] || 0,
            completion_tokens: usage[:completion_tokens] || 0,
            total_tokens: usage[:total_tokens] || 0
          })
        end
      end

      # Capture final agent result
      def capture_agent_result(span, result)
        # Result metadata
        span.set_attribute("agent.output_size", calculate_output_size(result))

        # Safe result (redacted)
        safe_result = redact_sensitive_dialog_data(result)
        span.set_attribute("dialog.final_result", safe_result)

        # Success indicators
        span.set_attribute("agent.workflow_status", result[:workflow_status]) if result[:workflow_status]
        if result[:error]
          span.set_attribute("agent.error_message", result[:error])
        end
      end

      # Calculate input data size
      def calculate_input_size
        return 0 unless @context
        context_data = @context.respond_to?(:to_h) ? @context.to_h : @context
        context_data.to_s.length rescue 0
      end

      # Calculate output data size
      def calculate_output_size(result)
        return 0 unless result
        result.to_s.length rescue 0
      end

      # Extract tool calls from conversation messages
      def extract_tool_calls_from_messages(messages)
        tool_calls = []
        messages.each do |msg|
          if msg[:role] == "assistant" && msg[:content]
            # Look for function call patterns in content
            # This is a simplified extraction - real implementation would depend on message format
            content = msg[:content].to_s
            if content.include?("function_call") || content.include?("tool_call")
              tool_calls << {
                message_content: content[0..200], # First 200 chars
                timestamp: msg[:timestamp]
              }
            end
          end
        end
        tool_calls
      end

      # Redact sensitive content from dialog
      def redact_sensitive_dialog_data(data)
        return data unless data.is_a?(Hash)

        redacted = {}
        data.each do |key, value|
          key_str = key.to_s.downcase
          if sensitive_dialog_key?(key_str)
            redacted[key] = "[REDACTED]"
          elsif value.is_a?(Hash)
            redacted[key] = redact_sensitive_dialog_data(value)
          elsif value.is_a?(Array) && value.any? { |v| v.is_a?(Hash) }
            redacted[key] = value.map { |v| v.is_a?(Hash) ? redact_sensitive_dialog_data(v) : v }
          else
            redacted[key] = value
          end
        end
        redacted
      end

      # Redact sensitive content from strings
      def redact_sensitive_content(content)
        return content unless content.is_a?(String)

        # Redact common sensitive patterns
        redacted = content.dup

        # API keys, tokens
        redacted.gsub!(/\b[A-Za-z0-9]{32,}\b/, "[REDACTED_TOKEN]")

        # Email addresses
        redacted.gsub!(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, "[REDACTED_EMAIL]")

        # Phone numbers (simple pattern)
        redacted.gsub!(/\b\d{3}-\d{3}-\d{4}\b/, "[REDACTED_PHONE]")

        # Credit card numbers (simple pattern)
        redacted.gsub!(/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/, "[REDACTED_CC]")

        redacted
      end

      # Check if dialog key contains sensitive information
      def sensitive_dialog_key?(key)
        sensitive_patterns = %w[
          password token secret key api_key auth credential
          email phone ssn social_security credit_card
          private_key access_token refresh_token
        ]
        sensitive_patterns.any? { |pattern| key.include?(pattern) }
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

      def setup_context_configuration
        # Configuration is already set at class level via DSL
        # No need to apply it again at instance level
      end

      def setup_logging_and_metrics
        # Note: log_events and track_metrics DSL methods were removed as they were not implemented.
      end


      # Check if agent should execute based on defined conditions
      def should_execute?(context, previous_result)
        # Skip execution conditions during pipeline validation
        return true if @validation_mode
        return true unless self.class._execution_conditions
        
        self.class._execution_conditions.evaluate(context, previous_result)
      end


      # Create a span for skipped agents to make them visible in traces
      def create_skipped_span(skip_reason, result_data, context)
        agent_name = self.class._context_config&.dig(:name) || self.class.name

        # Get the tracer following TracingRegistry priority hierarchy
        tracer = get_tracer_for_skipped_span

        if tracer
          # Create a span for the skipped agent
          tracer.agent_span(agent_name) do |span|
            # Add attributes to indicate this agent was skipped
            span.set_attribute("agent.skipped", true)
            span.set_attribute("agent.skip_reason", skip_reason)
            span.set_attribute("agent.name", agent_name)
            span.set_attribute("agent.class", self.class.name)

            # Add context information for debugging
            if context
              available_keys = context.respond_to?(:keys) ? context.keys : []
              span.set_attribute("agent.available_context_keys", available_keys.join(", "))
            end

            # Add any required context that might be missing
            if self.class._required_context_keys && context
              missing_keys = self.class._required_context_keys.reject do |key|
                context.respond_to?(:has?) ? context.has?(key) : context.key?(key)
              end
              if missing_keys.any?
                span.set_attribute("agent.missing_required_keys", missing_keys.join(", "))
              end
            end

            # Log the skip event
            log_info "⏭️ [#{agent_name}] Created span for skipped agent: #{skip_reason}"
          end
        else
          # Fallback: just log if no tracer available
          log_info "⏭️ [#{agent_name}] Skipped (no tracer): #{skip_reason}"
        end

        # Return the result data
        result_data
      end

      def extract_result_data(results)
        # If results is already a Hash with structured data matching agent's output fields, return it
        if results.is_a?(Hash) && !results.empty?
          # Check if the hash contains any of the declared output fields for this agent
          if self.class.respond_to?(:provided_fields) && self.class.provided_fields
            output_fields = self.class.provided_fields
            # Check if any of the output fields exist in results (either as symbol or string)
            if output_fields.any? { |field| results.key?(field.to_sym) || results.key?(field.to_s) }
              # Don't wrap in 'data' key - merge directly to avoid double-wrapping
              return ActiveSupport::HashWithIndifferentAccess.new({ success: true }.merge(results))
            end
          end
        end

        # Handle RunResult objects from RAAF Core
        if results.respond_to?(:final_output)
          content = results.final_output
          return parse_ai_response(content) if content && !content.to_s.empty?
        end

        if results.respond_to?(:messages)
          messages = results.messages
          if messages && messages.respond_to?(:any?) && messages.any?
            last_message = messages.last
            content = last_message[:content] || last_message["content"]
            return parse_ai_response(content) if content
          end
        end

        # Handle Result objects with .data
        if results.respond_to?(:data)
          return results.data if results.data
        end

        # Fallback: if results is a RunResult with empty messages, try to extract from raw response
        if defined?(RAAF::RunResult) && results.is_a?(RAAF::RunResult) && results.respond_to?(:to_h)
          result_hash = results.to_h
          # Try to get content from the hash representation
          if result_hash[:messages]&.any?
            content = result_hash[:messages].last[:content]
            return parse_ai_response(content) if content
          end
        end

        log_warn "🤔 [#{self.class.name}] Could not extract result data from #{results.class.name}"
        log_debug "Result details: #{results.inspect[0..500]}" if @debug_enabled
        { success: false, error: "Could not extract result data", transformation_metadata: {} }
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
        
        # Since core Agent now handles JSON repair and schema validation automatically
        # when configured, we can simplify this to basic JSON parsing with graceful fallback
        begin
          # Use RAAF::Utils.parse_json to get HashWithIndifferentAccess with nested conversion
          parsed = RAAF::Utils.parse_json(content)
          { success: true, data: parsed }
        rescue JSON::ParserError => e
          log_debug "ℹ️ [#{self.class.name}] Content is not JSON, returning as-is: #{e.message}"
          # Return content as-is since core Agent handles repair when needed
          { success: true, data: content }
        end
      end

      # Note: fault_tolerant_parse functionality has been moved to core Agent
      # The core Agent now handles JSON repair and schema validation automatically
      # when json_repair, normalize_keys, and validation_mode options are set

      # Log unparseable content for debugging and analysis
      def log_to_dead_letter(content, errors)
        log_error "💀 [DEAD_LETTER] #{self.class.name} - Failed to parse AI response"
        log_error "Content: #{content}"
        log_error "Errors: #{errors.join(', ')}"
        
        # In production, you might want to store this in a database or file
        # DeadLetterQueue.create!(
        #   agent_class: self.class.name,
        #   content: content,
        #   errors: errors,
        #   timestamp: Time.current
        # )
      end


      # Generate automatic transformations for output fields when none are configured
      def generate_auto_transformations_for_output_fields(base_result)
        # Check if we have output fields defined but no explicit transformations
        return base_result unless self.class.respond_to?(:provided_fields)

        output_fields = self.class.provided_fields
        return base_result if output_fields.nil? || output_fields.empty?

        # Extract data from the appropriate location in base_result
        source_data = base_result[:parsed_output] || base_result[:data] || base_result
        return base_result unless source_data.respond_to?(:[])

        log_debug "Auto-generating transformations for output fields: #{output_fields.inspect}"

        # Create result with only declared output fields in :results
        result = base_result.dup
        filtered_results = {}

        output_fields.each do |field_name|
          field_key = field_name.to_s
          field_symbol = field_name.to_sym

          # Try both string and symbol keys to extract the field
          field_value = source_data[field_key] || source_data[field_symbol]

          if field_value
            filtered_results[field_symbol] = field_value
            log_debug "Auto-extracted field #{field_symbol}: #{field_value.class}"
          else
            log_debug "Output field #{field_symbol} not found in AI response"
          end
        end

        # Update the :message key with only the declared output fields
        result[:message] = filtered_results
        result
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

      # Collect DSL-specific metadata for tracing spans
      #
      # @return [Hash] DSL metadata to include in agent spans
      def collect_dsl_metadata
        metadata = {}

        # Retry configuration
        if self.class._retry_config
          retry_config = self.class._retry_config
          metadata["retry_max_attempts"] = retry_config[:max_attempts] if retry_config[:max_attempts]
          metadata["retry_delay"] = retry_config[:delay] if retry_config[:delay]
          metadata["retry_backoff"] = retry_config[:backoff] if retry_config[:backoff]
          metadata["retry_enabled"] = "true"
        else
          metadata["retry_enabled"] = "false"
        end

        # Circuit breaker state
        if self.class._circuit_breaker_config
          cb_config = self.class._circuit_breaker_config
          metadata["circuit_breaker_enabled"] = "true"
          metadata["circuit_breaker_threshold"] = cb_config[:failure_threshold] if cb_config[:failure_threshold]
          metadata["circuit_breaker_timeout"] = cb_config[:timeout] if cb_config[:timeout]
        else
          metadata["circuit_breaker_enabled"] = "false"
        end

        # Timeout settings
        if self.class._context_config[:http_timeout]
          metadata["http_timeout"] = self.class._context_config[:http_timeout].to_s
        end

        # Execution conditions
        if self.class._execution_conditions
          metadata["execution_conditions"] = "true"
          metadata["conditions_count"] = self.class._execution_conditions.length.to_s
        else
          metadata["execution_conditions"] = "false"
        end

        # Prompt information
        prompt_spec = determine_prompt_spec
        if prompt_spec
          case prompt_spec
          when Class
            metadata["prompt_type"] = "class"
            metadata["prompt_class"] = prompt_spec.name
          when String, Symbol
            metadata["prompt_type"] = "file"
            metadata["prompt_file"] = prompt_spec.to_s
          end
        else
          metadata["prompt_type"] = "inline"
        end

        # Schema validation mode
        schema_def = build_schema
        if schema_def && schema_def.is_a?(Hash) && schema_def[:config]
          metadata["validation_mode"] = schema_def[:config][:mode].to_s
        end

        # Temperature setting
        if self.class._context_config[:temperature]
          metadata["temperature"] = self.class._context_config[:temperature].to_s
        end

        metadata
      end

      # Methods from Base class
      def create_openai_agent_instance
        # Build handoffs if configured
        handoff_agents = handoffs

        # Get schema configuration to determine JSON repair options
        schema_def = build_schema
        validation_mode = schema_def && schema_def.is_a?(Hash) && schema_def[:config] ?
                         schema_def[:config][:mode] : :strict

        # Build base configuration
        agent_config = {
          name: agent_name,
          instructions: build_instructions,
          model: model_name,
          max_turns: max_turns,
          max_tokens: max_tokens,
          timeout: self.class._context_config[:timeout],
          temperature: temperature,
          top_p: top_p,
          frequency_penalty: frequency_penalty,
          presence_penalty: presence_penalty,
          stop: stop,
          user: user,
          parallel_tool_calls: parallel_tool_calls,
          # Pass JSON repair and schema validation options to core Agent
          json_repair: [:tolerant, :partial].include?(validation_mode),
          normalize_keys: [:tolerant, :partial].include?(validation_mode),
          validation_mode: validation_mode
        }

        # Add model_settings with reasoning_effort if configured
        if (effort = self.class._context_config[:reasoning_effort])
          agent_config[:model_settings] = RAAF::ModelSettings.new(
            reasoning: { reasoning_effort: effort }
          )
        end

        # Add response format if structured output is requested
        if (format = response_format)
          agent_config[:response_format] = format
        end

        # Add tools if configured
        current_tools = tools

        if current_tools.any?
          agent_config[:tools] = current_tools
        end

        # Add handoffs if configured
        if handoff_agents.any?
          agent_config[:handoffs] = handoff_agents
        end

        # Add hooks if configured (bridge DSL hooks to Core execution)
        hooks_config = combined_hooks_config
        if hooks_config
          require_relative 'hooks/hooks_adapter'
          agent_config[:hooks] = RAAF::DSL::Hooks::HooksAdapter.new(hooks_config, self)
        end

        # Collect DSL metadata for tracing
        agent_config[:trace_metadata] = collect_dsl_metadata

        # Pass parent component for tracing hierarchy
        agent_config[:parent_component] = @parent_component if @parent_component

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

      def transform_ai_result(run_result, run_context)
        # Extract parsed output from messages (works for any AI provider)
        parsed_output = extract_final_output(run_result)

        # Build result in expected DSL format
        raaf_result = {
          workflow_status: "completed",
          success: true,
          results: parsed_output || {},  # AutoMerge expects this to be the parsed data hash, not the raw runner
          parsed_output: parsed_output,  # The parsed AI response
          context_variables: run_context,
          summary: build_result_summary(parsed_output)
        }

        # Preserve metadata from provider response (generic for all providers)
        # This is critical for passing citations and search results through the pipeline
        # The metadata is stored directly in run_result.metadata (populated by TurnExecutor)
        if run_result.respond_to?(:metadata) && run_result.metadata.is_a?(Hash) && run_result.metadata.any?
          # Store the entire metadata hash (includes search_results, citations, etc from provider)
          # This metadata was extracted and stored in context by TurnExecutor
          raaf_result[:metadata] = run_result.metadata
        end

        raaf_result
      end

      def extract_final_output(run_result)
        return nil unless run_result.respond_to?(:messages)

        # Find last assistant message
        last_assistant_message = run_result.messages.reverse.find { |m| m[:role] == "assistant" }
        return nil unless last_assistant_message

        content = last_assistant_message[:content]

        # Parse JSON strings and ensure HashWithIndifferentAccess for all hash data
        if content.is_a?(String)
          # Try to parse as JSON if it looks like JSON
          if content.strip.match?(/\A[\[{].*[\]}]\z/m)
            begin
              # Use Utils.parse_json which returns HashWithIndifferentAccess
              content = RAAF::Utils.parse_json(content)
              log_debug "Parsed JSON content to HashWithIndifferentAccess",
                        content_type: content.class.name,
                        keys_sample: content.is_a?(Hash) ? content.keys.first(3).inspect : nil
            rescue JSON::ParserError => e
              log_debug "Content looks like JSON but failed to parse: #{e.message}"
              # Return as-is if parsing fails
            end
          end
        elsif content.is_a?(Hash)
          # Ensure existing hashes also have indifferent access
          content = RAAF::Utils.indifferent_access(content)
          log_debug "Converted Hash to HashWithIndifferentAccess",
                    content_type: content.class.name
        elsif content.is_a?(Array)
          # For arrays, convert any nested hashes to indifferent access
          content = content.map { |item|
            item.is_a?(Hash) ? RAAF::Utils.indifferent_access(item) : item
          }
        end

        content
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

        # Debug: Show transformation inputs
        log_debug("apply_result_transformations", category: :agents, agent_name: agent_name)
        log_debug("Base result keys", category: :agents, 
                  keys: base_result.keys.inspect) if base_result.respond_to?(:keys)
        log_debug("Base result type", category: :agents, type: base_result.class.name)
        
        transformations = self.class._result_transformations
        log_debug("Transformations to apply", category: :agents, 
                  transformations: transformations.keys.inspect)
        
        # For AI results, the parsed output is in :parsed_output
        # For other results, it's in :data
        input_data = base_result[:parsed_output] || base_result[:data] || base_result
        
        log_debug "Processing transformation input data: #{input_data.class}"

        transformed_result = {}
        metadata = {}

        transformations.each do |field_name, field_config|
          begin
            # Extract source value
            source_value = extract_field_value(input_data, field_config)

            # Apply transformations and validations
            transformed_value = transform_field_value(source_value, field_config, input_data)

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

        # Merge transformed fields into the original result structure
        # This preserves all original fields (like workflow_status, results, etc.)
        # while adding the new transformed fields
        final_result = base_result.merge(transformed_result).merge(
          transformation_metadata: metadata
        )
        
        # Generic transformation logging
        log_debug "Transformation completed for #{agent_name} with #{final_result.keys.size} result keys"
        
        final_result
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

      def transform_field_value(source_value, field_config, raw_data = nil)
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
          transform = field_config[:transform]
          value = case transform
                  when Proc, Method
                    # Callable objects (Proc, lambda, Method) - check arity for parameter count
                    if transform.arity == -3 # 2 required params + **args (most flexible)
                      transform.call(value, raw_data)
                    elsif transform.arity == 2 || transform.arity == -2 # Exactly 2 params or 1 required + 1 optional
                      transform.call(value, raw_data)
                    else
                      # Backward compatibility: single parameter
                      transform.call(value)
                    end
                  when Symbol
                    # Symbol method name - call as instance method with arity checking
                    if respond_to?(transform, true)
                      method_obj = method(transform)
                      if method_obj.arity == -3 # 2 required params + **args (most flexible)
                        send(transform, value, raw_data)
                      elsif method_obj.arity == 2 || method_obj.arity == -2 # Exactly 2 params or 1 required + 1 optional
                        send(transform, value, raw_data)
                      else
                        # Backward compatibility: single parameter
                        send(transform, value)
                      end
                    else
                      raise ArgumentError, "Transform method '#{transform}' not found on #{self.class.name}"
                    end
                  else
                    raise ArgumentError, "Transform must be a Proc, Method, or Symbol, got #{transform.class}"
                  end
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


      # Handoff building method (consolidated from AgentDsl)
      def build_handoffs_from_config
        handoff_context_configs = self.class._context_config[:handoff_agents] || []
        handoff_context_configs.map do |handoff_config|
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

      # Context wrapper for run_if blocks that provides automatic variable access
      # 
      # This class wraps the context and previous result, providing method_missing
      # for automatic context variable access similar to prompt classes.
      #
      # @example Automatic context access in run_if blocks
      #   run_if do
      #     companies.present? && analysis_depth == "deep"
      #   end
      #
      class ConditionContext
        include RAAF::DSL::ContextAccess
        
        attr_reader :previous_result
        
        def initialize(context, previous_result = nil)
          @context = ensure_context_variables(context)
          @previous_result = previous_result
        end
        
        # Convenience methods for previous result checks
        def previous_succeeded?
          @previous_result && @previous_result[:success] != false
        end
        
        def previous_failed?
          @previous_result && @previous_result[:success] == false
        end
        
        def previous_result_has?(*keys)
          return false unless @previous_result.is_a?(Hash)
          keys.all? { |key| @previous_result.key?(key) && @previous_result[key] }
        end
        
        # Access to the raw context for compatibility with existing DSL methods
        def context
          @context
        end
      end

      # Execution conditions for conditional agent execution
      # 
      # Supports two execution modes:
      # 1. Explicit DSL mode (legacy): Uses context_has, context_value, etc.
      # 2. Automatic context mode (new): Direct variable access with method_missing
      #
      # @example Explicit DSL mode
      #   run_if do
      #     context_has :companies
      #     context_value :analysis_depth, equals: "deep"
      #   end
      #
      # @example Automatic context mode  
      #   run_if do
      #     companies.present? && analysis_depth == "deep"
      #   end
      #
      class ExecutionConditions
        def initialize(negate: false, &block)
          @conditions = []
          @negate = negate
          @block = block
          @use_automatic_mode = false
          
          # Try to detect if block uses explicit DSL methods
          if block_given?
            # First try explicit DSL mode
            begin
              instance_eval(&block)
              @use_automatic_mode = false
            rescue NoMethodError, NameError => e
              # If we get NoMethodError or NameError during explicit DSL evaluation,
              # this likely means the block uses automatic context access
              @conditions.clear  # Clear any partial conditions
              @use_automatic_mode = true
            end
          end
        end

        def evaluate(context, previous_result)
          if @use_automatic_mode
            # Use automatic context access mode
            condition_context = ConditionContext.new(context, previous_result)
            begin
              result = condition_context.instance_eval(&@block)
              # Convert result to boolean
              result = !!result
            rescue => e
              # If automatic mode fails, fall back to false
              Rails.logger&.warn("Execution condition evaluation failed: #{e.message}")
              result = false
            end
          else
            # Use explicit DSL mode
            result = @conditions.empty? || @conditions.all? { |condition| condition.call(context, previous_result) }
          end
          
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

      # Create a skipped span when agent execution is skipped
      def create_skipped_span(skip_reason, skip_result, resolved_context)
        tracer = get_tracer_for_skipped_span
        return skip_result unless tracer

        # Create a short-lived span to make the skip visible in traces
        # Let tracer determine parent automatically (no manual parent passing)
        tracer.agent_span(agent_name) do |span|

          # Mark as skipped with specific attributes
          span.set_attribute("agent.skipped", true)
          span.set_attribute("agent.skip_reason", skip_reason)
          span.set_attribute("agent.class", self.class.name)
          span.set_attribute("agent.name", agent_name)

          # Add debugging info about available vs required context
          if resolved_context
            span.set_attribute("agent.available_context_keys", resolved_context.keys)
            span.set_attribute("agent.context_size", resolved_context.keys.length)
          end

          # Set span status to indicate this was intentionally skipped (not an error)
          span.set_status(:ok)
          span.set_attribute("agent.success", false)
          span.set_attribute("agent.workflow_status", "skipped")

          # Add event to show when skip occurred
          span.add_event("agent.execution_skipped", attributes: {
            reason: skip_reason,
            timestamp: Time.now.utc.iso8601
          })

          # Return the skip result
          skip_result
        end
      end

      # Get tracer for skipped span creation following TracingRegistry priority hierarchy:
      # 1. RAAF::Tracing::TracingRegistry.current_tracer
      # 2. RAAF::Tracing::TraceProvider.tracer (existing behavior)
      # 3. nil (if nothing available)
      def get_tracer_for_skipped_span
        # Try TracingRegistry first if available
        if defined?(RAAF::Tracing::TracingRegistry)
          begin
            current_tracer = RAAF::Tracing::TracingRegistry.current_tracer
            # Don't use NoOpTracer for skipped spans - we want visibility
            unless defined?(RAAF::Tracing::NoOpTracer) && current_tracer.is_a?(RAAF::Tracing::NoOpTracer)
              return current_tracer
            end
          rescue StandardError
            # Fall through to TraceProvider if registry access fails
          end
        end

        # Fall back to existing TraceProvider behavior
        begin
          RAAF::Tracing::TraceProvider.tracer
        rescue NameError, NoMethodError
          # Final fallback if TraceProvider is not available
          nil
        end
      end

      # Automatically flush RAAF traces after agent execution
      # This ensures traces are persisted to database for all agent runs
      def auto_flush_raaf_traces
        return unless defined?(RAAF::Tracing::TraceProvider)

        provider = RAAF::Tracing::TraceProvider.instance
        provider.processors.each do |processor|
          processor.force_flush if processor.respond_to?(:force_flush)
        end

        RAAF.logger.debug "🔍 [RAAF Auto-Flush] Flushed traces after #{self.class.name} completion"
      rescue => e
        RAAF.logger.error "❌ [RAAF Auto-Flush] Failed to flush traces: #{e.message}"
      end
    end
  end
end