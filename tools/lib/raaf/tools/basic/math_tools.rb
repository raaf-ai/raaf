# frozen_string_literal: true

module RAAF
  module Tools
    module Basic
      ##
      # Mathematical tools for AI agents
      #
      # Provides safe mathematical calculations, unit conversions, random number
      # generation, and statistical analysis capabilities.
      #
      class MathTools
        include RAAF::Logger

        class << self
          ##
          # Safe calculator tool
          #
          # @return [RAAF::FunctionTool] Calculator tool
          #
          def calculate
            RAAF::FunctionTool.new(
              method(:safe_calculate),
              name: "calculate",
              description: "Perform safe mathematical calculations",
              parameters: {
                type: "object",
                properties: {
                  expression: {
                    type: "string",
                    description: "Mathematical expression to evaluate (e.g., '2 + 3', '10 * 5')"
                  }
                },
                required: ["expression"]
              }
            )
          end

          ##
          # Unit conversion tool
          #
          # @return [RAAF::FunctionTool] Unit conversion tool
          #
          def convert_units
            RAAF::FunctionTool.new(
              method(:convert_units_impl),
              name: "convert_units",
              description: "Convert between different units of measurement",
              parameters: {
                type: "object",
                properties: {
                  value: {
                    type: "number",
                    description: "The value to convert"
                  },
                  from_unit: {
                    type: "string",
                    description: "Source unit (e.g., 'km', 'lb', 'celsius')"
                  },
                  to_unit: {
                    type: "string",
                    description: "Target unit (e.g., 'miles', 'kg', 'fahrenheit')"
                  }
                },
                required: ["value", "from_unit", "to_unit"]
              }
            )
          end

          ##
          # Random number generation tool
          #
          # @return [RAAF::FunctionTool] Random generator tool
          #
          def generate_random
            RAAF::FunctionTool.new(
              method(:generate_random_impl),
              name: "generate_random",
              description: "Generate random numbers, strings, or selections",
              parameters: {
                type: "object",
                properties: {
                  type: {
                    type: "string",
                    enum: ["integer", "float", "string", "choice", "uuid"],
                    description: "Type of random generation"
                  },
                  min: {
                    type: "number",
                    description: "Minimum value (for numbers)"
                  },
                  max: {
                    type: "number",
                    description: "Maximum value (for numbers)"
                  },
                  length: {
                    type: "integer",
                    description: "Length (for strings)",
                    default: 10
                  },
                  choices: {
                    type: "array",
                    description: "Array of choices to select from",
                    items: { type: "string" }
                  }
                },
                required: ["type"]
              }
            )
          end

          ##
          # Statistical analysis tool
          #
          # @return [RAAF::FunctionTool] Statistical analysis tool
          #
          def statistical_analysis
            RAAF::FunctionTool.new(
              method(:analyze_statistics),
              name: "statistical_analysis",
              description: "Perform statistical analysis on numerical data",
              parameters: {
                type: "object",
                properties: {
                  data: {
                    type: "array",
                    items: { type: "number" },
                    description: "Array of numerical values"
                  },
                  analysis_type: {
                    type: "string",
                    enum: ["descriptive", "distribution", "correlation"],
                    description: "Type of statistical analysis",
                    default: "descriptive"
                  }
                },
                required: ["data"]
              }
            )
          end

          private

          def safe_calculate(expression:)
            return "Empty expression provided" if expression.nil? || expression.empty?

            # Security: Remove any dangerous characters
            cleaned_expr = expression.gsub(/[^0-9+\-*\/\s\(\).]/, "")
            
            return "Invalid expression: contains unsafe characters" if cleaned_expr != expression

            begin
              # Handle basic arithmetic expressions safely
              result = evaluate_expression(cleaned_expr)
              "The result is: #{result}"
            rescue StandardError => e
              "Error: #{e.message}"
            end
          end

          def convert_units_impl(value:, from_unit:, to_unit:)
            return "Invalid value" unless value.is_a?(Numeric)

            # Conversion factors to base units
            conversions = {
              # Length (meters)
              "mm" => 0.001, "cm" => 0.01, "m" => 1, "km" => 1000,
              "inch" => 0.0254, "ft" => 0.3048, "yard" => 0.9144, "mile" => 1609.34,
              
              # Weight (grams)
              "mg" => 0.001, "g" => 1, "kg" => 1000,
              "oz" => 28.35, "lb" => 453.59,
              
              # Temperature (handled separately)
              "celsius" => :celsius, "fahrenheit" => :fahrenheit, "kelvin" => :kelvin,
              
              # Volume (liters)
              "ml" => 0.001, "l" => 1, "liter" => 1,
              "cup" => 0.236588, "pint" => 0.473176, "quart" => 0.946353, "gallon" => 3.78541
            }

            from_factor = conversions[from_unit.downcase]
            to_factor = conversions[to_unit.downcase]

            return "Unknown unit: #{from_unit}" unless from_factor
            return "Unknown unit: #{to_unit}" unless to_factor

            # Handle temperature conversions separately
            if [from_factor, to_factor].any? { |f| f.is_a?(Symbol) }
              result = convert_temperature(value, from_unit.downcase, to_unit.downcase)
            else
              # Standard unit conversion
              base_value = value * from_factor
              result = base_value / to_factor
            end

            {
              original_value: value,
              original_unit: from_unit,
              converted_value: result.round(6),
              converted_unit: to_unit
            }.to_json
          end

          def generate_random_impl(type:, min: nil, max: nil, length: 10, choices: nil)
            case type
            when "integer"
              min ||= 0
              max ||= 100
              rand(min..max)
            when "float"
              min ||= 0.0
              max ||= 1.0
              rand * (max - min) + min
            when "string"
              chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
              Array.new(length) { chars.sample }.join
            when "choice"
              return "No choices provided" unless choices && !choices.empty?
              choices.sample
            when "uuid"
              require "securerandom"
              SecureRandom.uuid
            else
              "Unknown random type: #{type}"
            end
          end

          def analyze_statistics(data:, analysis_type: "descriptive")
            return "Empty data provided" if data.nil? || data.empty?
            return "Data must be an array of numbers" unless data.all? { |x| x.is_a?(Numeric) }

            case analysis_type
            when "descriptive"
              descriptive_stats(data)
            when "distribution"
              distribution_stats(data)
            when "correlation"
              "Correlation analysis requires paired data"
            else
              "Unknown analysis type: #{analysis_type}"
            end
          end

          def evaluate_expression(expr)
            # Simple expression evaluator for basic arithmetic
            # Only handles: +, -, *, /, (, )
            
            # Remove spaces
            expr = expr.gsub(/\s+/, "")
            
            # Check for valid characters only
            return "Invalid expression" unless expr.match?(/\A[0-9+\-*\/\(\).]+\z/)
            
            # Use a simple recursive descent parser
            tokens = tokenize(expr)
            result = parse_expression(tokens)
            
            return "Invalid expression" if result.nil?
            
            result
          end

          def tokenize(expr)
            tokens = []
            i = 0
            while i < expr.length
              case expr[i]
              when /\d/
                # Parse number
                j = i
                while j < expr.length && expr[j].match?(/[\d.]/)
                  j += 1
                end
                tokens << expr[i...j].to_f
                i = j
              when /[+\-*\/()]/
                tokens << expr[i]
                i += 1
              else
                i += 1
              end
            end
            tokens
          end

          def parse_expression(tokens)
            # Simple expression parser
            # This is a basic implementation - in production, use a proper parser
            begin
              # Convert to postfix notation and evaluate
              postfix = infix_to_postfix(tokens)
              evaluate_postfix(postfix)
            rescue StandardError
              nil
            end
          end

          def infix_to_postfix(tokens)
            # Shunting-yard algorithm
            output = []
            operators = []
            precedence = { "+" => 1, "-" => 1, "*" => 2, "/" => 2 }
            
            tokens.each do |token|
              if token.is_a?(Numeric)
                output << token
              elsif token == "("
                operators << token
              elsif token == ")"
                while operators.last != "("
                  output << operators.pop
                end
                operators.pop  # Remove "("
              elsif precedence[token]
                while !operators.empty? && operators.last != "(" && 
                      precedence[operators.last] && precedence[operators.last] >= precedence[token]
                  output << operators.pop
                end
                operators << token
              end
            end
            
            output + operators.reverse
          end

          def evaluate_postfix(postfix)
            stack = []
            
            postfix.each do |token|
              if token.is_a?(Numeric)
                stack << token
              else
                right = stack.pop
                left = stack.pop
                
                case token
                when "+"
                  stack << left + right
                when "-"
                  stack << left - right
                when "*"
                  stack << left * right
                when "/"
                  raise "Division by zero" if right == 0
                  stack << left / right
                end
              end
            end
            
            stack.first
          end

          def convert_temperature(value, from_unit, to_unit)
            # Convert to Celsius first
            celsius = case from_unit
                     when "celsius"
                       value
                     when "fahrenheit"
                       (value - 32) * 5 / 9
                     when "kelvin"
                       value - 273.15
                     else
                       raise "Unknown temperature unit: #{from_unit}"
                     end

            # Convert from Celsius to target unit
            case to_unit
            when "celsius"
              celsius
            when "fahrenheit"
              celsius * 9 / 5 + 32
            when "kelvin"
              celsius + 273.15
            else
              raise "Unknown temperature unit: #{to_unit}"
            end
          end

          def descriptive_stats(data)
            sorted_data = data.sort
            n = data.length
            
            mean = data.sum / n.to_f
            median = n.odd? ? sorted_data[n/2] : (sorted_data[n/2-1] + sorted_data[n/2]) / 2.0
            mode = data.group_by(&:itself).max_by { |_, v| v.length }&.first
            
            variance = data.sum { |x| (x - mean) ** 2 } / n.to_f
            std_dev = Math.sqrt(variance)
            
            {
              count: n,
              mean: mean.round(6),
              median: median.round(6),
              mode: mode,
              min: sorted_data.first,
              max: sorted_data.last,
              range: sorted_data.last - sorted_data.first,
              variance: variance.round(6),
              standard_deviation: std_dev.round(6)
            }.to_json
          end

          def distribution_stats(data)
            sorted_data = data.sort
            n = data.length
            
            # Quartiles
            q1 = percentile(sorted_data, 25)
            q3 = percentile(sorted_data, 75)
            iqr = q3 - q1
            
            {
              quartile_1: q1,
              quartile_3: q3,
              interquartile_range: iqr,
              percentile_5: percentile(sorted_data, 5),
              percentile_95: percentile(sorted_data, 95),
              outliers: detect_outliers(data, q1, q3, iqr)
            }.to_json
          end

          def percentile(sorted_data, p)
            n = sorted_data.length
            index = (p / 100.0) * (n - 1)
            
            if index == index.to_i
              sorted_data[index.to_i]
            else
              lower = sorted_data[index.floor]
              upper = sorted_data[index.ceil]
              lower + (upper - lower) * (index - index.floor)
            end
          end

          def detect_outliers(data, q1, q3, iqr)
            lower_bound = q1 - 1.5 * iqr
            upper_bound = q3 + 1.5 * iqr
            
            data.select { |x| x < lower_bound || x > upper_bound }
          end
        end
      end
    end
  end
end