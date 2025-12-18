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
        # @param force [Boolean] Force re-evaluation even if already completed (default: false)
        # @param manual [Boolean] Manual evaluation from UI (runs all evaluators) vs automatic (runs only automatic trigger mode checks)
        def perform(span_id:, policy_id:, force: false, manual: false)
          ::Rails.logger.info "🎯🎯🎯 [EvaluationJob] CODE VERSION 2025-12-03 - perform called for span #{span_id}, policy #{policy_id}, force: #{force}, manual: #{manual}"
          @manual_evaluation = manual

          # Load span and policy
          span = find_span(span_id)
          policy = find_policy(policy_id)

          # Create or find queue item
          queue_item = find_or_create_queue_item(span, policy)

          # Skip if already successfully completed WITH results (job retry after previous success)
          # This prevents InvalidStateTransition errors when job retries
          # against an already-completed queue item
          # successful? returns true for both "completed" and "partial" status
          # But we only skip if there are actual results stored - otherwise reset and re-run
          # UNLESS force: true is passed (manual re-evaluation from UI)
          if queue_item.successful? && !force
            has_results = queue_item.continuous_evaluation_results.exists?
            if has_results
              RAAF.logger.info "[ContinuousEval] Queue item already completed (#{queue_item.status}) with results, skipping re-evaluation for span #{span_id}"
              return
            else
              # Queue item marked complete but no results - reset and re-run
              RAAF.logger.info "[ContinuousEval] Queue item marked #{queue_item.status} but has no results, resetting for span #{span_id}"
              queue_item.retry!
            end
          elsif queue_item.successful? && force
            # Force re-evaluation: reset the queue item
            RAAF.logger.info "[ContinuousEval] Force re-evaluation requested, resetting queue item for span #{span_id}"
            queue_item.retry!
          end

          # Execute evaluation with partial failure handling
          begin
            queue_item.start!

            # Execute each evaluator, tracking success/failure
            results = execute_evaluators_with_partial_failure(span, policy, queue_item)

            # Determine final status based on results
            finalize_queue_item(queue_item, results)

            # Increment policy evaluation counter if any succeeded
            policy.increment_evaluation_count! if results[:succeeded] > 0
          rescue => e
            # Catastrophic failure (before any evaluator ran) - mark as failed
            queue_item.fail!(e.message, e.class.name) if queue_item.processing?
            raise
          end
        end

        private

        ##
        # Execute all evaluators with individual error handling
        # @return [Hash] Results with :succeeded, :failed counts and :errors array
        def execute_evaluators_with_partial_failure(span, policy, queue_item)
          results = { succeeded: 0, failed: 0, errors: [] }

          # For manual evaluations, run all evaluators (all checks)
          # For automatic evaluations, only run evaluators with automatic trigger mode checks
          evaluators_to_run = if @manual_evaluation
            RAAF.logger.info "[ContinuousEval] Manual evaluation - running all evaluators"
            policy.evaluators_for_manual_evaluation
          else
            RAAF.logger.info "[ContinuousEval] Automatic evaluation - running only automatic trigger mode checks"
            policy.evaluators_for_auto_evaluation
          end

          if evaluators_to_run.empty?
            RAAF.logger.info "[ContinuousEval] No evaluators to run (all checks may be manual trigger mode)"
            return results
          end

          evaluators_to_run.each do |evaluator_config|
            evaluator_name = evaluator_config['name'] || evaluator_config[:name] || 'unknown'
            begin
              execute_and_store_evaluator(span, policy, queue_item, evaluator_config)
              results[:succeeded] += 1
              RAAF.logger.debug "[ContinuousEval] Evaluator '#{evaluator_name}' succeeded for span #{span.span_id}"
            rescue StandardError => e
              results[:failed] += 1
              results[:errors] << { evaluator: evaluator_name, error: e.message, error_class: e.class.name }
              RAAF.logger.warn "[ContinuousEval] Evaluator '#{evaluator_name}' failed for span #{span.span_id}: #{e.message}"

              # Store failure result
              store_failure_result(span, policy, queue_item, evaluator_config, e)
            end
          end

          results
        end

        ##
        # Finalize queue item status based on execution results
        def finalize_queue_item(queue_item, results)
          if results[:failed] == 0
            # All evaluators succeeded
            queue_item.complete!
          elsif results[:succeeded] == 0
            # All evaluators failed - use fail! for retry logic
            error_summary = results[:errors].map { |e| "#{e[:evaluator]}: #{e[:error]}" }.join("; ")
            queue_item.fail!(error_summary, "MultipleEvaluatorFailure")
          else
            # Some succeeded, some failed - partial completion
            error_summary = results[:errors].map { |e| "#{e[:evaluator]}: #{e[:error]}" }.join("; ")
            queue_item.complete_partial!(error_summary)
          end
        end

        ##
        # Store a failure result when an evaluator fails
        def store_failure_result(span, policy, queue_item, evaluator_config, error)
          RAAF::Eval::Models::ContinuousEvaluationResult.create!(
            span_id: span.span_id,
            trace_id: span.trace_id,
            evaluation_policy_id: policy.id,
            queue_item_id: queue_item.id,
            evaluation_type: 'automated',
            evaluator_name: evaluator_config['name'] || evaluator_config[:name],
            evaluator_type: evaluator_config['type'] || evaluator_config[:type],
            evaluator_version: nil,
            agent_name: extract_agent_name(span),
            agent_version: extract_agent_version(span),
            model: extract_model(span),
            provider: extract_provider(span),
            environment: ::Rails.env,
            status: 'error',
            score: nil,
            scores: {},
            metrics: extract_metrics(span),
            reasoning: nil,
            details: {
              error_message: error.message,
              error_class: error.class.name,
              backtrace: error.backtrace&.first(10)
            },
            evaluation_duration_ms: nil,
            evaluation_started_at: nil,
            evaluation_completed_at: Time.current,
            metadata: { failure: true }
          )
        rescue StandardError => store_error
          # Log but don't fail if we can't store the failure result
          RAAF.logger.error "[ContinuousEval] Failed to store failure result: #{store_error.message}"
        end

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
          ::Rails.logger.info "🚀 [EvaluationJob] execute_and_store_evaluator starting for span #{span.span_id}"
          ::Rails.logger.info "🚀 [EvaluationJob] evaluator_config keys: #{evaluator_config.keys.inspect}"

          # Build evaluator from config using EvaluatorDiscovery
          evaluator = RAAF::Eval::Continuous::EvaluatorDiscovery.build(evaluator_config)

          # Extract checks (enabled fields) from config
          # Checks are in format "field_name:evaluator_type" (e.g., "individual_scores:consistency")
          # We need to extract just the field name for filtering
          checks = evaluator_config['checks'] || evaluator_config[:checks]
          only_fields = if checks.present?
            checks.map do |check|
              # Extract field name from "field:evaluator" or just "field" format
              field_name = check.to_s.split(':').first
              field_name.to_sym
            end.uniq
          end

          # Check if this is a statistical evaluator that needs historical consistency or re-runs
          evaluator_type = evaluator_config['type'] || evaluator_config[:type]

          # Also check if any specific evaluators require statistical processing (consistency, no_regression)
          # This handles the case where evaluator_type is 'rule_based' but individual checks use 'consistency'
          check_specific_evaluators = evaluator_config['check_specific_evaluators'] || evaluator_config[:check_specific_evaluators] || {}
          has_statistical_checks = check_specific_evaluators.values.any? { |v| %w[consistency no_regression].include?(v) }

          ::Rails.logger.info "🔍 [EvaluationJob] evaluator_type from config: #{evaluator_type.inspect}"
          ::Rails.logger.info "🔍 [EvaluationJob] check_specific_evaluators: #{check_specific_evaluators.inspect}"
          ::Rails.logger.info "🔍 [EvaluationJob] has_statistical_checks: #{has_statistical_checks}"

          if evaluator_type == 'statistical' || has_statistical_checks
            # For statistical evaluators or checks with consistency/no_regression, use statistical path
            ::Rails.logger.info "🔬 [EvaluationJob] Taking STATISTICAL path"
            stat_result = execute_statistical_evaluator(span, evaluator, evaluator_config, only_fields)
            # Statistical path returns { result: EvaluationResult, evaluation_metadata: Hash }
            result = stat_result[:result]
            evaluation_metadata = stat_result[:evaluation_metadata] || {}
            ::Rails.logger.info "🔬 [EvaluationJob] Got evaluation_metadata: #{evaluation_metadata.inspect}"
          else
            ::Rails.logger.info "📊 [EvaluationJob] Taking STANDARD path"
            # Convert span to span_data hash format expected by evaluators
            span_data = span_to_result_hash(span)

            # Debug: Log evaluator type and method resolution
            RAAF.logger.info "[EvaluationJob] Evaluator object: #{evaluator.inspect[0..200]}"
            RAAF.logger.info "[EvaluationJob] Evaluator is a Class: #{evaluator.is_a?(Class)}"
            RAAF.logger.info "[EvaluationJob] Evaluator responds to evaluate: #{evaluator.respond_to?(:evaluate)}"

            # Check criterion_scores type before evaluation
            sample_criterion = span_data.dig(:prospect_evaluations, 0, :criterion_scores)
            RAAF.logger.info "[EvaluationJob] criterion_scores type BEFORE evaluate: #{sample_criterion.class}"

            # Execute evaluation with optional field filtering
            result = evaluator.evaluate(span_data, only_fields: only_fields)
            evaluation_metadata = { mode: "standard" }
          end

          completed_at = Time.current
          duration_ms = ((completed_at - started_at) * 1000).round

          # Store individual result for each checked field (with evaluation metadata)
          store_per_field_results(span, policy, queue_item, evaluator_config, result, started_at, completed_at, duration_ms, only_fields, evaluation_metadata)
        end

        ##
        # Execute statistical evaluator using historical spans or re-running the agent.
        # Mode is determined by consistency_mode in evaluator config:
        # - "historical" (default): Fetch N recent spans and compare field values
        # - "rerun": Re-execute the agent N times with the same input
        # @param span [SpanRecord] The current span being evaluated
        # @param evaluator [Object] The evaluator instance
        # @param evaluator_config [Hash] Evaluator configuration
        # @param only_fields [Array<Symbol>, nil] Fields to evaluate
        # @return [EvaluationResult] Evaluation result
        def execute_statistical_evaluator(span, evaluator, evaluator_config, only_fields)
          ::Rails.logger.info "🔬 [EvaluationJob] execute_statistical_evaluator called for fields: #{only_fields.inspect}"

          # Get trials configuration (default to 3)
          check_trials = evaluator_config['check_trials'] || evaluator_config[:check_trials] || {}
          ::Rails.logger.info "🔬 [EvaluationJob] check_trials config: #{check_trials.inspect}"
          default_trials = evaluator_config.dig('config', 'trials') ||
                          evaluator_config.dig(:config, :trials) || 3

          # Get consistency mode configuration (default to "historical")
          check_consistency_modes = evaluator_config['check_consistency_modes'] || evaluator_config[:check_consistency_modes] || {}

          # Get the original checks to find full check names (field:evaluator format)
          checks = evaluator_config['checks'] || evaluator_config[:checks] || []

          # Determine consistency mode - check per-field first, then default
          # check_consistency_modes uses full check names (e.g., "product_market_fit_score:consistency")
          # while only_fields contains just field names (e.g., :product_market_fit_score)
          primary_field = only_fields&.first&.to_s
          consistency_mode = if primary_field
            # Find the full check name that starts with this field name
            matching_check = checks.find { |c| c.to_s.split(':').first == primary_field }
            if matching_check
              RAAF.logger.info "[ContinuousEval] Looking up consistency_mode for check: #{matching_check}"
              check_consistency_modes[matching_check] || check_consistency_modes[matching_check.to_s] || "historical"
            else
              # Fallback to just the field name
              check_consistency_modes[primary_field] || check_consistency_modes[primary_field.to_sym] || "historical"
            end
          else
            evaluator_config['consistency_mode'] || evaluator_config[:consistency_mode] || "historical"
          end

          ::Rails.logger.info "🔬 [EvaluationJob] Determined consistency_mode: #{consistency_mode}"
          agent_name = extract_agent_name(span)
          ::Rails.logger.info "🔬 [EvaluationJob] agent_name from span: #{agent_name}"

          if consistency_mode == "rerun"
            ::Rails.logger.info "🔄 [EvaluationJob] Calling execute_statistical_with_rerun"
            execute_statistical_with_rerun(span, evaluator, evaluator_config, only_fields, check_trials, default_trials)
          else
            ::Rails.logger.info "📜 [EvaluationJob] Calling execute_statistical_with_historical"
            execute_statistical_with_historical(span, evaluator, evaluator_config, only_fields, check_trials, default_trials, agent_name)
          end
        end

        ##
        # Execute statistical evaluator by re-running the LLM call multiple times.
        # This provides more accurate consistency checks for unique data scenarios.
        # Uses SpanReplayer to directly replay the LLM API call from captured span data,
        # avoiding the need to re-instantiate agents with potentially problematic context.
        # @param span [SpanRecord] The current span being evaluated
        # @param evaluator [Object] The evaluator instance
        # @param evaluator_config [Hash] Evaluator configuration
        # @param only_fields [Array<Symbol>, nil] Fields to evaluate
        # @param check_trials [Hash] Per-field trial configuration
        # @param default_trials [Integer] Default number of trials
        # @return [Hash] Hash with :result (EvaluationResult) and :evaluation_metadata (Hash)
        def execute_statistical_with_rerun(span, evaluator, evaluator_config, only_fields, check_trials, default_trials)
          agent_name = extract_agent_name(span)
          ::Rails.logger.info "🔄 [EvaluationJob] execute_statistical_with_rerun START for #{agent_name}"

          # Use SpanReplayer to directly replay the LLM API call
          # This avoids re-instantiating agents with serialized context (which fails
          # when prompt classes try to call ActiveRecord methods on hash objects)
          replayer = RAAF::Eval::SpanReplayer.new(span)

          unless replayer.replayable?
            ::Rails.logger.warn "⚠️ [EvaluationJob] Span not replayable (missing messages or model), falling back to historical mode"
            return execute_statistical_with_historical(span, evaluator, evaluator_config, only_fields, check_trials, default_trials, agent_name,
                                                       fallback_reason: "span_not_replayable")
          end

          ::Rails.logger.info "🔄 [EvaluationJob] SpanReplayer ready - model: #{replayer.original_model}, messages: #{replayer.original_messages.size}"

          # Determine the MAXIMUM number of trials across all fields
          max_trials = default_trials
          only_fields&.each do |field_name|
            field_key = field_name.to_s
            field_trials = check_trials[field_key] || check_trials[field_name.to_sym] || default_trials
            max_trials = [max_trials, field_trials].max
          end

          RAAF.logger.info "[ContinuousEval] Replaying LLM call #{max_trials} times (max across #{only_fields&.size || 0} fields)"

          # Replay the LLM call max_trials times
          run_results = []
          max_trials.times do |i|
            begin
              RAAF.logger.debug "[ContinuousEval] Replay #{i + 1}/#{max_trials} for #{agent_name}"
              replay_result = replayer.replay
              if replay_result[:success] && replay_result[:content].present?
                # Parse the JSON response content
                parsed_result = parse_replay_content(replay_result[:content])
                run_results << parsed_result if parsed_result
                ::Rails.logger.info "🔄 [EvaluationJob] Replay #{i + 1} succeeded, parsed keys: #{parsed_result&.keys&.first(5)}"
              else
                ::Rails.logger.warn "🔄 [EvaluationJob] Replay #{i + 1} failed: #{replay_result[:error]}"
              end
            rescue StandardError => e
              RAAF.logger.warn "[ContinuousEval] Replay #{i + 1} failed: #{e.message}"
            end
          end

          RAAF.logger.info "[ContinuousEval] Replay completed: #{run_results.size}/#{max_trials} successful runs"

          if run_results.size < 2
            RAAF.logger.warn "[ContinuousEval] Only #{run_results.size} successful replays (tried #{max_trials}), falling back to historical mode"
            return execute_statistical_with_historical(span, evaluator, evaluator_config, only_fields, check_trials, default_trials, agent_name,
                                                       fallback_reason: "replay_failed", attempted_reruns: max_trials, successful_reruns: run_results.size)
          end

          # Build span_data with replay values for ALL fields from the shared runs
          # Pass evaluator_config to enable transform_span_data and field selector lookup
          span_data = build_rerun_span_data(span, run_results, only_fields, check_trials, default_trials, evaluator_config: evaluator_config)
          ::Rails.logger.info "🔄 [EvaluationJob] span_data[:product_market_fit_score]: #{span_data[:product_market_fit_score].inspect}"
          ::Rails.logger.info "🔄 [EvaluationJob] span_data[:industry_score]: #{span_data[:industry_score].inspect}"

          RAAF.logger.info "[ContinuousEval] Consistency check using #{run_results.size} replays for #{only_fields&.size || 0} fields"

          # Execute evaluation and return with metadata
          evaluation_metadata = {
            mode: "replay",
            successful_reruns: run_results.size,
            replay_model: replayer.original_model
          }
          result = evaluator.evaluate(span_data, only_fields: only_fields)
          { result: result, evaluation_metadata: evaluation_metadata }
        end

        ##
        # Parse the content from a replay result.
        # Handles JSON parsing with markdown code fence removal.
        # @param content [String] Raw content from replay
        # @return [Hash, nil] Parsed hash or nil
        def parse_replay_content(content)
          return nil if content.blank?

          # Strip markdown code fences if present
          clean_content = content
            .gsub(/\A```(?:json)?\s*\n?/, '')
            .gsub(/\n?```\s*\z/, '')
            .strip

          parsed = JSON.parse(clean_content)
          deep_symbolize_keys(parsed)
        rescue JSON::ParserError => e
          ::Rails.logger.warn "🔄 [EvaluationJob] Failed to parse replay content: #{e.message}"
          nil
        end

        ##
        # Execute statistical evaluator using historical spans.
        # @param span [SpanRecord] The current span being evaluated
        # @param evaluator [Object] The evaluator instance
        # @param evaluator_config [Hash] Evaluator configuration
        # @param only_fields [Array<Symbol>, nil] Fields to evaluate
        # @param check_trials [Hash] Per-field trial configuration
        # @param default_trials [Integer] Default number of trials
        # @param agent_name [String] Agent name
        # @param fallback_reason [String, nil] Reason for fallback (if applicable)
        # @param attempted_reruns [Integer, nil] Number of reruns attempted (if fallback from rerun)
        # @param successful_reruns [Integer, nil] Number of successful reruns (if fallback from rerun)
        # @return [Hash] Hash with :result (EvaluationResult) and :evaluation_metadata (Hash)
        def execute_statistical_with_historical(span, evaluator, evaluator_config, only_fields, check_trials, default_trials, agent_name,
                                                fallback_reason: nil, attempted_reruns: nil, successful_reruns: nil)
          # Fetch historical spans for consistency comparison
          historical_spans = fetch_historical_spans(agent_name, span.span_id, default_trials)

          # Build evaluation metadata including fallback information
          evaluation_metadata = {}
          if fallback_reason
            evaluation_metadata[:fallback_reason] = fallback_reason
            evaluation_metadata[:attempted_reruns] = attempted_reruns if attempted_reruns
            evaluation_metadata[:successful_reruns] = successful_reruns if successful_reruns
            evaluation_metadata[:fallback_mode] = "historical"
            evaluation_metadata[:note] = "Complex agents with incremental processing may not support re-run mode. Using historical spans instead."
          end

          if historical_spans.empty?
            RAAF.logger.info "[ContinuousEval] No historical spans found for #{agent_name}, using single-span evaluation"
            span_data = span_to_result_hash(span)
            evaluation_metadata = evaluation_metadata.merge(mode: "single_span", historical_spans_found: 0)
            result = evaluator.evaluate(span_data, only_fields: only_fields)
            return { result: result, evaluation_metadata: evaluation_metadata }
          end

          RAAF.logger.info "[ContinuousEval] Found #{historical_spans.size} historical spans for consistency comparison"

          # Build span_data with historical values for each field
          # For consistency evaluation, we need to merge values from multiple spans
          span_data = build_historical_span_data(span, historical_spans, only_fields, check_trials, default_trials)
          evaluation_metadata = evaluation_metadata.merge(mode: "historical", historical_spans_found: historical_spans.size)

          # Execute evaluation
          result = evaluator.evaluate(span_data, only_fields: only_fields)
          { result: result, evaluation_metadata: evaluation_metadata }
        end

        ##
        # Find the agent class by name.
        # Searches in common namespaces for RAAF DSL agents.
        # @param agent_name [String] Agent name (e.g., "Prospect::ScoringAgent")
        # @return [Class, nil] Agent class or nil if not found
        def find_agent_class(agent_name)
          return nil if agent_name.blank?

          # Try direct constantize first
          begin
            return agent_name.constantize if agent_name.constantize.respond_to?(:new)
          rescue NameError
            # Continue to try other namespaces
          end

          # Try common AI agent namespaces
          %w[Ai::Agents:: Agents:: ::].each do |namespace|
            begin
              full_name = "#{namespace}#{agent_name}"
              klass = full_name.constantize
              return klass if klass.respond_to?(:new)
            rescue NameError
              # Continue to next namespace
            end
          end

          # Try converting agent_name from "DomainActionAgent" format to "Ai::Agents::Domain::Action"
          # e.g., "ProspectScoringAgent" → "Ai::Agents::Prospect::Scoring"
          if agent_name.end_with?('Agent')
            # Remove "Agent" suffix
            name_without_agent = agent_name.sub(/Agent$/, '')
            # Split on capital letters to get parts: "ProspectScoring" → ["Prospect", "Scoring"]
            parts = name_without_agent.scan(/[A-Z][a-z0-9]*/)
            if parts.size >= 2
              # Try Ai::Agents::Part1::Part2 (e.g., Ai::Agents::Prospect::Scoring)
              nested_name = "Ai::Agents::#{parts.join('::')}"
              begin
                klass = nested_name.constantize
                return klass if klass.respond_to?(:new)
              rescue NameError
                # Continue
              end
            end
          end

          nil
        end

        ##
        # Extract the original input message from a span.
        # @param span [SpanRecord] The span to extract input from
        # @return [String, nil] Original input or nil
        def extract_original_input(span)
          attrs = span.span_attributes || {}

          # Try various locations for input
          input = attrs['agent.input'] || attrs['input']
          return input if input.present?

          # Try to extract from conversation messages
          messages_json = attrs['agent.conversation_messages']
          return nil unless messages_json

          begin
            messages = messages_json.is_a?(String) ? JSON.parse(messages_json) : messages_json
            user_messages = messages.select { |m| m['role'] == 'user' }
            user_messages.first&.dig('content')
          rescue JSON::ParserError
            nil
          end
        end

        ##
        # Extract original context/parameters from a span.
        # @param span [SpanRecord] The span to extract context from
        # @return [Hash] Context hash (may be empty)
        def extract_original_context(span)
          ::Rails.logger.info "🔧 [EvaluationJob] extract_original_context START"
          attrs = span.span_attributes || {}

          # Try to get context from span attributes first
          context_json = attrs['agent.context'] || attrs['context']
          ::Rails.logger.info "🔧 [EvaluationJob] context_json from attrs: #{context_json.present? ? 'present' : 'nil'}"
          if context_json.present?
            begin
              context = context_json.is_a?(String) ? JSON.parse(context_json) : context_json
              ::Rails.logger.info "🔧 [EvaluationJob] Returning context from attrs with keys: #{context.keys.first(5)}"
              return deep_symbolize_keys(context)
            rescue JSON::ParserError => e
              ::Rails.logger.warn "🔧 [EvaluationJob] JSON parse failed for attrs context: #{e.message}"
              # Continue to try other methods
            end
          end

          # Try to extract context from input_data in the input (RAAF DSL agents often embed context in input)
          input = extract_original_input(span)
          ::Rails.logger.info "🔧 [EvaluationJob] input present: #{input.present?}, length: #{input&.length}"
          if input.present?
            begin
              # Strip markdown code fence if present (handle both ``` and ```json)
              ::Rails.logger.info "🔧 [EvaluationJob] Input first 100 chars: #{input.first(100).inspect}"
              clean_input = input.gsub(/\A```(?:json)?\s*\n?/, '').gsub(/\n?```\s*\z/, '')
              ::Rails.logger.info "🔧 [EvaluationJob] Clean input first 100 chars: #{clean_input.first(100).inspect}"
              parsed = JSON.parse(clean_input)
              ::Rails.logger.info "🔧 [EvaluationJob] Parsed JSON keys: #{parsed.keys.first(5)}"
              if parsed.is_a?(Hash) && parsed['input_data'].is_a?(Hash)
                ::Rails.logger.info "🔧 [EvaluationJob] ✅ Extracted context from input_data with keys: #{parsed['input_data'].keys.first(5)}"
                return deep_symbolize_keys(parsed['input_data'])
              else
                ::Rails.logger.info "🔧 [EvaluationJob] input_data not found or not a Hash"
              end
            rescue JSON::ParserError => e
              ::Rails.logger.warn "🔧 [EvaluationJob] JSON parse failed for input: #{e.message}"
              # Continue
            end
          end

          ::Rails.logger.info "🔧 [EvaluationJob] Returning empty context"
          {}
        end

        ##
        # Re-run an agent with the given input and context.
        # For RAAF DSL agents, the agent gets all data from context during initialization.
        # The `run` method is called without arguments.
        # @param agent_class [Class] The agent class to instantiate
        # @param input [String] The original input (for reference/logging, not passed to agent)
        # @param context [Hash] Context parameters including input_data
        # @return [Hash, nil] Result hash or nil on failure
        def rerun_agent(agent_class, input, context)
          ::Rails.logger.info "🏃 [EvaluationJob] rerun_agent called with class=#{agent_class}, input_size=#{input&.size}, context_keys=#{context&.keys}"

          # CRITICAL: Add force_reprocess: true for evaluation reruns
          # This bypasses skip_if callbacks in incremental processing agents
          # which may try to call AR methods on deserialized (hash) context objects.
          # For consistency evaluation, we want full reprocessing anyway.
          rerun_context = if context.present?
            context.merge(force_reprocess: true)
          else
            { force_reprocess: true }
          end

          # Instantiate the agent with context (RAAF DSL agents get all data from context)
          ::Rails.logger.info "🏃 [EvaluationJob] Instantiating agent with context (force_reprocess: true): #{rerun_context.keys}"
          agent = agent_class.new(**rerun_context)

          # Run the agent (RAAF DSL agents don't take input arguments - they use context)
          ::Rails.logger.info "🏃 [EvaluationJob] Calling agent.run (no input arg - RAAF DSL uses context)"
          result = agent.run
          ::Rails.logger.info "🏃 [EvaluationJob] Agent.run returned: #{result.class.name}"

          # Extract the result data
          if result.respond_to?(:to_h)
            ::Rails.logger.info "🏃 [EvaluationJob] Extracting via .to_h"
            result.to_h
          elsif result.respond_to?(:final_output)
            # Handle RAAF::Runner results
            ::Rails.logger.info "🏃 [EvaluationJob] Extracting via .final_output"
            parse_final_output(result.final_output)
          else
            ::Rails.logger.warn "🏃 [EvaluationJob] Could not extract result, returning nil"
            nil
          end
        rescue StandardError => e
          ::Rails.logger.error "🏃 [EvaluationJob] Agent re-run FAILED: #{e.class}: #{e.message}"
          ::Rails.logger.error "🏃 [EvaluationJob] Backtrace: #{e.backtrace.first(5).join("\n")}"
          nil
        end

        ##
        # Parse final output from agent run.
        # @param output [String, Hash] Output to parse
        # @return [Hash] Parsed output
        def parse_final_output(output)
          return output if output.is_a?(Hash)
          return {} if output.blank?

          begin
            JSON.parse(output, symbolize_names: true)
          rescue JSON::ParserError
            { output: output }
          end
        end

        ##
        # Build span_data with values from re-run results.
        # Respects per-field trial limits - if a field requests fewer trials than
        # we ran, only use that many values for that field.
        #
        # IMPORTANT: This method applies the evaluator's transform_span_data block
        # to each replay result before extracting field values. This is necessary
        # because field selection paths (e.g., 'prospect_evaluations.*.criterion_scores.industry.score')
        # may require transformed data structures.
        #
        # @param span [SpanRecord] Current span (for metadata)
        # @param run_results [Array<Hash>] Results from multiple agent runs
        # @param only_fields [Array<Symbol>, nil] Fields to evaluate
        # @param check_trials [Hash] Per-field trial configuration
        # @param default_trials [Integer] Default number of trials
        # @param evaluator_config [Hash] Evaluator configuration for transformation lookup
        # @return [Hash] Span data with arrays for consistency evaluation
        def build_rerun_span_data(span, run_results, only_fields, check_trials = {}, default_trials = 3, evaluator_config: nil)
          current_data = span_to_result_hash(span)
          ::Rails.logger.info "📦 [EvaluationJob] build_rerun_span_data called with #{run_results.size} results for fields: #{only_fields.inspect}"

          # Get the custom evaluator class for transformation
          evaluator_class = nil
          if evaluator_config
            evaluator_name = evaluator_config['name'] || evaluator_config[:name]
            evaluator_class = RAAF::Eval::Continuous::EvaluatorDiscovery.find_custom_evaluator_by_name(evaluator_name)
            ::Rails.logger.info "📦 [EvaluationJob] Found evaluator class: #{evaluator_class}" if evaluator_class
          end

          # Transform each replay result using the evaluator's span_transformer if available
          transformed_results = run_results.map do |result|
            if evaluator_class && evaluator_class.respond_to?(:span_transformer_block) && evaluator_class.span_transformer_block
              ::Rails.logger.info "📦 [EvaluationJob] Applying span_transformer_block to replay result"
              evaluator_class.span_transformer_block.call(result)
            else
              result
            end
          end

          # For each field, collect values from re-runs (respecting per-field limits)
          only_fields&.each do |field_name|
            field_key = field_name.to_s
            field_trials = check_trials[field_key] || check_trials[field_name.to_sym] || default_trials
            ::Rails.logger.info "📦 [EvaluationJob] Processing field '#{field_name}' with #{field_trials} trials"

            # Get field selections from the evaluator class to find field paths
            field_selections = evaluator_class&.respond_to?(:field_selections) ? evaluator_class.field_selections : []
            ::Rails.logger.info "📦 [EvaluationJob] Field selections available: #{field_selections&.size || 0}"

            # Collect values, limiting to the number of trials requested for this field
            values = transformed_results.first(field_trials).filter_map do |result|
              val = extract_field_value_from_result(result, field_name, field_selections)
              ::Rails.logger.info "📦 [EvaluationJob] - Extracted #{field_name} = #{val.inspect}"
              val
            end

            ::Rails.logger.info "📦 [EvaluationJob] Collected #{values.size} values for '#{field_name}': #{values.inspect}"

            # For consistency evaluator, the field value should be an array
            if values.size > 1
              current_data[field_name] = values
              RAAF.logger.debug "[ContinuousEval] Field '#{field_name}' using #{values.size}/#{field_trials} re-run values for consistency"
            else
              ::Rails.logger.warn "📦 [EvaluationJob] Only #{values.size} values collected, NOT assigning to current_data (needs > 1)"
            end
          end

          current_data
        end

        ##
        # Extract a field value from a result, using field selections if available
        # @param result [Hash] The result hash (possibly transformed)
        # @param field_name [Symbol] The field alias (e.g., :industry_score)
        # @param field_selections [Array<Hash>] Array of { path: ..., as: ... } from evaluator
        # @return [Object, nil] The extracted value
        def extract_field_value_from_result(result, field_name, field_selections)
          # First try direct access (for simple field names)
          val = result[field_name] || result[field_name.to_s]
          return val if val.present?

          # If we have field selections, find the path for this alias
          if field_selections && field_selections.any?
            selection = field_selections.find { |s| s[:as]&.to_sym == field_name.to_sym }
            if selection && selection[:path]
              ::Rails.logger.info "📦 [EvaluationJob] Using field_selection path: #{selection[:path]} for alias: #{field_name}"
              val = extract_value_by_path(result, selection[:path])
              return val if val.present?
            end
          end

          # Fallback: try common nested patterns for scoring agents
          # Pattern: prospect_evaluations.*.criterion_scores.<criterion>.score
          # where <criterion> maps to field names like industry_score -> industry
          if field_name.to_s.end_with?('_score')
            criterion_code = field_name.to_s.sub(/_score$/, '')
            val = extract_criterion_score(result, criterion_code)
            return val if val.present?
          end

          nil
        end

        ##
        # Extract a value from a hash using a dot-notation path
        # Supports wildcard (*) for array iteration
        # @param data [Hash] The data hash
        # @param path [String] Dot-notation path (e.g., "prospect_evaluations.*.criterion_scores.industry.score")
        # @return [Object, nil] The extracted value(s)
        def extract_value_by_path(data, path)
          parts = path.split('.')
          extract_value_by_parts(data, parts)
        end

        ##
        # Extract a value from a hash using path parts array
        # @param data [Object] Current data position
        # @param parts [Array<String>] Remaining path parts
        # @return [Object, nil] The extracted value
        def extract_value_by_parts(data, parts)
          return data if parts.empty?
          return nil if data.nil?

          current_part = parts.first
          remaining_parts = parts.drop(1)

          if current_part == '*'
            # Wildcard: data should be an array, iterate and continue with remaining path
            return nil unless data.is_a?(Array)

            if remaining_parts.empty?
              return data # Return the array itself if no remaining path
            else
              # For simplicity, return the first match from the array
              data.each do |item|
                val = extract_value_by_parts(item, remaining_parts)
                return val if val.present?
              end
              return nil
            end
          elsif data.is_a?(Hash)
            next_data = data[current_part.to_sym] || data[current_part.to_s]
            extract_value_by_parts(next_data, remaining_parts)
          elsif data.is_a?(Array) && current_part.match?(/^\d+$/)
            next_data = data[current_part.to_i]
            extract_value_by_parts(next_data, remaining_parts)
          else
            nil
          end
        end

        ##
        # Extract a criterion score from prospect_evaluations structure
        # @param result [Hash] The result hash
        # @param criterion_code [String] The criterion code (e.g., "industry")
        # @return [Object, nil] The score value
        def extract_criterion_score(result, criterion_code)
          result = result.to_h.with_indifferent_access if result.respond_to?(:to_h)
          evaluations = result[:prospect_evaluations] || result['prospect_evaluations'] || []
          return nil if evaluations.empty?

          first_eval = evaluations.first
          criterion_scores = first_eval[:criterion_scores] || first_eval['criterion_scores']
          return nil unless criterion_scores

          # Handle both array format (original) and hash format (transformed)
          if criterion_scores.is_a?(Hash)
            # Hash format: criterion_scores[criterion_code][:score]
            criterion = criterion_scores[criterion_code.to_sym] || criterion_scores[criterion_code.to_s]
            criterion[:score] || criterion['score'] if criterion
          elsif criterion_scores.is_a?(Array)
            # Array format: find by criterion_code
            cs = criterion_scores.find { |c| (c[:criterion_code] || c['criterion_code']) == criterion_code }
            cs[:score] || cs['score'] if cs
          end
        end

        ##
        # Fetch historical spans from the same agent for consistency comparison
        # @param agent_name [String] Agent name to match
        # @param current_span_id [String] Current span ID to exclude
        # @param limit [Integer] Maximum number of historical spans to fetch
        # @return [Array<SpanRecord>] Historical spans
        def fetch_historical_spans(agent_name, current_span_id, limit)
          RAAF::Rails::Tracing::SpanRecord
            .where("span_attributes->>'agent.name' = ?", agent_name)
            .where.not(span_id: current_span_id)
            .order(created_at: :desc)
            .limit(limit)
        end

        ##
        # Build span_data with historical values for consistency evaluation.
        # For each field, collects values from current + historical spans.
        # @param span [SpanRecord] Current span
        # @param historical_spans [Array<SpanRecord>] Historical spans
        # @param only_fields [Array<Symbol>, nil] Fields to evaluate
        # @param check_trials [Hash] Per-field trial configuration
        # @param default_trials [Integer] Default number of trials
        # @return [Hash] Span data with historical values
        def build_historical_span_data(span, historical_spans, only_fields, check_trials, default_trials)
          current_data = span_to_result_hash(span)

          # For each field, collect historical values
          only_fields&.each do |field_name|
            field_key = field_name.to_s
            trials = check_trials[field_key] || check_trials[field_name.to_sym] || default_trials

            # Collect values from current and historical spans (up to trials count)
            values = []
            values << current_data[field_name] if current_data[field_name].present?

            historical_spans.first(trials - 1).each do |hist_span|
              hist_data = span_to_result_hash(hist_span)
              values << hist_data[field_name] if hist_data[field_name].present?
            end

            # For consistency evaluator, the field value should be an array
            # This allows the consistency evaluator to calculate std_dev, etc.
            if values.size > 1
              current_data[field_name] = values
              RAAF.logger.debug "[ContinuousEval] Field '#{field_name}' using #{values.size} historical values for consistency"
            end
          end

          current_data
        end

        ##
        # Convert SpanRecord to span_data hash format expected by evaluators
        # The evaluator's DSL::Engine::Evaluator.evaluate method expects a Hash,
        # which it then uses to extract fields and create FieldContexts internally.
        # @param span [SpanRecord] The span record to convert
        # @return [Hash] Span data hash with all relevant fields
        def span_to_result_hash(span)
          result_hash = {
            agent_name: extract_agent_name(span),
            model: extract_model(span),
            input_messages: extract_messages(span, 'user'),
            output: extract_output_text(span),
            output_text: extract_output_text(span),
            tool_calls: extract_tool_calls(span),
            metadata: extract_metadata(span),
            usage: extract_token_usage(span),
            latency_ms: calculate_latency(span),
            cost_usd: calculate_cost(span)
          }

          # Parse the agent's structured output and merge it into result_hash
          # This allows evaluators to access fields like `prospect_evaluations` directly
          parsed_response = parse_agent_response(span)
          result_hash.merge!(parsed_response) if parsed_response.is_a?(Hash)

          result_hash
        end

        ##
        # Store individual result records for each evaluated field.
        # Creates one ContinuousEvaluationResult per field, enabling granular tracking.
        # @param span [SpanRecord] The span being evaluated
        # @param policy [EvaluationPolicy] The policy configuration
        # @param queue_item [EvaluationQueueItem] The queue item for this evaluation
        # @param evaluator_config [Hash] Configuration for this evaluator
        # @param result [EvaluationResult] The evaluation result with field_results
        # @param started_at [Time] When evaluation started
        # @param completed_at [Time] When evaluation completed
        # @param duration_ms [Integer] Total duration in milliseconds
        # @param only_fields [Array<Symbol>, nil] Fields that were evaluated (nil = all)
        # @param evaluation_metadata [Hash] Additional metadata about the evaluation execution (mode, fallback info, etc.)
        def store_per_field_results(span, policy, queue_item, evaluator_config, result, started_at, completed_at, duration_ms, only_fields, evaluation_metadata = {})
          evaluator_name = evaluator_config['name'] || evaluator_config[:name]
          evaluator_type = evaluator_config['type'] || evaluator_config[:type]

          # Get field results and individual evaluator results
          field_results = result.field_results
          evaluator_results = result.evaluator_results || {}

          # Filter to only the checked fields if specified
          fields_to_store = if only_fields.present?
            field_results.select { |field_name, _| only_fields.include?(field_name.to_sym) }
          else
            field_results
          end

          # Calculate duration per field (approximate)
          per_field_duration = fields_to_store.any? ? (duration_ms / fields_to_store.size) : duration_ms

          # Get span data for result formatting
          span_data = span_to_result_hash(span)

          # Create one result record per field
          fields_to_store.each do |field_name, field_result|
            # Extract reasoning from multiple possible locations
            # Evaluators may store it at top level or inside details
            reasoning = field_result[:reasoning] ||
                       field_result.dig(:details, :reasoning) ||
                       field_result.dig(:details, "reasoning") ||
                       field_result[:message]  # Fallback to message if no reasoning

            # Get the specific evaluators used for this field
            # evaluator_results[field_name] is a hash keyed by evaluator alias
            field_evaluators = evaluator_results[field_name] || evaluator_results[field_name.to_sym] || {}
            specific_evaluators = field_evaluators.keys.map(&:to_s)

            # Generate formatted markdown result using per-field formatter, evaluator formatter, or built-in
            formatted_markdown = generate_formatted_result(evaluator_config, field_name, field_result, span_data)

            # Build metadata including evaluation execution info (mode, fallback, etc.)
            result_metadata = {
              field_name: field_name.to_s,
              check_name: field_name.to_s,
              specific_evaluators: specific_evaluators
            }.merge(evaluation_metadata)

            RAAF::Eval::Models::ContinuousEvaluationResult.create!(
              span_id: span.span_id,
              trace_id: span.trace_id,
              evaluation_policy_id: policy.id,
              queue_item_id: queue_item.id,
              evaluation_type: 'automated',
              evaluator_name: evaluator_name,
              evaluator_type: evaluator_type,
              evaluator_version: nil,
              agent_name: extract_agent_name(span),
              agent_version: extract_agent_version(span),
              model: extract_model(span),
              provider: extract_provider(span),
              environment: ::Rails.env,
              status: determine_field_status(field_result),
              score: field_result[:score],
              scores: { field_name.to_s => field_result[:score] },
              metrics: extract_metrics(span),
              reasoning: reasoning,
              details: {
                field_name: field_name.to_s,
                result: field_result,
                formatted_markdown: formatted_markdown
              },
              evaluation_duration_ms: per_field_duration,
              evaluation_started_at: started_at,
              evaluation_completed_at: completed_at,
              metadata: result_metadata
            )
          end
        end

        ##
        # Generate formatted markdown result using the following priority:
        # 1. Per-field result_format block (defined in evaluate_field do ... end)
        # 2. Evaluator-level result_format block (defined on the evaluator class)
        # 3. Built-in evaluator format_result class method (for standard evaluators)
        #
        # @param evaluator_config [Hash] Configuration containing evaluator name
        # @param field_name [Symbol, String] The field name being evaluated
        # @param field_result [Hash] The evaluation result for a field
        # @param span_data [Hash] The original span data being evaluated
        # @return [String, nil] Markdown-formatted result or nil if no formatter defined
        def generate_formatted_result(evaluator_config, field_name, field_result, span_data)
          # Get the evaluator name from config
          evaluator_name = evaluator_config['name'] || evaluator_config[:name]
          return nil unless evaluator_name

          # Find the evaluator class using EvaluatorDiscovery
          evaluator_class = RAAF::Eval::Continuous::EvaluatorDiscovery.find_custom_evaluator_by_name(evaluator_name)

          if evaluator_class
            # Priority 1: Per-field result_format block
            if evaluator_class.respond_to?(:field_result_formatter_for)
              field_formatter = evaluator_class.field_result_formatter_for(field_name)
              if field_formatter
                return field_formatter.call(field_result, span_data)
              end
            end

            # Priority 2: Evaluator-level result_format block
            if evaluator_class.respond_to?(:result_formatter_block)
              evaluator_formatter = evaluator_class.result_formatter_block
              if evaluator_formatter
                return evaluator_formatter.call(field_result, span_data)
              end
            end
          end

          # Priority 3: Built-in evaluator format_result class method
          # Try to get the specific evaluator class from the field result's details
          try_builtin_evaluator_format(field_result)
        rescue StandardError => e
          RAAF.logger.warn "[ContinuousEval] Failed to generate formatted result: #{e.message}"
          nil
        end

        ##
        # Try to format result using built-in evaluator's format_result class method.
        # Detects which evaluator produced the result based on details keys.
        # @param field_result [Hash] The evaluation result containing details
        # @return [String, nil] Formatted markdown or nil
        def try_builtin_evaluator_format(field_result)
          details = field_result[:details] || {}

          # Detect evaluator type from details and try built-in formatter
          builtin_class = detect_builtin_evaluator_class(details)
          return nil unless builtin_class

          if builtin_class.respond_to?(:format_result)
            return builtin_class.format_result(field_result)
          end

          nil
        end

        ##
        # Detect which built-in evaluator class produced the result based on details keys.
        # @param details [Hash] The evaluation result details
        # @return [Class, nil] The evaluator class or nil
        def detect_builtin_evaluator_class(details)
          # Consistency evaluator: has coefficient_of_variation
          if details[:coefficient_of_variation] || details['coefficient_of_variation']
            return RAAF::Eval::Evaluators::Statistical::Consistency if defined?(RAAF::Eval::Evaluators::Statistical::Consistency)
          end

          # NoRegression evaluator: has no_baseline, drop, or max_drop
          if details[:no_baseline] || details['no_baseline'] ||
             details[:drop] || details['drop'] ||
             details[:max_drop] || details['max_drop']
            return RAAF::Eval::Evaluators::Regression::NoRegression if defined?(RAAF::Eval::Evaluators::Regression::NoRegression)
          end

          nil
        end

        ##
        # Determine status for a single field result
        # @param field_result [Hash] Result hash with :score key
        # @return [String] Status: "good", "average", or "bad"
        def determine_field_status(field_result)
          score = field_result[:score]
          return "bad" if score.nil?

          if score >= 0.8
            "good"
          elsif score >= 0.5
            "average"
          else
            "bad"
          end
        end

        # Keep legacy method for backwards compatibility
        def store_result(span, policy, queue_item, evaluator_config, result, started_at, completed_at, duration_ms)
          RAAF::Eval::Models::ContinuousEvaluationResult.create!(
            span_id: span.span_id,
            trace_id: span.trace_id,
            evaluation_policy_id: policy.id,
            queue_item_id: queue_item.id,
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
            score: result.average_score,
            scores: extract_field_scores(result),
            metrics: extract_metrics(span),
            reasoning: extract_reasoning(result),
            details: result.to_h,
            evaluation_duration_ms: duration_ms,
            evaluation_started_at: started_at,
            evaluation_completed_at: completed_at,
            metadata: {}
          )
        end

        ##
        # Extract field scores from EvaluationResult
        # @return [Hash] Field names to scores mapping
        def extract_field_scores(result)
          result.field_results.transform_values { |r| r[:score] }
        end

        ##
        # Extract combined reasoning from EvaluationResult
        # @return [String, nil] Combined reasoning text or nil
        def extract_reasoning(result)
          reasonings = result.field_results.filter_map { |_field, r| r[:reasoning] }
          reasonings.empty? ? nil : reasonings.join("\n\n")
        end

        def determine_status(result)
          # EvaluationResult uses label-based quality: "good", "average", "bad"
          result.overall_quality
        end

        def extract_agent_name(span)
          attrs = span.span_attributes || {}
          attrs['agent.name'] || attrs['agent_name'] || 'unknown'
        end

        def extract_agent_version(span)
          attrs = span.span_attributes || {}
          attrs['agent_version']
        end

        def extract_model(span)
          attrs = span.span_attributes || {}
          attrs['agent.model'] || attrs['model']
        end

        def extract_provider(span)
          attrs = span.span_attributes || {}
          attrs['provider']
        end

        def extract_messages(span, role)
          attrs = span.span_attributes || {}
          messages_json = attrs['agent.conversation_messages']
          return [] unless messages_json

          begin
            messages = messages_json.is_a?(String) ? JSON.parse(messages_json) : messages_json
            messages.select { |m| m['role'] == role }.map { |m| m['content'] }
          rescue JSON::ParserError
            []
          end
        end

        def extract_output_text(span)
          attrs = span.span_attributes || {}
          attrs['agent.final_agent_response'] || ''
        end

        ##
        # Parse agent's structured JSON response to make fields available for evaluation
        # @param span [SpanRecord] The span containing the response
        # @return [Hash, nil] Parsed response hash with symbolized keys, or nil if parsing fails
        def parse_agent_response(span)
          attrs = span.span_attributes || {}
          response_text = attrs['agent.final_agent_response']
          return nil if response_text.blank?

          begin
            parsed = response_text.is_a?(String) ? JSON.parse(response_text) : response_text
            # Recursively symbolize keys for consistent access
            deep_symbolize_keys(parsed)
          rescue JSON::ParserError
            # Response is not JSON, return nil
            nil
          end
        end

        ##
        # Recursively symbolize keys in a hash
        # @param obj [Object] Hash, Array, or primitive value
        # @return [Object] Object with symbolized keys (for hashes)
        def deep_symbolize_keys(obj)
          case obj
          when Hash
            obj.each_with_object({}) do |(key, value), result|
              result[key.to_sym] = deep_symbolize_keys(value)
            end
          when Array
            obj.map { |item| deep_symbolize_keys(item) }
          else
            obj
          end
        end

        def extract_tool_calls(span)
          attrs = span.span_attributes || {}
          tool_executions = attrs['agent.tool_executions']
          return [] unless tool_executions

          begin
            tool_executions.is_a?(String) ? JSON.parse(tool_executions) : tool_executions
          rescue JSON::ParserError
            []
          end
        end

        def extract_metadata(span)
          # Return span_attributes as metadata
          span.span_attributes || {}
        end

        def extract_metrics(span)
          {
            latency_ms: calculate_latency(span),
            tokens: extract_token_usage(span),
            cost: calculate_cost(span)
          }
        end

        def calculate_latency(span)
          # SpanRecord uses start_time and end_time, not started_at and ended_at
          return span.duration_ms if span.duration_ms
          return nil unless span.start_time && span.end_time
          ((span.end_time - span.start_time) * 1000).round
        end

        def extract_token_usage(span)
          attrs = span.span_attributes || {}
          {
            input_tokens: attrs['input_tokens']&.to_i || 0,
            output_tokens: attrs['output_tokens']&.to_i || 0,
            total_tokens: attrs['total_tokens']&.to_i || 0
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
