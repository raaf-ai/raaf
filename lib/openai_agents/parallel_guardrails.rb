require 'async'

module OpenAIAgents
  ##
  # ParallelGuardrails - Execute guardrails in parallel for better performance
  #
  # This module provides parallel execution of guardrails matching the Python
  # implementation's async approach. Input guardrails can run in parallel
  # with the main LLM call for faster overall execution.
  module ParallelGuardrails
    class GuardrailResult
      attr_reader :guardrail, :result, :error, :duration

      def initialize(guardrail:, result: nil, error: nil, duration: nil)
        @guardrail = guardrail
        @result = result
        @error = error
        @duration = duration
      end

      def success?
        @error.nil?
      end

      def tripwire_triggered?
        @result&.tripwire_triggered == true
      end
    end

    ##
    # Execute input guardrails in parallel
    #
    # @param guardrails [Array<InputGuardrail>] guardrails to execute
    # @param context_wrapper [RunContextWrapper] current run context
    # @param agent [Agent] the agent being executed
    # @param input [String] the input being validated
    # @return [Array<GuardrailResult>] results from all guardrails
    def self.run_input_guardrails_parallel(guardrails, context_wrapper, agent, input)
      return [] if guardrails.empty?

      if async_available?
        run_async_guardrails(guardrails, context_wrapper, agent, input)
      else
        run_sync_guardrails(guardrails, context_wrapper, agent, input)
      end
    end

    ##
    # Execute output guardrails in parallel
    #
    # @param guardrails [Array<OutputGuardrail>] guardrails to execute
    # @param context_wrapper [RunContextWrapper] current run context
    # @param agent [Agent] the agent being executed
    # @param output [String] the output being validated
    # @return [Array<GuardrailResult>] results from all guardrails
    def self.run_output_guardrails_parallel(guardrails, context_wrapper, agent, output)
      return [] if guardrails.empty?

      if async_available?
        run_async_guardrails(guardrails, context_wrapper, agent, output)
      else
        run_sync_guardrails(guardrails, context_wrapper, agent, output)
      end
    end

    ##
    # Process guardrail results and handle tripwires
    #
    # @param results [Array<GuardrailResult>] guardrail execution results
    # @param type [Symbol] :input or :output
    # @raise [InputGuardrailTripwireTriggered, OutputGuardrailTripwireTriggered] if tripwire triggered
    def self.process_guardrail_results(results, type = :input)
      # Check for any tripwires first
      tripwire_result = results.find(&:tripwire_triggered?)
      
      if tripwire_result
        error_class = type == :input ? 
          Guardrails::InputGuardrailTripwireTriggered : 
          Guardrails::OutputGuardrailTripwireTriggered
          
        raise error_class.new(
          "#{type.capitalize} guardrail '#{tripwire_result.guardrail.name}' triggered",
          triggered_by: tripwire_result.guardrail.name,
          metadata: tripwire_result.result&.output_info
        )
      end

      # Log any execution errors
      error_results = results.select { |r| !r.success? }
      error_results.each do |error_result|
        warn "Guardrail #{error_result.guardrail.name} failed: #{error_result.error}"
      end

      results
    end

    ##
    # Execute guardrails concurrently with early termination on tripwire
    #
    # @param guardrails [Array<Guardrail>] guardrails to execute
    # @param context_wrapper [RunContextWrapper] current run context
    # @param agent [Agent] the agent being executed
    # @param content [String] content being validated
    # @return [Array<GuardrailResult>] results from guardrails
    def self.run_guardrails_with_early_termination(guardrails, context_wrapper, agent, content)
      return [] if guardrails.empty?

      if async_available?
        run_async_with_cancellation(guardrails, context_wrapper, agent, content)
      else
        run_sync_guardrails(guardrails, context_wrapper, agent, content)
      end
    end

    private

    def self.async_available?
      defined?(Async) && Async.current_task
    rescue
      false
    end

    def self.run_async_guardrails(guardrails, context_wrapper, agent, content)
      results = []
      
      Async do |task|
        # Create tasks for each guardrail
        guardrail_tasks = guardrails.map do |guardrail|
          task.async do
            start_time = Time.now
            
            begin
              result = guardrail.run(context_wrapper, agent, content)
              duration = Time.now - start_time
              
              GuardrailResult.new(
                guardrail: guardrail,
                result: result,
                duration: duration
              )
            rescue => e
              duration = Time.now - start_time
              
              GuardrailResult.new(
                guardrail: guardrail,
                error: e,
                duration: duration
              )
            end
          end
        end

        # Wait for all guardrails to complete
        guardrail_tasks.each do |guardrail_task|
          results << guardrail_task.wait
        end
      end

      results
    end

    def self.run_async_with_cancellation(guardrails, context_wrapper, agent, content)
      results = []
      
      Async do |task|
        # Create tasks for each guardrail
        guardrail_tasks = guardrails.map do |guardrail|
          task.async do
            start_time = Time.now
            
            begin
              result = guardrail.run(context_wrapper, agent, content)
              duration = Time.now - start_time
              
              guardrail_result = GuardrailResult.new(
                guardrail: guardrail,
                result: result,
                duration: duration
              )
              
              # If this guardrail triggered a tripwire, cancel other tasks
              if guardrail_result.tripwire_triggered?
                guardrail_tasks.each { |t| t.stop if t != task.current_task }
              end
              
              guardrail_result
            rescue => e
              duration = Time.now - start_time
              
              GuardrailResult.new(
                guardrail: guardrail,
                error: e,
                duration: duration
              )
            end
          end
        end

        # Wait for all tasks to complete or be cancelled
        guardrail_tasks.each do |guardrail_task|
          begin
            results << guardrail_task.wait
          rescue Async::Stop
            # Task was cancelled, skip
          end
        end
      end

      results
    end

    def self.run_sync_guardrails(guardrails, context_wrapper, agent, content)
      guardrails.map do |guardrail|
        start_time = Time.now
        
        begin
          result = guardrail.run(context_wrapper, agent, content)
          duration = Time.now - start_time
          
          GuardrailResult.new(
            guardrail: guardrail,
            result: result,
            duration: duration
          )
        rescue => e
          duration = Time.now - start_time
          
          GuardrailResult.new(
            guardrail: guardrail,
            error: e,
            duration: duration
          )
        end
      end
    end

    ##
    # Enhanced guardrail runner with timing and metrics
    #
    # @param guardrails [Array<Guardrail>] guardrails to execute
    # @param context_wrapper [RunContextWrapper] current run context
    # @param agent [Agent] the agent being executed
    # @param content [String] content being validated
    # @param parallel [Boolean] whether to run in parallel
    # @return [Hash] detailed execution results
    def self.run_guardrails_with_metrics(guardrails, context_wrapper, agent, content, parallel: true)
      return { results: [], total_duration: 0, parallel: false } if guardrails.empty?

      start_time = Time.now
      
      results = if parallel && async_available?
        run_async_guardrails(guardrails, context_wrapper, agent, content)
      else
        run_sync_guardrails(guardrails, context_wrapper, agent, content)
      end
      
      total_duration = Time.now - start_time
      
      {
        results: results,
        total_duration: total_duration,
        parallel: parallel && async_available?,
        guardrail_count: guardrails.length,
        success_count: results.count(&:success?),
        error_count: results.count { |r| !r.success? },
        tripwire_count: results.count(&:tripwire_triggered?),
        average_duration: results.map(&:duration).sum / results.length.to_f
      }
    end
  end
end