# frozen_string_literal: true

require 'ostruct'
require 'securerandom'
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

          # Check if first part was skipped - for now, continue execution anyway
          # Future improvement: could make this configurable per agent
          if context.respond_to?(:get) && context.get(:_agent_skipped)
            puts "🔍 [CHAINED_AGENT] First part was skipped, but continuing with second part"
            # Clean up the skip marker for next agent
            context = context.set(:_agent_skipped, nil)
          end

          # Execute second part regardless of first part skip status
          # This allows pipeline to continue even if some agents are skipped
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

          first_name = @first.respond_to?(:name) ? @first.name : @first.class.name
          second_name = @second.respond_to?(:name) ? @second.name : @second.class.name
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
          puts "🔍 [CHAINED_AGENT] Starting execute_single_agent for: #{agent_name}"
          puts "🔍 [CHAINED_AGENT] Agent class: #{agent_class.name}"
          puts "🔍 [CHAINED_AGENT] Context keys: #{context.respond_to?(:keys) ? context.keys : 'unknown'}"
          log_debug "Executing agent: #{agent_name}"

          # Check requirements
          if agent_class.respond_to?(:requirements_met?)
            puts "🔍 [CHAINED_AGENT] Agent has requirements_met? method"
            puts "🔍 [CHAINED_AGENT] Required fields: #{agent_class.required_fields rescue 'error getting required fields'}"

            requirements_met = agent_class.requirements_met?(context)
            puts "🔍 [CHAINED_AGENT] Requirements met?: #{requirements_met}"

            unless requirements_met
              puts "🔍 [CHAINED_AGENT] ⚠️ REQUIREMENTS NOT MET - SKIPPING AGENT: #{agent_name}"
              log_warn "Skipping #{agent_name}: requirements not met"
              log_debug "  Required: #{agent_class.required_fields}"
              log_debug "  Available in context: #{context.keys if context.respond_to?(:keys)}"

              # Create a span for the skipped agent to make it visible in traces
              pipeline_instance = context.respond_to?(:get) ? context.get(:pipeline_instance) : context[:pipeline_instance]
              puts "🔍 [CHAINED_AGENT] Pipeline instance found: #{pipeline_instance&.class&.name || 'nil'}"
              puts "🔍 [CHAINED_AGENT] Pipeline responds to with_tracing?: #{pipeline_instance&.respond_to?(:with_tracing)}"

              if pipeline_instance && pipeline_instance.respond_to?(:with_tracing)
                puts "🔍 [CHAINED_AGENT] Creating span for skipped agent: #{agent_name}"
                puts "🔍 [CHAINED_AGENT] Pipeline current span: #{pipeline_instance.current_span&.dig(:span_id) || 'nil'}"

                # Create a proper agent-like object that can create agent spans
                require 'ostruct'

                # Create a minimal agent-like object with tracing capability
                skipped_agent = Class.new do
                  include RAAF::Tracing::Traceable
                  trace_as :agent  # This is crucial - sets the span kind to :agent

                  def initialize(name, parent_component)
                    @name = name
                    @parent_component = parent_component
                  end

                  attr_reader :name, :parent_component
                end.new(agent_name, pipeline_instance)

                # Use the fake agent to create a proper agent span with correct hierarchy
                skipped_agent.with_tracing(:execute,
                                          parent_component: pipeline_instance,
                                          agent_name: agent_name,
                                          "agent.status" => "skipped",
                                          "agent.skip_reason" => "requirements_not_met",
                                          "agent.required_fields" => agent_class.required_fields.join(", "),
                                          "agent.available_fields" => (context.respond_to?(:keys) ? context.keys.join(", ") : "unknown")) do
                  # No-op - just create the span to show the agent was considered
                  puts "🔍 [CHAINED_AGENT] Inside skipped agent span block"
                  log_debug "Created span for skipped agent: #{agent_name}"
                  nil  # Return nil from span block
                end
                puts "🔍 [CHAINED_AGENT] Completed span creation for skipped agent: #{agent_name}"
              else
                puts "🔍 [CHAINED_AGENT] ❌ Cannot create span for skipped agent - no pipeline instance or no with_tracing method"
              end

              # Mark context as having a skipped agent to propagate skip condition
              context = context.set(:_agent_skipped, true) if context.respond_to?(:set)
              puts "🔍 [CHAINED_AGENT] Returning context with _agent_skipped marker"
              return context
            end
          else
            puts "🔍 [CHAINED_AGENT] Agent does NOT have requirements_met? method, proceeding with execution"
          end

          # Execute agent - ContextVariables now supports direct splatting via to_hash method
          agent_params = context.to_h

          # Pass pipeline instance as parent_component for tracing hierarchy
          pipeline_instance = context.respond_to?(:get) ? context.get(:pipeline_instance) : context[:pipeline_instance]
          if pipeline_instance
            agent_params[:parent_component] = pipeline_instance
          end

          # Convert to regular hash first, then transform keys to symbols for RAAF::DSL::Agent compatibility
          regular_hash = agent_params.to_h
          symbolized_params = regular_hash.transform_keys(&:to_sym)

          agent = agent_class.new(**symbolized_params)
          log_debug "Agent #{agent_name} initialized"

          # Inject pipeline schema into agent if available
          # pipeline_instance is already retrieved above
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

      end
    end
  end
end