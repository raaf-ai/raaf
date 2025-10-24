# frozen_string_literal: true

require "set"
require_relative "../pipeline_dsl"
require_relative "../context_flow_tracker"
require_relative "../pipelineable"
require_relative "../context_access"
require_relative "../hooks/hook_context"
require_relative "../agent"
require_relative "pipeline_failure_error"
require_relative "../pipeline_streaming_integration"

module RAAF
  # New Pipeline base class for elegant DSL
  # Supports agent chaining with >> and | operators
  #
  # DSL Design Philosophy:
  # - Declarative over imperative: Define flow structure, not execution steps
  # - Context-aware: Automatic field validation and propagation
  # - Ruby-idiomatic: Uses familiar patterns (context, defaults, readers)
  #
  # Usage Pattern:
  #   class MyPipeline < RAAF::Pipeline
  #     flow Agent1 >> Agent2 >> (Agent3 | Agent4) >> Agent5
  #     context { default :optional_field, "default_value" }
  #   end
  class Pipeline
    include RAAF::DSL::Pipelineable
    include RAAF::DSL::ContextAccess
    include RAAF::DSL::ContextConfiguration
    include RAAF::DSL::Hooks::HookContext
    prepend RAAF::DSL::PipelineStreamingIntegration

    # Include Traceable module for proper span hierarchy
    include RAAF::Tracing::Traceable
    trace_as :pipeline

    attr_reader :current_span

    class << self
      attr_reader :flow_chain, :on_end_block, :pipeline_schema_block
      attr_accessor :skip_validation

      # Traceable component type
      def trace_component_type
        :pipeline
      end
      
      # Define the agent execution flow using DSL operators
      # Stores the chained/parallel agent structure for execution
      def flow(chain)
        @flow_chain = chain
        # Keep thread-local variable available for ChainedAgent field validation
        # Thread.current[:raaf_pipeline_context_fields] = nil  # Removed: This was clearing context fields too early
      end
      
      # Define shared schema for all agents in the pipeline using field DSL
      # This schema will be automatically injected into agents
      # Uses the same SchemaBuilder class that agents use
      def pipeline_schema(&block)
        if block_given?
          # Use the same SchemaBuilder class that agents use to ensure consistency
          builder = RAAF::DSL::Agent::SchemaBuilder.new(&block)
          built_schema = builder.build
          
          # Store as a proc that returns the complete built schema (schema + config)
          @pipeline_schema_block = proc { built_schema }
        end
        @pipeline_schema_block
      end
      
      # Define on_end hook using DSL block
      # Executes after all agents complete with the final result
      def on_end(&block)
        if block_given?
          @on_end_block = block
        end
        @on_end_block
      end
      
      # Context DSL method provided by ContextConfiguration module
      # Override to add pipeline-specific behavior (thread local variable)
      #
      # THREAD SAFETY NOTE (LOW PRIORITY):
      # Uses Thread.current for pipeline context fields during class definition only.
      # This is SAFE because:
      # - Only used at class definition time (not runtime)
      # - Data is consumed immediately by flow() DSL during same thread
      # - Not accessed by background jobs or different threads
      # - Cleared after flow() completes
      #
      # Unlike the fixed issues (_tools_config, _context_config), this does NOT
      # cause background job failures because it's transient class definition data.
      def context(&block)
        super(&block)  # Call the ContextConfiguration module's method

        # Make context fields available immediately for flow definition
        Thread.current[:raaf_pipeline_context_fields] = context_fields if block_given?
        _context_config[:context_rules] || {}
      end
      
      # Backward compatibility method
      def context_config
        _context_config[:context_rules] || {}
      end
      
      # Get required fields from context configuration - now uses ContextConfiguration module
      # This method delegates to the module's implementation
      
      # Get all fields declared in context (both required and optional)
      # These are the fields that will be preserved through the pipeline
      def context_fields
        context_rules = _context_config[:context_rules] || {}
        requirements = context_rules[:required] || []
        defaults = context_rules[:optional] || {}
        outputs = context_rules[:output] || []
        
        # All context fields are preserved through the pipeline
        (requirements + defaults.keys + outputs).uniq
      end
      
      # Disable validation for this pipeline
      def skip_validation!
        @skip_validation = true
      end
      
      # Enable validation (default)
      def enable_validation!
        @skip_validation = false
      end
    end
    
    # Initialize a pipeline with flexible context options
    #
    # Supports the same flexible API as RAAF agents for consistency:
    # 1. With context hash: Pipeline.new(context: { key: value })
    # 2. With keyword args: Pipeline.new(key: value, key2: value2)
    # 3. Mixed: Pipeline.new(context: base_context, extra_key: value)
    #
    # @param context [Hash, nil] Optional context hash (like agents)
    # @param tracer [RAAF::Tracing::SpanTracer, nil] Optional tracer for span creation
    # @param provided_context [Hash] Additional context as keyword arguments
    def initialize(context: nil, tracer: nil, **provided_context)
      # Support both context: hash and direct keyword arguments like agents do
      if context
        # Context provided explicitly (like agents)
        @context = build_context_from_param(context).merge(provided_context)
      else
        # Use keyword arguments as context
        @context = build_initial_context(provided_context)
      end

      @flow = self.class.flow_chain
      @tracer = tracer || get_default_tracer
      # Add pipeline instance to context - now works with ContextVariables
      @context = @context.set(:pipeline_instance, self) if @context.respond_to?(:set)
      validate_initial_context!
    end
    
    # Access the pipeline schema for agents
    def pipeline_schema
      self.class.pipeline_schema_block
    end
    
    # Validate all agents in the pipeline with context flow tracking
    def validate_pipeline!
      errors = []
      
      # First, provide pipeline context fields to the flow chain for validation
      # This ensures ChainedAgent knows about all pipeline-level context fields
      # Single agents don't need this, only ChainedAgent/ParallelAgents do
      if @flow.respond_to?(:validate_with_pipeline_context)
        @flow.validate_with_pipeline_context(self.class.context_fields)
      end
      
      # Track context as it flows through the pipeline
      context_hash = @context.respond_to?(:to_h) ? @context.to_h : @context
      tracker = RAAF::DSL::ContextFlowTracker.new(context_hash)
      
      # Validate the entire flow
      validate_flow_with_tracking(@flow, tracker, errors)
      
      if errors.any?
        error_message = "Pipeline validation failed! Context errors detected:\n\n"
        errors.each do |error|
          error_message += "Stage #{error[:stage_number]}: #{error[:stage]}\n"
          error_message += "   Error: #{error[:message]}\n"
          error_message += "   Context at this stage: #{error[:available_context].inspect}\n"
          
          if error[:missing_variables]
            error_message += "   Missing: #{error[:missing_variables].inspect}\n"
          end
          
          error_message += "\n"
        end
        
        # Add summary
        error_message += "Context Flow Summary:\n"
        summary = tracker.summary
        error_message += "  Initial context: #{summary[:initial_context].inspect}\n"
        error_message += "  Final context: #{summary[:final_context].inspect}\n"
        error_message += "  Fields added during pipeline: #{summary[:fields_added].inspect}\n"
        
        raise RAAF::DSL::Error, error_message
      end
      
      if defined?(RAAF::Logger) && self.respond_to?(:log_info)
        log_info "Pipeline validation successful", 
                 stages: tracker.stage_number,
                 initial_context: tracker.summary[:initial_context],
                 final_context: tracker.summary[:final_context]
      end
      
      true
    end

    def run
      # Use Traceable module for proper span management (always available)
      with_tracing(:run) do
        execute_pipeline_logic
      end
    end

    private

    # Core pipeline execution logic (used by both traced and untraced execution)
    def execute_pipeline_logic
      # Initialize result collection for auto-merge
      @agent_results = []

      # Validate pipeline before execution (enabled by default)
      unless self.class.skip_validation
        validate_pipeline!
      end

      begin
        # Update @context with accumulated data from agents
        @context = execute_chain(@flow, @context)

        # Auto-merge all agent results intelligently
        merged_result = auto_merge_results(@agent_results)

        # Execute on_end hook if defined and capture modified result
        if self.class.on_end_block
          merged_result = execute_callback_with_parameters(merged_result, &self.class.on_end_block)
        end

        # Ensure success flag is present
        merged_result[:success] = true unless merged_result.key?(:success)

        # Sanitize the result to ensure it's serializable and free of circular references
        # This converts ActiveRecord objects to plain hashes and maintains HashWithIndifferentAccess
        sanitize_result(merged_result)

      rescue RAAF::DSL::PipelineDSL::PipelineFailureError => e
        # Pipeline failed - return structured error result
        RAAF.logger.error "Pipeline #{pipeline_name} failed at agent '#{e.agent_name}': #{e.error_message}"

        error_result = ActiveSupport::HashWithIndifferentAccess.new({
          success: false,
          error: e.error_message,
          error_type: e.error_type || "pipeline_failure",
          failed_at: e.agent_name,
          pipeline: pipeline_name,
          full_error_details: e.full_result
        })

        sanitize_result(error_result)
      end
    end

    # Get pipeline name for span creation
    def pipeline_name
      self.class.name || "UnknownPipeline"
    end


    # Generate flow structure description
    def flow_structure_description(flow)
      case flow
      when DSL::PipelineDSL::ChainedAgent
        "#{agent_name(flow.first)} >> #{flow_structure_description(flow.second)}"
      when DSL::PipelineDSL::ParallelAgents
        agents = flow.agents.map { |a| agent_name(a) }
        "(#{agents.join(' | ')})"
      when DSL::PipelineDSL::ConfiguredAgent, DSL::PipelineDSL::RemappedAgent
        agent_name(flow.agent_class)
      when Class
        flow.name || flow.to_s
      else
        flow.to_s
      end
    end

    # Count total agents in flow
    def count_agents_in_flow(flow)
      case flow
      when DSL::PipelineDSL::ChainedAgent
        count_agents_in_flow(flow.first) + count_agents_in_flow(flow.second)
      when DSL::PipelineDSL::ParallelAgents
        flow.agents.length
      when DSL::PipelineDSL::ConfiguredAgent, DSL::PipelineDSL::RemappedAgent, Class
        1
      else
        1
      end
    end

    # Detect execution mode (sequential, parallel, mixed)
    def detect_execution_mode(flow)
      has_sequential = has_chained_agents?(flow)
      has_parallel = has_parallel_agents?(flow)

      if has_sequential && has_parallel
        "mixed"
      elsif has_parallel
        "parallel"
      else
        "sequential"
      end
    end

    # Check if flow has chained agents (sequential)
    def has_chained_agents?(flow)
      case flow
      when DSL::PipelineDSL::ChainedAgent
        true
      when DSL::PipelineDSL::ParallelAgents
        flow.agents.any? { |a| has_chained_agents?(a) }
      else
        false
      end
    end

    # Check if flow has parallel agents
    def has_parallel_agents?(flow)
      case flow
      when DSL::PipelineDSL::ParallelAgents
        true
      when DSL::PipelineDSL::ChainedAgent
        has_parallel_agents?(flow.first) || has_parallel_agents?(flow.second)
      else
        false
      end
    end

    # Get agent name from flow element
    def agent_name(agent)
      case agent
      when Class
        agent.name || agent.to_s
      when DSL::PipelineDSL::ConfiguredAgent, DSL::PipelineDSL::RemappedAgent
        agent.agent_class.name || agent.agent_class.to_s
      else
        agent.to_s
      end
    end

    # Redact sensitive data from context/results
    def redact_sensitive_data(data)
      return data unless data.is_a?(Hash)

      redacted = {}
      data.each do |key, value|
        key_str = key.to_s.downcase
        if sensitive_key?(key_str)
          redacted[key] = "[REDACTED]"
        elsif value.is_a?(Hash)
          redacted[key] = redact_sensitive_data(value)
        elsif value.is_a?(Array) && value.any? { |v| v.is_a?(Hash) }
          redacted[key] = value.map { |v| v.is_a?(Hash) ? redact_sensitive_data(v) : v }
        else
          redacted[key] = value
        end
      end
      redacted
    end

    # Check if key contains sensitive information
    def sensitive_key?(key)
      sensitive_patterns = %w[
        password token secret key api_key auth credential
        email phone ssn social_security credit_card
      ]
      sensitive_patterns.any? { |pattern| key.include?(pattern) }
    end

    # Execute callback with parameter signature (matching agent hooks)
    # Pipeline hooks now use the same signature as agent hooks: |context, pipeline, result|
    def execute_callback_with_parameters(result, &block)
      # Convert result to context variables for consistency
      context_vars = case result
                     when RAAF::DSL::ContextVariables
                       result
                     when Hash
                       RAAF::DSL::ContextVariables.new(result)
                     else
                       RAAF::DSL::ContextVariables.new({})
                     end
      
      # Check block arity to maintain backward compatibility
      if block.arity == 0
        # Legacy: parameterless block with direct context access (deprecated)
        # Temporarily store the current context
        old_context = instance_variable_get(:@context)
        instance_variable_set(:@context, context_vars)
        
        begin
          callback_result = instance_eval(&block)
          callback_result || context_vars
        ensure
          instance_variable_set(:@context, old_context)
        end
      else
        # New: parameter-based signature matching agent hooks
        # Hook receives: |context, pipeline, result|
        # Use the updated context that contains accumulated data from all agents
        callback_result = block.call(@context, self, context_vars)
        callback_result || context_vars
      end
    end
    
    def build_context_from_param(context_param)
      case context_param
      when Hash
        ensure_context_variables(context_param)
      when RAAF::DSL::ContextVariables
        context_param
      else
        raise ArgumentError, "Pipeline context must be a Hash or ContextVariables, got #{context_param.class}"
      end
    end
    
    def build_initial_context(provided_context)
      # Start with provided context
      context = provided_context.dup
      
      # Apply enhanced context configuration (unified with agents)
      context_rules = self.class._context_config[:context_rules] || {}
      
      # Process optional fields with defaults
      if context_rules[:optional]
        context_rules[:optional].each do |key, default_value|
          context[key] ||= default_value.is_a?(Proc) ? default_value.call : default_value
        end
      end
      
      # Add any computed context fields (if we have build_*_context methods)
      all_fields = []
      all_fields.concat(context_rules[:required] || [])
      all_fields.concat(context_rules[:optional]&.keys || [])
      all_fields.concat(self.class.required_fields || [])
      
      all_fields.uniq.each do |field|
        method_name = "build_#{field}_context"
        if respond_to?(method_name, true)
          context[field] ||= send(method_name)
        end
      end
      
      # Convert to ContextVariables to ensure consistency and prevent recursion
      ensure_context_variables(context)
    end
    
    def validate_initial_context!
      return unless @flow
      
      # Validate Pipeline's own required fields first
      context_rules = self.class._context_config[:context_rules] || {}
      pipeline_required = context_rules[:required] || []
      pipeline_optional = context_rules[:optional]&.keys || []
      provided = @context.keys.map(&:to_sym)
      
      # Check Pipeline's required fields
      missing_pipeline_fields = pipeline_required - provided
      if missing_pipeline_fields.any?
        raise ArgumentError, <<~MSG
          Pipeline initialization error!
          
          Pipeline #{self.class.name} requires: #{pipeline_required.inspect}
          You provided: #{@context.keys.inspect} (as symbols: #{provided.inspect})
          Missing: #{missing_pipeline_fields.inspect}
          
          Either:
          1. Add missing fields when creating the pipeline:
             pipeline = #{self.class.name}.new(
               #{missing_pipeline_fields.map { |f| "#{f}: #{f}_value" }.join(",\n               ")}
             )
          
          2. Or define defaults in the pipeline class:
             class #{self.class.name}
               context do
                 optional #{missing_pipeline_fields.map { |f| "#{f}: \"default_value\"" }.join(", ")}
               end
             end
        MSG
      end
      
      # Validate first agent requirements
      first_agent = extract_first_agent(@flow)
      return unless first_agent && first_agent.respond_to?(:externally_required_fields)
      
      # Use externally_required_fields to only check for fields without defaults
      externally_required = first_agent.externally_required_fields
      missing_agent_fields = externally_required - provided
      
      if missing_agent_fields.any?
        # Show both externally required and all required for debugging
        all_required = first_agent.respond_to?(:required_fields) ? first_agent.required_fields : externally_required
        
        raise ArgumentError, <<~MSG
          Pipeline initialization error!
          
          First agent #{first_agent.name} requires: #{all_required.inspect}
          You provided: #{@context.keys.inspect} (as symbols: #{provided.inspect})
          Missing: #{missing_agent_fields.inspect}
          
          Add missing fields when creating the pipeline:
             pipeline = #{self.class.name}.new(
               #{missing_agent_fields.map { |f| "#{f}: #{f}_value" }.join(",\n               ")}
             )
        MSG
      end
    end
    
    def extract_first_agent(chain)
      case chain
      when DSL::PipelineDSL::ChainedAgent
        extract_first_agent(chain.first)
      when DSL::PipelineDSL::ParallelAgents
        agents = chain.agents
        agents.first if agents
      when DSL::PipelineDSL::ConfiguredAgent
        chain.agent_class
      when DSL::PipelineDSL::RemappedAgent
        chain.agent_class
      when Class
        chain
      else
        nil
      end
    end
    
    def execute_chain(chain, context)
      case chain
      when DSL::PipelineDSL::ChainedAgent, DSL::PipelineDSL::ParallelAgents, DSL::PipelineDSL::ConfiguredAgent, DSL::PipelineDSL::RemappedAgent
        updated_context = chain.execute(context, @agent_results)
        # Return updated context if the chain execution updated it, otherwise original context
        updated_context || context
      when Class
        agent_result, updated_context = execute_agent(chain, context)
        @agent_results << agent_result if agent_result.is_a?(Hash)
        updated_context
      when Symbol
        send(chain, context) if respond_to?(chain, true)
        context
      else
        raise "Unknown chain type: #{chain.class}"
      end
    end
    
    def execute_agent(agent_class, context)
      unless agent_class.respond_to?(:requirements_met?) && agent_class.requirements_met?(context)
        RAAF.logger.warn "Skipping #{agent_class.name}: requirements not met"
        return [{}, context]  # Return empty result and unchanged context for skipped agents
      end

      # ContextVariables now supports direct splatting via to_hash method
      # Create instance - works for both Agent and Service classes
      # Pass parent_component (this pipeline) for proper span hierarchy
      instance_params = context.to_h
      instance_params[:parent_component] = self  # Pass pipeline object, not span

      # Don't pass tracer explicitly - let agents discover via TracingRegistry (ambient context pattern)
      instance = agent_class.new(**instance_params)

      # Inject pipeline schema if available
      if pipeline_schema && instance.respond_to?(:inject_pipeline_schema)
        logger.debug "Injecting schema into #{agent_class.name}"
        instance.inject_pipeline_schema(pipeline_schema)
      end

      # Execute based on type - Services use 'call', Agents use 'run'
      # Prioritize 'call' method if available (for agents with custom processing)
      logger&.debug "Executing #{agent_class.name}"
      result = if is_service_class?(agent_class)
        instance.call
      elsif instance.respond_to?(:call)
        instance.call
      else
        instance.run
      end

      # Check for failure in result - propagate immediately if agent/service failed
      if result.is_a?(Hash) && result.key?(:success) && result[:success] == false
        agent_name = agent_class.respond_to?(:agent_name) ? agent_class.agent_name : agent_class.name
        raise RAAF::DSL::PipelineDSL::PipelineFailureError.new(agent_name, result)
      end

      # Merge provisions into context (for backward compatibility)
      if agent_class.respond_to?(:provided_fields)
        agent_class.provided_fields.each do |field|
          if result.respond_to?(:[]) && result[field]
            context = context.set(field, result[field])
          end
        end
      end

      # Also merge the entire result into context for pipeline context accumulation
      if result.respond_to?(:[]) && result.is_a?(Hash)
        result.each do |key, value|
          # Only merge non-internal fields (avoid success, errors, etc.)
          unless key.to_s.match?(/^(success|error|errors|status|metadata)$/i)
            context = context.set(key, value)
          end
        end
      end

      # Return both the agent's result and the updated context
      agent_result = result.respond_to?(:to_h) ? result.to_h : (result.is_a?(Hash) ? result : {})
      [agent_result, context]
    end
    
    # Check if a class is a Service (as opposed to an Agent)
    def is_service_class?(klass)
      # Check if the class inherits from RAAF::DSL::Service
      klass < RAAF::DSL::Service
    rescue NameError
      # RAAF::DSL::Service might not be loaded yet
      false
    end
    
    # Simple logger accessor for pipeline
    def logger
      return nil unless defined?(RAAF) && RAAF.respond_to?(:logger)
      RAAF.logger
    end
    
    # Validate flow with context tracking through pipeline stages
    def validate_flow_with_tracking(flow, tracker, errors)
      case flow
      when DSL::PipelineDSL::ChainedAgent
        # Sequential chain - validate each stage in order
        validate_flow_with_tracking(flow.first, tracker, errors)
        validate_flow_with_tracking(flow.second, tracker, errors)
        
      when DSL::PipelineDSL::ParallelAgents
        # Parallel execution - each branch gets current context
        flow.agents.each_with_index do |agent, index|
          branch_tracker = tracker.create_branch_tracker
          validate_single_stage(agent, branch_tracker, errors, "parallel_#{index + 1}")
          tracker.merge_branch_results(branch_tracker)
        end
        
      when DSL::PipelineDSL::ConfiguredAgent
        validate_single_stage(flow.agent_class, tracker, errors)

      when DSL::PipelineDSL::RemappedAgent
        # For RemappedAgent, validate using the RemappedAgent itself (which handles field mapping)
        validate_single_stage(flow, tracker, errors)

      when DSL::PipelineDSL::BatchedAgent
        # BatchedAgent wraps a component and processes in chunks
        # Validate the wrapped component
        validate_flow_with_tracking(flow.wrapped_component, tracker, errors)

      when DSL::PipelineDSL::IteratingAgent
        # IteratingAgent wraps an agent and iterates over array
        # Validate the wrapped agent class
        validate_single_stage(flow.agent_class, tracker, errors)

      when Class
        validate_single_stage(flow, tracker, errors)
        
      else
        # Unknown flow type - add warning but continue
        errors << {
          stage_number: tracker.stage_number + 1,
          stage: "unknown_flow_type",
          message: "Unknown flow type: #{flow.class}",
          available_context: tracker.available_keys,
          missing_variables: nil
        }
      end
    end
    
    # Validate a single stage (agent or service) with context tracking
    def validate_single_stage(stage_class, tracker, errors, stage_name = nil)
      # Handle different stage types
      if stage_class.is_a?(DSL::PipelineDSL::RemappedAgent)
        # For RemappedAgent, use its mapped fields and validate the underlying agent
        stage_name ||= "RemappedAgent(#{stage_class.agent_class.name})"

        # Enter this stage in the tracker
        tracker.enter_stage(stage_name)

        begin
          # Add output fields that this stage will provide (after mapping)
          if stage_class.respond_to?(:provided_fields)
            output_fields = stage_class.provided_fields
            tracker.add_output_fields(output_fields)
          end

          # Validate requirements are met (with input mapping applied)
          context_hash = tracker.current_context
          unless stage_class.requirements_met?(context_hash)
            required = stage_class.required_fields || []
            available = context_hash.keys
            missing = required - available

            raise StandardError, "RemappedAgent requirements not met. Required: #{required.inspect}, Available: #{available.inspect}, Missing: #{missing.inspect}"
          end

        rescue StandardError => e
          handle_validation_error(e, stage_name, tracker, errors)
        end
      else
        # Handle regular agent/service classes
        stage_name ||= stage_class.respond_to?(:name) ? stage_class.name : stage_class.to_s

        # Enter this stage in the tracker
        tracker.enter_stage(stage_name)

        begin
          # FIRST: Add output fields that this stage will provide to the tracker
          # This allows downstream stages to know these fields will be available
          if stage_class.respond_to?(:provided_fields)
            output_fields = stage_class.provided_fields
            tracker.add_output_fields(output_fields)
          elsif stage_class.respond_to?(:output_fields)
            output_fields = stage_class.output_fields
            tracker.add_output_fields(output_fields)
          end

          # THEN: Create test instance with context that includes simulated outputs
          context_hash = tracker.current_context

          # Try to create agent/service instance with validation mode enabled
          # This skips run_if execution conditions during validation
          test_instance = stage_class.new(validation_mode: true, **context_hash)

          # Validate using unified Pipelineable interface if supported
          if test_instance.can_validate_for_pipeline?
            test_instance.validate_for_pipeline(context_hash)
          end

        rescue StandardError => e
          handle_validation_error(e, stage_name, tracker, errors)
        end
      end
    end

    # Helper method to handle validation errors consistently
    def handle_validation_error(error, stage_name, tracker, errors)
      # Capture validation error with context
      missing_vars = nil

      # Extract missing variables from error message if it's a context error
      if error.message.include?("Missing variables:")
        # Try to extract missing variables from error message
        match = error.message.match(/Missing variables: \[(.*?)\]/)
        missing_vars = match ? match[1].split(', ').map(&:strip) : nil
      end

      errors << {
        stage_number: tracker.stage_number,
        stage: stage_name,
        message: error.message,
        available_context: tracker.available_keys,
        missing_variables: missing_vars
      }
    end

    # Auto-merge all agent results intelligently
    # Combines results from all agents in the pipeline, merging arrays by ID and hashes deeply
    def auto_merge_results(agent_results)
      return ActiveSupport::HashWithIndifferentAccess.new if agent_results.empty?

      # Start with first result as base
      merged = agent_results.first.dup

      # Merge each subsequent result
      agent_results[1..-1].each do |result|
        merged = deep_merge_results(merged, result)
      end

      # Wrap final result in HashWithIndifferentAccess for consistent symbol/string access
      ActiveSupport::HashWithIndifferentAccess.new(merged)
    end

    # Deep merge two result hashes, handling arrays and nested hashes intelligently
    def deep_merge_results(base, new_result)
      new_result.each do |key, value|
        if base[key].is_a?(Array) && value.is_a?(Array)
          # Intelligently merge arrays by matching IDs
          base[key] = merge_arrays_by_id(base[key], value)
        elsif base[key].is_a?(Hash) && value.is_a?(Hash)
          # Recursively merge nested hashes with indifferent access
          base[key] = ActiveSupport::HashWithIndifferentAccess.new(deep_merge_results(base[key], value))
        elsif value.is_a?(Hash)
          # Convert new hash values to indifferent access
          base[key] = ActiveSupport::HashWithIndifferentAccess.new(value)
        else
          # Simple replacement or addition for scalars
          base[key] = value
        end
      end
      base
    end

    # Merge two arrays by matching ID fields, combining objects with same ID
    # Handles both symbol and string keys (:id, "id", :name, "name")
    def merge_arrays_by_id(base_array, new_array)
      # Build lookup table from base array
      base_lookup = {}
      base_array.each do |item|
        if item.is_a?(Hash)
          id = item[:id] || item["id"] || item[:name] || item["name"]
          base_lookup[id] = ActiveSupport::HashWithIndifferentAccess.new(item.dup) if id
        end
      end

      # Merge new items into lookup table
      new_array.each do |new_item|
        if new_item.is_a?(Hash)
          id = new_item[:id] || new_item["id"] || new_item[:name] || new_item["name"]
          if id && base_lookup[id]
            # Deep merge with existing item
            base_lookup[id] = ActiveSupport::HashWithIndifferentAccess.new(deep_merge_results(base_lookup[id], new_item))
          else
            # Add new item (generate ID if missing) with indifferent access
            key = id || SecureRandom.uuid
            base_lookup[key] = ActiveSupport::HashWithIndifferentAccess.new(new_item.dup)
          end
        end
      end

      base_lookup.values
    end

    # Sanitize pipeline result using Rails' built-in serializable_hash for ActiveRecord objects
    # This leverages Rails' battle-tested implementation for handling serialization and circular references
    def sanitize_result(result)
      case result
      when defined?(ActiveRecord::Base) && ActiveRecord::Base
        # Use Rails' built-in method - it handles circular references automatically
        ActiveSupport::HashWithIndifferentAccess.new(result.serializable_hash)
      when Hash
        # Recursively sanitize hash values while preserving indifferent access
        ActiveSupport::HashWithIndifferentAccess.new(
          result.transform_values { |v| sanitize_result(v) }
        )
      when Array
        # Recursively sanitize array items
        result.map { |item| sanitize_result(item) }
      when Time, Date, DateTime
        # Convert time objects to ISO strings
        result.respond_to?(:iso8601) ? result.iso8601 : result.to_s
      else
        # Basic types pass through unchanged
        result
      end
    rescue => e
      Rails.logger.error "Pipeline sanitization error: #{e.message}" if defined?(Rails)
      result.to_s
    end

    # Get the default tracer following TracingRegistry priority hierarchy:
    # 1. Explicit tracer parameter (already handled in initialize)
    # 2. RAAF::Tracing::TracingRegistry.current_tracer
    # 3. RAAF.tracer (existing fallback)
    # 4. nil (if nothing available)
    def get_default_tracer
      # Try TracingRegistry first if available
      if defined?(RAAF::Tracing::TracingRegistry)
        begin
          current_tracer = RAAF::Tracing::TracingRegistry.current_tracer
          # Only use if it's not a NoOpTracer or if that's the best we can get
          return current_tracer
        rescue StandardError
          # Fall through to RAAF.tracer if registry access fails
        end
      end

      # Fall back to RAAF.tracer
      RAAF.tracer
    end

    # ContextConfig class provided by ContextConfiguration module
  end
end