# frozen_string_literal: true

module RAAF
  module Testing
    ##
    # Mock provider for testing AI agents
    #
    # Provides a test-friendly LLM provider that returns predefined responses
    # without making actual API calls. Useful for consistent, fast testing.
    #
    class MockProvider
      include RAAF::Logging

      # @return [String] Default response when no specific response is configured
      attr_reader :default_response

      # @return [Float] Simulated response delay in seconds
      attr_reader :response_delay

      # @return [Float] Failure rate (0.0-1.0) for simulating API failures
      attr_reader :failure_rate

      # @return [Boolean] Whether to track usage statistics
      attr_reader :usage_tracking

      # @return [Hash] Response mappings
      attr_reader :responses

      # @return [Hash] Usage statistics
      attr_reader :usage_stats

      # Class-level tracking with thread safety
      @@instances = []
      @@global_responses = {}
      @@class_mutex = Mutex.new

      ##
      # Initialize mock provider
      #
      # @param default_response [String] Default response text
      # @param response_delay [Float] Simulated delay in seconds
      # @param failure_rate [Float] Failure rate (0.0-1.0)
      # @param usage_tracking [Boolean] Whether to track usage
      #
      def initialize(default_response: "I'm a test agent.", response_delay: 0.1, failure_rate: 0.0, usage_tracking: true)
        @default_response = default_response
        @response_delay = response_delay
        @failure_rate = failure_rate
        @usage_tracking = usage_tracking
        @responses = {}
        @usage_stats = {
          total_requests: 0,
          successful_requests: 0,
          failed_requests: 0,
          total_tokens: 0,
          average_response_time: 0.0
        }
        @request_history = []
        
        @@class_mutex.synchronize do
          @@instances << self
        end
      end

      ##
      # Add a response for a specific input
      #
      # @param input [String, Regexp] Input to match
      # @param response [String, Hash] Response to return
      #
      # @example Simple response
      #   provider.add_response("Hello", "Hi there!")
      #
      # @example Response with metadata
      #   provider.add_response("Weather", {
      #     content: "It's sunny today",
      #     metadata: { source: "weather_api" }
      #   })
      #
      # @example Pattern matching
      #   provider.add_response(/weather/i, "I'll check the weather for you")
      #
      def add_response(input, response)
        @responses[input] = response
      end

      ##
      # Add multiple responses at once
      #
      # @param responses [Hash] Hash of input => response pairs
      #
      # @example
      #   provider.add_responses({
      #     "Hello" => "Hi there!",
      #     "Goodbye" => "See you later!",
      #     /weather/i => "It's sunny today"
      #   })
      #
      def add_responses(responses)
        @responses.merge!(responses)
      end

      ##
      # Remove a response
      #
      # @param input [String, Regexp] Input to remove
      #
      def remove_response(input)
        @responses.delete(input)
      end

      ##
      # Clear all responses
      #
      def clear_responses
        @responses.clear
      end

      ##
      # Process a request (main provider interface)
      #
      # @param messages [Array<Hash>] Messages to process
      # @param options [Hash] Request options
      # @return [Hash] Response hash
      #
      def process_request(messages, **options)
        start_time = Time.current
        
        # Track request
        @usage_stats[:total_requests] += 1
        @request_history << {
          messages: messages,
          options: options,
          timestamp: start_time
        }

        # Simulate delay
        sleep(@response_delay) if @response_delay > 0

        # Simulate failure
        if @failure_rate > 0 && rand < @failure_rate
          @usage_stats[:failed_requests] += 1
          raise "Simulated API failure (failure_rate: #{@failure_rate})"
        end

        # Extract user message
        user_message = extract_user_message(messages)
        
        # Find matching response
        response_content = find_matching_response(user_message)
        
        # Build response
        response = build_response(response_content, user_message, options)
        
        # Track success
        @usage_stats[:successful_requests] += 1
        
        # Update timing statistics
        response_time = Time.current - start_time
        update_timing_stats(response_time)
        
        # Add timing to response
        response[:metadata] ||= {}
        response[:metadata][:response_time] = response_time
        
        log_debug("Mock provider response", {
          input: user_message,
          output: response_content,
          response_time: response_time
        })
        
        response
      end

      ##
      # Get request history
      #
      # @return [Array<Hash>] Array of request records
      #
      def request_history
        @request_history.dup
      end

      ##
      # Get last request
      #
      # @return [Hash, nil] Last request or nil if no requests
      #
      def last_request
        @request_history.last
      end

      ##
      # Reset statistics and history
      #
      def reset_stats
        @usage_stats = {
          total_requests: 0,
          successful_requests: 0,
          failed_requests: 0,
          total_tokens: 0,
          average_response_time: 0.0
        }
        @request_history.clear
      end

      ##
      # Get usage statistics
      #
      # @return [Hash] Usage statistics
      #
      def stats
        @usage_stats.merge(
          success_rate: calculate_success_rate,
          response_count: @responses.size,
          recent_requests: @request_history.last(10)
        )
      end

      ##
      # Check if provider has response for input
      #
      # @param input [String] Input to check
      # @return [Boolean] True if response exists
      #
      def has_response?(input)
        find_matching_response(input) != @default_response
      end

      ##
      # Simulate streaming response
      #
      # @param messages [Array<Hash>] Messages to process
      # @param options [Hash] Request options
      # @yield [chunk] Yields each chunk of the response
      # @return [Hash] Final response
      #
      def stream_request(messages, **options, &block)
        response = process_request(messages, **options)
        content = response[:content] || response["content"]
        
        # Split content into chunks
        chunks = split_into_chunks(content)
        
        # Yield each chunk with delay
        chunks.each_with_index do |chunk, index|
          sleep(@response_delay / chunks.size) if @response_delay > 0
          
          chunk_data = {
            content: chunk,
            index: index,
            total_chunks: chunks.size,
            finished: index == chunks.size - 1
          }
          
          yield(chunk_data) if block_given?
        end
        
        response.merge(streaming: true, chunks: chunks)
      end

      # Class methods
      class << self
        ##
        # Get all provider instances
        #
        # @return [Array<MockProvider>] All provider instances
        #
        def instances
          @@class_mutex.synchronize do
            @@instances.dup
          end
        end

        ##
        # Add global response available to all providers
        #
        # @param input [String, Regexp] Input to match
        # @param response [String, Hash] Response to return
        #
        def add_global_response(input, response)
          @@class_mutex.synchronize do
            @@global_responses[input] = response
          end
        end

        ##
        # Clear all global responses
        #
        def clear_global_responses
          @@class_mutex.synchronize do
            @@global_responses.clear
          end
        end

        ##
        # Clear all responses from all providers
        #
        def clear_all_responses
          @@class_mutex.synchronize do
            @@instances.each(&:clear_responses)
          end
          clear_global_responses
        end

        ##
        # Get global statistics
        #
        # @return [Hash] Combined statistics from all providers
        #
        def global_stats
          total_stats = {
            total_requests: 0,
            successful_requests: 0,
            failed_requests: 0,
            total_tokens: 0,
            provider_count: 0
          }

          @@class_mutex.synchronize do
            total_stats[:provider_count] = @@instances.size
            
            @@instances.each do |provider|
              stats = provider.stats
              total_stats[:total_requests] += stats[:total_requests]
              total_stats[:successful_requests] += stats[:successful_requests]
              total_stats[:failed_requests] += stats[:failed_requests]
              total_stats[:total_tokens] += stats[:total_tokens]
            end
          end

          total_stats[:success_rate] = if total_stats[:total_requests] > 0
                                        total_stats[:successful_requests].to_f / total_stats[:total_requests]
                                      else
                                        0.0
                                      end

          total_stats
        end

        ##
        # Reset all provider statistics
        #
        def reset_all_stats
          @@class_mutex.synchronize do
            @@instances.each(&:reset_stats)
          end
        end

        ##
        # Clear all cached responses
        #
        def clear_all_caches
          @@class_mutex.synchronize do
            @@instances.each(&:clear_responses)
          end
        end

        ##
        # Get cached responses count
        #
        # @return [Integer] Total cached responses
        #
        def cached_responses
          @@class_mutex.synchronize do
            @@instances.sum { |provider| provider.responses.size }
          end
        end
      end

      private

      def extract_user_message(messages)
        return "" unless messages.is_a?(Array) && messages.any?
        
        # Find the last user message
        user_message = messages.reverse.find { |m| m[:role] == "user" || m["role"] == "user" }
        return "" unless user_message
        
        user_message[:content] || user_message["content"] || ""
      end

      def find_matching_response(input)
        # Check instance responses first
        matching_response = find_response_match(@responses, input)
        return matching_response if matching_response
        
        # Check global responses (with synchronization)
        @@class_mutex.synchronize do
          matching_response = find_response_match(@@global_responses, input)
          return matching_response if matching_response
        end
        
        # Return default response
        @default_response
      end

      def find_response_match(responses, input)
        responses.each do |pattern, response|
          case pattern
          when String
            return extract_response_content(response) if pattern == input
          when Regexp
            return extract_response_content(response) if input.match?(pattern)
          end
        end
        
        nil
      end

      def extract_response_content(response)
        case response
        when String
          response
        when Hash
          response[:content] || response["content"] || response.to_s
        else
          response.to_s
        end
      end

      def build_response(content, user_message, options)
        # Calculate token usage
        input_tokens = estimate_tokens(user_message)
        output_tokens = estimate_tokens(content)
        total_tokens = input_tokens + output_tokens
        
        # Update usage tracking
        if @usage_tracking
          @usage_stats[:total_tokens] += total_tokens
        end
        
        # Build response structure
        response = {
          messages: [
            { role: "user", content: user_message },
            { role: "assistant", content: content }
          ],
          usage: {
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            total_tokens: total_tokens
          },
          metadata: {
            provider: "mock",
            model: options[:model] || "mock-model",
            temperature: options[:temperature] || 0.7,
            max_tokens: options[:max_tokens] || 1000
          }
        }
        
        # Add any additional metadata from response config
        if @responses.find { |k, v| v.is_a?(Hash) && v[:metadata] }
          pattern, response_config = @responses.find { |k, v| v.is_a?(Hash) && v[:metadata] }
          if response_config && response_config[:metadata]
            response[:metadata].merge!(response_config[:metadata])
          end
        end
        
        response
      end

      def estimate_tokens(text)
        # Simple token estimation (roughly 4 characters per token)
        return 0 if text.nil? || text.empty?
        
        (text.length / 4.0).ceil
      end

      def calculate_success_rate
        return 0.0 if @usage_stats[:total_requests] == 0
        
        @usage_stats[:successful_requests].to_f / @usage_stats[:total_requests]
      end

      def update_timing_stats(response_time)
        current_avg = @usage_stats[:average_response_time]
        request_count = @usage_stats[:total_requests]
        
        # Calculate new average
        @usage_stats[:average_response_time] = if request_count == 1
                                                response_time
                                              else
                                                (current_avg * (request_count - 1) + response_time) / request_count
                                              end
      end

      def split_into_chunks(content, chunk_size = 10)
        return [content] if content.length <= chunk_size
        
        chunks = []
        words = content.split
        current_chunk = []
        
        words.each do |word|
          if current_chunk.join(" ").length + word.length + 1 <= chunk_size
            current_chunk << word
          else
            chunks << current_chunk.join(" ") unless current_chunk.empty?
            current_chunk = [word]
          end
        end
        
        chunks << current_chunk.join(" ") unless current_chunk.empty?
        chunks
      end
    end
  end
end