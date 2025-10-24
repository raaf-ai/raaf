# frozen_string_literal: true

module RAAF
  module DSL
    module IntelligentStreaming
      # Represents a streaming scope within a pipeline flow
      #
      # A scope defines the boundaries where intelligent streaming is active,
      # starting from a trigger agent and encompassing all subsequent agents
      # in the flow until a natural boundary (end of flow or next streaming agent).
      #
      # @example Simple scope
      #   scope = Scope.new(
      #     trigger_agent: QuickFitAnalyzer,
      #     scope_agents: [DeepIntel, Enrichment],
      #     stream_size: 100,
      #     array_field: :companies
      #   )
      class Scope
        attr_reader :trigger_agent, :scope_agents, :stream_size, :array_field

        # Initialize a new Scope
        #
        # @param trigger_agent [Class] The agent that triggers streaming
        # @param scope_agents [Array<Class>] Agents within the streaming scope
        # @param stream_size [Integer] Number of items per stream
        # @param array_field [Symbol, nil] Field containing array to stream
        def initialize(trigger_agent:, scope_agents:, stream_size:, array_field: nil)
          @trigger_agent = trigger_agent
          @scope_agents = scope_agents || []
          @stream_size = stream_size
          @array_field = array_field
        end

        # Check if this scope is valid
        #
        # @return [Boolean] true if scope has valid configuration
        def valid?
          !!(trigger_agent && stream_size && stream_size > 0)
        end

        # Check if an agent is included in this scope
        #
        # @param agent [Class] Agent to check
        # @return [Boolean] true if agent is in scope
        def includes_agent?(agent)
          agent == trigger_agent || scope_agents.include?(agent)
        end

        # Get all agents in scope (trigger + scope agents)
        #
        # @return [Array<Class>] All agents in the streaming scope
        def all_agents
          [trigger_agent] + scope_agents
        end

        # Convert scope to hash representation
        #
        # @return [Hash] Scope metadata as hash
        def to_h
          {
            trigger_agent: trigger_agent&.name || trigger_agent.to_s,
            scope_agents: scope_agents.map { |a| a&.name || a.to_s },
            stream_size: stream_size,
            array_field: array_field
          }
        end
      end
    end
  end
end