# frozen_string_literal: true

module RAAF

  module DSL

    module AgentDsl

      # Context storage configuration methods for agent DSL
      module Context

        extend ActiveSupport::Concern

        class_methods do
          # Configure context storage keys
          def stores_in_context(*keys)
            if keys.any?
              _agent_config[:context_storage_keys] = keys.map(&:to_sym)
            else
              _agent_config[:context_storage_keys] || []
            end
          end

          # Add a single context storage key
          def store_in_context(key)
            current_keys = _agent_config[:context_storage_keys] || []
            _agent_config[:context_storage_keys] = (current_keys + [key.to_sym]).uniq
          end

          # Get all context storage keys (including inherited ones)
          def context_storage_keys
            _agent_config[:context_storage_keys] || []
          end
        end

      end

    end

  end

end
