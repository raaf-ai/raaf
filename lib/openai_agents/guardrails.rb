# frozen_string_literal: true

# Main module file that loads all guardrail components
require_relative "guardrails/base"
require_relative "guardrails/input_guardrail"
require_relative "guardrails/output_guardrail"
require_relative "guardrails/built_in"

module OpenAIAgents
  # Guardrails provide input and output validation for agents
  # matching the Python SDK's guardrail functionality
  module Guardrails
    # Make builder methods available at module level
    extend InputGuardrailBuilder
    extend OutputGuardrailBuilder

    # Convenience method to create a profanity guardrail
    def self.profanity_guardrail(**options)
      BuiltIn::ProfanityGuardrail.new(**options)
    end

    # Convenience method to create a PII guardrail
    def self.pii_guardrail(**options)
      BuiltIn::PIIGuardrail.new(**options)
    end

    # Convenience method to create a length guardrail
    def self.length_guardrail(**options)
      BuiltIn::LengthGuardrail.new(**options)
    end

    # Convenience method to create a JSON schema guardrail
    def self.json_schema_guardrail(**options)
      BuiltIn::JSONSchemaGuardrail.new(**options)
    end

    # Convenience method to create a topic relevance guardrail
    def self.topic_relevance_guardrail(**options)
      BuiltIn::TopicRelevanceGuardrail.new(**options)
    end
  end
end