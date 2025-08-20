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
          # Check which fields might be available from initial context
          likely_initial = @missing_fields & [:product, :company, :market_data, :analysis_depth]
          truly_missing = @missing_fields - likely_initial
          
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
          
          if likely_initial.any?
            msg += <<~MSG
              
              Note: These fields are typically provided in initial context: #{likely_initial.inspect}
              Make sure to include them when creating the pipeline instance.
            MSG
          end
          
          msg
        end
        
        def producer_name
          @producer.respond_to?(:name) ? @producer.name : @producer.class.name
        end
        
        def consumer_name
          @consumer.respond_to?(:name) ? @consumer.name : @consumer.class.name
        end
      end
    end
  end
end