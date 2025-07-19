# frozen_string_literal: true

require 'concurrent'

module RAAF
  module Guardrails
    # Executes multiple guardrails in parallel for improved performance
    class ParallelGuardrails
      attr_reader :guardrails, :max_parallel, :timeout

      def initialize(guardrails, max_parallel: nil, timeout: 5)
        @guardrails = guardrails
        @max_parallel = max_parallel || guardrails.size
        @timeout = timeout
        @executor = create_executor
      end

      # Check input through all guardrails in parallel
      def check_input(content, context = {})
        execute_parallel_checks(:check_input, content, context)
      end

      # Check output through all guardrails in parallel
      def check_output(content, context = {})
        execute_parallel_checks(:check_output, content, context)
      end

      # Add a guardrail to the collection
      def add_guardrail(guardrail)
        @guardrails << guardrail
      end

      # Remove a guardrail from the collection
      def remove_guardrail(guardrail)
        @guardrails.delete(guardrail)
      end

      # Configure monitoring for performance tracking
      def configure_monitoring
        @monitoring_config = {
          enable_timing: false,
          enable_profiling: false,
          performance_threshold: 100,
          alert_on_slow_guardrails: false
        }
        
        yield @monitoring_config if block_given?
      end

      # Get metrics for all guardrails
      def metrics
        @guardrails.each_with_object({}) do |guardrail, metrics|
          guardrail_name = guardrail.class.name.split('::').last
          metrics[guardrail_name] = guardrail.metrics if guardrail.respond_to?(:metrics)
        end
      end

      # Shutdown the executor cleanly
      def shutdown
        @executor.shutdown
        @executor.wait_for_termination(@timeout)
      end

      private

      def create_executor
        Concurrent::ThreadPoolExecutor.new(
          min_threads: 1,
          max_threads: @max_parallel,
          max_queue: @guardrails.size * 2,
          fallback_policy: :caller_runs
        )
      end

      def execute_parallel_checks(method, content, context)
        start_time = Time.now if monitoring_enabled?
        
        # Create futures for all guardrail checks
        futures = @guardrails.map do |guardrail|
          Concurrent::Future.execute(executor: @executor) do
            guardrail_start = Time.now if monitoring_enabled?
            
            begin
              result = guardrail.public_send(method, content, context)
              
              if monitoring_enabled?
                elapsed = Time.now - guardrail_start
                check_performance(guardrail, elapsed)
              end
              
              result
            rescue StandardError => e
              # Return error result instead of raising
              error_result(guardrail, e)
            end
          end
        end
        
        # Wait for all futures to complete
        results = futures.map { |future| future.value(@timeout) }
        
        # Combine results
        combined_result = combine_results(results)
        
        if monitoring_enabled?
          total_elapsed = Time.now - start_time
          log_performance_metrics(total_elapsed, results)
        end
        
        combined_result
      end

      def combine_results(results)
        all_violations = []
        blocked = false
        should_redact = false
        modified_content = nil
        
        results.each do |result|
          next unless result
          
          # Aggregate violations
          if result.violated?
            all_violations.concat(result.violations)
          end
          
          # Check if any guardrail wants to block
          blocked = true if result.should_block?
          
          # Check if any guardrail wants to redact
          if result.should_redact? && result.content
            should_redact = true
            modified_content = result.content
          end
        end
        
        # Determine final action
        final_action = if blocked
                        :block
                      elsif should_redact
                        :redact
                      elsif all_violations.any?
                        :flag
                      else
                        nil
                      end
        
        GuardrailResult.new(
          safe: all_violations.empty?,
          action: final_action,
          content: modified_content,
          violations: all_violations,
          metadata: {
            guardrails_executed: @guardrails.size,
            results_count: results.size,
            parallel_execution: true
          }
        )
      end

      def error_result(guardrail, error)
        GuardrailResult.new(
          safe: false,
          action: :log,
          content: nil,
          violations: [{
            type: :guardrail_error,
            guardrail: guardrail.class.name,
            error: error.message,
            severity: :medium,
            description: "Guardrail execution failed: #{error.message}"
          }],
          metadata: {
            error_class: error.class.name,
            backtrace: error.backtrace&.first(5)
          }
        )
      end

      def monitoring_enabled?
        @monitoring_config && @monitoring_config[:enable_timing]
      end

      def check_performance(guardrail, elapsed_ms)
        elapsed = elapsed_ms * 1000 # Convert to milliseconds
        
        if @monitoring_config[:alert_on_slow_guardrails] && 
           elapsed > @monitoring_config[:performance_threshold]
          log_slow_guardrail(guardrail, elapsed)
        end
      end

      def log_slow_guardrail(guardrail, elapsed_ms)
        guardrail_name = guardrail.class.name.split('::').last
        puts "[PERF WARNING] Slow guardrail: #{guardrail_name} took #{elapsed_ms.round(2)}ms"
      end

      def log_performance_metrics(total_elapsed, results)
        return unless @monitoring_config[:enable_profiling]
        
        puts "[PERF] Parallel guardrails execution:"
        puts "  Total time: #{(total_elapsed * 1000).round(2)}ms"
        puts "  Guardrails executed: #{@guardrails.size}"
        puts "  Results collected: #{results.size}"
        puts "  Violations found: #{results.sum { |r| r&.violations&.size || 0 }}"
      end
    end
  end
end