# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # EvaluationEngine orchestrates evaluation runs by re-executing agents
    # with modified configurations and collecting metrics.
    class EvaluationEngine
      ##
      # Create a new evaluation run
      # @param name [String] Name of the evaluation run
      # @param baseline_span [Hash, Object] Baseline span data or span object
      # @param configurations [Array<Hash>] Array of configuration hashes
      # @param description [String, nil] Optional description
      # @param initiated_by [String, nil] User or system identifier
      # @return [RAAF::Eval::Models::EvaluationRun]
      def create_run(name:, baseline_span:, configurations:, description: nil, initiated_by: nil)
        # Serialize baseline span if needed
        span_data = baseline_span.is_a?(Hash) ? baseline_span : SpanSerializer.serialize(baseline_span)

        # Store baseline span
        baseline = Models::EvaluationSpan.create!(
          span_id: span_data[:span_id] || SecureRandom.uuid,
          trace_id: span_data[:trace_id] || SecureRandom.uuid,
          parent_span_id: span_data[:parent_span_id],
          span_type: span_data[:span_type] || "agent",
          span_data: span_data,
          source: "evaluation_run"
        )

        # Create evaluation run
        run = Models::EvaluationRun.create!(
          name: name,
          description: description,
          baseline_span_id: baseline.span_id,
          initiated_by: initiated_by,
          status: "pending"
        )

        # Create configurations
        configurations.each_with_index do |config, index|
          Models::EvaluationConfiguration.create!(
            evaluation_run: run,
            name: config[:name],
            configuration_type: determine_configuration_type(config[:changes]),
            changes: config[:changes],
            execution_order: config[:execution_order] || index,
            metadata: config[:metadata] || {}
          )
        end

        run
      end

      ##
      # Execute an evaluation run
      # @param run [RAAF::Eval::Models::EvaluationRun] Run to execute
      # @return [Array<RAAF::Eval::Models::EvaluationResult>] Results
      def execute_run(run)
        run.start!

        # Get baseline span
        baseline_span = Models::EvaluationSpan.find_by!(span_id: run.baseline_span_id)
        baseline_config = SpanDeserializer.deserialize(baseline_span.span_data)

        results = []

        run.evaluation_configurations.ordered.each do |config|
          begin
            result = execute_configuration(run, config, baseline_config, baseline_span)
            results << result
          rescue StandardError => e
            RAAF::Eval.logger.error("Configuration execution failed: #{e.message}")
            result = create_failed_result(run, config, e)
            results << result
          end
        end

        run.complete!
        results
      rescue StandardError => e
        run.fail!(e.message)
        raise
      end

      private

      def determine_configuration_type(changes)
        types = []
        types << "model" if changes[:model] || changes["model"]
        types << "provider" if changes[:provider] || changes["provider"]
        types << "parameter" if changes[:parameters] || changes["parameters"]
        types << "prompt" if changes[:instructions] || changes["instructions"]

        return "combined" if types.size > 1
        return "#{types.first}_change" if types.size == 1
        "combined"
      end

      def execute_configuration(run, config, baseline_config, baseline_span)
        # Apply configuration changes
        modified_config = apply_configuration_changes(baseline_config, config.changes)

        # Create agent with modified configuration
        agent = create_agent_from_config(modified_config)

        # Execute agent
        runner = RAAF::Runner.new(agent: agent)
        input_messages = modified_config[:input_messages]
        last_user_message = input_messages.reverse.find { |m| m[:role] == "user" || m["role"] == "user" }
        user_input = last_user_message&.dig(:content) || last_user_message&.dig("content") || "Continue"

        # Execute and capture result
        result_data = runner.run(user_input)

        # Serialize result span
        result_span = create_result_span(run, result_data, modified_config)

        # Create evaluation result
        eval_result = Models::EvaluationResult.create!(
          evaluation_run: run,
          evaluation_configuration: config,
          result_span_id: result_span.span_id,
          status: "running"
        )

        # Calculate metrics
        calculate_and_store_metrics(eval_result, baseline_span, result_span)

        eval_result.complete!
        eval_result
      end

      def apply_configuration_changes(baseline_config, changes)
        config = baseline_config.dup
        config[:model] = changes[:model] || changes["model"] if changes[:model] || changes["model"]
        config[:provider] = changes[:provider] || changes["provider"] if changes[:provider] || changes["provider"]
        config[:instructions] = changes[:instructions] || changes["instructions"] if changes[:instructions] || changes["instructions"]

        if changes[:parameters] || changes["parameters"]
          params = changes[:parameters] || changes["parameters"]
          config[:parameters] = config[:parameters].merge(params)
        end

        config
      end

      def create_agent_from_config(config)
        RAAF::Agent.new(
          name: config[:agent_name],
          instructions: config[:instructions],
          model: config[:model],
          **config[:parameters]
        )
      end

      def create_result_span(run, result_data, config)
        span_data = {
          agent_name: config[:agent_name],
          model: config[:model],
          instructions: config[:instructions],
          parameters: config[:parameters],
          input_messages: config[:input_messages],
          output_messages: result_data.messages,
          metadata: {
            tokens: result_data.usage&.dig(:total_tokens),
            input_tokens: result_data.usage&.dig(:input_tokens),
            output_tokens: result_data.usage&.dig(:output_tokens)
          }
        }

        Models::EvaluationSpan.create!(
          span_id: SecureRandom.uuid,
          trace_id: SecureRandom.uuid,
          span_type: "agent",
          span_data: span_data,
          source: "evaluation_run",
          evaluation_run: run
        )
      end

      def calculate_and_store_metrics(eval_result, baseline_span, result_span)
        # Calculate token metrics
        token_metrics = Metrics::TokenMetrics.calculate(baseline_span, result_span)
        eval_result.update!(token_metrics: token_metrics)

        # Calculate latency metrics (mock for now)
        latency_metrics = { total_ms: 1000 }
        eval_result.update!(latency_metrics: latency_metrics)

        # Calculate baseline comparison
        comparison = BaselineComparator.compare(baseline_span, result_span, token_metrics, latency_metrics)
        eval_result.update!(baseline_comparison: comparison)
      end

      def create_failed_result(run, config, error)
        Models::EvaluationResult.create!(
          evaluation_run: run,
          evaluation_configuration: config,
          result_span_id: SecureRandom.uuid,
          status: "failed",
          error_message: error.message,
          error_backtrace: error.backtrace&.join("\n")
        )
      end
    end
  end
end
