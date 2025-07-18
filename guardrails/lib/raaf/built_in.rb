# frozen_string_literal: true

require_relative "input_guardrail"
require_relative "output_guardrail"

module RAAF
  module Guardrails
    ##
    # Built-in guardrails for common use cases
    #
    # This module provides pre-built guardrails for common validation scenarios
    # like profanity detection, PII checking, length limits, JSON validation,
    # and topic relevance. These guardrails can be used directly or extended
    # for custom validation logic.
    #
    # @example Using built-in guardrails
    #   agent = RAAF::Agent.new(name: "Support")
    #   
    #   # Add profanity filter
    #   agent.add_input_guardrail(
    #     RAAF::Guardrails.profanity_guardrail
    #   )
    #   
    #   # Add PII detection
    #   agent.add_input_guardrail(
    #     RAAF::Guardrails.pii_guardrail
    #   )
    #   
    #   # Add length limit for outputs
    #   agent.add_output_guardrail(
    #     RAAF::Guardrails.length_guardrail(max_length: 1000)
    #   )
    #
    module BuiltIn
      ##
      # Input guardrail that detects profanity and inappropriate content
      #
      # Uses pattern matching to identify profanity, violent language,
      # and hate speech in user inputs. Can be customized with additional
      # patterns for specific use cases.
      #
      # @example Default usage
      #   guardrail = BuiltIn::ProfanityGuardrail.new
      #
      # @example Custom patterns
      #   guardrail = BuiltIn::ProfanityGuardrail.new(
      #     patterns: [
      #       /\bcustom_word\b/i,
      #       /\banother_pattern\b/i
      #     ]
      #   )
      #
      class ProfanityGuardrail < InputGuardrail
        # Default patterns for detecting inappropriate content
        INAPPROPRIATE_PATTERNS = [
          /\b(fuck|shit|damn|hell|ass|bitch|bastard)\b/i,
          /\b(kill|murder|suicide|die|death)\b/i,
          /\b(hate|racist|racism|sexist|sexism)\b/i
        ].freeze

        ##
        # Initialize profanity guardrail
        #
        # @param name [String] Name for the guardrail
        # @param patterns [Array<Regexp>] Custom patterns to check
        #
        def initialize(name: "profanity_check", patterns: INAPPROPRIATE_PATTERNS)
          @patterns = patterns
          super(method(:check_profanity), name: name)
        end

        private

        def check_profanity(_context, _agent, input)
          content = extract_content(input)

          @patterns.each do |pattern|
            if content.match?(pattern)
              return GuardrailFunctionOutput.new(
                output_info: {
                  matched_pattern: pattern.source,
                  content_snippet: content[0..100]
                },
                tripwire_triggered: true
              )
            end
          end

          GuardrailFunctionOutput.new(
            output_info: { checked: true, clean: true },
            tripwire_triggered: false
          )
        end

        def extract_content(input)
          case input
          when String
            input
          when Array
            input.map { |item| item[:content] || item["content"] || "" }.join(" ")
          else
            input.to_s
          end
        end
      end

      ##
      # Input guardrail that detects Personally Identifiable Information (PII)
      #
      # Scans input for common PII patterns including Social Security Numbers,
      # credit card numbers, email addresses, and phone numbers. Can be
      # customized with additional patterns for specific PII types.
      #
      # @example Default usage
      #   guardrail = BuiltIn::PIIGuardrail.new
      #
      # @example Custom PII patterns
      #   guardrail = BuiltIn::PIIGuardrail.new(
      #     patterns: {
      #       ssn: /\b\d{3}-\d{2}-\d{4}\b/,
      #       employee_id: /\bEMP\d{6}\b/,
      #       custom_id: /\b[A-Z]{2}\d{8}\b/
      #     }
      #   )
      #
      class PIIGuardrail < InputGuardrail
        # Default patterns for common PII types
        PII_PATTERNS = {
          ssn: /\b\d{3}-\d{2}-\d{4}\b/,
          credit_card: /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,
          email: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
          phone: /\b(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/
        }.freeze

        ##
        # Initialize PII detection guardrail
        #
        # @param name [String] Name for the guardrail
        # @param patterns [Hash<Symbol, Regexp>] Custom PII patterns
        #
        def initialize(name: "pii_check", patterns: PII_PATTERNS)
          @patterns = patterns
          super(method(:check_pii), name: name)
        end

        private

        def check_pii(_context, _agent, input)
          content = extract_content(input)
          detected_pii = []

          @patterns.each do |type, pattern|
            detected_pii << type if content.match?(pattern)
          end

          if detected_pii.any?
            GuardrailFunctionOutput.new(
              output_info: {
                detected_pii_types: detected_pii,
                message: "PII detected in input"
              },
              tripwire_triggered: true
            )
          else
            GuardrailFunctionOutput.new(
              output_info: { checked: true, pii_free: true },
              tripwire_triggered: false
            )
          end
        end

        def extract_content(input)
          case input
          when String
            input
          when Array
            input.map { |item| item[:content] || item["content"] || "" }.join(" ")
          else
            input.to_s
          end
        end
      end

      ##
      # Output guardrail that enforces response length limits
      #
      # Ensures agent responses stay within specified character limits.
      # Useful for maintaining concise responses or fitting within
      # UI constraints.
      #
      # @example Basic usage
      #   guardrail = BuiltIn::LengthGuardrail.new(max_length: 500)
      #
      # @example Custom length limit
      #   guardrail = BuiltIn::LengthGuardrail.new(
      #     max_length: 280,  # Twitter-style limit
      #     name: "tweet_length"
      #   )
      #
      class LengthGuardrail < OutputGuardrail
        ##
        # Initialize length validation guardrail
        #
        # @param max_length [Integer] Maximum allowed character count
        # @param name [String] Name for the guardrail
        #
        def initialize(max_length: 2000, name: "length_check")
          @max_length = max_length
          super(method(:check_length), name: name)
        end

        private

        def check_length(_context, _agent, output)
          length = output.to_s.length

          if length > @max_length
            GuardrailFunctionOutput.new(
              output_info: {
                length: length,
                max_length: @max_length,
                exceeded_by: length - @max_length
              },
              tripwire_triggered: true
            )
          else
            GuardrailFunctionOutput.new(
              output_info: {
                length: length,
                max_length: @max_length,
                within_limit: true
              },
              tripwire_triggered: false
            )
          end
        end
      end

      ##
      # Output guardrail that validates JSON structure against a schema
      #
      # Ensures agent outputs valid JSON that conforms to a specified
      # JSON Schema. Useful for structured data extraction and API
      # response validation.
      #
      # @example Basic schema validation
      #   schema = {
      #     type: "object",
      #     properties: {
      #       name: { type: "string" },
      #       age: { type: "integer" }
      #     },
      #     required: ["name"]
      #   }
      #   
      #   guardrail = BuiltIn::JSONSchemaGuardrail.new(schema: schema)
      #
      # @example Complex nested schema
      #   schema = {
      #     type: "object",
      #     properties: {
      #       user: {
      #         type: "object",
      #         properties: {
      #           id: { type: "integer" },
      #           email: { type: "string" }
      #         }
      #       },
      #       items: {
      #         type: "array",
      #         items: { type: "string" }
      #       }
      #     }
      #   }
      #
      class JSONSchemaGuardrail < OutputGuardrail
        ##
        # Initialize JSON schema validation guardrail
        #
        # @param schema [Hash] JSON Schema definition
        # @param name [String] Name for the guardrail
        #
        def initialize(schema:, name: "json_schema_validation")
          @schema = schema
          super(method(:validate_json), name: name)
        end

        private

        def validate_json(_context, _agent, output)
          # Try to parse as JSON
          error_result = validate_and_parse_json(output)
          return error_result if error_result

          data = case output
                 when String
                   JSON.parse(output)
                 when Hash
                   output
                 else
                   return GuardrailFunctionOutput.new(
                     output_info: {
                       error: "Output must be JSON string or Hash",
                       received_type: output.class.name
                     },
                     tripwire_triggered: true
                   )
                 end

          # Validate against schema if data is available
          validate_against_schema(data)
        end

        def validate_and_parse_json(output)
          return nil unless output.is_a?(String)

          begin
            JSON.parse(output)
            nil # No error
          rescue JSON::ParserError => e
            GuardrailFunctionOutput.new(
              output_info: {
                error: "Invalid JSON",
                parse_error: e.message
              },
              tripwire_triggered: true
            )
          end
        end

        def validate_against_schema(data)
          # Validate against schema
          validation_errors = schema_validation_errors(data, @schema)

          if validation_errors.any?
            GuardrailFunctionOutput.new(
              output_info: {
                valid: false,
                errors: validation_errors
              },
              tripwire_triggered: true
            )
          else
            GuardrailFunctionOutput.new(
              output_info: {
                valid: true,
                data: data
              },
              tripwire_triggered: false
            )
          end
        end

        def schema_validation_errors(data, schema, path = "")
          errors = []

          # Check type
          if schema[:type]
            expected_type = schema[:type]
            actual_type = case data
                          when Hash then "object"
                          when Array then "array"
                          when String then "string"
                          when Integer then "integer"
                          when Float then "number"
                          when TrueClass, FalseClass then "boolean"
                          when NilClass then "null"
                          else "unknown"
                          end

            errors << "#{path}: Expected #{expected_type}, got #{actual_type}" if expected_type != actual_type
          end

          # Object validation
          if schema[:type] == "object" && data.is_a?(Hash)
            # Required properties
            schema[:required]&.each do |prop|
              unless data.key?(prop.to_s) || data.key?(prop.to_sym)
                errors << "#{path}: Missing required property '#{prop}'"
              end
            end

            # Property validation
            schema[:properties]&.each do |prop, prop_schema|
              if data.key?(prop.to_s) || data.key?(prop.to_sym)
                value = data[prop.to_s] || data[prop.to_sym]
                errors.concat(validate_against_schema(value, prop_schema, "#{path}.#{prop}"))
              end
            end
          end

          # Array validation
          if schema[:type] == "array" && data.is_a?(Array) && schema[:items]
            data.each_with_index do |item, index|
              errors.concat(validate_against_schema(item, schema[:items], "#{path}[#{index}]"))
            end
          end

          errors
        end
      end

      ##
      # Input guardrail that ensures messages stay on allowed topics
      #
      # Validates that user input is relevant to specified allowed topics.
      # Uses simple keyword matching by default, but can be extended
      # with more sophisticated relevance detection.
      #
      # @example Basic topic filtering
      #   guardrail = BuiltIn::TopicRelevanceGuardrail.new(
      #     allowed_topics: ["customer support", "billing", "technical help"]
      #   )
      #
      # @example Domain-specific topics
      #   guardrail = BuiltIn::TopicRelevanceGuardrail.new(
      #     allowed_topics: [
      #       "product features",
      #       "pricing plans", 
      #       "integration support",
      #       "API documentation"
      #     ],
      #     name: "product_topics"
      #   )
      #
      class TopicRelevanceGuardrail < InputGuardrail
        ##
        # Initialize topic relevance guardrail
        #
        # @param allowed_topics [Array<String>] List of allowed topics
        # @param name [String] Name for the guardrail
        #
        def initialize(allowed_topics:, name: "topic_relevance")
          @allowed_topics = allowed_topics
          super(method(:check_relevance), name: name)
        end

        private

        def check_relevance(_context, _agent, input)
          content = extract_content(input).downcase

          # Simple keyword matching - in production, use embeddings or LLM
          relevant = @allowed_topics.any? do |topic|
            keywords = topic.downcase.split(/\s+/)
            keywords.any? { |keyword| content.include?(keyword) }
          end

          if relevant
            GuardrailFunctionOutput.new(
              output_info: {
                on_topic: true,
                allowed_topics: @allowed_topics
              },
              tripwire_triggered: false
            )
          else
            GuardrailFunctionOutput.new(
              output_info: {
                on_topic: false,
                allowed_topics: @allowed_topics,
                message: "Input appears to be off-topic"
              },
              tripwire_triggered: true
            )
          end
        end

        def extract_content(input)
          case input
          when String
            input
          when Array
            input.map { |item| item[:content] || item["content"] || "" }.join(" ")
          else
            input.to_s
          end
        end
      end
    end
  end
end
