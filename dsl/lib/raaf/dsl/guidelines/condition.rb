# frozen_string_literal: true

module RAAF
  module DSL
    module Guidelines
      # Base class for all condition types
      # Conditions determine when a guideline should be applied
      class Condition
        # Factory method to wrap various condition formats
        # @param condition [Regexp, Hash, Proc, Condition, TrueClass] The condition to wrap
        # @return [Condition] A condition instance
        def self.wrap(condition)
          case condition
          when Condition
            condition
          when Regexp
            RegexCondition.new(condition)
          when Hash
            if condition[:type] == :llm
              LLMCondition.new(condition[:prompt])
            else
              SchemaCondition.new(condition)
            end
          when Proc
            ProcCondition.new(condition)
          when String
            KeywordCondition.new(condition)
          when Array
            KeywordCondition.new(*condition)
          when TrueClass
            AlwaysCondition.new
          else
            raise ArgumentError, "Unknown condition type: #{condition.class}"
          end
        end

        # Check if the condition matches the given context and input
        # @param context [Hash] The execution context
        # @param input [String, Hash] The input to check
        # @return [Boolean, Symbol] true if matches, false if not, :requires_llm_evaluation for deferred LLM check
        def matches?(context, input)
          raise NotImplementedError, "Subclasses must implement #matches?"
        end
      end

      # Condition that always matches
      class AlwaysCondition < Condition
        def matches?(_context, _input)
          true
        end

        def to_s
          "always"
        end
      end

      # Fast regex-based pattern matching
      # Use for detecting keywords or patterns in input text
      class RegexCondition < Condition
        attr_reader :pattern

        def initialize(pattern)
          @pattern = pattern
        end

        def matches?(_context, input)
          text = extract_text(input)
          return false if text.nil?

          @pattern.match?(text)
        end

        def to_s
          "regex(#{@pattern.inspect})"
        end

        private

        def extract_text(input)
          case input
          when String
            input
          when Hash
            input.values.select { |v| v.is_a?(String) }.join(" ")
          else
            input.to_s
          end
        end
      end

      # Simple keyword detection
      # Matches if any of the specified keywords appear in the input
      class KeywordCondition < Condition
        attr_reader :keywords

        def initialize(*keywords)
          @keywords = keywords.flatten.map(&:downcase)
        end

        def matches?(_context, input)
          text = extract_text(input)&.downcase
          return false if text.nil?

          @keywords.any? { |keyword| text.include?(keyword) }
        end

        def to_s
          "keywords(#{@keywords.join(', ')})"
        end

        private

        def extract_text(input)
          case input
          when String
            input
          when Hash
            input.values.select { |v| v.is_a?(String) }.join(" ")
          else
            input.to_s
          end
        end
      end

      # Field-based rules for structured context matching
      # Supports operators: :eq, :ne, :in, :not_in, :gt, :lt, :gte, :lte, :matches, :present, :blank
      class SchemaCondition < Condition
        OPERATORS = %i[eq ne in not_in gt lt gte lte matches present blank contains].freeze

        attr_reader :field, :operator, :value

        def initialize(config)
          @field = config[:field]
          @operator = config[:operator] || :eq
          @value = config[:value]

          unless OPERATORS.include?(@operator)
            raise ArgumentError, "Unknown operator: #{@operator}. Valid operators: #{OPERATORS.join(', ')}"
          end
        end

        def matches?(context, _input)
          field_value = extract_field_value(context, @field)
          evaluate_operator(field_value)
        end

        def to_s
          "schema(#{@field} #{@operator} #{@value.inspect})"
        end

        private

        def extract_field_value(context, field)
          return nil unless context.is_a?(Hash)

          # Support nested field access with dot notation
          fields = field.to_s.split(".")
          fields.reduce(context) do |obj, f|
            break nil unless obj.is_a?(Hash)

            obj[f.to_sym] || obj[f.to_s]
          end
        end

        def evaluate_operator(field_value)
          case @operator
          when :eq
            field_value == @value
          when :ne
            field_value != @value
          when :in
            Array(@value).include?(field_value)
          when :not_in
            !Array(@value).include?(field_value)
          when :gt
            field_value.respond_to?(:>) && field_value > @value
          when :lt
            field_value.respond_to?(:<) && field_value < @value
          when :gte
            field_value.respond_to?(:>=) && field_value >= @value
          when :lte
            field_value.respond_to?(:<=) && field_value <= @value
          when :matches
            field_value.is_a?(String) && @value.is_a?(Regexp) && @value.match?(field_value)
          when :present
            !field_value.nil? && field_value != "" && field_value != []
          when :blank
            field_value.nil? || field_value == "" || field_value == []
          when :contains
            field_value.is_a?(Array) && field_value.include?(@value)
          else
            false
          end
        end
      end

      # Custom Ruby logic condition
      # The proc receives (context, input) and should return true/false
      class ProcCondition < Condition
        attr_reader :proc

        def initialize(proc)
          @proc = proc
        end

        def matches?(context, input)
          result = @proc.call(context, input)
          result == true
        rescue StandardError => e
          RAAF.logger.warn "[Guidelines] ProcCondition raised error: #{e.message}"
          false
        end

        def to_s
          "proc(...)"
        end
      end

      # Complex condition requiring LLM evaluation (fallback)
      # Use sparingly - adds latency and cost
      class LLMCondition < Condition
        attr_reader :prompt

        def initialize(prompt)
          @prompt = prompt
        end

        # Returns :requires_llm_evaluation to signal GuidelineEngine
        # that this condition needs LLM-based evaluation
        def matches?(_context, _input)
          :requires_llm_evaluation
        end

        # Actual LLM evaluation is performed by GuidelineEngine
        # This method is called by the engine with an LLM provider
        def evaluate_with_llm(llm_provider, context, input)
          evaluation_prompt = build_evaluation_prompt(context, input)

          response = llm_provider.chat_completion(
            messages: [{ role: "user", content: evaluation_prompt }],
            model: "gpt-4o-mini",
            max_tokens: 10,
            temperature: 0
          )

          parse_llm_response(response)
        rescue StandardError => e
          RAAF.logger.error "[Guidelines] LLMCondition evaluation failed: #{e.message}"
          false
        end

        def to_s
          "llm(#{@prompt.truncate(50)})"
        end

        private

        def build_evaluation_prompt(context, input)
          <<~PROMPT
            Evaluate if the following condition applies to the given context and input.
            Respond with ONLY "yes" or "no".

            CONDITION: #{@prompt}

            CONTEXT: #{context.to_json}

            INPUT: #{input.is_a?(Hash) ? input.to_json : input}

            Does this condition apply? (yes/no)
          PROMPT
        end

        def parse_llm_response(response)
          content = response.dig(:choices, 0, :message, :content) ||
                    response.dig("choices", 0, "message", "content") ||
                    ""
          content.strip.downcase.start_with?("yes")
        end
      end

      # Composite condition that combines multiple conditions with AND logic
      class AndCondition < Condition
        attr_reader :conditions

        def initialize(*conditions)
          @conditions = conditions.map { |c| Condition.wrap(c) }
        end

        def matches?(context, input)
          @conditions.all? do |condition|
            result = condition.matches?(context, input)
            return :requires_llm_evaluation if result == :requires_llm_evaluation

            result
          end
        end

        def to_s
          "and(#{@conditions.map(&:to_s).join(', ')})"
        end
      end

      # Composite condition that combines multiple conditions with OR logic
      class OrCondition < Condition
        attr_reader :conditions

        def initialize(*conditions)
          @conditions = conditions.map { |c| Condition.wrap(c) }
        end

        def matches?(context, input)
          llm_needed = false

          @conditions.each do |condition|
            result = condition.matches?(context, input)
            return true if result == true

            llm_needed = true if result == :requires_llm_evaluation
          end

          llm_needed ? :requires_llm_evaluation : false
        end

        def to_s
          "or(#{@conditions.map(&:to_s).join(', ')})"
        end
      end

      # Negation condition
      class NotCondition < Condition
        attr_reader :condition

        def initialize(condition)
          @condition = Condition.wrap(condition)
        end

        def matches?(context, input)
          result = @condition.matches?(context, input)
          return :requires_llm_evaluation if result == :requires_llm_evaluation

          !result
        end

        def to_s
          "not(#{@condition})"
        end
      end
    end
  end
end
