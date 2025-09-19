# frozen_string_literal: true

module RAAF
  module DSL
    module Pipeline
      # DeclarativePipeline provides a simple DSL for orchestrating multiple AI agents
      #
      # This class eliminates complex orchestrator code by providing a declarative
      # way to define agent pipelines with automatic dependency management, error
      # handling, and result aggregation.
      #
      # @example Simple linear pipeline
      #   class MarketDiscovery < RAAF::DSL::Pipeline
      #     requires :product, :company
      #     
      #     step :analyze_markets, using: Market::Analysis
      #     step :search_companies, using: Company::Search, needs: [:analyze_markets]
      #     step :score_prospects, using: Prospect::Scoring, needs: [:search_companies]
      #     
      #     finalize_with :compile_results
      #   end
      #
      # @example Advanced pipeline with parallel execution
      #   class ComplexPipeline < RAAF::DSL::Pipeline
      #     step :data_gathering, using: DataGatherer
      #     
      #     parallel_steps :market_analysis, :competitor_analysis,
      #       using: [Market::Analysis, Competitor::Analysis],
      #       needs: [:data_gathering]
      #     
      #     step :final_recommendation, using: Recommendation::Generator,
      #       needs: [:market_analysis, :competitor_analysis]
      #       
      #     on_step_failure :market_analysis, fallback_to: :simple_market_analysis
      #     on_pipeline_failure retry_count: 1, then: :partial_results
      #   end
      #
      class DeclarativePipeline < RAAF::DSL::Agent
        # AgentDsl and AgentHooks functionality now inherited from Agent class

        # Pipeline configuration DSL
        class << self
          attr_accessor :_pipeline_config, :_required_context_keys, :_steps, 
                       :_parallel_groups, :_error_handlers, :_finalizer

          # Declare required context keys for the pipeline
          def requires(*keys)
            self._required_context_keys ||= []
            self._required_context_keys.concat(keys.map(&:to_sym))
          end

          # Define a pipeline step
          #
          # @param name [Symbol] Step identifier
          # @param using [Class] Agent class to use for this step
          # @param needs [Array<Symbol>] Dependencies on other steps
          # @param merge_as [Symbol] Key to merge results under in context
          # @param timeout [Integer] Step timeout in seconds
          # @param retry_on_failure [Boolean] Whether to retry this step on failure
          #
          def step(name, using:, needs: [], merge_as: nil, timeout: nil, retry_on_failure: false)
            self._steps ||= []
            self._steps << {
              name: name,
              agent_class: using,
              dependencies: needs.map(&:to_sym),
              merge_as: merge_as || name,
              timeout: timeout,
              retry_on_failure: retry_on_failure,
              parallel: false
            }
          end

          # Define multiple steps to run in parallel
          #
          # @param names [Array<Symbol>] Step names
          # @param using [Array<Class>] Agent classes (must match names length)
          # @param needs [Array<Symbol>] Shared dependencies
          # @param timeout [Integer] Timeout for parallel execution
          #
          def parallel_steps(*names, using:, needs: [], timeout: nil)
            if names.length != using.length
              raise ArgumentError, "Number of step names must match number of agent classes"
            end

            self._parallel_groups ||= []
            parallel_group_id = :"parallel_group_#{_parallel_groups.length}"
            
            names.zip(using).each do |name, agent_class|
              self._steps ||= []
              self._steps << {
                name: name,
                agent_class: agent_class,
                dependencies: needs.map(&:to_sym),
                merge_as: name,
                timeout: timeout,
                retry_on_failure: false,
                parallel: true,
                parallel_group: parallel_group_id
              }
            end

            self._parallel_groups << {
              id: parallel_group_id,
              steps: names,
              timeout: timeout
            }
          end

          # Define what to do when a step fails
          #
          # @param step_name [Symbol] Step that might fail
          # @param fallback_to [Symbol] Method to call as fallback
          # @param retry_count [Integer] Number of retries before fallback
          #
          def on_step_failure(step_name, fallback_to: nil, retry_count: 0)
            self._error_handlers ||= {}
            self._error_handlers[step_name] = {
              type: :step_failure,
              fallback_method: fallback_to,
              retry_count: retry_count
            }
          end

          # Define what to do when the entire pipeline fails
          #
          # @param retry_count [Integer] Number of full pipeline retries
          # @param then [Symbol] Method to call after retries exhausted
          #
          def on_pipeline_failure(retry_count: 0, then: nil)
            self._error_handlers ||= {}
            self._error_handlers[:pipeline] = {
              type: :pipeline_failure,
              retry_count: retry_count,
              fallback_method: binding.local_variable_get(:then)
            }
          end

          # Define the method to call for result finalization
          #
          # @param method_name [Symbol] Method to call with all step results
          #
          def finalize_with(method_name)
            self._finalizer = method_name
          end

          # Inherit configuration from parent class
          def inherited(subclass)
            super
            
            subclass._pipeline_config = _pipeline_config&.dup
            subclass._required_context_keys = _required_context_keys&.dup
            subclass._steps = _steps&.dup
            subclass._parallel_groups = _parallel_groups&.dup
            subclass._error_handlers = _error_handlers&.dup
            subclass._finalizer = _finalizer
          end
        end

        # Initialize pipeline with context
        def initialize(context:)
          @context = context.is_a?(Hash) ? ContextVariables.new(context) : context
          @step_results = {}
          @execution_log = []
          @current_step = 0
          @total_steps = self.class._steps&.length || 0

          validate_context!
          super(context: @context)
        end

        # Execute the pipeline
        def call
          pipeline_name = self.class.name
          RAAF.logger.info "🚀 [#{pipeline_name}] Starting pipeline execution"

          begin
            execute_pipeline_with_retry
          rescue => e
            handle_pipeline_error(e)
          ensure
            log_pipeline_completion
          end
        end

        # RAAF DSL compatibility methods (no-op for pipelines)
        def build_instructions
          "Pipeline orchestrator - no direct AI interaction"
        end

        def build_schema
          { type: "object", properties: { pipeline: { type: "string" } } }
        end

        def build_user_prompt
          "Execute pipeline steps"
        end

        protected

        # Context accessor for pipeline steps
        attr_reader :context

        private

        def validate_context!
          return unless self.class._required_context_keys

          missing_keys = self.class._required_context_keys.reject do |key|
            @context.has?(key)
          end

          if missing_keys.any?
            raise ArgumentError, "Pipeline requires context keys: #{missing_keys.join(', ')}"
          end
        end

        def execute_pipeline_with_retry
          pipeline_retries = self.class._error_handlers&.dig(:pipeline, :retry_count) || 0
          attempts = 0

          begin
            attempts += 1
            execute_pipeline_steps
            finalize_pipeline_results
          rescue => e
            if attempts <= pipeline_retries
              RAAF.logger.warn "🔄 [#{self.class.name}] Pipeline retry #{attempts}/#{pipeline_retries}: #{e.message}"
              retry
            else
              # Try fallback method if configured
              fallback_method = self.class._error_handlers&.dig(:pipeline, :fallback_method)
              if fallback_method && respond_to?(fallback_method, true)
                RAAF.logger.info "🔄 [#{self.class.name}] Executing pipeline fallback: #{fallback_method}"
                return send(fallback_method, e, @step_results)
              end
              raise
            end
          end
        end

        def execute_pipeline_steps
          return { success: true, results: {} } unless self.class._steps

          # Build dependency graph
          dependency_graph = build_dependency_graph
          
          # Execute steps in dependency order
          execution_order = topological_sort(dependency_graph)
          
          execution_order.each do |step_group|
            if step_group.is_a?(Array)
              # Parallel execution
              execute_parallel_steps(step_group)
            else
              # Single step execution
              execute_single_step(step_group)
            end
          end

          { success: true, results: @step_results }
        end

        def build_dependency_graph
          graph = {}
          
          self.class._steps.each do |step_config|
            step_name = step_config[:name]
            dependencies = step_config[:dependencies]
            
            graph[step_name] = {
              config: step_config,
              dependencies: dependencies,
              dependents: []
            }
          end
          
          # Build dependents list
          graph.each do |step_name, step_info|
            step_info[:dependencies].each do |dep|
              if graph[dep]
                graph[dep][:dependents] << step_name
              end
            end
          end
          
          graph
        end

        def topological_sort(graph)
          # Group parallel steps
          parallel_groups = self.class._parallel_groups || []
          execution_order = []
          completed = Set.new
          
          while completed.size < graph.size
            # Find steps with no incomplete dependencies
            ready_steps = graph.select do |step_name, step_info|
              !completed.include?(step_name) && 
              step_info[:dependencies].all? { |dep| completed.include?(dep) }
            end.keys
            
            if ready_steps.empty?
              raise "Circular dependency detected in pipeline"
            end
            
            # Group parallel steps together
            parallel_ready = []
            sequential_ready = []
            
            ready_steps.each do |step_name|
              step_config = graph[step_name][:config]
              if step_config[:parallel]
                parallel_ready << step_name
              else
                sequential_ready << step_name
              end
            end
            
            # Add parallel groups
            parallel_groups.each do |group|
              group_steps = group[:steps] & parallel_ready
              if group_steps.length > 1
                execution_order << group_steps
                completed.merge(group_steps)
                parallel_ready -= group_steps
              end
            end
            
            # Add remaining parallel steps individually  
            parallel_ready.each do |step_name|
              execution_order << step_name
              completed.add(step_name)
            end
            
            # Add sequential steps
            sequential_ready.each do |step_name|
              execution_order << step_name
              completed.add(step_name)
            end
          end
          
          execution_order
        end

        def execute_single_step(step_name)
          step_config = find_step_config(step_name)
          @current_step += 1
          
          RAAF.logger.info "🔄 [#{self.class.name}] Executing step #{@current_step}/#{@total_steps}: #{step_name}"
          
          begin
            # Build context for this step
            step_context = build_step_context(step_config)
            
            # Execute with timeout if configured
            result = if step_config[:timeout]
              execute_with_timeout(step_config[:agent_class], step_context, step_config[:timeout])
            else
              execute_agent(step_config[:agent_class], step_context)
            end
            
            # Store result
            store_step_result(step_name, step_config, result)
            
            RAAF.logger.info "✅ [#{self.class.name}] Step completed: #{step_name}"
            
          rescue => e
            handle_step_error(step_name, step_config, e)
          end
        end

        def execute_parallel_steps(step_names)
          RAAF.logger.info "🔄 [#{self.class.name}] Executing parallel steps: #{step_names.join(', ')}"
          
          threads = step_names.map do |step_name|
            Thread.new do
              step_config = find_step_config(step_name)
              
              begin
                step_context = build_step_context(step_config)
                result = execute_agent(step_config[:agent_class], step_context)
                [step_name, step_config, result, nil]
              rescue => e
                [step_name, step_config, nil, e]
              end
            end
          end
          
          # Wait for all threads and process results
          threads.each do |thread|
            step_name, step_config, result, error = thread.value
            
            if error
              handle_step_error(step_name, step_config, error)
            else
              store_step_result(step_name, step_config, result)
            end
          end
          
          RAAF.logger.info "✅ [#{self.class.name}] Parallel steps completed: #{step_names.join(', ')}"
        end

        def find_step_config(step_name)
          self.class._steps.find { |step| step[:name] == step_name }
        end

        def build_step_context(step_config)
          # Start with original context
          step_context = @context
          
          # Add results from dependencies
          step_config[:dependencies].each do |dep_name|
            if @step_results[dep_name]
              step_context = step_context.set(dep_name, @step_results[dep_name])
            end
          end
          
          step_context
        end

        def execute_with_timeout(agent_class, context, timeout)
          require 'timeout'
          
          Timeout.timeout(timeout) do
            execute_agent(agent_class, context)
          end
        rescue Timeout::Error => e
          raise StandardError, "Step timed out after #{timeout} seconds"
        end

        def execute_agent(agent_class, context)
          agent = agent_class.new(context: context)
          result = agent.call
          
          # Normalize result
          if result.is_a?(Hash) && result[:success] == false
            raise StandardError, result[:error] || "Agent execution failed"
          end
          
          result
        end

        def store_step_result(step_name, step_config, result)
          merge_key = step_config[:merge_as]
          
          # Extract data from result if it's a standard RAAF result
          data = if result.is_a?(Hash) && result.key?(:data)
            result[:data]
          elsif result.is_a?(Hash) && result.key?('data')
            result['data']
          else
            result
          end
          
          @step_results[merge_key] = data
          
          # Log execution
          @execution_log << {
            step: step_name,
            agent: step_config[:agent_class].name,
            status: :completed,
            timestamp: Time.current
          }
        end

        def handle_step_error(step_name, step_config, error)
          RAAF.logger.error "❌ [#{self.class.name}] Step failed: #{step_name} - #{error.message}"
          
          # Check for step-specific error handler
          error_handler = self.class._error_handlers&.[](step_name)
          
          if error_handler && error_handler[:fallback_method]
            fallback_method = error_handler[:fallback_method]
            
            if respond_to?(fallback_method, true)
              RAAF.logger.info "🔄 [#{self.class.name}] Executing step fallback: #{fallback_method}"
              fallback_result = send(fallback_method, error, step_name)
              store_step_result(step_name, step_config, fallback_result)
              return
            end
          end
          
          # Log execution failure
          @execution_log << {
            step: step_name,
            agent: step_config[:agent_class].name,
            status: :failed,
            error: error.message,
            timestamp: Time.current
          }
          
          raise error
        end

        def finalize_pipeline_results
          if self.class._finalizer && respond_to?(self.class._finalizer, true)
            RAAF.logger.info "🏁 [#{self.class.name}] Finalizing results with: #{self.class._finalizer}"
            return send(self.class._finalizer, @step_results)
          end
          
          # Default finalization
          {
            success: true,
            results: @step_results,
            execution_log: @execution_log,
            pipeline: self.class.name
          }
        end

        def handle_pipeline_error(error)
          RAAF.logger.error "❌ [#{self.class.name}] Pipeline failed: #{error.message}"
          RAAF.logger.error error.backtrace.join("\n")
          
          {
            success: false,
            error: "Pipeline execution failed: #{error.message}",
            partial_results: @step_results,
            execution_log: @execution_log,
            pipeline: self.class.name
          }
        end

        def log_pipeline_completion
          duration = @execution_log.any? ? Time.current - @execution_log.first[:timestamp] : 0
          
          RAAF.logger.info "🏁 [#{self.class.name}] Pipeline execution completed",
                            category: :pipeline,
                            data: {
                              steps_completed: @execution_log.count { |log| log[:status] == :completed },
                              steps_failed: @execution_log.count { |log| log[:status] == :failed },
                              total_duration_ms: (duration * 1000).round(2)
                            }
        end

        # Default finalization method (can be overridden)
        def compile_results(step_results)
          {
            success: true,
            results: step_results,
            pipeline: self.class.name
          }
        end
      end
    end

    # Convenience alias
    Pipeline = Pipeline::DeclarativePipeline
  end
end