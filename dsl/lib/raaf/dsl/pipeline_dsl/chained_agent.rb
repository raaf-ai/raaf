# frozen_string_literal: true

require_relative 'field_mismatch_error'

module RAAF
  module DSL
    module PipelineDSL
      # Represents a chain of two agents to be executed in sequence
      # This is the core building block of the Pipeline DSL, created when using >> operator
      #
      # DSL Usage: 
      #   Agent1 >> Agent2 creates ChainedAgent.new(Agent1, Agent2)
      #   Agent1 >> Agent2 >> Agent3 creates ChainedAgent.new(ChainedAgent.new(Agent1, Agent2), Agent3)
      #
      # Why >> operator: Chosen for its visual similarity to shell piping and data flow direction
      # Field mapping: Automatically validates that producer fields match consumer requirements
      class ChainedAgent

        include Logger

        attr_reader :first, :second, :pipeline_context_fields
        
        def initialize(first, second, pipeline_context_fields: nil)
          @first = first
          @second = second
          @pipeline_context_fields = pipeline_context_fields || []

          # Store validation as a closure to be called later with complete context
          @validation_proc = proc { validate_field_compatibility! }

          # Defer validation until explicitly called by pipeline or user
          # This allows for flexible testing and runtime behavior
        end
        
        # DSL operator: Chain this agent with the next one in sequence
        # Creates a new ChainedAgent where current chain becomes first, next_agent becomes second
        def >>(next_agent)
          ChainedAgent.new(self, next_agent, pipeline_context_fields: @pipeline_context_fields)
        end
        
        # DSL operator: Run this agent in parallel with another
        # Creates ParallelAgents wrapping both agents for concurrent execution
        def |(parallel_agent)
          ParallelAgents.new([self, parallel_agent])
        end
        
        # Validate with pipeline context fields provided at runtime
        # This allows the pipeline to pass its context fields after they're defined
        def validate_with_pipeline_context(pipeline_context_fields)
          @pipeline_context_fields = pipeline_context_fields if pipeline_context_fields
          @validation_proc&.call
          
          # Recursively validate nested chains
          if @first.respond_to?(:validate_with_pipeline_context)
            @first.validate_with_pipeline_context(pipeline_context_fields)
          end
          if @second.respond_to?(:validate_with_pipeline_context)
            @second.validate_with_pipeline_context(pipeline_context_fields)
          end
        end
        
        def execute(context, agent_results = nil)
          # Ensure context is ContextVariables if it's a plain Hash
          unless context.respond_to?(:set)
            context = RAAF::DSL::ContextVariables.new(context)
          end

          # Execute first part
          context = execute_part(@first, context, agent_results)
          # Execute second part with validation
          execute_part(@second, context, agent_results)
        end
        
        # Extract metadata for chained agents
        def required_fields
          # Return the requirements of the first agent in the chain
          case @first
          when ChainedAgent
            @first.required_fields
          when Class
            @first.respond_to?(:required_fields) ? @first.required_fields : []
          when ConfiguredAgent
            @first.required_fields
          when IteratingAgent
            @first.required_fields
          when RemappedAgent
            @first.required_fields
          else
            []
          end
        end

        def provided_fields
          # Return what the last agent in the chain provides
          case @second
          when ChainedAgent
            @second.provided_fields
          when Class
            @second.respond_to?(:provided_fields) ? @second.provided_fields : []
          when ConfiguredAgent
            @second.provided_fields
          when IteratingAgent
            @second.provided_fields
          when RemappedAgent
            @second.provided_fields
          else
            []
          end
        end

        def requirements_met?(context)
          case @first
          when ChainedAgent, ConfiguredAgent, IteratingAgent, RemappedAgent
            @first.requirements_met?(context)
          when Class
            @first.respond_to?(:requirements_met?) ? @first.requirements_met?(context) : true
          else
            true
          end
        end
        
        private

        # Field mapping validation: Ensures producer/consumer compatibility at chain creation time
        # Why early validation: Catches field mismatches during development, not runtime
        # Field mapping decisions:
        # - Producer fields must satisfy consumer requirements (enforced)
        # - Pipeline context fields are allowed (from pipeline setup)
        # - Fields with context defaults in the agent are allowed
        # - Missing non-pipeline fields raise FieldMismatchError
        def validate_field_compatibility!
          return unless @first.respond_to?(:provided_fields) && @second.respond_to?(:required_fields)

          provided = @first.provided_fields
          required = @second.required_fields
          missing = required - provided
          
          # Check if the second agent has context defaults for missing fields
          if @second.respond_to?(:_context_config)
            agent_config = @second._context_config
            if agent_config && agent_config[:context_rules] && agent_config[:context_rules][:defaults]
              defaults = agent_config[:context_rules][:defaults]
              # Remove fields that have defaults from the missing list
              missing = missing - defaults.keys
            end
          end
          
          return if missing.empty?
          
          # Use dynamic pipeline context fields if available
          # These fields are declared in the pipeline's context block and will be available at runtime
          pipeline_provided_fields = @pipeline_context_fields

          # Add common generic context fields that are typically available
          generic_context_fields = [:user, :data, :config, :options, :settings]
          available_from_context = pipeline_provided_fields + generic_context_fields

          # Filter out fields that are provided by pipeline context
          non_context_missing = missing - available_from_context

          # Only raise error for fields that can't come from pipeline context or defaults
          if non_context_missing.any?
            raise FieldMismatchError.new(@first, @second, non_context_missing, available_from_context)
          end
        end
        
        def execute_part(part, context, agent_results = nil)
          case part
          when ChainedAgent
            part.execute(context, agent_results)
          when ParallelAgents
            part.execute(context, agent_results)
          when ConfiguredAgent
            part.execute(context, agent_results)
          when IteratingAgent
            part.execute(context, agent_results)
          when RemappedAgent
            part.execute(context, agent_results)
          when Class
            execute_single_agent(part, context, agent_results)
          when Symbol
            # Method handler - look for method in pipeline instance
            if context.respond_to?(:pipeline_instance) && context.pipeline_instance
              if context.pipeline_instance.respond_to?(part, true)
                context.pipeline_instance.send(part, context)
              end
            end
            context
          else
            raise "RAAF Framework Error: Unrecognized pipeline part type: #{part.class.name}. This indicates a bug in the RAAF framework - all pipeline parts must be handled explicitly."
          end
        end
        
        def execute_single_agent(agent_class, context, agent_results = nil)
          agent_name = agent_class.respond_to?(:agent_name) ? agent_class.agent_name : agent_class.name
          log_debug "Executing agent: #{agent_name}"

          # Check requirements
          if agent_class.respond_to?(:requirements_met?)
            unless agent_class.requirements_met?(context)
              log_warn "Skipping #{agent_name}: requirements not met"
              log_debug "  Required: #{agent_class.required_fields}"
              log_debug "  Available in context: #{context.keys if context.respond_to?(:keys)}"

              # Create skipped span for pipeline agents
              create_pipeline_skipped_span(agent_class, agent_name, context)

              return context
            end
          end

          # Execute agent - ContextVariables now supports direct splatting via to_hash method
          agent = agent_class.new(**context)
          log_debug "Agent #{agent_name} initialized"

          # Inject pipeline schema into agent if available
          # Check if we have a pipeline instance with schema available
          pipeline_instance = context.respond_to?(:get) ? context.get(:pipeline_instance) : context[:pipeline_instance]
          if pipeline_instance && pipeline_instance.respond_to?(:pipeline_schema)
            pipeline_schema = pipeline_instance.pipeline_schema

            if pipeline_schema && agent.respond_to?(:inject_pipeline_schema)
              agent.inject_pipeline_schema(pipeline_schema)
            end
          end

          # Call appropriate execution method based on agent type
          if agent.respond_to?(:call) && agent.class.superclass.name == 'RAAF::DSL::Service'
            result = agent.call
          else
            result = agent.run
          end

          # Collect agent result for auto-merge if agent_results array provided
          if agent_results && result.is_a?(Hash)
            agent_results << result
          end

          # Merge provided fields into context (for backward compatibility)
          # If the agent has AutoMerge enabled, the result already contains properly merged data
          # and we should use the complete results rather than extracting individual fields
          if agent_class.respond_to?(:auto_merge_enabled?) && agent_class.auto_merge_enabled? &&
             result.is_a?(Hash) && result[:results]
            # Use the complete merged results from AutoMerge
            result[:results].each do |field, field_value|
              context = context.set(field, field_value)
            end
          elsif agent_class.respond_to?(:provided_fields)
            # Fallback to individual field extraction for agents without AutoMerge
            agent_class.provided_fields.each do |field|
              if result.is_a?(Hash) && result.key?(field)
                field_value = result[field]
                context = context.set(field, field_value)
              elsif result.respond_to?(field)
                field_value = result.send(field)
                context = context.set(field, field_value)
              end
            end
          end

          log_debug "Agent #{agent_name} execution completed"
          context
        end

        # Create a skipped span for pipeline agents when requirements are not met
        def create_pipeline_skipped_span(agent_class, agent_name, context)
          # Get tracer from global RAAF instance to avoid context access issues
          # The pipeline_instance.tracer call was triggering context restrictions
          tracer = RAAF.tracer

          # Only create span if tracer is available
          return unless tracer

          # Get pipeline instance for parent span information (without accessing tracer)
          pipeline_instance = context.respond_to?(:get) ? context.get(:pipeline_instance) : context[:pipeline_instance]

          # Create a short-lived span to make the skip visible in traces
          tracer.agent_span(agent_name) do |span|
            # Get parent span from pipeline instance if available
            parent_span = pipeline_instance&.respond_to?(:parent_span) ? pipeline_instance.parent_span : nil
            span.instance_variable_set(:@parent_id, parent_span.span_id) if parent_span

            # Mark as skipped with specific attributes
            span.set_attribute("agent.skipped", true)
            span.set_attribute("agent.skip_reason", "requirements_not_met")
            span.set_attribute("agent.class", agent_class.name)
            span.set_attribute("agent.name", agent_name)

            # Add debugging info about requirements vs available context
            required_fields = agent_class.respond_to?(:required_fields) ? agent_class.required_fields : []
            available_keys = context.respond_to?(:keys) ? context.keys : []

            span.set_attribute("agent.required_fields", required_fields)
            span.set_attribute("agent.available_context_keys", available_keys)
            span.set_attribute("agent.missing_fields", required_fields - available_keys)

            # Set span status to indicate this was intentionally skipped (not an error)
            span.set_status(:ok)
            span.set_attribute("agent.success", false)
            span.set_attribute("agent.workflow_status", "skipped")

            # Add event to show when skip occurred
            span.add_event("agent.execution_skipped", attributes: {
              reason: "requirements_not_met",
              required_fields: required_fields,
              available_fields: available_keys,
              timestamp: Time.now.utc.iso8601
            })
          end
        end
      end
    end
  end
end