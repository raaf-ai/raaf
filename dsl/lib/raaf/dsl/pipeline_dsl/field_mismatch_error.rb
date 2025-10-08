# frozen_string_literal: true

module RAAF
  module DSL
    module PipelineDSL
      # Error raised when field requirements don't match between agents
      class FieldMismatchError < StandardError
        def initialize(producer, consumer, missing_fields, context_fields = [])
          @producer = producer
          @consumer = consumer
          @missing_fields = missing_fields
          @context_fields = context_fields
          super(build_message)
        end
        
        private
        
        def build_message
          # Check which fields might be available from pipeline context
          pipeline_provided = @missing_fields & @context_fields
          truly_missing = @missing_fields - pipeline_provided
          
          msg = <<~MSG
            Pipeline Field Mismatch Error!
            
            #{consumer_name} requires fields: #{@consumer.required_fields.inspect}
            #{producer_name} only provides: #{@producer.provided_fields.inspect}
          MSG
          
          if truly_missing.any?
            msg += <<~MSG
              
              Missing fields that must be provided: #{truly_missing.inspect}
              
              To fix this:
              1. Update #{producer_name}'s result_transform to provide: #{truly_missing.inspect}
              2. Or update #{consumer_name} to not require these fields
              3. Or add an intermediate agent that provides the transformation
            MSG
          end
          
          if pipeline_provided.any?
            msg += <<~MSG
              
              Note: These fields are available from pipeline context: #{pipeline_provided.inspect}
              Make sure they are declared in the pipeline's context block.
            MSG
          end
          
          msg
        end
        
        def producer_name
          extract_agent_name(@producer)
        end
        
        def consumer_name
          extract_agent_name(@consumer)
        end
        
        # Extract actual agent name from pipeline components
        def extract_agent_name(component)
          case component
          when RAAF::DSL::PipelineDSL::ChainedAgent
            # For chained agents, get the last agent in the chain (the one that provides fields)
            extract_agent_name(component.second)
          when RAAF::DSL::PipelineDSL::ParallelAgents
            # For parallel agents, show all agent names
            agent_names = component.agents.map { |agent| extract_agent_name(agent) }
            "(#{agent_names.join(' | ')})"
          when RAAF::DSL::PipelineDSL::BatchedAgent
            # For batched agents, get the wrapped component's name
            extract_agent_name(component.wrapped_component)
          when RAAF::DSL::PipelineDSL::IteratingAgent
            # For iterating agents, get the underlying agent class
            extract_agent_name(component.agent_class)
          when RAAF::DSL::PipelineDSL::RemappedAgent
            # For remapped agents, get the underlying agent class
            extract_agent_name(component.agent_class)
          when RAAF::DSL::PipelineDSL::ConfiguredAgent
            # For configured agents, get the underlying agent class
            extract_agent_name(component.agent_class)
          when Class
            # Regular class - return the name
            component.name
          else
            # Fallback to class name or object inspection
            if component.respond_to?(:name)
              component.name
            elsif component.respond_to?(:class)
              component.class.name
            else
              component.to_s
            end
          end
        end
      end
    end
  end
end