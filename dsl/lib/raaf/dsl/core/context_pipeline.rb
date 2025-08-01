# frozen_string_literal: true

module RAAF
  module DSL
    # ContextPipeline provides a fluent interface for chaining agent executions
    #
    # This class simplifies multi-agent workflows by automatically flowing context
    # and results between agents, reducing boilerplate and preventing common errors.
    #
    # @example Basic pipeline
    #   pipeline = RAAF::DSL::ContextPipeline.new(product: product, company: company)
    #     .pipe(Market::Analysis, :analysis)
    #     .pipe(Market::Scoring, :scoring, markets: -> (ctx) { ctx.get(:analysis)[:markets] })
    #     .pipe(Market::SearchTermGenerator, :search_terms)
    #   
    #   results = pipeline.execute
    #   
    # @example With error handling
    #   pipeline = RAAF::DSL::ContextPipeline.new(initial_context)
    #     .on_error { |error, stage| handle_pipeline_error(error, stage) }
    #     .pipe(DataGatherer, :raw_data)
    #     .pipe(DataProcessor, :processed_data)
    #     .execute
    #
    # @example With conditional execution
    #   pipeline = RAAF::DSL::ContextPipeline.new(context)
    #     .pipe(Analysis, :analysis)
    #     .pipe_if(-> (ctx) { ctx.get(:analysis)[:score] > 70 }, Enrichment, :enrichment)
    #     .execute
    #
    class ContextPipeline
      # @return [ContextVariables] The current context
      attr_reader :context
      
      # @return [Hash] Results from each pipeline stage
      attr_reader :results
      
      # @return [Array<Hash>] Pipeline stage definitions
      attr_reader :stages
      
      # @return [Hash] Pipeline execution metadata
      attr_reader :metadata

      # Initialize a new ContextPipeline
      #
      # @param initial_context [Hash, ContextVariables] Initial context
      # @param debug [Boolean] Enable debug logging
      #
      def initialize(initial_context = {}, debug: false)
        @context = build_context(initial_context)
        @results = {}
        @stages = []
        @metadata = {
          started_at: nil,
          completed_at: nil,
          stage_durations: {},
          total_duration_ms: nil
        }
        @debug = debug
        @error_handler = nil
        @before_stage_hook = nil
        @after_stage_hook = nil
      end

      # Add an agent to the pipeline
      #
      # @param agent_class [Class] The agent class to execute
      # @param result_key [Symbol] Key to store the result under
      # @param context_additions [Hash] Additional context for this agent
      # @yield [context] Optional block to compute dynamic context additions
      # @return [ContextPipeline] Self for method chaining
      #
      # @example Static context additions
      #   pipeline.pipe(SearchAgent, :search_results, max_results: 10)
      #
      # @example Dynamic context additions
      #   pipeline.pipe(ScoringAgent, :scores, markets: -> (ctx) { ctx.get(:analysis)[:markets] })
      #
      def pipe(agent_class, result_key, context_additions = {}, &block)
        stage = {
          agent_class: agent_class,
          result_key: result_key,
          context_additions: context_additions,
          dynamic_context: block,
          condition: nil
        }
        
        @stages << stage
        debug_log("Added stage: #{agent_class.name} -> :#{result_key}")
        
        self
      end

      # Add an agent conditionally
      #
      # @param condition [Proc] Condition to evaluate
      # @param agent_class [Class] The agent class to execute if condition is true
      # @param result_key [Symbol] Key to store the result under
      # @param context_additions [Hash] Additional context for this agent
      # @return [ContextPipeline] Self for method chaining
      #
      # @example
      #   pipeline.pipe_if(
      #     -> (ctx) { ctx.get(:score) > 80 },
      #     EnrichmentAgent,
      #     :enrichment
      #   )
      #
      def pipe_if(condition, agent_class, result_key, context_additions = {})
        stage = {
          agent_class: agent_class,
          result_key: result_key,
          context_additions: context_additions,
          dynamic_context: nil,
          condition: condition
        }
        
        @stages << stage
        debug_log("Added conditional stage: #{agent_class.name} -> :#{result_key}")
        
        self
      end

      # Set error handler for the pipeline
      #
      # @yield [error, stage_info] Block to handle errors
      # @return [ContextPipeline] Self for method chaining
      #
      # @example
      #   pipeline.on_error do |error, stage_info|
      #     Rails.logger.error "Pipeline failed at #{stage_info[:agent_class]}: #{error.message}"
      #   end
      #
      def on_error(&block)
        @error_handler = block
        self
      end

      # Set before stage hook
      #
      # @yield [stage_info, context] Block to execute before each stage
      # @return [ContextPipeline] Self for method chaining
      #
      def before_stage(&block)
        @before_stage_hook = block
        self
      end

      # Set after stage hook
      #
      # @yield [stage_info, result, context] Block to execute after each stage
      # @return [ContextPipeline] Self for method chaining
      #
      def after_stage(&block)
        @after_stage_hook = block
        self
      end

      # Execute the pipeline
      #
      # @param halt_on_error [Boolean] Whether to stop on first error
      # @return [Hash] Pipeline execution results
      #
      def execute(halt_on_error: true)
        @metadata[:started_at] = Time.current
        debug_log("Starting pipeline execution with #{@stages.size} stages")
        
        @stages.each_with_index do |stage, index|
          stage_info = {
            stage_number: index + 1,
            agent_class: stage[:agent_class],
            result_key: stage[:result_key]
          }
          
          begin
            # Check condition if present
            if stage[:condition]
              unless evaluate_condition(stage[:condition], @context)
                debug_log("Skipping #{stage[:agent_class].name} - condition not met")
                @results[stage[:result_key]] = { skipped: true, reason: "condition_not_met" }
                next
              end
            end
            
            # Execute stage
            result = execute_stage(stage, stage_info)
            
            # Store result
            @results[stage[:result_key]] = result
            
            # Update context with successful result
            if result[:success]
              @context = @context.set(stage[:result_key], result)
            elsif halt_on_error
              handle_stage_error(result, stage_info)
              break
            end
            
          rescue => e
            error_result = handle_execution_error(e, stage_info)
            @results[stage[:result_key]] = error_result
            
            break if halt_on_error
          end
        end
        
        @metadata[:completed_at] = Time.current
        @metadata[:total_duration_ms] = calculate_total_duration
        
        build_pipeline_result
      end

      # Execute the pipeline and return only the final result
      #
      # @return [Hash] The last stage's result
      #
      def execute_last
        execute
        @results.values.last
      end

      # Get intermediate result by key
      #
      # @param key [Symbol] Result key
      # @return [Hash, nil] The result for the given key
      #
      def result(key)
        @results[key]
      end

      # Check if pipeline succeeded
      #
      # @return [Boolean] True if all stages succeeded
      #
      def success?
        @results.values.all? { |r| r[:success] || r[:skipped] }
      end

      # Get pipeline execution summary
      #
      # @return [Hash] Execution summary
      #
      def summary
        {
          success: success?,
          stages_executed: @results.size,
          stages_succeeded: @results.values.count { |r| r[:success] },
          stages_failed: @results.values.count { |r| r[:success] == false && !r[:skipped] },
          stages_skipped: @results.values.count { |r| r[:skipped] },
          total_duration_ms: @metadata[:total_duration_ms],
          stage_durations: @metadata[:stage_durations]
        }
      end

      private

      # Build initial context
      def build_context(initial)
        case initial
        when ContextVariables
          initial
        when Hash
          ContextVariables.new(initial, debug: @debug)
        else
          raise ArgumentError, "Initial context must be Hash or ContextVariables"
        end
      end

      # Execute a single pipeline stage
      def execute_stage(stage, stage_info)
        start_time = Time.current
        
        # Build context for this stage
        stage_context = build_stage_context(stage)
        
        # Before hook
        @before_stage_hook&.call(stage_info, stage_context)
        
        debug_log("Executing #{stage[:agent_class].name}")
        
        # Create and run agent
        agent = stage[:agent_class].new(context: stage_context)
        result = agent.call
        
        # Track duration
        duration_ms = ((Time.current - start_time) * 1000).round(2)
        @metadata[:stage_durations][stage[:result_key]] = duration_ms
        
        debug_log("Completed #{stage[:agent_class].name} in #{duration_ms}ms")
        
        # After hook
        @after_stage_hook&.call(stage_info, result, stage_context)
        
        result
      end

      # Build context for a specific stage
      def build_stage_context(stage)
        # Start with current context
        stage_context = @context
        
        # Add static context additions
        if stage[:context_additions].any?
          resolved_additions = resolve_context_additions(stage[:context_additions])
          stage_context = stage_context.update(resolved_additions)
        end
        
        # Add dynamic context if provided
        if stage[:dynamic_context]
          dynamic_additions = stage[:dynamic_context].call(@context)
          stage_context = stage_context.update(dynamic_additions) if dynamic_additions
        end
        
        stage_context
      end

      # Resolve context additions (handle procs and lambdas)
      def resolve_context_additions(additions)
        additions.transform_values do |value|
          case value
          when Proc
            value.call(@context)
          else
            value
          end
        end
      end

      # Evaluate a condition
      def evaluate_condition(condition, context)
        condition.call(context)
      rescue => e
        debug_log("Condition evaluation failed: #{e.message}")
        false
      end

      # Handle stage error
      def handle_stage_error(error_result, stage_info)
        return unless @error_handler
        
        @error_handler.call(
          StandardError.new(error_result[:error]),
          stage_info.merge(result: error_result)
        )
      end

      # Handle execution error
      def handle_execution_error(error, stage_info)
        debug_log("Stage failed with error: #{error.message}")
        
        @error_handler&.call(error, stage_info)
        
        {
          success: false,
          error: error.message,
          error_type: error.class.name,
          stage: stage_info[:agent_class].name
        }
      end

      # Calculate total pipeline duration
      def calculate_total_duration
        return nil unless @metadata[:started_at] && @metadata[:completed_at]
        
        ((@metadata[:completed_at] - @metadata[:started_at]) * 1000).round(2)
      end

      # Build final pipeline result
      def build_pipeline_result
        {
          success: success?,
          results: @results,
          context: @context.to_h,
          metadata: @metadata,
          summary: summary
        }
      end

      # Debug logging helper
      def debug_log(message)
        return unless @debug

        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.debug "[ContextPipeline] #{message}"
        else
          puts "[ContextPipeline] #{message}"
        end
      end
    end
  end
end