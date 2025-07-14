# frozen_string_literal: true

require "json"
require "csv"
require "yaml"

module OpenAIAgents
  ##
  # Data pipeline framework for agent-based data processing
  #
  # This module provides a comprehensive pipeline framework for building
  # data processing workflows using OpenAI agents. It supports various
  # processing stages including filtering, mapping, validation, enrichment,
  # aggregation, and output generation.
  #
  # @example Basic pipeline usage
  #   require 'openai_agents/data_pipeline'
  #   
  #   # Create a pipeline
  #   pipeline = DataPipeline::PipelineBuilder.new("data-processor")
  #     .input(:json)
  #     .filter { |item| item[:status] == "active" }
  #     .map_with_agent(data_processor_agent)
  #     .validate(required_fields: [:id, :name])
  #     .output(:csv, file: "processed_data.csv")
  #     .build
  #   
  #   # Process data
  #   result = pipeline.process(input_data)
  #   puts "Processed #{result[:processed]} items"
  #
  # @example Advanced agent-based processing
  #   enrichment_agent = Agent.new(
  #     name: "DataEnricher",
  #     instructions: "Enrich customer data with additional insights"
  #   )
  #   
  #   pipeline = DataPipeline::Pipeline.new("customer-enrichment")
  #     .add_stage(DataPipeline::AgentStage.new(enrichment_agent))
  #     .add_stage(DataPipeline::ValidationStage.new(
  #       schema: customer_schema
  #     ))
  #     .add_stage(DataPipeline::OutputStage.new(
  #       format: :jsonl,
  #       destination: "enriched_customers.jsonl"
  #     ))
  #
  # @example Error handling and metrics
  #   result = pipeline.process(data)
  #   puts "Success rate: #{result[:processed] / result[:total] * 100}%"
  #   puts "Errors: #{result[:errors]}"
  #   
  #   # Access detailed metrics
  #   pipeline.metrics.each do |stage, metrics|
  #     puts "#{stage}: #{metrics[:duration]}ms"
  #   end
  #
  # @see Agent Agent class for AI-powered processing
  # @see FunctionTool Function tools for custom operations
  # @since 1.0.0
  #
  module DataPipeline
    ##
    # Main pipeline class
    #
    # Orchestrates data flow through multiple processing stages, providing
    # error handling, metrics collection, and state management. Supports
    # both synchronous and asynchronous processing modes.
    #
    # @example Creating and configuring a pipeline
    #   pipeline = Pipeline.new("user-data-processor", {
    #     parallel: true,
    #     max_workers: 4,
    #     error_strategy: :continue
    #   })
    #   
    #   pipeline
    #     .add_stage(FilterStage.new { |item| item[:active] })
    #     .add_stage(AgentStage.new(processing_agent))
    #     .add_stage(OutputStage.new(format: :json))
    #
    # @example Processing data with error handling
    #   begin
    #     result = pipeline.process(raw_data)
    #     puts "Processed: #{result[:processed]}, Errors: #{result[:errors]}"
    #   rescue PipelineError => e
    #     puts "Pipeline failed: #{e.message}"
    #   end
    #
    class Pipeline
      # @return [String] Pipeline name for identification
      attr_reader :name
      
      # @return [Array<Stage>] Ordered list of processing stages
      attr_reader :stages
      
      # @return [Hash] Pipeline configuration options
      attr_reader :config
      
      # @return [Symbol] Current pipeline state (:idle, :running, :completed, :error)
      attr_reader :state

      ##
      # Initialize a new pipeline
      #
      # @param name [String] Pipeline identifier
      # @param config [Hash] Configuration options
      # @option config [Boolean] :parallel (false) Enable parallel processing
      # @option config [Integer] :max_workers (4) Maximum worker threads
      # @option config [Symbol] :error_strategy (:stop) How to handle errors (:stop, :continue, :skip)
      # @option config [Boolean] :collect_metrics (true) Whether to collect performance metrics
      #
      def initialize(name, config = {})
        @name = name
        @config = default_config.merge(config)
        @stages = []
        @state = :idle
        @metrics = { processed: 0, errors: 0, skipped: 0 }
        @mutex = Mutex.new
      end

      ##
      # Add a stage to the pipeline
      #
      # Stages are executed in the order they are added. Each stage
      # receives the output from the previous stage as input.
      #
      # @param stage [Stage] Processing stage to add
      # @return [Pipeline] Self for method chaining
      #
      # @example
      #   pipeline.add_stage(FilterStage.new { |item| item[:valid] })
      #           .add_stage(AgentStage.new(processor_agent))
      #
      def add_stage(stage)
        @mutex.synchronize do
          @stages << stage
          stage.pipeline = self
        end
        self
      end

      ##
      # Alias for add_stage providing fluent interface
      #
      # @param stage [Stage] Processing stage to add
      # @return [Pipeline] Self for method chaining
      #
      def pipe(stage)
        add_stage(stage)
      end

      ##
      # Process data through the pipeline
      #
      # Executes all stages in sequence, passing data from one stage to the next.
      # Supports error handling strategies and collects performance metrics.
      #
      # @param input_data [Object] Data to process (Array, Hash, String, etc.)
      # @return [Hash] Processing results with metrics
      #   - :processed [Integer] Number of items successfully processed
      #   - :errors [Integer] Number of errors encountered
      #   - :skipped [Integer] Number of items skipped
      #   - :output [Object] Final processed data
      #   - :duration [Float] Total processing time in seconds
      #   - :stage_metrics [Hash] Per-stage performance metrics
      #
      # @raise [PipelineError] If pipeline fails and error_strategy is :stop
      #
      # @example
      #   result = pipeline.process([
      #     { id: 1, name: "John", status: "active" },
      #     { id: 2, name: "Jane", status: "inactive" }
      #   ])
      #   
      #   puts "Processed #{result[:processed]} items in #{result[:duration]}s"
      #
      def process(input_data)
        @state = :running

        begin
          # Prepare input
          data = prepare_input(input_data)

          # Process through stages
          @stages.each_with_index do |stage, index|
            stage_context = {
              stage_index: index,
              total_stages: @stages.length,
              pipeline: @name
            }

            data = stage.process(data, stage_context)

            # Handle stage results
            case data
            when nil
              @metrics[:skipped] += 1
              break
            when StageError
              handle_stage_error(stage, data)
              break unless @config[:continue_on_error]
            end
          end

          @metrics[:processed] += 1
          data
        rescue StandardError => e
          @metrics[:errors] += 1
          handle_pipeline_error(e)
        ensure
          @state = :idle
        end
      end

      # Process batch of data
      def process_batch(data_array, options = {})
        options = @config[:batch_options].merge(options)
        results = []

        if options[:parallel]
          process_parallel(data_array, options, results)
        else
          process_sequential(data_array, results)
        end

        results
      end

      # Stream processing
      def process_stream(stream, options = {})
        @state = :streaming

        begin
          stream.each do |item|
            result = process(item)
            yield(result) if block_given?
          end
        ensure
          @state = :idle
        end
      end

      # Get pipeline metrics
      def metrics
        @mutex.synchronize { @metrics.dup }
      end

      # Reset metrics
      def reset_metrics
        @mutex.synchronize do
          @metrics = { processed: 0, errors: 0, skipped: 0 }
        end
      end

      # Validate pipeline configuration
      def validate
        errors = []

        errors << "Pipeline has no stages" if @stages.empty?

        @stages.each_with_index do |stage, index|
          stage_errors = stage.validate
          stage_errors.each do |error|
            errors << "Stage #{index} (#{stage.name}): #{error}"
          end
        end

        errors
      end

      private

      def default_config
        {
          continue_on_error: false,
          error_handler: :log,
          batch_options: {
            parallel: false,
            max_threads: 4,
            chunk_size: 100
          },
          monitoring: {
            enabled: true,
            interval: 60
          }
        }
      end

      def prepare_input(data)
        case data
        when String
          data
        when Hash, Array
          data
        when Pathname, File
          File.read(data)
        else
          data.to_s
        end
      end

      def process_parallel(data_array, options, results)
        threads = []
        chunks = data_array.each_slice(options[:chunk_size])

        chunks.each do |chunk|
          if threads.size >= options[:max_threads]
            threads.first.join
            threads.shift
          end

          thread = Thread.new do
            chunk.map { |item| process(item) }
          end

          threads << thread
        end

        threads.each(&:join)
        results.flatten!
      end

      def process_sequential(data_array, results)
        data_array.each do |item|
          results << process(item)
        end
      end

      def handle_stage_error(stage, error)
        case @config[:error_handler]
        when :log
          warn "[Pipeline Error] Stage '#{stage.name}': #{error.message}"
        when :raise
          raise error
        when Proc
          @config[:error_handler].call(stage, error)
        end
      end

      def handle_pipeline_error(error)
        case @config[:error_handler]
        when :log
          warn "[Pipeline Error] #{@name}: #{error.message}"
        when :raise
          raise error
        when Proc
          @config[:error_handler].call(self, error)
        end
      end
    end

    # Base stage class
    class Stage
      attr_reader :name, :options
      attr_accessor :pipeline

      def initialize(name, options = {})
        @name = name
        @options = options
      end

      def process(data, context = {})
        raise NotImplementedError, "Subclasses must implement process"
      end

      def validate
        []
      end
    end

    # Transform stage using agent
    class AgentStage < Stage
      def initialize(name, agent:, prompt: nil, **options)
        super(name, options)
        @agent = agent
        @prompt = prompt
      end

      def process(data, context = {})
        messages = build_messages(data, context)

        runner = Runner.new(agent: @agent)
        result = runner.run(messages)

        extract_result(result)
      end

      def validate
        errors = []
        errors << "Agent is required" unless @agent
        errors << "Agent must have instructions" if @agent && @agent.instructions.nil?
        errors
      end

      private

      def build_messages(data, context)
        content = @prompt ? @prompt.gsub("{{data}}", data.to_s) : data.to_s

        [
          {
            role: "user",
            content: content
          }
        ]
      end

      def extract_result(result)
        result.messages.last[:content]
      end
    end

    # Filter stage
    class FilterStage < Stage
      def initialize(name, &block)
        super(name)
        @filter_block = block
      end

      def process(data, context = {})
        if @filter_block.call(data)
          data
        else
          nil # Skip this item
        end
      end
    end

    # Map stage
    class MapStage < Stage
      def initialize(name, &block)
        super(name)
        @map_block = block
      end

      def process(data, context = {})
        @map_block.call(data)
      end
    end

    # Validation stage
    class ValidationStage < Stage
      def initialize(name, schema: nil, &block)
        super(name)
        @schema = schema
        @validation_block = block
      end

      def process(data, context = {})
        errors = validate_data(data)

        if errors.empty?
          data
        else
          StageError.new("Validation failed", errors: errors)
        end
      end

      private

      def validate_data(data)
        errors = []

        errors.concat(validate_schema(data)) if @schema

        if @validation_block
          custom_errors = @validation_block.call(data)
          errors.concat(Array(custom_errors))
        end

        errors
      end

      def validate_schema(data)
        # Simple schema validation
        errors = []

        @schema.each do |key, rules|
          value = data[key]

          errors << "#{key} is required" if rules[:required] && value.nil?

          errors << "#{key} must be a #{rules[:type]}" if rules[:type] && value && !value.is_a?(rules[:type])

          errors << "#{key} format is invalid" if rules[:pattern] && value && !value.match?(rules[:pattern])
        end

        errors
      end
    end

    # Enrichment stage
    class EnrichmentStage < Stage
      def initialize(name, source:, &block)
        super(name)
        @source = source
        @enrichment_block = block
      end

      def process(data, context = {})
        enrichment_data = fetch_enrichment_data(data)

        if @enrichment_block
          @enrichment_block.call(data, enrichment_data)
        else
          data.merge(enrichment_data)
        end
      end

      private

      def fetch_enrichment_data(data)
        case @source
        when Hash
          @source
        when Proc
          @source.call(data)
        when String
          # Could be a file path or URL
          {}
        else
          {}
        end
      end
    end

    # Split stage - splits data into multiple items
    class SplitStage < Stage
      def initialize(name, &block)
        super(name)
        @split_block = block
      end

      def process(data, context = {})
        items = @split_block.call(data)

        # Process each item through remaining stages
        items.map do |item|
          # Clone remaining stages and process
          remaining_stages = context[:remaining_stages] || []
          sub_pipeline = Pipeline.new("#{@pipeline.name}_split")

          remaining_stages.each { |stage| sub_pipeline.add_stage(stage) }
          sub_pipeline.process(item)
        end.flatten
      end
    end

    # Aggregate stage - combines multiple items
    class AggregateStage < Stage
      def initialize(name, window_size: nil, &block)
        super(name)
        @window_size = window_size
        @aggregate_block = block
        @buffer = []
      end

      def process(data, context = {})
        @buffer << data

        if should_aggregate?
          result = @aggregate_block.call(@buffer)
          @buffer.clear
          result
        else
          nil # Skip until window is full
        end
      end

      private

      def should_aggregate?
        @window_size.nil? || @buffer.size >= @window_size
      end
    end

    # Output stage
    class OutputStage < Stage
      def initialize(name, destination:, format: :json)
        super(name)
        @destination = destination
        @format = format
      end

      def process(data, context = {})
        formatted_data = format_data(data)
        write_output(formatted_data)
        data # Pass through
      end

      private

      def format_data(data)
        case @format
        when :json
          JSON.pretty_generate(data)
        when :yaml
          data.to_yaml
        when :csv
          data.values.join(",") if data.is_a?(Hash)
        else
          data.to_s
        end
      end

      def write_output(formatted_data)
        case @destination
        when String
          File.write(@destination, formatted_data)
        when :stdout
          puts formatted_data
        when IO
          @destination.write(formatted_data)
        when Proc
          @destination.call(formatted_data)
        end
      end
    end

    # Pipeline builder DSL
    class PipelineBuilder
      def self.build(name, &)
        builder = new(name)
        builder.instance_eval(&)
        builder.pipeline
      end

      attr_reader :pipeline

      def initialize(name)
        @pipeline = Pipeline.new(name)
      end

      def source(data)
        @source_data = data
        self
      end

      def filter(&)
        @pipeline.add_stage(FilterStage.new("filter", &))
        self
      end

      def map(&)
        @pipeline.add_stage(MapStage.new("map", &))
        self
      end

      def transform(agent:, prompt: nil)
        @pipeline.add_stage(AgentStage.new("transform", agent: agent, prompt: prompt))
        self
      end

      def validate(schema: nil, &)
        @pipeline.add_stage(ValidationStage.new("validate", schema: schema, &))
        self
      end

      def enrich(source:, &)
        @pipeline.add_stage(EnrichmentStage.new("enrich", source: source, &))
        self
      end

      def split(&)
        @pipeline.add_stage(SplitStage.new("split", &))
        self
      end

      def aggregate(window_size: nil, &)
        @pipeline.add_stage(AggregateStage.new("aggregate", window_size: window_size, &))
        self
      end

      def output(destination:, format: :json)
        @pipeline.add_stage(OutputStage.new("output", destination: destination, format: format))
        self
      end

      def run(data = nil)
        data ||= @source_data
        @pipeline.process(data)
      end
    end

    # Predefined pipeline templates
    module Templates
      # ETL pipeline template
      def self.etl_pipeline(name, agent)
        PipelineBuilder.build(name) do
          # Extract
          map do |data|
            JSON.parse(data)
          rescue StandardError
            data
          end

          # Transform with agent
          transform(
            agent: agent,
            prompt: "Clean and standardize this data: {{data}}"
          )

          # Load
          output(destination: "#{name}_output.json", format: :json)
        end
      end

      # Data validation pipeline
      def self.validation_pipeline(name, schema)
        PipelineBuilder.build(name) do
          validate(schema: schema)

          filter { |data| data[:status] == "valid" }

          output(destination: :stdout, format: :yaml)
        end
      end

      # Log processing pipeline
      def self.log_pipeline(name, agent)
        PipelineBuilder.build(name) do
          # Parse log lines
          map do |line|
            if (match = line.match(/\[(\w+)\] (.+)/))
              { level: match[1], message: match[2], raw: line }
            else
              { level: "INFO", message: line, raw: line }
            end
          end

          # Filter errors and warnings
          filter { |log| %w[ERROR WARN].include?(log[:level]) }

          # Analyze with agent
          transform(
            agent: agent,
            prompt: "Analyze this log entry and suggest fixes: {{data}}"
          )

          # Output results
          output(destination: "#{name}_analysis.json", format: :json)
        end
      end
    end

    # Stage error class
    class StageError < StandardError
      attr_reader :errors

      def initialize(message, errors: [])
        super(message)
        @errors = errors
      end
    end

    # Pipeline error
    class PipelineError < StandardError; end
  end
end
