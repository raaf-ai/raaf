# frozen_string_literal: true

require_relative "../pipeline_dsl"
require_relative "../context_flow_tracker"
require_relative "../pipelineable"
require_relative "../context_access"
require_relative "../agent"

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

    class << self
      attr_reader :flow_chain, :context_config, :after_run_block, :pipeline_schema_block
      attr_accessor :skip_validation
      
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
      
      # Define after_run hook using DSL block
      # Executes after all agents complete with the final result
      def after_run(&block)
        if block_given?
          @after_run_block = block
        end
        @after_run_block
      end
      
      # Context DSL - unified with agents using ContextConfig
      # Provides enhanced context management with required, optional, and output fields
      def context(&block)
        if block_given?
          config = ContextConfig.new
          config.instance_eval(&block)
          @context_config = config.to_h
          
          # Make context fields available immediately for flow definition
          Thread.current[:raaf_pipeline_context_fields] = context_fields
        end
        @context_config ||= {}
      end
      
      # Get required fields from context configuration
      def required_fields
        context_config = @context_config || {}
        requirements = context_config[:required] || []
        defaults = context_config[:optional] || {}
        # Include both explicitly required fields and those with defaults
        (requirements + defaults.keys).uniq
      end
      
      # Get all fields declared in context (both required and optional)
      # These are the fields that will be preserved through the pipeline
      def context_fields
        context_config = @context_config || {}
        requirements = context_config[:required] || []
        defaults = context_config[:optional] || {}
        outputs = context_config[:output] || []
        
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
    # @param provided_context [Hash] Additional context as keyword arguments
    def initialize(context: nil, **provided_context)
      # Support both context: hash and direct keyword arguments like agents do
      if context
        # Context provided explicitly (like agents)
        @context = build_context_from_param(context).merge(provided_context)
      else
        # Use keyword arguments as context
        @context = build_initial_context(provided_context)
      end
      
      @flow = self.class.flow_chain
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
      # Validate pipeline before execution (enabled by default)
      unless self.class.skip_validation
        validate_pipeline!
      end
      
      result = execute_chain(@flow, @context)
      
      # Execute after_run hook if defined
      if self.class.after_run_block
        execute_callback_with_context(result, &self.class.after_run_block)
      end
      
      # Convert ContextVariables result to hash with success flag
      # This ensures all pipelines return a consistent result structure
      final_result = if result.respond_to?(:to_h)
        # Convert ContextVariables to hash while preserving all data
        result_hash = result.to_h
        # Add success flag to indicate pipeline completed successfully
        result_hash[:success] = true
        result_hash
      elsif result.is_a?(Hash)
        # Already a hash, just add success flag if not present
        result[:success] = true unless result.key?(:success)
        result
      else
        # Fallback for other result types
        { success: true, result: result }
      end
      
      final_result
    end
    
    private
    
    # Execute callback with universal context access
    # Creates an execution environment where context variables are available as direct variables
    def execute_callback_with_context(result, &block)
      # Create a context-aware object for callback execution
      callback_context = Object.new
      
      # Add universal context access to the callback object
      callback_context.define_singleton_method(:method_missing) do |method_name, *args, &nested_block|
        if args.empty? && !nested_block
          # Check if this variable exists in context
          return @context.get(method_name) if @context&.has?(method_name)
          
          # Standard Ruby NameError for missing variables
          raise NameError, "undefined variable `#{method_name}'"
        else
          super(method_name, *args, &nested_block)
        end
      end
      
      # Add respond_to_missing for Ruby introspection
      callback_context.define_singleton_method(:respond_to_missing?) do |method_name, include_private = false|
        @context&.has?(method_name) || super(method_name, include_private)
      end
      
      # Set context for callback (convert to ContextVariables if needed)
      context_vars = case @context
                     when RAAF::DSL::ContextVariables
                       @context
                     when Hash
                       RAAF::DSL::ContextVariables.new(@context)
                     else
                       RAAF::DSL::ContextVariables.new({})
                     end
      
      callback_context.instance_variable_set(:@context, context_vars)
      
      # Execute the callback with universal context access
      callback_context.instance_exec(result, &block)
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
      config = self.class.context_config
      
      # Process optional fields with defaults
      if config && config[:optional]
        config[:optional].each do |key, default_value|
          context[key] ||= default_value.is_a?(Proc) ? default_value.call : default_value
        end
      end
      
      # Add any computed context fields (if we have build_*_context methods)
      all_fields = []
      all_fields.concat(config[:required] || []) if config
      all_fields.concat(config[:optional]&.keys || []) if config
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
      config = self.class.context_config
      pipeline_required = config && config[:required] ? config[:required] : []
      pipeline_optional = config && config[:optional] ? config[:optional].keys : []
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
      when Class
        chain
      else
        nil
      end
    end
    
    def execute_chain(chain, context)
      case chain
      when DSL::PipelineDSL::ChainedAgent, DSL::PipelineDSL::ParallelAgents, DSL::PipelineDSL::ConfiguredAgent
        chain.execute(context)
      when Class
        execute_agent(chain, context)
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
        return context
      end
      
      # ContextVariables now supports direct splatting via to_hash method
      # Create instance - works for both Agent and Service classes
      instance = agent_class.new(**context)
      
      # Inject pipeline schema if available
      if pipeline_schema && instance.respond_to?(:inject_pipeline_schema)
        logger.debug "Injecting schema into #{agent_class.name}"
        instance.inject_pipeline_schema(pipeline_schema)
      end
      
      # Execute based on type - Services use 'call', Agents use 'run'
      logger.debug "Executing #{agent_class.name}"
      result = if is_service_class?(agent_class)
        instance.call
      else
        instance.run
      end
      
      # Merge provisions into context
      if agent_class.respond_to?(:provided_fields)
        agent_class.provided_fields.each do |field|
          if result.respond_to?(:[]) && result[field]
            context[field] = result[field]
          end
        end
      end
      
      context
    end
    
    # Check if a class is a Service (as opposed to an Agent)
    def is_service_class?(klass)
      # Check if the class inherits from RAAF::DSL::Service
      klass < RAAF::DSL::Service
    rescue NameError
      # RAAF::DSL::Service might not be loaded yet
      false
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
        # Capture validation error with context
        missing_vars = nil
        
        # Extract missing variables from error message if it's a context error
        if e.message.include?("Missing variables:")
          # Try to extract missing variables from error message
          match = e.message.match(/Missing variables: \[(.*?)\]/)
          missing_vars = match ? match[1].split(', ').map(&:strip) : nil
        end
        
        errors << {
          stage_number: tracker.stage_number,
          stage: stage_name,
          message: e.message,
          available_context: tracker.available_keys,
          missing_variables: missing_vars
        }
      end
    end
    
    # ContextConfig class - unified with Agent DSL implementation
    # Provides enhanced context management with required, optional, and output field declarations
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
      
      # Keep existing methods for additional functionality
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
  end
end