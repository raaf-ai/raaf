# frozen_string_literal: true

require_relative "scope"

module RAAF
  module DSL
    module IntelligentStreaming
      # Manages intelligent streaming scopes within a pipeline
      #
      # Responsible for detecting streaming scopes from a pipeline flow,
      # validating scope configurations, and managing scope execution.
      #
      # @example Detecting scopes in a pipeline flow
      #   manager = Manager.new
      #   scopes = manager.detect_scopes(flow_chain)
      class Manager
        include RAAF::Logger if defined?(RAAF::Logger)

        # Detect streaming scopes from a pipeline flow chain
        #
        # @param flow_chain [Object] The pipeline flow chain (can be nested with >> and | operators)
        # @return [Array<Scope>] Array of detected streaming scopes
        def detect_scopes(flow_chain)
          agents = flatten_flow_chain(flow_chain)
          scopes = []
          current_scope = nil

          agents.each_with_index do |agent, index|
            agent_class = resolve_agent_class(agent)

            if agent_class.respond_to?(:streaming_trigger?) && agent_class.streaming_trigger?
              # Start a new scope
              if current_scope
                # Close the previous scope
                scopes << build_scope(current_scope)
              end

              current_scope = {
                trigger_agent: agent_class,
                trigger_index: index,
                agents: [],
                config: agent_class.streaming_config
              }
            elsif current_scope
              # Add agent to current scope
              current_scope[:agents] << agent_class

              # Check if this agent triggers a new scope (would close current)
              if agent_class.respond_to?(:streaming_trigger?) && agent_class.streaming_trigger?
                # This agent starts a new scope, close current
                scopes << build_scope(current_scope)
                current_scope = {
                  trigger_agent: agent_class,
                  trigger_index: index,
                  agents: [],
                  config: agent_class.streaming_config
                }
              end
            end
          end

          # Close any remaining scope
          if current_scope
            scopes << build_scope(current_scope)
          end

          validate_scopes!(scopes)
          scopes
        end

        # Validate an array of scopes
        #
        # @param scopes [Array<Scope>] Scopes to validate
        # @raise [ConfigurationError] if scopes are invalid
        def validate_scopes!(scopes)
          scopes.each do |scope|
            unless scope.valid?
              raise ConfigurationError, "Invalid streaming scope: #{scope.to_h}"
            end
          end
        end

        # Flatten a flow chain into a linear array of agents
        #
        # @param chain [Object] Flow chain with >> and | operators
        # @return [Array] Flattened array of agents
        def flatten_flow_chain(chain)
          return [chain] unless chain.respond_to?(:to_a) ||
                                chain.respond_to?(:agents) ||
                                (chain.respond_to?(:first_agent) && chain.respond_to?(:second_agent))

          if chain.respond_to?(:to_a)
            # Handle arrays and parallel agents
            chain.to_a.flat_map { |item| flatten_flow_chain(item) }
          elsif chain.respond_to?(:agents)
            # Handle ChainedAgent and similar wrappers
            chain.agents.flat_map { |agent| flatten_flow_chain(agent) }
          elsif chain.respond_to?(:first_agent) && chain.respond_to?(:second_agent)
            # Handle ChainedAgent structure
            flatten_flow_chain(chain.first_agent) + flatten_flow_chain(chain.second_agent)
          else
            [chain]
          end
        end

        private

        def build_scope(scope_data)
          config = scope_data[:config]

          Scope.new(
            trigger_agent: scope_data[:trigger_agent],
            scope_agents: scope_data[:agents],
            stream_size: config.stream_size,
            array_field: config.array_field
          )
        end

        def resolve_agent_class(agent)
          case agent
          when Class
            agent
          when String, Symbol
            # Try to constantize string/symbol agent names
            Object.const_get(agent.to_s)
          else
            # For instances or wrappers, try to get the class
            agent.class
          end
        rescue NameError
          agent
        end

        class ConfigurationError < StandardError; end
      end
    end
  end
end