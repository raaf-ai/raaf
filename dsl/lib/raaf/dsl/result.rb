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

      # @param data [Hash, nil] Hash data when called as new(hash)
      # @param success [Boolean] Success flag when called with keywords
      # @param error [String, nil] Error message
      # @param context_variables [ContextVariables] Context variables
      def initialize(data = nil, success: nil, error: nil, context_variables: nil, **kwargs)
        if data.is_a?(Hash) && success.nil? && kwargs.empty?
          # Called as new(hash_data)
          @data = convert_string_keys_to_symbols(data)
          @success = @data[:success]
          @error = @data[:error] || error
          @context_variables = context_variables || RAAF::DSL::ContextVariables.new({})
        elsif data.nil? && (!success.nil? || !kwargs.empty?)
          # Called as new(success: true, key: value) or new(key: value)
          all_data = kwargs.merge(success: success).compact
          @data = convert_string_keys_to_symbols(all_data)
          @success = success
          @error = error
          @context_variables = context_variables || RAAF::DSL::ContextVariables.new({})
        elsif data.nil? && success.nil? && kwargs.empty?
          # Called as new() with no arguments
          @data = {}
          @success = nil
          @error = error
          @context_variables = context_variables || RAAF::DSL::ContextVariables.new({})
        else
          # Original API - called with required keywords
          @success = success
          @data = data || {}
          @error = error
          @context_variables = context_variables || RAAF::DSL::ContextVariables.new({})
        end
      end

      private

      def convert_string_keys_to_symbols(hash)
        return hash unless hash.is_a?(Hash)
        hash.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
      end

      public

      def success?
        !!@success
      end

      def failure?
        !@success
      end

      def error?
        !@success || !!@error
      end

      # Hash-like access methods
      def [](key)
        @data[key]
      end

      def []=(key, value)
        @data[key] = value
      end

      def fetch(key, *args, &block)
        @data.fetch(key, *args, &block)
      end

      def key?(key)
        @data.key?(key)
      end

      def keys
        @data.keys
      end

      def values
        @data.values
      end

      def each(&block)
        if block_given?
          @data.each(&block)
        else
          @data.each
        end
      end

      def size
        @data.size
      end

      def empty?
        @data.empty?
      end

      def to_h
        @data.dup
      end

      def to_json(*args)
        @data.to_json(*args)
      end

      def merge(other_hash)
        self.class.new(@data.merge(other_hash))
      end

      def merge!(other_hash)
        @data.merge!(other_hash)
        self
      end

      def inspect
        "#<#{self.class.name}:#{object_id.to_s(16)} @data=#{@data.inspect} @success=#{@success}>"
      end

      def ==(other)
        if other.is_a?(self.class)
          @data == other.data
        elsif other.is_a?(Hash)
          @data == other
        else
          false
        end
      end

      # Delegate missing methods to @data hash
      def method_missing(method_name, *args, &block)
        if @data.respond_to?(method_name)
          @data.send(method_name, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @data.respond_to?(method_name) || super
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
          # Return empty strings as-is
          return raw_data if raw_data.strip.empty?

          # Attempt JSON parsing - return raw string if it fails
          JSON.parse(raw_data)
        else
          raw_data
        end
      rescue JSON::ParserError => e
        # Not an error - just plain text response (no schema or CSV output)
        RAAF.logger.debug "[RAAF] String is not JSON, returning raw text: #{raw_data[0..100]}"
        raw_data  # Return raw string instead of raising error
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
