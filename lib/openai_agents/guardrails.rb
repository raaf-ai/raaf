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
    def self.profanity_guardrail(**)
      BuiltIn::ProfanityGuardrail.new(**)
    end

    # Convenience method to create a PII guardrail
    def self.pii_guardrail(**)
      BuiltIn::PIIGuardrail.new(**)
    end

    # Convenience method to create a length guardrail
    def self.length_guardrail(**)
      BuiltIn::LengthGuardrail.new(**)
    end

    # Convenience method to create a JSON schema guardrail
    def self.json_schema_guardrail(**)
      BuiltIn::JSONSchemaGuardrail.new(**)
    end

    # Convenience method to create a topic relevance guardrail
    def self.topic_relevance_guardrail(**)
      BuiltIn::TopicRelevanceGuardrail.new(**)
    end
  end
end
