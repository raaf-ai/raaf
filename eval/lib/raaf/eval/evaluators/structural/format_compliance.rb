# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Structural
        # Validates output format compliance
        class FormatCompliance
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :format_compliance

          # Evaluate format compliance
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :format (required)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            expected_format = options[:format]
            
            unless expected_format
              return {
                passed: false,
                score: 0.0,
                details: { error: "No format specified" },
                message: "Format validation requires :format parameter"
              }
            end

            value = field_context.value
            violations = check_format_compliance(value, expected_format)
            
            passed = violations.empty?

            {
              passed: passed,
              score: calculate_score(violations),
              details: {
                expected_format: expected_format,
                violations: violations,
                value_type: value.class.name
              },
              message: passed ? "Complies with format: #{expected_format}" : "Format violations: #{violations.join(', ')}"
            }
          end

          private

          def check_format_compliance(value, format)
            violations = []
            
            case format
            when :email
              violations << "invalid email format" unless valid_email?(value)
            when :url
              violations << "invalid URL format" unless valid_url?(value)
            when :markdown
              violations.concat(check_markdown_format(value))
            when :csv
              violations.concat(check_csv_format(value))
            when :xml
              violations.concat(check_xml_format(value))
            when :uuid
              violations << "invalid UUID format" unless valid_uuid?(value)
            when Hash
              # Custom format specification
              violations.concat(check_custom_format(value, format))
            else
              violations << "unknown format: #{format}"
            end

            violations
          end

          def valid_email?(value)
            return false unless value.is_a?(String)
            value.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
          end

          def valid_url?(value)
            return false unless value.is_a?(String)
            value.match?(/\Ahttps?:\/\/[\w\-]+(\.[\w\-]+)+[\/\w\-._~:?#\[\]@!\$&'()*+,;=.]*\z/)
          end

          def valid_uuid?(value)
            return false unless value.is_a?(String)
            value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
          end

          def check_markdown_format(value)
            violations = []
            return ["not a string"] unless value.is_a?(String)
            
            # Check for basic markdown structure
            lines = value.split("\n")
            
            # Check for headers
            has_headers = lines.any? { |l| l.match?(/^#+\s/) }
            
            # Check for unbalanced markdown
            if value.count("**") % 2 != 0
              violations << "unbalanced bold markers"
            end
            
            if value.count("*") % 2 != 0 && (value.count("*") - value.count("**") * 2) % 2 != 0
              violations << "unbalanced italic markers"
            end
            
            violations
          end

          def check_csv_format(value)
            violations = []
            return ["not a string"] unless value.is_a?(String)
            
            lines = value.split("\n")
            return ["empty CSV"] if lines.empty?
            
            # Check for consistent column count
            column_counts = lines.map { |l| l.split(",").size }
            unless column_counts.uniq.size == 1
              violations << "inconsistent column count"
            end
            
            violations
          end

          def check_xml_format(value)
            violations = []
            return ["not a string"] unless value.is_a?(String)
            
            # Basic XML validation
            unless value.match?(/<\?xml/)
              violations << "missing XML declaration"
            end
            
            # Check for balanced tags (simplified)
            open_tags = value.scan(/<(\w+)[^>]*>/).flatten
            close_tags = value.scan(/<\/(\w+)>/).flatten
            
            if open_tags.sort != close_tags.sort
              violations << "unbalanced XML tags"
            end
            
            violations
          end

          def check_custom_format(value, format_spec)
            violations = []
            
            if format_spec[:pattern] && value.is_a?(String)
              unless value.match?(Regexp.new(format_spec[:pattern]))
                violations << "doesn't match pattern: #{format_spec[:pattern]}"
              end
            end
            
            if format_spec[:min_length] && value.respond_to?(:length)
              if value.length < format_spec[:min_length]
                violations << "too short (min: #{format_spec[:min_length]})"
              end
            end
            
            if format_spec[:max_length] && value.respond_to?(:length)
              if value.length > format_spec[:max_length]
                violations << "too long (max: #{format_spec[:max_length]})"
              end
            end
            
            violations
          end

          def calculate_score(violations)
            return 1.0 if violations.empty?
            return 0.0 if violations.size >= 3

            1.0 - (violations.size / 3.0)
          end
        end
      end
    end
  end
end
