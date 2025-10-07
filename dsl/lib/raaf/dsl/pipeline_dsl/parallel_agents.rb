# frozen_string_literal: true

require 'thread'
require_relative 'pipeline_failure_error'

module RAAF
  module DSL
    module PipelineDSL
      # Represents multiple agents to be executed in parallel
      # Created using | operator: (Agent1 | Agent2 | Agent3)
      #
      # DSL Usage Patterns:
      #   Agent1 | Agent2                    # Two agents in parallel
      #   (Agent1 | Agent2) >> Agent3        # Parallel then sequential
      #   Agent1 >> (Agent2 | Agent3)        # Sequential then parallel
      #
      # Why | operator: Visual similarity to shell pipe OR operation and parallel processing
      # Execution model: True parallelism using Ruby threads, each agent gets copy of context
      # Field merging: Results from all parallel agents are merged into single context
      class ParallelAgents
        attr_reader :agents
        
        def initialize(agents)
          @agents = agents.flatten
        end
        
        # DSL operator: Add another agent to parallel execution group
        # Flattens nested parallel agents into single group for efficiency
        def |(other_agent)
          ParallelAgents.new(@agents + [other_agent])
        end
        
        # DSL operator: Chain entire parallel group with next agent
        # All parallel agents complete before next agent executes
        def >>(next_agent)
          ChainedAgent.new(self, next_agent)
        end
        
        # Parallel execution: Create thread for each agent, merge results
        # Field merging strategy: Union of all agent results (last writer wins for conflicts)
        # Error handling: Any failure in parallel agents stops the entire pipeline
        def execute(context, agent_results = nil)
          results = @agents.map do |agent|
            Thread.new do
              execute_single(agent, context.dup)  # Each agent gets own context copy
            end
          end.map(&:value)

          # Merge all results into context - field conflicts resolved by last writer wins
          results.each do |result|
            context.merge!(result) if result.is_a?(Hash)
          end

          context
        end
        
        def required_fields
          # Union of all parallel agents' requirements
          @agents.flat_map do |agent|
            case agent
            when Class
              agent.respond_to?(:required_fields) ? agent.required_fields : []
            when ChainedAgent, ConfiguredAgent, IteratingAgent
              agent.required_fields
            else
              []
            end
          end.uniq
        end
        
        def provided_fields
          # Union of all parallel agents' provisions
          @agents.flat_map do |agent|
            case agent
            when Class
              agent.respond_to?(:provided_fields) ? agent.provided_fields : []
            when ChainedAgent, ConfiguredAgent, IteratingAgent
              agent.provided_fields
            else
              []
            end
          end.uniq
        end
        
        def requirements_met?(context)
          # All parallel agents must have their requirements met
          @agents.all? do |agent|
            case agent
            when Class
              !agent.respond_to?(:requirements_met?) || agent.requirements_met?(context)
            when ChainedAgent, ConfiguredAgent, IteratingAgent
              agent.requirements_met?(context)
            else
              true
            end
          end
        end
        
        private
        
        def execute_single(agent, context)
          case agent
          when ChainedAgent
            agent.execute(context)
            extract_provided_fields(agent, context)
          when ConfiguredAgent
            agent.execute(context)
          when IteratingAgent
            agent.execute(context)
            extract_provided_fields(agent, context)
          when Class
            return {} unless agent.respond_to?(:requirements_met?)
            return {} unless agent.requirements_met?(context)

            agent_instance = agent.new(context: context)
            result = agent_instance.run

            # Check for failure in result - propagate immediately if agent failed
            if result.is_a?(Hash) && result.key?(:success) && result[:success] == false
              agent_name = agent.respond_to?(:agent_name) ? agent.agent_name : agent.name
              raise PipelineFailureError.new(agent_name, result)
            end

            # Extract only the provided fields
            provided_data = {}
            if agent.respond_to?(:provided_fields)
              agent.provided_fields.each do |field|
                provided_data[field] = result[field] if result.respond_to?(:[]) && result[field]
              end
            end

            provided_data
          else
            {}
          end
        end
        
        def extract_provided_fields(agent, context)
          # Extract provided fields from context after execution
          provided_data = {}
          if agent.respond_to?(:provided_fields)
            agent.provided_fields.each do |field|
              provided_data[field] = context[field] if context.respond_to?(:[]) && context[field]
            end
          end
          provided_data
        end
        
        def agent_name(agent)
          case agent
          when Class
            agent.name
          when ChainedAgent, ConfiguredAgent, ParallelAgents, IteratingAgent
            agent.class.name
          else
            agent.to_s
          end
        end
      end
    end
  end
end