# frozen_string_literal: true

module RAAF
  module DSL
    module PipelineDSL
      # Extensions to RAAF::DSL::Agent for pipeline introspection
      module AgentIntrospection
        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          # Extract required fields from context_reader declarations
          def required_fields
            fields = []
            
            # From context_reader declarations
            if respond_to?(:_context_reader_config) && _context_reader_config
              fields.concat(_context_reader_config.keys)
            end
            
            # Add any fields defined in context block with defaults
            if respond_to?(:_agent_config) && _agent_config && _agent_config[:context_rules]
              defaults = _agent_config[:context_rules][:defaults]
              fields.concat(defaults.keys) if defaults
            end
            
            fields.uniq
          end
          
          # Extract provided fields from result_transform declarations
          def provided_fields
            return [] unless respond_to?(:_result_transformations) && _result_transformations
            
            _result_transformations.keys
          end
          
          # Check if agent requirements are satisfied
          def requirements_met?(context)
            required = required_fields
            
            # Check if context has all required fields
            if context.is_a?(Hash)
              required.all? { |field| context.key?(field) }
            elsif context.respond_to?(:keys)
              required.all? { |field| context.keys.include?(field) }
            else
              # For ContextVariables or other context objects
              required.all? do |field| 
                context.respond_to?(field) || 
                (context.respond_to?(:[]) && !context[field].nil?)
              end
            end
          end
          
          # Operator for chaining
          def >>(next_agent)
            ChainedAgent.new(self, next_agent)
          end
          
          # Operator for parallel
          def |(parallel_agent)
            ParallelAgents.new([self, parallel_agent])
          end
          
          # Inline configuration methods
          def timeout(seconds)
            ConfiguredAgent.new(self, timeout: seconds)
          end
          
          def retry(times)
            ConfiguredAgent.new(self, retry: times)
          end
          
          def limit(count)
            ConfiguredAgent.new(self, limit: count)
          end
        end
      end
    end
  end
end

# Include introspection in the Agent base class
module RAAF
  module DSL
    class Agent
      include PipelineDSL::AgentIntrospection
    end
  end
end