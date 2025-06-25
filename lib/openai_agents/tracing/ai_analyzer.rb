# frozen_string_literal: true

module OpenAIAgents
  module Tracing
    # rubocop:disable Metrics/ClassLength
    class AIAnalyzer
      # AI-powered analysis for root cause analysis and optimization suggestions

      def initialize(config = {})
        @config = {
          # AI Analysis settings
          enable_ai_analysis: config[:enable_ai_analysis] != false,
          analysis_model: config[:analysis_model] || "gpt-4o",
          analysis_temperature: config[:analysis_temperature] || 0.3,

          # Analysis depth
          max_traces_to_analyze: config[:max_traces_to_analyze] || 50,
          max_spans_per_trace: config[:max_spans_per_trace] || 100,

          # Pattern recognition
          enable_pattern_recognition: config[:enable_pattern_recognition] != false,
          pattern_confidence_threshold: config[:pattern_confidence_threshold] || 0.7,

          # Caching
          cache_analysis_results: config[:cache_analysis_results] != false,
          cache_ttl: config[:cache_ttl] || 1.hour,

          # Rate limiting
          analysis_rate_limit: config[:analysis_rate_limit] || 10, # per minute

          # OpenAI API configuration
          openai_api_key: config[:openai_api_key] || ENV.fetch("OPENAI_API_KEY", nil)
        }

        @analysis_cache = {}
        @pattern_database = PatternDatabase.new
        @rate_limiter = RateLimiter.new(@config[:analysis_rate_limit])

        setup_ai_client if @config[:enable_ai_analysis]
      end

      def analyze_root_cause(trace_id, error_context = {})
        return { error: "AI analysis disabled" } unless @config[:enable_ai_analysis]
        return { error: "Rate limit exceeded" } unless @rate_limiter.allow?

        # Check cache first
        cache_key = "root_cause:#{trace_id}:#{error_context.hash}"
        if @config[:cache_analysis_results] && @analysis_cache[cache_key]
          cached_result = @analysis_cache[cache_key]
          return cached_result if cached_result[:cached_at] > Time.current - @config[:cache_ttl]
        end

        trace = find_trace(trace_id)
        return { error: "Trace not found" } unless trace

        # Gather comprehensive trace data
        trace_data = extract_trace_data(trace)

        # Identify error patterns
        error_patterns = identify_error_patterns(trace_data)

        # Perform AI analysis
        ai_analysis = perform_ai_root_cause_analysis(trace_data, error_patterns, error_context)

        # Combine with pattern-based analysis
        pattern_analysis = analyze_known_patterns(trace_data, error_patterns)

        result = {
          trace_id: trace_id,
          analysis_timestamp: Time.current,
          root_cause_analysis: ai_analysis,
          pattern_analysis: pattern_analysis,
          error_patterns: error_patterns,
          recommendations: generate_root_cause_recommendations(ai_analysis, pattern_analysis),
          confidence_score: calculate_confidence_score(ai_analysis, pattern_analysis),
          similar_incidents: find_similar_incidents(trace_data, error_patterns)
        }

        # Cache the result
        @analysis_cache[cache_key] = result.merge(cached_at: Time.current) if @config[:cache_analysis_results]

        result
      end

      def generate_optimization_suggestions(timeframe: 24.hours, tenant_id: nil, workflow_name: nil)
        return { error: "AI analysis disabled" } unless @config[:enable_ai_analysis]
        return { error: "Rate limit exceeded" } unless @rate_limiter.allow?

        # Gather performance data
        performance_data = gather_performance_data(timeframe, tenant_id, workflow_name)

        # Identify optimization opportunities
        optimization_opportunities = identify_optimization_opportunities(performance_data)

        # Perform AI analysis for suggestions
        ai_suggestions = perform_ai_optimization_analysis(performance_data, optimization_opportunities)

        # Generate actionable recommendations
        recommendations = generate_optimization_recommendations(ai_suggestions, performance_data)

        {
          analysis_timestamp: Time.current,
          timeframe: timeframe,
          filters: { tenant_id: tenant_id, workflow_name: workflow_name },
          performance_summary: performance_data[:summary],
          optimization_opportunities: optimization_opportunities,
          ai_suggestions: ai_suggestions,
          recommendations: recommendations,
          estimated_impact: calculate_optimization_impact(recommendations, performance_data)
        }
      end

      def analyze_performance_anomalies(anomalies)
        return { error: "AI analysis disabled" } unless @config[:enable_ai_analysis]
        return { error: "Rate limit exceeded" } unless @rate_limiter.allow?

        # Group anomalies by type and severity
        grouped_anomalies = group_anomalies(anomalies)

        # Perform AI analysis on anomaly patterns
        ai_analysis = perform_ai_anomaly_analysis(grouped_anomalies)

        # Generate insights and recommendations
        insights = generate_anomaly_insights(ai_analysis, grouped_anomalies)

        {
          analysis_timestamp: Time.current,
          anomaly_count: anomalies.size,
          anomaly_groups: grouped_anomalies,
          ai_analysis: ai_analysis,
          insights: insights,
          root_causes: extract_potential_root_causes(ai_analysis),
          preventive_measures: suggest_preventive_measures(ai_analysis, insights)
        }
      end

      def analyze_cost_patterns(cost_data)
        return { error: "AI analysis disabled" } unless @config[:enable_ai_analysis]
        return { error: "Rate limit exceeded" } unless @rate_limiter.allow?

        # Extract cost patterns and trends
        cost_patterns = extract_cost_patterns(cost_data)

        # Perform AI analysis
        ai_analysis = perform_ai_cost_analysis(cost_patterns, cost_data)

        # Generate cost optimization strategies
        strategies = generate_cost_optimization_strategies(ai_analysis, cost_patterns)

        {
          analysis_timestamp: Time.current,
          cost_summary: cost_data[:totals],
          patterns_identified: cost_patterns,
          ai_analysis: ai_analysis,
          optimization_strategies: strategies,
          potential_savings: calculate_potential_savings(strategies, cost_data)
        }
      end

      def predict_system_behavior(current_metrics, prediction_horizon = 24.hours)
        return { error: "AI analysis disabled" } unless @config[:enable_ai_analysis]
        return { error: "Rate limit exceeded" } unless @rate_limiter.allow?

        # Prepare metrics data for prediction
        metrics_data = prepare_metrics_for_prediction(current_metrics)

        # Generate AI-powered predictions
        predictions = perform_ai_prediction_analysis(metrics_data, prediction_horizon)

        # Calculate confidence intervals
        confidence_intervals = calculate_prediction_confidence(predictions, metrics_data)

        {
          prediction_timestamp: Time.current,
          prediction_horizon: prediction_horizon,
          current_metrics: current_metrics,
          predictions: predictions,
          confidence_intervals: confidence_intervals,
          risk_factors: identify_risk_factors(predictions),
          recommended_actions: recommend_proactive_actions(predictions)
        }
      end

      private

      def setup_ai_client
        return unless @config[:openai_api_key]

        @ai_client = OpenAI::Client.new(
          access_token: @config[:openai_api_key],
          request_timeout: 30
        )
      end

      def find_trace(trace_id)
        return unless defined?(OpenAIAgents::Tracing::Trace)

        OpenAIAgents::Tracing::Trace.find_by(trace_id: trace_id)
      end

      def extract_trace_data(trace)
        spans = trace.spans.includes(:trace).order(:start_time)

        {
          trace_id: trace.trace_id,
          workflow_name: trace.workflow_name,
          status: trace.status,
          duration_ms: trace.duration_ms,
          started_at: trace.started_at,
          ended_at: trace.ended_at,
          metadata: trace.metadata,
          spans: spans.map { |span| extract_span_data(span) },
          error_spans: spans.select { |s| s.status == "error" }.map { |span| extract_error_data(span) },
          performance_metrics: calculate_trace_performance_metrics(spans)
        }
      end

      def extract_span_data(span)
        {
          span_id: span.span_id,
          name: span.name,
          kind: span.kind,
          status: span.status,
          duration_ms: span.duration_ms,
          start_time: span.start_time,
          end_time: span.end_time,
          parent_span_id: span.parent_span_id,
          attributes: sanitize_attributes(span.attributes),
          events: span.events
        }
      end

      def extract_error_data(span)
        error_data = extract_span_data(span)
        error_data.merge!(
          error_type: span.attributes&.dig("error.type"),
          error_message: span.attributes&.dig("error.message"),
          error_stack: span.attributes&.dig("error.stack_trace"),
          error_code: span.attributes&.dig("error.code")
        )
        error_data
      end

      def sanitize_attributes(attributes)
        return {} unless attributes.is_a?(Hash)

        # Remove sensitive data and limit size
        sanitized = {}
        attributes.each do |key, value|
          next if sanitized.size >= 50 # Limit number of attributes
          next if sensitive_attribute?(key)

          sanitized[key] = truncate_value(value)
        end
        sanitized
      end

      def sensitive_attribute?(key)
        key_str = key.to_s.downcase
        %w[password secret token key auth].any? { |sensitive| key_str.include?(sensitive) }
      end

      def truncate_value(value)
        case value
        when String
          value.length > 500 ? "#{value[0..497]}..." : value
        when Hash
          value.keys.length > 10 ? "Hash(#{value.keys.length} keys)" : value
        when Array
          value.length > 20 ? "Array(#{value.length} items)" : value
        else
          value
        end
      end

      def identify_error_patterns(trace_data)
        patterns = []

        error_spans = trace_data[:error_spans]
        return patterns if error_spans.empty?

        # Common error patterns
        patterns << detect_timeout_pattern(error_spans)
        patterns << detect_rate_limit_pattern(error_spans)
        patterns << detect_authentication_pattern(error_spans)
        patterns << detect_resource_exhaustion_pattern(error_spans)
        patterns << detect_dependency_failure_pattern(error_spans)

        patterns.compact
      end

      def detect_timeout_pattern(error_spans)
        timeout_indicators = %w[timeout TimeoutError connection_timeout read_timeout]

        timeout_spans = error_spans.select do |span|
          error_message = span[:error_message].to_s.downcase
          timeout_indicators.any? { |indicator| error_message.include?(indicator) }
        end

        return nil if timeout_spans.empty?

        {
          type: "timeout",
          affected_spans: timeout_spans.size,
          confidence: timeout_spans.size.to_f / error_spans.size,
          details: {
            average_duration: timeout_spans.map { |s| s[:duration_ms] }.compact.sum / timeout_spans.size,
            affected_operations: timeout_spans.map { |s| s[:name] }.uniq
          }
        }
      end

      def detect_rate_limit_pattern(error_spans)
        rate_limit_indicators = %w[rate_limit too_many_requests 429 quota_exceeded]

        rate_limit_spans = error_spans.select do |span|
          error_message = span[:error_message].to_s.downcase
          rate_limit_indicators.any? { |indicator| error_message.include?(indicator) }
        end

        return nil if rate_limit_spans.empty?

        {
          type: "rate_limit",
          affected_spans: rate_limit_spans.size,
          confidence: rate_limit_spans.size.to_f / error_spans.size,
          details: {
            services: rate_limit_spans.map { |s| s[:attributes]&.dig("service.name") }.compact.uniq,
            frequency: calculate_error_frequency(rate_limit_spans)
          }
        }
      end

      def detect_authentication_pattern(error_spans)
        auth_indicators = %w[unauthorized 401 403 authentication authorization invalid_token]

        auth_spans = error_spans.select do |span|
          error_message = span[:error_message].to_s.downcase
          auth_indicators.any? { |indicator| error_message.include?(indicator) }
        end

        return nil if auth_spans.empty?

        {
          type: "authentication",
          affected_spans: auth_spans.size,
          confidence: auth_spans.size.to_f / error_spans.size,
          details: {
            operations: auth_spans.map { |s| s[:name] }.uniq,
            error_codes: auth_spans.map { |s| s[:error_code] }.compact.uniq
          }
        }
      end

      def detect_resource_exhaustion_pattern(error_spans)
        resource_indicators = %w[memory cpu disk quota limit exceeded insufficient]

        resource_spans = error_spans.select do |span|
          error_message = span[:error_message].to_s.downcase
          resource_indicators.any? { |indicator| error_message.include?(indicator) }
        end

        return nil if resource_spans.empty?

        {
          type: "resource_exhaustion",
          affected_spans: resource_spans.size,
          confidence: resource_spans.size.to_f / error_spans.size,
          details: {
            resource_types: extract_resource_types(resource_spans),
            severity: resource_spans.size > error_spans.size * 0.5 ? "high" : "medium"
          }
        }
      end

      def detect_dependency_failure_pattern(error_spans)
        dependency_indicators = %w[connection_failed service_unavailable dns network]

        dependency_spans = error_spans.select do |span|
          error_message = span[:error_message].to_s.downcase
          dependency_indicators.any? { |indicator| error_message.include?(indicator) } ||
            span[:kind] == "external"
        end

        return nil if dependency_spans.empty?

        {
          type: "dependency_failure",
          affected_spans: dependency_spans.size,
          confidence: dependency_spans.size.to_f / error_spans.size,
          details: {
            failed_services: dependency_spans.map { |s| s[:attributes]&.dig("external_service.name") }.compact.uniq,
            cascade_effect: dependency_spans.any? { |s| s[:parent_span_id] }
          }
        }
      end

      def perform_ai_root_cause_analysis(trace_data, error_patterns, error_context)
        return { error: "AI client not configured" } unless @ai_client

        prompt = build_root_cause_analysis_prompt(trace_data, error_patterns, error_context)

        begin
          response = @ai_client.chat(
            parameters: {
              model: @config[:analysis_model],
              messages: [{ role: "user", content: prompt }],
              temperature: @config[:analysis_temperature],
              max_tokens: 1500
            }
          )

          parse_ai_response(response.dig("choices", 0, "message", "content"))
        rescue StandardError => e
          { error: "AI analysis failed: #{e.message}" }
        end
      end

      def build_root_cause_analysis_prompt(trace_data, error_patterns, error_context)
        <<~PROMPT
          You are an expert system reliability engineer analyzing a failed trace from an AI agent system.#{" "}

          TRACE INFORMATION:
          - Trace ID: #{trace_data[:trace_id]}
          - Workflow: #{trace_data[:workflow_name]}
          - Status: #{trace_data[:status]}
          - Duration: #{trace_data[:duration_ms]}ms
          - Error Spans: #{trace_data[:error_spans].size}

          ERROR PATTERNS DETECTED:
          #{error_patterns.map { |p| "- #{p[:type]}: #{p[:confidence].round(2)} confidence" }.join("\n")}

          ERROR SPANS DETAILS:
          #{trace_data[:error_spans].map do |span|
            "- #{span[:name]} (#{span[:kind]}): #{span[:error_message]}"
          end.join("\n")}

          ADDITIONAL CONTEXT:
          #{error_context.map { |k, v| "- #{k}: #{v}" }.join("\n")}

          Please provide a structured root cause analysis including:
          1. Primary root cause (most likely cause)
          2. Contributing factors (secondary causes)
          3. Impact assessment (severity and scope)
          4. Immediate remediation steps
          5. Long-term prevention measures

          Format your response as JSON with the following structure:
          {
            "primary_root_cause": "description",
            "contributing_factors": ["factor1", "factor2"],
            "impact_assessment": {
              "severity": "low|medium|high|critical",
              "scope": "isolated|workflow|system|global",
              "affected_users": "estimate"
            },
            "immediate_remediation": ["step1", "step2"],
            "prevention_measures": ["measure1", "measure2"],
            "confidence": 0.85
          }
        PROMPT
      end

      def parse_ai_response(response_text)
        return { error: "Empty response" } if response_text.blank?

        # Try to extract JSON from the response
        json_match = response_text.match(/\{.*\}/m)
        return { error: "No JSON found in response" } unless json_match

        JSON.parse(json_match[0])
      rescue JSON::ParserError => e
        { error: "Failed to parse AI response: #{e.message}", raw_response: response_text }
      end

      def analyze_known_patterns(trace_data, error_patterns)
        # Pattern-based analysis using historical data
        known_patterns = @pattern_database.find_similar_patterns(error_patterns)

        {
          matched_patterns: known_patterns,
          pattern_confidence: calculate_pattern_confidence(known_patterns, error_patterns),
          historical_solutions: extract_historical_solutions(known_patterns),
          success_rate: calculate_historical_success_rate(known_patterns)
        }
      end

      def generate_root_cause_recommendations(ai_analysis, pattern_analysis)
        recommendations = []

        # AI-generated recommendations
        ai_analysis[:immediate_remediation]&.each do |action|
          recommendations << {
            type: "immediate",
            action: action,
            source: "ai_analysis",
            priority: "high"
          }
        end

        ai_analysis[:prevention_measures]&.each do |measure|
          recommendations << {
            type: "preventive",
            action: measure,
            source: "ai_analysis",
            priority: "medium"
          }
        end

        # Pattern-based recommendations
        pattern_analysis[:historical_solutions]&.each do |solution|
          recommendations << {
            type: "historical",
            action: solution[:description],
            source: "pattern_analysis",
            priority: solution[:success_rate] > 0.8 ? "high" : "medium",
            success_rate: solution[:success_rate]
          }
        end

        recommendations.sort_by { |r| [priority_order(r[:priority]), -r[:success_rate].to_f] }
      end

      def priority_order(priority)
        case priority
        when "critical" then 0
        when "high" then 1
        when "medium" then 2
        when "low" then 3
        else 4
        end
      end

      def calculate_confidence_score(ai_analysis, pattern_analysis)
        ai_confidence = ai_analysis[:confidence] || 0.5
        pattern_confidence = pattern_analysis[:pattern_confidence] || 0.5

        # Weighted average favoring AI analysis if it has high confidence
        if ai_confidence > 0.8
          ((ai_confidence * 0.7) + (pattern_confidence * 0.3)).round(3)
        else
          ((ai_confidence * 0.5) + (pattern_confidence * 0.5)).round(3)
        end
      end

      def find_similar_incidents(trace_data, error_patterns)
        # Find traces with similar error patterns
        # This would query the database for similar patterns
        []
      end

      def gather_performance_data(timeframe, tenant_id, workflow_name)
        # Gather comprehensive performance data for analysis
        # This would collect metrics, traces, and patterns
        {
          summary: {
            total_traces: 0,
            avg_duration: 0,
            error_rate: 0,
            p95_duration: 0
          },
          traces: [],
          patterns: [],
          bottlenecks: []
        }
      end

      def identify_optimization_opportunities(performance_data)
        opportunities = []

        # Identify common optimization opportunities
        opportunities << detect_slow_operations(performance_data)
        opportunities << detect_redundant_calls(performance_data)
        opportunities << detect_inefficient_patterns(performance_data)

        opportunities.compact
      end

      def detect_slow_operations(performance_data)
        # Implementation would analyze performance data for slow operations
        nil
      end

      def detect_redundant_calls(performance_data)
        # Implementation would identify redundant or duplicate operations
        nil
      end

      def detect_inefficient_patterns(performance_data)
        # Implementation would find inefficient workflow patterns
        nil
      end

      def perform_ai_optimization_analysis(performance_data, opportunities)
        # AI analysis for optimization suggestions
        { suggestions: [] }
      end

      def generate_optimization_recommendations(ai_suggestions, performance_data)
        []
      end

      def calculate_optimization_impact(recommendations, performance_data)
        {
          estimated_improvement: "25%",
          confidence: 0.7
        }
      end

      # Additional helper methods would be implemented here...

      def group_anomalies(anomalies)
        anomalies.group_by { |a| a[:type] }
      end

      def perform_ai_anomaly_analysis(grouped_anomalies)
        { analysis: "Anomaly analysis not yet implemented" }
      end

      def generate_anomaly_insights(ai_analysis, grouped_anomalies)
        []
      end

      def extract_potential_root_causes(ai_analysis)
        []
      end

      def suggest_preventive_measures(ai_analysis, insights)
        []
      end

      def extract_cost_patterns(cost_data)
        []
      end

      def perform_ai_cost_analysis(cost_patterns, cost_data)
        { analysis: "Cost analysis not yet implemented" }
      end

      def generate_cost_optimization_strategies(ai_analysis, cost_patterns)
        []
      end

      def calculate_potential_savings(strategies, cost_data)
        0.0
      end

      def prepare_metrics_for_prediction(current_metrics)
        current_metrics
      end

      def perform_ai_prediction_analysis(metrics_data, prediction_horizon)
        { predictions: [] }
      end

      def calculate_prediction_confidence(predictions, metrics_data)
        {}
      end

      def identify_risk_factors(predictions)
        []
      end

      def recommend_proactive_actions(predictions)
        []
      end

      def calculate_trace_performance_metrics(spans)
        {
          total_spans: spans.count,
          avg_duration: spans.map(&:duration_ms).compact.sum / spans.count,
          max_duration: spans.map(&:duration_ms).compact.max
        }
      end

      def calculate_error_frequency(spans)
        # Calculate frequency of errors
        spans.size
      end

      def extract_resource_types(spans)
        # Extract types of resources from error messages
        []
      end

      # Supporting classes
      class PatternDatabase
        def initialize
          @patterns = []
        end

        def find_similar_patterns(error_patterns)
          []
        end
      end

      class RateLimiter
        def initialize(limit_per_minute)
          @limit = limit_per_minute
          @requests = []
        end

        def allow?
          now = Time.current
          @requests.reject! { |time| time < now - 1.minute }

          if @requests.size < @limit
            @requests << now
            true
          else
            false
          end
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
