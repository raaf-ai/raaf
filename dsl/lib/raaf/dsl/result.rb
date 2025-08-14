# frozen_string_literal: true

module RAAF
  module DSL
    # Standardized result object for agent runs
    #
    # This class provides a consistent interface for accessing the results of an
    # agent execution, abstracting away the underlying details of the RAAF-core
    # response. It offers methods to check for success, access parsed data,
    # and retrieve error information.
    #
    # @attr_reader [Boolean] success Whether the agent run was successful
    # @attr_reader [Object, nil] data The parsed data from the AI response
    # @attr_reader [String, nil] error The error message if the run failed
    # @attr_reader [ContextVariables] context_variables The context used for the run
    #
    class Result
      attr_reader :success, :data, :error, :context_variables

      # @param success [Boolean]
      # @param data [Object, nil]
      # @param error [String, nil]
      # @param context_variables [ContextVariables]
      def initialize(success:, data:, error: nil, context_variables:)
        @success = success
        @data = data
        @error = error
        @context_variables = context_variables
      end

      def success?
        @success
      end

      def failure?
        !@success
      end

      # Returns parsed JSON data automatically extracted from various RAAF result formats
      # This method handles the common patterns used by agents to extract structured data
      # from AI responses, eliminating the need for repetitive parsing logic
      #
      # @return [Hash, Array, Object] Parsed data structure
      # @raise [RAAF::ParseError] If JSON parsing fails
      def parsed_data
        @parsed_data ||= extract_and_parse_data
      end

      # Returns the raw response data without parsing
      # Use this when you need access to the original string format
      #
      # @return [String, Object] Raw response data
      def raw_response_data
        extract_raw_data
      end

      private

      def extract_and_parse_data
        raw_data = extract_raw_data
        
        # Return as-is if already parsed
        return raw_data if raw_data.is_a?(Hash) || raw_data.is_a?(Array)
        
        # Parse JSON string
        if raw_data.is_a?(String)
          JSON.parse(raw_data)
        else
          raw_data
        end
      rescue JSON::ParserError => e
        RAAF.logger.error "[RAAF] JSON parsing failed: #{e.message}"
        raise RAAF::ParseError, "Could not parse AI response: #{e.message}"
      end
      
      def extract_raw_data
        # Handle all current extraction patterns that agents use
        
        # Pattern B: Message-based extraction (most common in Prospect Radar)
        if @data.is_a?(Hash) && @data[:messages]&.any?
          last_message = @data[:messages].last
          return last_message[:content] if last_message && last_message[:role] == "assistant"
        end
        
        # Pattern C: Final output access
        if respond_to?(:final_output) && final_output
          return final_output
        elsif @data.is_a?(Hash) && @data[:final_output]
          return @data[:final_output]
        end
        
        # Pattern A: Direct data access
        return @data if @data
        
        # Fallback
        self
      end
    end
  end
end
