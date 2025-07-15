# frozen_string_literal: true

# Main module file that loads all guardrail components
require_relative "guardrails/base"
require_relative "guardrails/input_guardrail"
require_relative "guardrails/output_guardrail"
require_relative "guardrails/built_in"

module RubyAIAgentsFactory
  ##
  # Guardrails provide safety and validation mechanisms for agent conversations
  #
  # The Guardrails module implements a comprehensive system for validating
  # both user inputs and agent outputs, ensuring conversations remain safe,
  # appropriate, and within defined boundaries. This matches the Python SDK's
  # guardrail functionality for cross-language compatibility.
  #
  # ## Types of Guardrails
  #
  # - **Input Guardrails**: Validate user messages before processing
  # - **Output Guardrails**: Validate agent responses before returning
  #
  # ## Built-in Guardrails
  #
  # - `profanity_guardrail`: Detects and blocks profane content
  # - `pii_guardrail`: Identifies personally identifiable information
  # - `length_guardrail`: Enforces message length limits
  # - `json_schema_guardrail`: Validates JSON structure
  # - `topic_relevance_guardrail`: Ensures content stays on topic
  #
  # @example Using built-in guardrails
  #   agent = RubyAIAgentsFactory::Agent.new(name: "Support")
  #   
  #   # Add input validation
  #   agent.add_input_guardrail(
  #     RubyAIAgentsFactory::Guardrails.profanity_guardrail
  #   )
  #   
  #   # Add output validation
  #   agent.add_output_guardrail(
  #     RubyAIAgentsFactory::Guardrails.pii_guardrail(
  #       tripwire: true,
  #       redact: true
  #     )
  #   )
  #
  # @example Creating custom guardrails
  #   custom_guardrail = RubyAIAgentsFactory::Guardrails.create_input_guardrail(
  #     name: "business_hours",
  #     validate: ->(context, agent, input) {
  #       if Time.now.hour < 9 || Time.now.hour > 17
  #         RubyAIAgentsFactory::Guardrails::GuardrailResult.new(
  #           safe: false,
  #           flagged: true,
  #           explanation: "Support is only available 9 AM - 5 PM"
  #         )
  #       else
  #         RubyAIAgentsFactory::Guardrails::GuardrailResult.new(safe: true)
  #       end
  #     }
  #   )
  #
  module Guardrails
    # Make builder methods available at module level
    extend InputGuardrailBuilder
    extend OutputGuardrailBuilder

    ##
    # Create a profanity detection guardrail
    #
    # Detects and optionally blocks messages containing profane language.
    #
    # @param tripwire [Boolean] Whether to raise an exception on detection
    # @param custom_words [Array<String>] Additional words to flag
    # @return [BuiltIn::ProfanityGuardrail] Configured guardrail
    #
    # @example
    #   guardrail = Guardrails.profanity_guardrail(
    #     tripwire: true,
    #     custom_words: ["spam", "scam"]
    #   )
    #
    def self.profanity_guardrail(**)
      BuiltIn::ProfanityGuardrail.new(**)
    end

    ##
    # Create a PII (Personally Identifiable Information) detection guardrail
    #
    # Identifies sensitive information like SSNs, credit cards, emails, etc.
    #
    # @param tripwire [Boolean] Whether to raise an exception on detection
    # @param redact [Boolean] Whether to redact detected PII
    # @param types [Array<Symbol>] Types of PII to detect
    # @return [BuiltIn::PIIGuardrail] Configured guardrail
    #
    # @example
    #   guardrail = Guardrails.pii_guardrail(
    #     redact: true,
    #     types: [:ssn, :credit_card, :email]
    #   )
    #
    def self.pii_guardrail(**)
      BuiltIn::PIIGuardrail.new(**)
    end

    ##
    # Create a message length validation guardrail
    #
    # Enforces minimum and maximum length constraints on messages.
    #
    # @param min_length [Integer, nil] Minimum allowed length
    # @param max_length [Integer, nil] Maximum allowed length
    # @param tripwire [Boolean] Whether to raise an exception on violation
    # @return [BuiltIn::LengthGuardrail] Configured guardrail
    #
    # @example
    #   guardrail = Guardrails.length_guardrail(
    #     min_length: 10,
    #     max_length: 1000
    #   )
    #
    def self.length_guardrail(**)
      BuiltIn::LengthGuardrail.new(**)
    end

    ##
    # Create a JSON schema validation guardrail
    #
    # Validates that output conforms to a specified JSON schema.
    #
    # @param schema [Hash] JSON schema definition
    # @param tripwire [Boolean] Whether to raise an exception on violation
    # @return [BuiltIn::JSONSchemaGuardrail] Configured guardrail
    #
    # @example
    #   guardrail = Guardrails.json_schema_guardrail(
    #     schema: {
    #       type: "object",
    #       properties: {
    #         name: { type: "string" },
    #         age: { type: "integer", minimum: 0 }
    #       },
    #       required: ["name"]
    #     }
    #   )
    #
    def self.json_schema_guardrail(**)
      BuiltIn::JSONSchemaGuardrail.new(**)
    end

    ##
    # Create a topic relevance guardrail
    #
    # Ensures messages stay relevant to specified topics.
    #
    # @param allowed_topics [Array<String>] List of allowed topics
    # @param blocked_topics [Array<String>] List of blocked topics
    # @param tripwire [Boolean] Whether to raise an exception on violation
    # @return [BuiltIn::TopicRelevanceGuardrail] Configured guardrail
    #
    # @example
    #   guardrail = Guardrails.topic_relevance_guardrail(
    #     allowed_topics: ["customer support", "billing"],
    #     blocked_topics: ["politics", "personal advice"]
    #   )
    #
    def self.topic_relevance_guardrail(**)
      BuiltIn::TopicRelevanceGuardrail.new(**)
    end
  end
end
