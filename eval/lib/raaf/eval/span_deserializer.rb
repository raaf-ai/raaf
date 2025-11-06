# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # SpanDeserializer reconstructs RAAF agents from serialized span data
    class SpanDeserializer
      class << self
        ##
        # Deserialize span data to executable agent configuration
        # @param span_data [Hash] Serialized span data
        # @return [Hash] Agent configuration ready for execution
        def deserialize(span_data)
          {
            agent_name: span_data[:agent_name] || span_data["agent_name"],
            model: span_data[:model] || span_data["model"],
            instructions: span_data[:instructions] || span_data["instructions"],
            parameters: span_data[:parameters] || span_data["parameters"] || {},
            input_messages: span_data[:input_messages] || span_data["input_messages"] || [],
            context_variables: span_data[:context_variables] || span_data["context_variables"] || {},
            provider_details: span_data[:provider_details] || span_data["provider_details"] || {}
          }
        end

        ##
        # Validate serialized data completeness
        # @param span_data [Hash] Serialized span data
        # @return [Boolean] true if valid
        # @raise [DeserializationError] if invalid
        def validate!(span_data)
          required_fields = [:agent_name, :model, :input_messages]
          missing_fields = required_fields.select do |field|
            span_data[field].nil? && span_data[field.to_s].nil?
          end

          if missing_fields.any?
            raise DeserializationError, "Missing required fields: #{missing_fields.join(', ')}"
          end

          true
        end
      end
    end
  end
end
