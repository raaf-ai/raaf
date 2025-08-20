# frozen_string_literal: true

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
        attr_reader :first, :second
        
        def initialize(first, second)
          @first = first
          @second = second
          validate_field_compatibility!
        end
        
        # DSL operator: Chain this agent with the next one in sequence
        # Creates a new ChainedAgent where current chain becomes first, next_agent becomes second
        def >>(next_agent)
          ChainedAgent.new(self, next_agent)
        end
        
        # DSL operator: Run this agent in parallel with another
        # Creates ParallelAgents wrapping both agents for concurrent execution
        def |(parallel_agent)
          ParallelAgents.new([self, parallel_agent])
        end
        
        def execute(context)
          # Execute first part
          context = execute_part(@first, context)
          # Execute second part with validation
          execute_part(@second, context)
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
          else
            []
          end
        end
        
        def requirements_met?(context)
          case @first
          when ChainedAgent, ConfiguredAgent, IteratingAgent
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
        # - Initial context fields are allowed (from pipeline setup)
        # - Fields with context defaults in the agent are allowed
        # - Missing non-initial fields raise FieldMismatchError
        def validate_field_compatibility!
          return unless @first.respond_to?(:provided_fields) && @second.respond_to?(:required_fields)
          
          provided = @first.provided_fields
          required = @second.required_fields
          missing = required - provided
          
          # Check if the second agent has context defaults for missing fields
          if @second.respond_to?(:_agent_config)
            agent_config = @second._agent_config
            if agent_config && agent_config[:context_rules] && agent_config[:context_rules][:defaults]
              defaults = agent_config[:context_rules][:defaults]
              # Remove fields that have defaults from the missing list
              missing = missing - defaults.keys
            end
          end
          
          # Allow certain fields to come from initial context
          # These fields are typically provided when creating the pipeline instance
          initial_context_fields = [
            :product, :company, :market_data, :analysis_depth, 
            :existing_icps, :focus_areas,
            :scoring_weights, :scoring_framework_version,
            :search_limit, :threshold,
            :min_companies, :max_companies, :limit
          ]
          non_initial_missing = missing - initial_context_fields
          
          # Only raise error for fields that can't come from initial context or defaults
          if non_initial_missing.any?
            raise FieldMismatchError.new(@first, @second, non_initial_missing, initial_context_fields)
          end
        end
        
        def execute_part(part, context)
          case part
          when ChainedAgent
            part.execute(context)
          when ParallelAgents
            part.execute(context)
          when ConfiguredAgent
            part.execute(context)
          when IteratingAgent
            part.execute(context)
          when Class
            execute_single_agent(part, context)
          when Symbol
            # Method handler - look for method in pipeline instance
            if context.respond_to?(:pipeline_instance) && context.pipeline_instance
              if context.pipeline_instance.respond_to?(part, true)
                context.pipeline_instance.send(part, context)
              end
            end
            context
          else
            context
          end
        end
        
        def execute_single_agent(agent_class, context)
          # Check requirements
          if agent_class.respond_to?(:requirements_met?)
            unless agent_class.requirements_met?(context)
              RAAF.logger.warn "Skipping #{agent_class.name}: requirements not met"
              RAAF.logger.debug "  Required: #{agent_class.required_fields}"
              RAAF.logger.debug "  Available in context: #{context.keys if context.respond_to?(:keys)}"
              return context
            end
          end
          
          # Execute agent - convert context to keyword arguments to trigger context DSL processing
          context_hash = context.is_a?(RAAF::DSL::ContextVariables) ? context.to_h : context
          agent = agent_class.new(**context_hash)
          result = agent.run
          
          # Merge provided fields into context
          if agent_class.respond_to?(:provided_fields)
            agent_class.provided_fields.each do |field|
              if result.is_a?(Hash) && result.key?(field)
                context[field] = result[field]
              elsif result.respond_to?(field)
                context[field] = result.send(field)
              end
            end
          end
          
          context
        end
      end
    end
  end
end