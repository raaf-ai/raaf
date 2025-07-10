# frozen_string_literal: true

require "json"
require_relative "input_guardrail"

module OpenAIAgents
  module Guardrails
    # PII (Personally Identifiable Information) detection guardrail
    class PIIDetector < InputGuardrail
      # PII patterns with confidence scores
      PII_PATTERNS = {
        # High confidence patterns
        ssn: {
          pattern: /\b\d{3}-?\d{2}-?\d{4}\b/,
          name: "Social Security Number",
          confidence: 0.9,
          validator: ->(match) { match.gsub(/\D/, "").length == 9 }
        },
        credit_card: {
          pattern: /\b(?:\d[ -]*?){13,19}\b/,
          name: "Credit Card Number",
          confidence: 0.85,
          validator: ->(match) { luhn_valid?(match.gsub(/\D/, "")) }
        },
        email: {
          pattern: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
          name: "Email Address",
          confidence: 0.95,
          validator: ->(match) { match.include?("@") && match.include?(".") }
        },
        phone: {
          pattern: /\b(?:\+?1[-.\s]?)?\(?([0-9]{3})\)?[-.\s]?([0-9]{3})[-.\s]?([0-9]{4})\b/,
          name: "Phone Number",
          confidence: 0.8,
          validator: ->(match) { match.gsub(/\D/, "").length >= 10 }
        },

        # Medium confidence patterns
        ip_address: {
          pattern: /\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/,
          name: "IP Address",
          confidence: 0.7,
          validator: ->(match) { match.split(".").all? { |octet| octet.to_i <= 255 } }
        },
        drivers_license: {
          pattern: /\b[A-Z]{1,2}\d{5,8}\b/,
          name: "Driver's License",
          confidence: 0.6,
          validator: ->(match) { match.length.between?(6, 10) }
        },
        passport: {
          pattern: /\b[A-Z][0-9]{8}\b/,
          name: "Passport Number",
          confidence: 0.65,
          validator: ->(match) { match.length == 9 }
        },

        # Lower confidence patterns (may have false positives)
        bank_account: {
          pattern: /\b\d{8,17}\b/,
          name: "Bank Account Number",
          confidence: 0.5,
          validator: ->(match) { match.length.between?(8, 17) }
        },
        date_of_birth: {
          pattern: %r{\b(?:0[1-9]|1[0-2])[-/](?:0[1-9]|[12]\d|3[01])[-/](?:19|20)\d{2}\b},
          name: "Date of Birth",
          confidence: 0.6,
          validator: ->(match) { valid_date?(match) }
        },

        # Location patterns
        zip_code: {
          pattern: /\b\d{5}(?:-\d{4})?\b/,
          name: "ZIP Code",
          confidence: 0.5,
          validator: ->(match) { [5, 9].include?(match.gsub(/\D/, "").length) }
        },

        # Medical information
        medicare: {
          pattern: /\b\d{3}-?\d{2}-?\d{4}[A-Z]\b/i,
          name: "Medicare Number",
          confidence: 0.85,
          validator: ->(match) { match.gsub(/[^0-9A-Z]/i, "").length == 10 }
        },

        # Financial information
        iban: {
          pattern: /\b[A-Z]{2}\d{2}[A-Z0-9]{4}\d{7}(?:[A-Z0-9]?){0,16}\b/,
          name: "IBAN",
          confidence: 0.8,
          validator: ->(match) { match.length.between?(15, 34) }
        },

        # Custom patterns for names (lower confidence)
        person_name: {
          pattern: /\b(?:[A-Z][a-z]+ ){1,3}[A-Z][a-z]+\b/,
          name: "Person Name",
          confidence: 0.3,
          validator: ->(match) { common_name?(match) }
        }
      }.freeze

      # Common first and last names for validation
      COMMON_FIRST_NAMES = %w[
        John Jane Michael Mary David Sarah Robert Lisa James Jennifer
        William Linda Richard Karen Joseph Betty Thomas Helen Christopher
        Sandra Charles Donna Daniel Carol Matthew Ruth Anthony Sharon
      ].freeze

      COMMON_LAST_NAMES = %w[
        Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez
        Martinez Hernandez Lopez Gonzalez Wilson Anderson Thomas Taylor
        Moore Jackson Martin Lee Perez Thompson White Harris Sanchez
      ].freeze

      attr_reader :sensitivity_level, :custom_patterns, :redaction_enabled, :detection_stats

      def initialize(name: "pii_detector", sensitivity_level: :medium, redaction_enabled: true, custom_patterns: {})
        super(name: name)
        @sensitivity_level = sensitivity_level
        @redaction_enabled = redaction_enabled
        @custom_patterns = custom_patterns
        @detection_stats = Hash.new(0)
        @confidence_threshold = confidence_threshold_for_level(sensitivity_level)
      end

      def check(context)
        input_text = extract_text_from_context(context)
        output_text = context[:output] || ""

        input_detections = detect_pii(input_text, "input")
        output_detections = detect_pii(output_text, "output")

        all_detections = input_detections + output_detections

        if all_detections.any?
          handle_detections(context, all_detections)
        else
          GuardrailResult.new(
            passed: true,
            message: "No PII detected"
          )
        end
      end

      # Detect PII in text
      def detect_pii(text, source = "unknown")
        detections = []

        # Check standard patterns
        PII_PATTERNS.merge(@custom_patterns).each do |type, config|
          next if config[:confidence] < @confidence_threshold

          matches = text.scan(config[:pattern])
          matches.each do |match|
            match_str = match.is_a?(Array) ? match.join : match.to_s

            # Validate match if validator exists
            next if config[:validator] && !config[:validator].call(match_str)

            # Additional context checking for low confidence patterns
            next if (config[:confidence] < 0.6) && !context_suggests_pii?(text, match_str, type)

            position = text.index(match_str)
            detections << {
              type: type,
              name: config[:name],
              value: match_str,
              position: position,
              confidence: config[:confidence],
              source: source,
              context: extract_context(text, position, match_str.length)
            }

            @detection_stats[type] += 1
          end
        end

        # Deduplicate overlapping detections
        deduplicate_detections(detections)
      end

      # Redact PII from text
      def redact_text(text, detections = nil)
        detections ||= detect_pii(text)
        redacted = text.dup

        # Sort by position in reverse order to maintain positions
        detections.sort_by { |d| -d[:position] }.each do |detection|
          replacement = redaction_for(detection)
          redacted[detection[:position], detection[:value].length] = replacement
        end

        redacted
      end

      # Get detection statistics
      def stats
        {
          total_detections: @detection_stats.values.sum,
          by_type: @detection_stats.dup,
          sensitivity_level: @sensitivity_level,
          patterns_count: PII_PATTERNS.size + @custom_patterns.size
        }
      end

      # Reset detection statistics
      def reset_stats
        @detection_stats.clear
      end

      private

      def confidence_threshold_for_level(level)
        case level
        when :low
          0.8
        when :medium
          0.6
        when :high
          0.3
        else
          0.6
        end
      end

      def extract_text_from_context(context)
        if context[:messages]
          context[:messages].map { |m| m[:content] || m["content"] }.join(" ")
        elsif context[:input]
          context[:input].to_s
        else
          ""
        end
      end

      def handle_detections(context, detections)
        high_confidence = detections.select { |d| d[:confidence] >= 0.8 }
        medium_confidence = detections.select { |d| d[:confidence] >= 0.5 && d[:confidence] < 0.8 }

        if high_confidence.any?
          if @redaction_enabled && context[:output]
            # Redact PII from output
            context[:output] = redact_text(context[:output], detections.select { |d| d[:source] == "output" })
          end

          GuardrailResult.new(
            passed: false,
            message: format_detection_message(high_confidence),
            metadata: {
              detections: detections,
              redacted: @redaction_enabled,
              severity: "high"
            }
          )
        elsif medium_confidence.any? && @sensitivity_level != :low
          GuardrailResult.new(
            passed: true,
            message: "Potential PII detected (medium confidence)",
            metadata: {
              detections: medium_confidence,
              severity: "medium"
            }
          )
        else
          GuardrailResult.new(
            passed: true,
            message: "Low confidence PII patterns detected",
            metadata: {
              detections: detections,
              severity: "low"
            }
          )
        end
      end

      def format_detection_message(detections)
        types = detections.map { |d| d[:name] }.uniq
        "PII detected: #{types.join(", ")}"
      end

      def redaction_for(detection)
        case detection[:type]
        when :email
          parts = detection[:value].split("@")
          "#{parts[0][0..1]}***@***.***"
        when :phone
          "***-***-#{detection[:value][-4..]}"
        when :ssn
          "***-**-#{detection[:value][-4..]}"
        when :credit_card
          "****-****-****-#{detection[:value][-4..]}"
        else
          "[#{detection[:name].upcase}]"
        end
      end

      def extract_context(text, position, length, context_size = 20)
        start_pos = [0, position - context_size].max
        end_pos = [text.length, position + length + context_size].min

        context = text[start_pos...end_pos]

        # Add ellipsis if truncated
        context = "...#{context}" if start_pos > 0
        context = "#{context}..." if end_pos < text.length

        context
      end

      def deduplicate_detections(detections)
        # Remove overlapping detections, keeping higher confidence ones
        detections.sort_by { |d| [-d[:confidence], d[:position]] }
                  .each_with_object([]) do |detection, result|
          # Check if this detection overlaps with any existing one
          overlaps = result.any? do |existing|
            detection[:source] == existing[:source] &&
              ranges_overlap?(
                detection[:position]...(detection[:position] + detection[:value].length),
                existing[:position]...(existing[:position] + existing[:value].length)
              )
          end

          result << detection unless overlaps
        end
      end

      def ranges_overlap?(range1, range2)
        range1.cover?(range2.begin) || range2.cover?(range1.begin)
      end

      def context_suggests_pii?(text, match, type)
        # Look for contextual clues around the match
        position = text.index(match)
        return false unless position

        # Get surrounding context
        context_start = [0, position - 50].max
        context_end = [text.length, position + match.length + 50].min
        context = text[context_start...context_end].downcase

        case type
        when :person_name
          context =~ /\b(name|called|named|contact|person|individual|customer|client|user)\b/
        when :date_of_birth
          context =~ /\b(birth|born|dob|birthday|age)\b/
        when :bank_account
          context =~ /\b(account|bank|routing|iban|swift)\b/
        when :zip_code
          context =~ /\b(address|zip|postal|code|location)\b/
        else
          true
        end
      end

      # Luhn algorithm for credit card validation
      def self.luhn_valid?(number)
        return false unless number.match?(/^\d+$/)

        digits = number.chars.map(&:to_i)
        check_sum = digits.reverse.each_with_index.map do |digit, index|
          if index.odd?
            digit * 2 > 9 ? (digit * 2) - 9 : digit * 2
          else
            digit
          end
        end.sum

        (check_sum % 10).zero?
      end

      # Date validation
      def self.valid_date?(date_str)
        require "date"
        Date.parse(date_str.gsub(%r{[-/]}, "-"))
        true
      rescue ArgumentError
        false
      end

      # Name validation using common names
      def self.common_name?(name)
        parts = name.split(/\s+/)
        return false if parts.length < 2

        first_name = parts.first
        last_name = parts.last

        COMMON_FIRST_NAMES.any? { |n| n.casecmp(first_name) == 0 } ||
          COMMON_LAST_NAMES.any? { |n| n.casecmp(last_name) == 0 }
      end
    end

    # Specialized PII detector for healthcare contexts
    class HealthcarePIIDetector < PIIDetector
      HEALTHCARE_PATTERNS = {
        mrn: {
          pattern: /\b(?:MRN|Medical Record Number)[:\s]*([A-Z0-9]{6,12})\b/i,
          name: "Medical Record Number",
          confidence: 0.9,
          validator: ->(match) { match.length >= 6 }
        },
        npi: {
          pattern: /\b\d{10}\b/,
          name: "National Provider Identifier",
          confidence: 0.7,
          validator: ->(match) { valid_npi?(match) }
        },
        insurance_id: {
          pattern: /\b[A-Z]{3}\d{9}\b/,
          name: "Insurance ID",
          confidence: 0.75,
          validator: ->(match) { match.length == 12 }
        },
        dea: {
          pattern: /\b[A-Z]{2}\d{7}\b/,
          name: "DEA Number",
          confidence: 0.8,
          validator: ->(match) { valid_dea?(match) }
        }
      }.freeze

      def initialize(**args)
        super
        @custom_patterns.merge!(HEALTHCARE_PATTERNS)
      end

      def self.valid_npi?(number)
        return false unless number.match?(/^\d{10}$/)

        # NPI uses Luhn algorithm with specific implementation
        number.chars.map(&:to_i)
        # Prepend 80840 prefix for validation
        full_number = "80840#{number}"
        luhn_valid?(full_number)
      end

      def self.valid_dea?(number)
        return false unless number.match?(/^[A-Z]{2}\d{7}$/)

        # DEA number validation algorithm
        digits = number[2..].chars.map(&:to_i)
        sum1 = digits[0] + digits[2] + digits[4]
        sum2 = digits[1] + digits[3] + digits[5]
        check = (sum1 + (sum2 * 2)) % 10

        digits[6] == check
      end
    end

    # Specialized PII detector for financial contexts
    class FinancialPIIDetector < PIIDetector
      FINANCIAL_PATTERNS = {
        routing_number: {
          pattern: /\b\d{9}\b/,
          name: "Routing Number",
          confidence: 0.7,
          validator: ->(match) { valid_routing_number?(match) }
        },
        swift_code: {
          pattern: /\b[A-Z]{6}[A-Z0-9]{2}(?:[A-Z0-9]{3})?\b/,
          name: "SWIFT Code",
          confidence: 0.85,
          validator: ->(match) { [8, 11].include?(match.length) }
        },
        tax_id: {
          pattern: /\b\d{2}-?\d{7}\b/,
          name: "Tax ID/EIN",
          confidence: 0.8,
          validator: ->(match) { match.gsub(/\D/, "").length == 9 }
        },
        bitcoin_address: {
          pattern: /\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b/,
          name: "Bitcoin Address",
          confidence: 0.9,
          validator: ->(match) { match.length.between?(26, 35) }
        }
      }.freeze

      def initialize(**args)
        super
        @custom_patterns.merge!(FINANCIAL_PATTERNS)
      end

      def self.valid_routing_number?(number)
        return false unless number.match?(/^\d{9}$/)

        # ABA routing number validation
        digits = number.chars.map(&:to_i)
        checksum = ((3 * (digits[0] + digits[3] + digits[6])) +
                   (7 * (digits[1] + digits[4] + digits[7])) +
                   (digits[2] + digits[5] + digits[8])) % 10

        checksum.zero?
      end
    end
  end
end
