# frozen_string_literal: true

require_relative "data_merger"

module RAAF
  module DSL
    # Agent pipeline DSL for orchestrating multi-agent workflows
    # Provides a declarative way to chain agents together with data flow management
    #
    # @example Simple linear pipeline
    #   pipeline = AgentPipeline.build do
    #     step :search, agent: CompanySearchAgent do
    #       input :product, :target_market
    #       output :companies
    #     end
    #     
    #     step :enrich, agent: CompanyEnrichmentAgent do
    #       input :companies
    #       output :enriched_companies
    #     end
    #     
    #     step :score, agent: ProspectScoringAgent do
    #       input :enriched_companies, :product
    #       output :scored_prospects
    #     end
    #   end
    #   
    #   result = pipeline.execute(product: product, target_market: market)
    #
    # @example Conditional execution and parallel steps
    #   pipeline = AgentPipeline.build do
    #     step :discovery, agent: MarketDiscoveryAgent do
    #       input :product, :company
    #       output :markets
    #     end
    #     
    #     parallel_group :enrichment do
    #       step :search_companies, agent: CompanySearchAgent do
    #         input :markets
    #         output :raw_companies
    #         condition { |ctx| ctx.get(:markets)&.size > 0 }
    #       end
    #       
    #       step :gather_stakeholders, agent: StakeholderGathererAgent do
    #         input :markets
    #         output :stakeholder_data
    #         condition { |ctx| ctx.get(:markets)&.any? { |m| m[:priority] == "high" } }
    #       end
    #     end
    #     
    #     step :merge_data, handler: :merge_enrichment_results do
    #       input :raw_companies, :stakeholder_data
    #       output :merged_data
    #     end
    #   end
    #
    class AgentPipeline
      include RAAF::Logger
      def self.build(&block)
        builder = PipelineBuilder.new
        builder.instance_eval(&block)
        new(builder.steps, builder.config)
      end

      def initialize(steps, config = {})
        @steps = steps
        @config = config
        @data_merger = DataMerger.new
        setup_merge_strategies
      end

      # Execute the pipeline with initial context
      #
      # @param initial_context [Hash] Initial context data
      # @return [Hash] Final pipeline result
      #
      def execute(initial_context = {}, debug: false)
        context = RAAF::DSL::ContextVariables.new(initial_context, debug: debug)
        execution_log = []
        
        log_info "🚀 [Pipeline] Starting execution with #{@steps.size} steps"
        
        begin
          @steps.each_with_index do |step, index|
            step_result = execute_step(step, context, index + 1)
            execution_log << step_result[:log_entry]
            
            # Handle step failure
            unless step_result[:success]
              return build_failure_result(step, step_result, execution_log, context)
            end
            
            # Update context with step outputs
            context = merge_step_output(context, step, step_result[:result])
          end
          
          # Build successful result
          build_success_result(execution_log, context)
          
        rescue => e
          log_error "❌ [Pipeline] Execution failed: #{e.message}"
          build_error_result(e, execution_log, context)
        end
      end

      private

      def execute_step(step, context, step_number)
        log_info "🔄 [Pipeline] Step #{step_number}: #{step.name} (#{step.type})"
        
        start_time = Time.current
        
        case step.type
        when :agent
          execute_agent_step(step, context)
        when :parallel_group
          execute_parallel_group(step, context)
        when :handler
          execute_handler_step(step, context)
        else
          {
            success: false,
            error: "Unknown step type: #{step.type}",
            log_entry: build_log_entry(step, step_number, start_time, false)
          }
        end
      rescue => e
        {
          success: false,
          error: e.message,
          exception: e,
          log_entry: build_log_entry(step, step_number, start_time, false, e.message)
        }
      end

      def execute_agent_step(step, context)
        # Check step condition if defined
        if step.condition && !step.condition.call(context)
          log_info "⏭️ [Pipeline] Skipping step #{step.name} (condition not met)"
          return {
            success: true,
            skipped: true,
            result: {},
            log_entry: build_log_entry(step, nil, Time.current, true, "Skipped - condition not met")
          }
        end
        
        # Extract input data for agent
        input_context = extract_step_inputs(step, context)
        
        # Execute agent
        agent_instance = create_agent_instance(step.agent, input_context)
        result = agent_instance.run(context: input_context)
        
        {
          success: result[:success] != false,
          result: result,
          log_entry: build_log_entry(step, nil, Time.current, result[:success] != false)
        }
      end

      def execute_parallel_group(step, context)
        log_info "🔀 [Pipeline] Executing parallel group: #{step.name}"
        
        # Execute all parallel steps
        parallel_results = step.parallel_steps.map do |parallel_step|
          Thread.new do
            execute_step(parallel_step, context, 0)
          end
        end.map(&:value)
        
        # Check if all succeeded
        all_success = parallel_results.all? { |result| result[:success] }
        
        # Merge parallel results
        merged_result = merge_parallel_results(parallel_results, step)
        
        {
          success: all_success,
          result: merged_result,
          parallel_results: parallel_results,
          log_entry: build_log_entry(step, nil, Time.current, all_success)
        }
      end

      def execute_handler_step(step, context)
        # Extract input data
        input_data = extract_step_inputs(step, context)
        
        # Execute custom handler
        handler_result = if step.handler_proc
          step.handler_proc.call(input_data, context)
        elsif step.handler_method
          send(step.handler_method, input_data, context)
        else
          raise "No handler defined for step #{step.name}"
        end
        
        {
          success: true,
          result: { data: handler_result },
          log_entry: build_log_entry(step, nil, Time.current, true)
        }
      end

      def extract_step_inputs(step, context)
        input_context = RAAF::DSL::ContextVariables.new({}, debug: context.debug_enabled)
        
        step.input_fields.each do |field|
          if context.has?(field)
            input_context = input_context.set(field, context.get(field))
          end
        end
        
        input_context
      end

      def merge_step_output(context, step, step_result)
        # Extract output data based on step configuration
        step_data = case step_result
                   when Hash
                     step_result[:data] || step_result
                   else
                     step_result
                   end
        
        # Set output fields in context
        if step.output_fields.size == 1 && step_data.is_a?(Hash) && !step_data.key?(step.output_fields.first)
          # Single output field - set the entire result
          output_key = step.output_fields.first
          context = context.set(output_key, step_data)
        else
          # Multiple output fields or structured data
          step.output_fields.each do |field|
            if step_data.is_a?(Hash) && (step_data.key?(field) || step_data.key?(field.to_s))
              value = step_data[field] || step_data[field.to_s]
              context = context.set(field, value)
            end
          end
        end
        
        context
      end

      def merge_parallel_results(parallel_results, step)
        # Extract data from successful results
        successful_data = parallel_results
          .select { |result| result[:success] }
          .map { |result| result[:result] }
        
        # Use data merger to combine results intelligently
        if successful_data.size > 1
          @data_merger.merge(*successful_data, data_type: step.merge_strategy || :default)
        elsif successful_data.size == 1
          successful_data.first
        else
          {}
        end
      end

      def create_agent_instance(agent_class, input_context)
        case agent_class
        when Class
          agent_class.new(context: input_context)
        when String, Symbol
          # Constantize agent name
          agent_name = agent_class.to_s
          agent_constant = Object.const_get(agent_name)
          agent_constant.new(context: input_context)
        else
          raise ArgumentError, "Invalid agent class: #{agent_class}"
        end
      end

      def build_log_entry(step, step_number, start_time, success, message = nil)
        {
          step_name: step.name,
          step_type: step.type,
          step_number: step_number,
          success: success,
          duration_ms: ((Time.current - start_time) * 1000).round(2),
          message: message,
          timestamp: Time.current.iso8601
        }
      end

      def build_success_result(execution_log, final_context)
        {
          success: true,
          workflow_status: "completed",
          context: final_context,
          execution_log: execution_log,
          summary: "Pipeline completed successfully with #{execution_log.size} steps"
        }
      end

      def build_failure_result(failed_step, step_result, execution_log, context)
        {
          success: false,
          workflow_status: "failed",
          failed_step: failed_step.name,
          error: step_result[:error],
          context: context,
          execution_log: execution_log,
          summary: "Pipeline failed at step: #{failed_step.name}"
        }
      end

      def build_error_result(exception, execution_log, context)
        {
          success: false,
          workflow_status: "error",
          error: exception.message,
          exception: exception.class.name,
          context: context,
          execution_log: execution_log,
          summary: "Pipeline execution error: #{exception.message}"
        }
      end

      def setup_merge_strategies
        # Set up common merge strategies for the data merger
        @data_merger.merge_strategy(:companies) do
          key_field :website_domain
          merge_arrays :technologies, :contact_emails, :social_profiles
          prefer_latest :employee_count, :funding_stage, :last_updated
          combine_objects :enrichment_data
        end

        @data_merger.merge_strategy(:stakeholders) do
          key_field :linkedin_url
          merge_arrays :email_addresses, :phone_numbers
          prefer_latest :current_title, :department
          combine_objects :contact_attempts
        end
      end


      # Custom merge handlers for common patterns
      def merge_enrichment_results(input_data, context)
        companies = input_data.get(:raw_companies) || []
        stakeholders = input_data.get(:stakeholder_data) || []
        
        {
          companies: companies,
          stakeholders: stakeholders,
          total_records: companies.size + stakeholders.size
        }
      end
    end

    # Pipeline builder DSL
    class PipelineBuilder
      attr_reader :steps, :config

      def initialize
        @steps = []
        @config = {}
      end

      # Define a single agent step
      def step(name, agent: nil, handler: nil, &block)
        step_builder = StepBuilder.new(name, :agent)
        
        if agent
          step_builder.agent = agent
        elsif handler.is_a?(Symbol)
          step_builder.type = :handler
          step_builder.handler_method = handler
        elsif handler.is_a?(Proc)
          step_builder.type = :handler
          step_builder.handler_proc = handler
        end
        
        step_builder.instance_eval(&block) if block_given?
        @steps << step_builder.build
      end

      # Define a parallel execution group
      def parallel_group(name, merge_strategy: :default, &block)
        group_builder = ParallelGroupBuilder.new(name)
        group_builder.merge_strategy = merge_strategy
        group_builder.instance_eval(&block)
        @steps << group_builder.build
      end

      # Set pipeline-level configuration
      def configure(&block)
        @config.merge!(instance_eval(&block) || {})
      end
    end

    # Individual step builder
    class StepBuilder
      attr_accessor :name, :type, :agent, :handler_method, :handler_proc
      attr_reader :input_fields, :output_fields

      def initialize(name, type)
        @name = name
        @type = type
        @input_fields = []
        @output_fields = []
        @condition = nil
      end

      def input(*fields)
        @input_fields.concat(fields)
      end

      def output(*fields)
        @output_fields.concat(fields)
      end

      def condition(&block)
        @condition = block
      end

      def build
        PipelineStep.new(
          name: @name,
          type: @type,
          agent: @agent,
          handler_method: @handler_method,
          handler_proc: @handler_proc,
          input_fields: @input_fields,
          output_fields: @output_fields,
          condition: @condition
        )
      end
    end

    # Parallel group builder
    class ParallelGroupBuilder
      attr_accessor :name, :merge_strategy
      attr_reader :parallel_steps

      def initialize(name)
        @name = name
        @merge_strategy = :default
        @parallel_steps = []
      end

      def step(name, agent: nil, handler: nil, &block)
        step_builder = StepBuilder.new(name, agent ? :agent : :handler)
        step_builder.agent = agent if agent
        step_builder.handler_method = handler if handler.is_a?(Symbol)
        step_builder.handler_proc = handler if handler.is_a?(Proc)
        step_builder.instance_eval(&block) if block_given?
        @parallel_steps << step_builder.build
      end

      def build
        PipelineStep.new(
          name: @name,
          type: :parallel_group,
          parallel_steps: @parallel_steps,
          merge_strategy: @merge_strategy
        )
      end
    end

    # Pipeline step data structure
    class PipelineStep
      attr_reader :name, :type, :agent, :handler_method, :handler_proc,
                  :input_fields, :output_fields, :condition, :parallel_steps, :merge_strategy

      def initialize(name:, type:, agent: nil, handler_method: nil, handler_proc: nil,
                     input_fields: [], output_fields: [], condition: nil, 
                     parallel_steps: [], merge_strategy: nil)
        @name = name
        @type = type
        @agent = agent
        @handler_method = handler_method
        @handler_proc = handler_proc
        @input_fields = input_fields
        @output_fields = output_fields
        @condition = condition
        @parallel_steps = parallel_steps
        @merge_strategy = merge_strategy
      end
    end
  end
end