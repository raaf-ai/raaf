# frozen_string_literal: true

require_relative "input_guardrail"
require_relative "output_guardrail"

module OpenAIAgents
  module Guardrails
    # Built-in guardrails for common use cases
    module BuiltIn
      # Input guardrail that checks for profanity or inappropriate content
      class ProfanityGuardrail < InputGuardrail
        INAPPROPRIATE_PATTERNS = [
          /\b(fuck|shit|damn|hell|ass|bitch|bastard)\b/i,
          /\b(kill|murder|suicide|die|death)\b/i,
          /\b(hate|racist|racism|sexist|sexism)\b/i
        ].freeze

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

      # Input guardrail that checks for PII (Personal Identifiable Information)
      class PIIGuardrail < InputGuardrail
        PII_PATTERNS = {
          ssn: /\b\d{3}-\d{2}-\d{4}\b/,
          credit_card: /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,
          email: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
          phone: /\b(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/
        }.freeze

        def initialize(name: "pii_check", patterns: PII_PATTERNS)
          @patterns = patterns
          super(method(:check_pii), name: name)
        end

        private

        def check_pii(_context, _agent, input)
          content = extract_content(input)
          detected_pii = []

          @patterns.each do |type, pattern|
            if content.match?(pattern)
              detected_pii << type
            end
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

      # Output guardrail that checks response length
      class LengthGuardrail < OutputGuardrail
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

      # Output guardrail that validates JSON structure
      class JSONSchemaGuardrail < OutputGuardrail
        def initialize(schema:, name: "json_schema_validation")
          @schema = schema
          super(method(:validate_json), name: name)
        end

        private

        def validate_json(_context, _agent, output)
          # Try to parse as JSON
          data = case output
          when String
            begin
              JSON.parse(output)
            rescue JSON::ParserError => e
              return GuardrailFunctionOutput.new(
                output_info: { 
                  error: "Invalid JSON",
                  parse_error: e.message
                },
                tripwire_triggered: true
              )
            end
          when Hash
            output
          else
            return GuardrailFunctionOutput.new(
              output_info: { 
                error: "Output is not JSON",
                output_type: output.class.name
              },
              tripwire_triggered: true
            )
          end

          # Validate against schema
          validation_errors = validate_against_schema(data, @schema)
          
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

        def validate_against_schema(data, schema, path = "")
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
            
            if expected_type != actual_type
              errors << "#{path}: Expected #{expected_type}, got #{actual_type}"
            end
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
          if schema[:type] == "array" && data.is_a?(Array)
            if schema[:items]
              data.each_with_index do |item, index|
                errors.concat(validate_against_schema(item, schema[:items], "#{path}[#{index}]"))
              end
            end
          end

          errors
        end
      end

      # Topic relevance guardrail - checks if input is on-topic
      class TopicRelevanceGuardrail < InputGuardrail
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