# frozen_string_literal: true

module RAAF
  module DSL
    module Resilience
      # SmartRetry provides intelligent retry mechanisms with circuit breakers,
      # exponential backoff, and contextual error handling for AI agents.
      #
      # This module can be included in any class to add sophisticated retry
      # capabilities that understand AI-specific failure modes like rate limits,
      # context size limits, and model availability issues.
      #
      # @example Basic retry configuration
      #   class MyAgent
      #     include RAAF::DSL::Resilience::SmartRetry
      #     
      #     retry_on :rate_limit, max_attempts: 5, backoff: :exponential
      #     retry_on :timeout, max_attempts: 3, delay: 2
      #     circuit_breaker threshold: 10, timeout: 300
      #   end
      #
      # @example Advanced contextual retries
      #   class ComplexAgent
      #     include RAAF::DSL::Resilience::SmartRetry
      #     
      #     retry_on :context_too_large, 
      #       max_attempts: 2,
      #       strategy: :reduce_context,
      #       reduction_factor: 0.7
      #       
      #     retry_on :model_overloaded,
      #       max_attempts: 3,
      #       strategy: :fallback_model,
      #       fallback_to: "gpt-4o-mini"
      #   end
      #
      module SmartRetry
        extend ActiveSupport::Concern

        # Error classifications for AI operations
        ERROR_PATTERNS = {
          rate_limit: [
            /rate limit/i, /too many requests/i, /quota exceeded/i,
            /throttl/i, /429/
          ],
          timeout: [
            /timeout/i, /timed out/i, /request timeout/i,
            /read timeout/i, /connection timeout/i
          ],
          context_too_large: [
            /context.*too large/i, /maximum context length/i,
            /context size.*exceed/i, /token limit/i,
            /input.*too long/i
          ],
          model_overloaded: [
            /model.*overloaded/i, /service unavailable/i,
            /temporarily unavailable/i, /503/, /502/
          ],
          invalid_request: [
            /invalid request/i, /malformed/i, /bad request/i,
            /400/, /validation error/i
          ],
          network_error: [
            /network/i, /connection/i, /dns/i, /socket/i,
            /unreachable/i, /connection refused/i
          ],
          authentication_error: [
            /unauthorized/i, /authentication/i, /401/,
            /invalid.*key/i, /forbidden/i, /403/
          ]
        }.freeze

        # Backoff strategies
        BACKOFF_STRATEGIES = {
          linear: ->(attempt, base_delay) { base_delay * attempt },
          exponential: ->(attempt, base_delay) { base_delay * (2 ** (attempt - 1)) },
          fibonacci: ->(attempt, base_delay) { 
            fib = [1, 1]
            (attempt - 1).times { fib << fib[-1] + fib[-2] }
            base_delay * fib[attempt - 1]
          },
          jittered: ->(attempt, base_delay) {
            base = base_delay * (2 ** (attempt - 1))
            jitter = rand(0.1..0.3) * base
            base + jitter
          }
        }.freeze

        included do
          class_attribute :_retry_configs, :_circuit_breaker_config, :_fallback_strategies
          self._retry_configs = {}
          self._circuit_breaker_config = nil
          self._fallback_strategies = {}
        end

        class_methods do
          # Configure retry behavior for specific error types
          #
          # @param error_type [Symbol] Type of error to retry on
          # @param max_attempts [Integer] Maximum retry attempts
          # @param delay [Numeric] Base delay between retries in seconds
          # @param backoff [Symbol] Backoff strategy (:linear, :exponential, :fibonacci, :jittered)
          # @param strategy [Symbol] Special retry strategy for this error type
          # @param jitter [Boolean] Add random jitter to delay
          # @param condition [Proc] Custom condition to determine if retry should happen
          #
          def retry_on(error_type, max_attempts: 3, delay: 1, backoff: :exponential,
                      strategy: nil, jitter: true, condition: nil, **strategy_options)
            self._retry_configs = _retry_configs.merge(
              error_type => {
                max_attempts: max_attempts,
                delay: delay,
                backoff: backoff,
                strategy: strategy,
                jitter: jitter,
                condition: condition,
                strategy_options: strategy_options
              }
            )
          end

          # Configure circuit breaker
          #
          # @param threshold [Integer] Number of failures before opening circuit
          # @param timeout [Integer] Seconds to keep circuit open
          # @param reset_timeout [Integer] Seconds before attempting to close circuit
          # @param failure_rate_threshold [Float] Failure rate (0.0-1.0) to trigger circuit
          # @param minimum_requests [Integer] Minimum requests before calculating failure rate
          #
          def circuit_breaker(threshold: 5, timeout: 60, reset_timeout: 300,
                             failure_rate_threshold: 0.5, minimum_requests: 10)
            self._circuit_breaker_config = {
              threshold: threshold,
              timeout: timeout,
              reset_timeout: reset_timeout,
              failure_rate_threshold: failure_rate_threshold,
              minimum_requests: minimum_requests
            }
          end

          # Configure fallback strategies
          #
          # @param error_type [Symbol] Error type to configure fallback for
          # @param strategy [Symbol] Fallback strategy name
          # @param options [Hash] Strategy-specific options
          #
          def fallback_strategy(error_type, strategy:, **options)
            self._fallback_strategies = _fallback_strategies.merge(
              error_type => { strategy: strategy, options: options }
            )
          end
        end

        # Instance methods
        def initialize(*args, **kwargs)
          super
          initialize_resilience_state
        end

        # Execute a block with smart retry logic
        #
        # @param operation_name [String] Name for logging purposes
        # @param block [Proc] Block to execute with retry logic
        # @return [Object] Result of the block execution
        #
        def with_smart_retry(operation_name = "operation", &block)
          check_circuit_breaker!
          
          attempt = 0
          start_time = Time.current
          last_error = nil

          begin
            attempt += 1
            
            # Execute the block
            result = yield
            
            # Record success for circuit breaker
            record_success
            
            # Log successful retry if this wasn't the first attempt
            if attempt > 1
              log_retry_success(operation_name, attempt - 1, Time.current - start_time)
            end
            
            result
            
          rescue => error
            last_error = error
            error_type = classify_error(error)
            retry_config = _retry_configs[error_type] || _retry_configs[:default]
            
            # Check if we should retry
            if should_retry?(error, error_type, attempt, retry_config)
              # Apply retry strategy if configured
              if retry_config&.dig(:strategy)
                apply_retry_strategy(error_type, retry_config, attempt, error)
              end
              
              # Calculate delay
              delay = calculate_delay(retry_config, attempt)
              
              log_retry_attempt(operation_name, error, attempt, retry_config&.dig(:max_attempts), delay)
              
              sleep(delay) if delay > 0
              retry
            else
              # No more retries, record failure and handle
              record_failure
              handle_final_failure(operation_name, error, error_type, attempt)
            end
          end
        end

        # Check if circuit breaker allows execution
        def circuit_breaker_open?
          return false unless _circuit_breaker_config
          
          @circuit_breaker_state == :open ||
          (@circuit_breaker_state == :half_open && should_reject_request?)
        end

        # Get current resilience statistics
        def resilience_stats
          {
            circuit_breaker: {
              state: @circuit_breaker_state,
              failures: @circuit_breaker_failures,
              successes: @circuit_breaker_successes,
              last_failure: @circuit_breaker_last_failure,
              failure_rate: calculate_failure_rate
            },
            retry_attempts: @total_retry_attempts,
            successful_retries: @successful_retries
          }
        end

        private

        def initialize_resilience_state
          @circuit_breaker_state = :closed
          @circuit_breaker_failures = 0
          @circuit_breaker_successes = 0
          @circuit_breaker_last_failure = nil
          @circuit_breaker_requests = []
          @total_retry_attempts = 0
          @successful_retries = 0
        end

        def check_circuit_breaker!
          return unless _circuit_breaker_config
          
          case @circuit_breaker_state
          when :open
            if Time.current - @circuit_breaker_last_failure > _circuit_breaker_config[:timeout]
              @circuit_breaker_state = :half_open
              log_circuit_breaker_state_change(:half_open)
            else
              raise CircuitBreakerOpenError, "Circuit breaker is open"
            end
          when :half_open
            # Allow limited requests in half-open state
          end
        end

        def classify_error(error)
          error_message = error.message.to_s
          error_class = error.class.name
          
          ERROR_PATTERNS.each do |error_type, patterns|
            patterns.each do |pattern|
              if pattern.is_a?(Regexp)
                return error_type if error_message.match?(pattern) || error_class.match?(pattern)
              else
                return error_type if error_message.include?(pattern.to_s)
              end
            end
          end
          
          # Check for custom error classifications
          case error
          when JSON::ParserError
            :json_error
          when ArgumentError
            error_message.include?("context") ? :context_error : :invalid_request
          when Net::Error, SocketError
            :network_error
          when Timeout::Error
            :timeout
          else
            :unknown_error
          end
        end

        def should_retry?(error, error_type, attempt, retry_config)
          return false unless retry_config
          return false if attempt >= retry_config[:max_attempts]
          
          # Check custom condition
          if retry_config[:condition]
            return false unless retry_config[:condition].call(error, attempt)
          end
          
          # Don't retry certain error types
          case error_type
          when :authentication_error, :invalid_request
            return false
          end
          
          true
        end

        def apply_retry_strategy(error_type, retry_config, attempt, error)
          strategy = retry_config[:strategy]
          options = retry_config[:strategy_options] || {}
          
          case strategy
          when :reduce_context
            apply_context_reduction_strategy(options, attempt, error)
          when :fallback_model
            apply_model_fallback_strategy(options, attempt, error)
          when :simplify_prompt
            apply_prompt_simplification_strategy(options, attempt, error)
          when :custom
            apply_custom_strategy(error_type, options, attempt, error)
          end
        end

        def apply_context_reduction_strategy(options, attempt, error)
          reduction_factor = options[:reduction_factor] || 0.8
          
          if respond_to?(:reduce_context_size, true)
            new_size = (@current_context_size || 4000) * reduction_factor
            send(:reduce_context_size, new_size.to_i)
            RAAF.logger.info "🔄 Context reduced to #{new_size.to_i} tokens for retry #{attempt}"
          end
        end

        def apply_model_fallback_strategy(options, attempt, error)
          fallback_model = options[:fallback_to] || "gpt-4o-mini"
          
          if respond_to?(:switch_model, true)
            send(:switch_model, fallback_model)
            RAAF.logger.info "🔄 Switched to fallback model #{fallback_model} for retry #{attempt}"
          end
        end

        def apply_prompt_simplification_strategy(options, attempt, error)
          if respond_to?(:simplify_prompt, true)
            simplification_level = attempt
            send(:simplify_prompt, simplification_level)
            RAAF.logger.info "🔄 Simplified prompt (level #{simplification_level}) for retry #{attempt}"
          end
        end

        def apply_custom_strategy(error_type, options, attempt, error)
          strategy_method = options[:method]
          if strategy_method && respond_to?(strategy_method, true)
            send(strategy_method, error_type, attempt, error, options)
          end
        end

        def calculate_delay(retry_config, attempt)
          return 0 unless retry_config
          
          base_delay = retry_config[:delay] || 1
          backoff_strategy = retry_config[:backoff] || :exponential
          
          # Calculate base delay using backoff strategy
          delay = BACKOFF_STRATEGIES[backoff_strategy]&.call(attempt, base_delay) || base_delay
          
          # Add jitter if enabled
          if retry_config[:jitter]
            jitter = rand(0.1..0.3) * delay
            delay += jitter
          end
          
          # Cap maximum delay
          [delay, 60].min # Max 60 seconds
        end

        def record_success
          return unless _circuit_breaker_config
          
          @circuit_breaker_successes += 1
          @circuit_breaker_requests << { success: true, timestamp: Time.current }
          cleanup_old_requests
          
          # Close circuit if in half-open state
          if @circuit_breaker_state == :half_open
            @circuit_breaker_state = :closed
            @circuit_breaker_failures = 0
            log_circuit_breaker_state_change(:closed)
          end
        end

        def record_failure
          return unless _circuit_breaker_config
          
          @circuit_breaker_failures += 1
          @circuit_breaker_last_failure = Time.current
          @circuit_breaker_requests << { success: false, timestamp: Time.current }
          cleanup_old_requests
          
          # Check if circuit should open
          if should_open_circuit?
            @circuit_breaker_state = :open
            log_circuit_breaker_state_change(:open)
          end
        end

        def should_open_circuit?
          return false unless _circuit_breaker_config
          
          config = _circuit_breaker_config
          
          # Check failure count threshold
          return true if @circuit_breaker_failures >= config[:threshold]
          
          # Check failure rate if enough requests
          recent_requests = @circuit_breaker_requests.last(config[:minimum_requests])
          if recent_requests.length >= config[:minimum_requests]
            failure_rate = recent_requests.count { |r| !r[:success] }.to_f / recent_requests.length
            return true if failure_rate >= config[:failure_rate_threshold]
          end
          
          false
        end

        def should_reject_request?
          # In half-open state, allow some requests through
          rand < 0.1  # 10% chance of allowing request
        end

        def calculate_failure_rate
          return 0.0 if @circuit_breaker_requests.empty?
          
          failures = @circuit_breaker_requests.count { |r| !r[:success] }
          failures.to_f / @circuit_breaker_requests.length
        end

        def cleanup_old_requests
          # Keep only last 100 requests
          @circuit_breaker_requests = @circuit_breaker_requests.last(100)
        end

        def handle_final_failure(operation_name, error, error_type, attempts)
          # Try fallback strategy if configured
          fallback = _fallback_strategies[error_type]
          if fallback && respond_to?(fallback[:strategy], true)
            RAAF.logger.info "🔄 Applying fallback strategy #{fallback[:strategy]} for #{error_type}"
            begin
              return send(fallback[:strategy], error, fallback[:options])
            rescue => fallback_error
              RAAF.logger.error "❌ Fallback strategy failed: #{fallback_error.message}"
            end
          end
          
          # Log final failure
          log_final_failure(operation_name, error, error_type, attempts)
          
          # Re-raise the original error
          raise error
        end

        def log_retry_attempt(operation_name, error, attempt, max_attempts, delay)
          @total_retry_attempts += 1
          
          RAAF.logger.warn "🔄 [SmartRetry] #{operation_name} retry #{attempt}/#{max_attempts} in #{delay.round(2)}s: #{error.message}",
                             category: :resilience,
                             data: {
                               operation: operation_name,
                               error_type: classify_error(error),
                               attempt: attempt,
                               max_attempts: max_attempts,
                               delay_seconds: delay.round(2)
                             }
        end

        def log_retry_success(operation_name, retry_count, total_duration)
          @successful_retries += 1
          
          RAAF.logger.info "✅ [SmartRetry] #{operation_name} succeeded after #{retry_count} retries in #{total_duration.round(2)}s",
                            category: :resilience,
                            data: {
                              operation: operation_name,
                              retry_count: retry_count,
                              total_duration_seconds: total_duration.round(2)
                            }
        end

        def log_final_failure(operation_name, error, error_type, attempts)
          RAAF.logger.error "❌ [SmartRetry] #{operation_name} failed permanently after #{attempts} attempts: #{error.message}",
                             category: :resilience,
                             data: {
                               operation: operation_name,
                               error_type: error_type,
                               total_attempts: attempts,
                               final_error: error.message
                             }
        end

        def log_circuit_breaker_state_change(new_state)
          RAAF.logger.info "🔌 [CircuitBreaker] State changed to #{new_state}",
                            category: :resilience,
                            data: {
                              new_state: new_state,
                              failures: @circuit_breaker_failures,
                              successes: @circuit_breaker_successes,
                              failure_rate: calculate_failure_rate
                            }
        end

        # Custom error for circuit breaker
        class CircuitBreakerOpenError < StandardError; end
      end
    end
  end
end