# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # EvaluationJob executes evaluators on a span based on policy configuration.
      # This is the core job that processes individual evaluation requests.
      #
      # Flow:
      # 1. Fetch span and policy from database
      # 2. Create/update queue item with 'running' status
      # 3. Execute each configured evaluator
      # 4. Store results in ContinuousEvaluationResult
      # 5. Mark queue item as completed
      # 6. Increment policy evaluation counter
      #
      # Error Handling:
      # - Retries on transient failures (network, rate limits)
      # - Discards on permanent failures (span not found)
      # - Updates queue item with failure status and error details
      class EvaluationJob < RAAF::Rails::ApplicationJob
        queue_as :raaf_evaluations

        # Discard on permanent errors
        discard_on RAAF::Eval::SpanNotFoundError
        discard_on ActiveRecord::RecordNotFound

        # Retry on transient errors with exponential backoff
        retry_on RAAF::Eval::RateLimitError, wait: :polynomially_longer, attempts: 5
        retry_on Faraday::ConnectionFailed, wait: :polynomially_longer, attempts: 3
        retry_on Timeout::Error, wait: :polynomially_longer, attempts: 3

        ##
        # Execute evaluation for a span
        # @param span_id [String] Span UUID
        # @param policy_id [Integer] EvaluationPolicy ID
        def perform(span_id:, policy_id:)
          # Load span and policy
          span = find_span(span_id)
          policy = find_policy(policy_id)

          # Create or find queue item
          queue_item = find_or_create_queue_item(span, policy)

          # Execute evaluation
          begin
            queue_item.start!

            # Execute each evaluator in policy
            policy.evaluator_configs.each do |evaluator_config|
              execute_and_store_evaluator(span, policy, queue_item, evaluator_config)
            end

            # Mark as completed
            queue_item.complete!

            # Increment policy evaluation counter
            policy.increment_evaluation_count!
          rescue => e
            # Mark as failed (will retry if possible)
            queue_item.fail!(e.message, e.class.name)
            raise
          end
        end

        private

        def find_span(span_id)
          span = RAAF::Rails::Tracing::SpanRecord.find_by(span_id: span_id)
          raise RAAF::Eval::SpanNotFoundError, "Span not found: #{span_id}" unless span
          span
        end

        def find_policy(policy_id)
          RAAF::Eval::Models::EvaluationPolicy.find(policy_id)
        end

        def find_or_create_queue_item(span, policy)
          RAAF::Eval::Models::EvaluationQueueItem.find_or_create_by!(
            span_id: span.span_id,
            trace_id: span.trace_id,
            evaluation_policy: policy
          ) do |item|
            item.priority = policy.priority
            item.max_attempts = policy.max_retries
            item.status = 'pending'
            item.scheduled_at = Time.current
          end
        end

        def execute_and_store_evaluator(span, policy, queue_item, evaluator_config)
          started_at = Time.current

          # Build evaluator from config using EvaluatorDiscovery
          evaluator = RAAF::Eval::Continuous::EvaluatorDiscovery.build(evaluator_config)

          # Convert span to evaluation format
          field_context = span_to_field_context(span)

          # Execute evaluation
          result = evaluator.evaluate(field_context)

          completed_at = Time.current
          duration_ms = ((completed_at - started_at) * 1000).round

          # Store result
          store_result(span, policy, queue_item, evaluator_config, result, started_at, completed_at, duration_ms)
        end

        def span_to_field_context(span)
          # Convert SpanRecord to FieldContext format expected by evaluators
          # This maps span data to the format used by the evaluation DSL
          RAAF::Eval::DSL::FieldContext.new(
            agent_name: extract_agent_name(span),
            model: extract_model(span),
            input_messages: extract_messages(span, 'user'),
            output_text: extract_output_text(span),
            tool_calls: extract_tool_calls(span),
            metadata: extract_metadata(span)
          )
        end

        def store_result(span, policy, queue_item, evaluator_config, result, started_at, completed_at, duration_ms)
          RAAF::Eval::Models::ContinuousEvaluationResult.create!(
            span_id: span.span_id,
            trace_id: span.trace_id,
            evaluation_policy: policy,
            queue_item: queue_item,
            evaluation_type: 'automated',
            evaluator_name: evaluator_config['name'] || evaluator_config[:name],
            evaluator_type: evaluator_config['type'] || evaluator_config[:type],
            evaluator_version: nil, # TODO: Add version tracking
            agent_name: extract_agent_name(span),
            agent_version: extract_agent_version(span),
            model: extract_model(span),
            provider: extract_provider(span),
            environment: ::Rails.env,
            status: determine_status(result),
            score: result.score,
            scores: result.field_scores || {},
            metrics: extract_metrics(span),
            reasoning: result.reasoning,
            details: result.to_h,
            evaluation_duration_ms: duration_ms,
            evaluation_started_at: started_at,
            evaluation_completed_at: completed_at,
            metadata: {}
          )
        end

        def determine_status(result)
          if result.passed?
            'passed'
          elsif result.failed?
            'failed'
          elsif result.warning?
            'warning'
          else
            'error'
          end
        end

        def extract_agent_name(span)
          span.data.dig('agent', 'name') ||
            span.metadata['agent_name'] ||
            'unknown'
        end

        def extract_agent_version(span)
          span.metadata['agent_version']
        end

        def extract_model(span)
          span.data.dig('request', 'model') ||
            span.metadata['model']
        end

        def extract_provider(span)
          span.metadata['provider']
        end

        def extract_messages(span, role)
          messages = span.data.dig('request', 'messages') || []
          messages.select { |m| m['role'] == role }.map { |m| m['content'] }
        end

        def extract_output_text(span)
          span.data.dig('response', 'content') ||
            span.data.dig('response', 'message', 'content') ||
            ''
        end

        def extract_tool_calls(span)
          span.data.dig('response', 'tool_calls') || []
        end

        def extract_metadata(span)
          span.metadata || {}
        end

        def extract_metrics(span)
          {
            latency_ms: calculate_latency(span),
            tokens: extract_token_usage(span),
            cost: calculate_cost(span)
          }
        end

        def calculate_latency(span)
          return nil unless span.started_at && span.ended_at
          ((span.ended_at - span.started_at) * 1000).round
        end

        def extract_token_usage(span)
          usage = span.data.dig('response', 'usage') || {}
          {
            input_tokens: usage['prompt_tokens'] || usage['input_tokens'] || 0,
            output_tokens: usage['completion_tokens'] || usage['output_tokens'] || 0,
            total_tokens: usage['total_tokens'] || 0
          }
        end

        def calculate_cost(span)
          # TODO: Implement cost calculation based on model and token usage
          0.0
        end
      end
    end
  end
end
