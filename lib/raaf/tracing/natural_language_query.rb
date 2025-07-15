# frozen_string_literal: true

require_relative "../logging"

module RubyAIAgentsFactory
  module Tracing
    # rubocop:disable Metrics/ClassLength
    class NaturalLanguageQuery
      include RubyAIAgentsFactory::Logger
      # Natural language interface for querying tracing data
      # Supports queries like "show me slow traces from yesterday" or "find errors in customer support workflow"

      QUERY_PATTERNS = {
        # Time-based patterns
        time_patterns: [
          { pattern: /\b(?:yesterday|today|last (?:hour|day|week|month))\b/i, type: :time_reference },
          { pattern: /\b(?:in the (?:last|past)) (\d+) (hours?|days?|weeks?|months?)\b/i, type: :time_duration },
          { pattern: /\bbetween (.+?) and (.+?)\b/i, type: :time_range },
          { pattern: /\bsince (.+?)\b/i, type: :time_since },
          { pattern: /\bon (\d{4}-\d{2}-\d{2})\b/i, type: :specific_date }
        ],

        # Performance patterns
        performance_patterns: [
          {
            pattern: /\b(?:slow|slowest|taking (?:longer|more) than|over|above) (\d+)\s*(ms|sec|seconds?|min|minutes?)\b/i, # rubocop:disable Layout/LineLength
            type: :duration_threshold
          },
          { pattern: /\b(?:fast|fastest|quick|under|below) (\d+)\s*(ms|sec|seconds?|min|minutes?)\b/i,
            type: :fast_threshold },
          { pattern: /\b(?:slow|slowest)\b/i, type: :slow_general },
          { pattern: /\b(?:fast|fastest|quick)\b/i, type: :fast_general },
          { pattern: /\bp95|p99|percentile/i, type: :percentile }
        ],

        # Error patterns
        error_patterns: [
          { pattern: /\b(?:error|errors|failed|failure|failing)\b/i, type: :errors },
          { pattern: /\b(?:successful|success|completed|ok)\b/i, type: :success },
          { pattern: /\berror rate (?:above|over|greater than) (\d+)%?\b/i, type: :error_rate_threshold },
          { pattern: /\b(?:timeout|timeouts)\b/i, type: :timeout_errors },
          { pattern: /\b(?:429|rate limit|quota)\b/i, type: :rate_limit_errors }
        ],

        # Workflow patterns
        workflow_patterns: [
          { pattern: /\bworkflow (.+?)\b/i, type: :workflow_name },
          { pattern: /\bin (?:the )?(.+?) workflow\b/i, type: :workflow_context },
          { pattern: /\b(?:agent|model|llm|tool) (.+?)\b/i, type: :component_type },
          { pattern: /\busing (.+?) model\b/i, type: :model_name }
        ],

        # Quantity patterns
        quantity_patterns: [
          { pattern: /\btop (\d+)\b/i, type: :top_n },
          { pattern: /\b(?:first|last) (\d+)\b/i, type: :limit },
          { pattern: /\bmore than (\d+)\b/i, type: :greater_than },
          { pattern: /\bless than (\d+)\b/i, type: :less_than }
        ],

        # Tenant patterns
        tenant_patterns: [
          { pattern: /\btenant (.+?)\b/i, type: :tenant_id },
          { pattern: /\bproject (.+?)\b/i, type: :project_id },
          { pattern: /\buser (.+?)\b/i, type: :user_id },
          { pattern: /\bfor (?:tenant|project|user) (.+?)\b/i, type: :entity_filter }
        ],

        # Cost patterns
        cost_patterns: [
          { pattern: /\bcost(?:s|ing)? (?:above|over|greater than) \$?(\d+(?:\.\d+)?)\b/i, type: :cost_threshold },
          { pattern: /\bexpensive|costly|high cost\b/i, type: :high_cost },
          { pattern: /\bcheap|low cost|inexpensive\b/i, type: :low_cost },
          { pattern: /\btotal cost|cost breakdown\b/i, type: :cost_analysis }
        ],

        # Action patterns
        action_patterns: [
          { pattern: /\b(?:show|display|list|find|get|retrieve)\b/i, type: :show },
          { pattern: /\b(?:count|how many)\b/i, type: :count },
          { pattern: /\b(?:analyze|analysis|breakdown)\b/i, type: :analyze },
          { pattern: /\b(?:compare|comparison)\b/i, type: :compare },
          { pattern: /\b(?:summarize|summary)\b/i, type: :summarize }
        ]
      }.freeze

      def initialize(config = {})
        @config = {
          # NLP settings
          enable_ai_parsing: config[:enable_ai_parsing] != false,
          ai_model: config[:ai_model] || "gpt-4o",

          # Query limits
          max_results: config[:max_results] || 100,
          default_timeframe: config[:default_timeframe] || 24.hours,

          # Caching
          cache_parsed_queries: config[:cache_parsed_queries] != false,
          cache_ttl: config[:cache_ttl] || 1.hour,

          # OpenAI configuration
          openai_api_key: config[:openai_api_key] || ENV.fetch("OPENAI_API_KEY", nil)
        }

        @query_cache = {}
        @ai_client = setup_ai_client if @config[:enable_ai_parsing]
      end

      def query(natural_language_query)
        # Normalize the query
        normalized_query = normalize_query(natural_language_query)

        # Check cache first
        cache_key = Digest::SHA256.hexdigest(normalized_query)
        if @config[:cache_parsed_queries] && @query_cache[cache_key]
          cached_result = @query_cache[cache_key]
          if cached_result[:cached_at] > Time.current - @config[:cache_ttl]
            return execute_cached_query(cached_result[:parsed_query], natural_language_query)
          end
        end

        # Parse the natural language query
        parsed_query = parse_natural_language(normalized_query)

        # Cache the parsed query
        if @config[:cache_parsed_queries]
          @query_cache[cache_key] = {
            parsed_query: parsed_query,
            cached_at: Time.current
          }
        end

        # Execute the query
        execute_query(parsed_query, natural_language_query)
      end

      def suggest_queries
        [
          "Show me slow traces from yesterday",
          "Find errors in the customer support workflow",
          "What are the top 10 most expensive traces this week?",
          "Show me timeouts in the last 2 hours",
          "Count successful traces for tenant ABC today",
          "Find traces using GPT-4 model with high costs",
          "Show me the slowest LLM calls in the past day",
          "Analyze error patterns in the last week",
          "Find traces with duration over 30 seconds",
          "Show me all failed handoffs yesterday",
          "What workflows have error rates above 10%?",
          "Compare performance between today and yesterday",
          "Show cost breakdown by model for this month",
          "Find traces with more than 50 spans",
          "Show me rate limit errors in the last hour"
        ]
      end

      def explain_query(natural_language_query)
        parsed_query = parse_natural_language(normalize_query(natural_language_query))

        {
          original_query: natural_language_query,
          parsed_components: parsed_query,
          sql_equivalent: generate_sql_explanation(parsed_query),
          filters_applied: extract_filters_explanation(parsed_query),
          estimated_results: estimate_result_count(parsed_query)
        }
      end

      private

      def normalize_query(query)
        # Basic normalization
        query.strip
             .gsub(/\s+/, " ")
             .gsub(/[^\w\s\-.,!?:;]/, "")
      end

      def parse_natural_language(query)
        parsed = {
          original_query: query,
          action: extract_action(query),
          entity: extract_entity(query),
          filters: extract_filters(query),
          timeframe: extract_timeframe(query),
          sorting: extract_sorting(query),
          aggregation: extract_aggregation(query),
          limit: extract_limit(query)
        }

        # Use AI for complex parsing if enabled
        if @config[:enable_ai_parsing] && requires_ai_parsing?(parsed)
          ai_parsed = parse_with_ai(query, parsed)
          parsed = merge_ai_parsing(parsed, ai_parsed)
        end

        # Apply defaults
        apply_defaults(parsed)
      end

      def extract_action(query)
        QUERY_PATTERNS[:action_patterns].each do |pattern_info|
          return pattern_info[:type] if query.match?(pattern_info[:pattern])
        end
        :show # default action
      end

      def extract_entity(query)
        case query
        when /\btraces?\b/i then :traces
        when /\bspans?\b/i then :spans
        when /\berrors?\b/i then :errors
        when /\bcosts?\b/i then :costs
        when /\bworkflows?\b/i then :workflows
        when /\bmodels?\b/i then :models
        else :traces # default entity
        end
      end

      def extract_filters(query)
        filters = {}

        # Extract time-based filters
        time_filter = extract_time_filter(query)
        filters.merge!(time_filter) if time_filter.any?

        # Extract performance filters
        performance_filter = extract_performance_filter(query)
        filters.merge!(performance_filter) if performance_filter.any?

        # Extract error filters
        error_filter = extract_error_filter(query)
        filters.merge!(error_filter) if error_filter.any?

        # Extract workflow filters
        workflow_filter = extract_workflow_filter(query)
        filters.merge!(workflow_filter) if workflow_filter.any?

        # Extract tenant filters
        tenant_filter = extract_tenant_filter(query)
        filters.merge!(tenant_filter) if tenant_filter.any?

        # Extract cost filters
        cost_filter = extract_cost_filter(query)
        filters.merge!(cost_filter) if cost_filter.any?

        filters
      end

      def extract_time_filter(query)
        filters = {}

        QUERY_PATTERNS[:time_patterns].each do |pattern_info|
          match = query.match(pattern_info[:pattern])
          next unless match

          case pattern_info[:type]
          when :time_reference
            filters[:timeframe] = parse_time_reference(match[0])
          when :time_duration
            amount = match[1].to_i
            unit = match[2]
            filters[:timeframe] = parse_duration(amount, unit)
          when :time_range
            filters[:start_time] = parse_time_string(match[1])
            filters[:end_time] = parse_time_string(match[2])
          when :time_since
            filters[:start_time] = parse_time_string(match[1])
          when :specific_date
            date = Date.parse(match[1])
            filters[:start_time] = date.beginning_of_day
            filters[:end_time] = date.end_of_day
          end
          break
        end

        filters
      end

      def extract_performance_filter(query)
        filters = {}

        QUERY_PATTERNS[:performance_patterns].each do |pattern_info|
          match = query.match(pattern_info[:pattern])
          next unless match

          case pattern_info[:type]
          when :duration_threshold
            duration_ms = parse_duration_to_ms(match[1], match[2])
            filters[:min_duration_ms] = duration_ms
          when :fast_threshold
            duration_ms = parse_duration_to_ms(match[1], match[2])
            filters[:max_duration_ms] = duration_ms
          when :slow_general
            filters[:performance_category] = :slow
          when :fast_general
            filters[:performance_category] = :fast
          when :percentile
            filters[:include_percentiles] = true
          end
          break
        end

        filters
      end

      def extract_error_filter(query)
        filters = {}

        QUERY_PATTERNS[:error_patterns].each do |pattern_info|
          match = query.match(pattern_info[:pattern])
          next unless match

          case pattern_info[:type]
          when :errors
            filters[:status] = "error"
          when :success
            filters[:status] = "ok"
          when :error_rate_threshold
            filters[:min_error_rate] = match[1].to_f
          when :timeout_errors
            filters[:error_type] = "timeout"
          when :rate_limit_errors
            filters[:error_type] = "rate_limit"
          end
          break
        end

        filters
      end

      def extract_workflow_filter(query)
        filters = {}

        QUERY_PATTERNS[:workflow_patterns].each do |pattern_info|
          match = query.match(pattern_info[:pattern])
          next unless match

          case pattern_info[:type]
          when :workflow_name, :workflow_context
            filters[:workflow_name] = match[1].strip
          when :component_type
            filters[:span_kind] = normalize_component_type(match[1])
          when :model_name
            filters[:model] = match[1].strip
          end
        end

        filters
      end

      def extract_tenant_filter(query)
        filters = {}

        QUERY_PATTERNS[:tenant_patterns].each do |pattern_info|
          match = query.match(pattern_info[:pattern])
          next unless match

          case pattern_info[:type]
          when :tenant_id
            filters[:tenant_id] = match[1].strip
          when :project_id
            filters[:project_id] = match[1].strip
          when :user_id
            filters[:user_id] = match[1].strip
          when :entity_filter
            # This would need more sophisticated parsing
            filters[:entity_context] = match[1].strip
          end
        end

        filters
      end

      def extract_cost_filter(query)
        filters = {}

        QUERY_PATTERNS[:cost_patterns].each do |pattern_info|
          match = query.match(pattern_info[:pattern])
          next unless match

          case pattern_info[:type]
          when :cost_threshold
            filters[:min_cost] = match[1].to_f
          when :high_cost
            filters[:cost_category] = :high
          when :low_cost
            filters[:cost_category] = :low
          when :cost_analysis
            filters[:include_cost_breakdown] = true
          end
        end

        filters
      end

      def extract_timeframe(query)
        # Extract timeframe or return default
        time_filter = extract_time_filter(query)
        time_filter[:timeframe] || @config[:default_timeframe]
      end

      def extract_sorting(query)
        case query
        when /\bslowest\b/i then { field: :duration_ms, direction: :desc }
        when /\bfastest\b/i then { field: :duration_ms, direction: :asc }
        when /\bmost expensive\b/i then { field: :cost, direction: :desc }
        when /\blatest\b/i then { field: :started_at, direction: :desc }
        when /\boldest\b/i then { field: :started_at, direction: :asc }
        else { field: :started_at, direction: :desc } # default
        end
      end

      def extract_aggregation(query)
        case query
        when /\bcount\b/i then :count
        when /\bsum|total\b/i then :sum
        when /\baverage|avg\b/i then :average
        when /\bmax|maximum\b/i then :max
        when /\bmin|minimum\b/i then :min
        when /\bbreakdown\b/i then :group_by
        end
      end

      def extract_limit(query)
        QUERY_PATTERNS[:quantity_patterns].each do |pattern_info|
          match = query.match(pattern_info[:pattern])
          next unless match

          case pattern_info[:type]
          when :top_n, :limit
            return match[1].to_i
          end
        end

        @config[:max_results] # default limit
      end

      def requires_ai_parsing?(parsed)
        # Check if the query is complex enough to require AI parsing
        complex_patterns = [
          /\bcompare\b/i,
          /\bbetween .+ and .+\b/i,
          /\bif .+ then .+\b/i,
          /\bwhen .+ was .+\b/i
        ]

        complex_patterns.any? { |pattern| parsed[:original_query].match?(pattern) }
      end

      def parse_with_ai(query, initial_parsed)
        return {} unless @ai_client

        prompt = build_query_parsing_prompt(query, initial_parsed)

        begin
          response = @ai_client.chat(
            parameters: {
              model: @config[:ai_model],
              messages: [{ role: "user", content: prompt }],
              temperature: 0.1,
              max_tokens: 800
            }
          )

          ai_response = response.dig("choices", 0, "message", "content")
          parse_ai_query_response(ai_response)
        rescue StandardError => e
          log_error("AI query parsing failed", error: e.message, error_class: e.class.name)
          {}
        end
      end

      def build_query_parsing_prompt(query, initial_parsed)
        <<~PROMPT
          You are a query parser for a distributed tracing system. Parse this natural language query into structured filters.

          QUERY: "#{query}"

          INITIAL PARSING: #{initial_parsed.to_json}

          Please enhance or correct the parsing and return a JSON object with these possible fields:
          - timeframe: duration in hours/days (e.g., 24, 168 for week)
          - start_time: ISO timestamp
          - end_time: ISO timestamp
          - workflow_name: exact workflow name
          - status: "ok", "error", "running"
          - min_duration_ms: minimum duration threshold
          - max_duration_ms: maximum duration threshold
          - span_kind: "agent", "llm", "tool", "function"
          - model: AI model name
          - tenant_id: tenant identifier
          - error_type: specific error category
          - limit: number of results
          - sort_by: field to sort by
          - sort_direction: "asc" or "desc"

          Return only valid JSON. If uncertain about a value, omit that field.
        PROMPT
      end

      def parse_ai_query_response(response)
        return {} if response.blank?

        # Extract JSON from response
        json_match = response.match(/\{.*\}/m)
        return {} unless json_match

        JSON.parse(json_match[0])
      rescue JSON::ParserError
        {}
      end

      def merge_ai_parsing(initial_parsed, ai_parsed)
        # Merge AI parsing results with initial parsing, preferring AI results
        initial_parsed[:filters].merge!(ai_parsed)
        initial_parsed
      end

      def apply_defaults(parsed)
        parsed[:timeframe] ||= @config[:default_timeframe]
        parsed[:limit] ||= @config[:max_results]
        parsed[:sorting] ||= { field: :started_at, direction: :desc }
        parsed
      end

      def execute_query(parsed_query, original_query)
        start_time = Time.current

        begin
          # Build the database query based on parsed parameters
          query_builder = QueryBuilder.new(parsed_query)
          results = query_builder.execute

          # Format results based on requested action and entity
          formatted_results = format_results(results, parsed_query)

          {
            query: original_query,
            parsed_query: parsed_query,
            results: formatted_results,
            metadata: {
              execution_time_ms: ((Time.current - start_time) * 1000).round(2),
              result_count: results.size,
              query_type: determine_query_type(parsed_query)
            }
          }
        rescue StandardError => e
          {
            query: original_query,
            error: e.message,
            suggestions: generate_error_suggestions(e, parsed_query)
          }
        end
      end

      def execute_cached_query(parsed_query, original_query)
        # Execute a cached query with fresh data
        execute_query(parsed_query, original_query)
      end

      def format_results(results, parsed_query)
        case parsed_query[:entity]
        when :traces
          format_trace_results(results, parsed_query)
        when :spans
          format_span_results(results, parsed_query)
        when :errors
          format_error_results(results, parsed_query)
        when :costs
          format_cost_results(results, parsed_query)
        else
          results
        end
      end

      def format_trace_results(traces, parsed_query)
        formatted = traces.map do |trace|
          {
            trace_id: trace.trace_id,
            workflow_name: trace.workflow_name,
            status: trace.status,
            duration_ms: trace.duration_ms,
            started_at: trace.started_at,
            span_count: trace.spans.count,
            error_count: trace.spans.where(status: "error").count
          }
        end

        # Add aggregations if requested
        formatted = apply_aggregation(formatted, parsed_query[:aggregation]) if parsed_query[:aggregation]

        formatted
      end

      def format_span_results(spans, parsed_query)
        spans.map do |span|
          {
            span_id: span.span_id,
            trace_id: span.trace_id,
            name: span.name,
            kind: span.kind,
            status: span.status,
            duration_ms: span.duration_ms,
            start_time: span.start_time
          }
        end
      end

      def format_error_results(spans, parsed_query)
        spans.where(status: "error").map do |span|
          {
            span_id: span.span_id,
            trace_id: span.trace_id,
            name: span.name,
            error_type: span.attributes&.dig("error.type"),
            error_message: span.attributes&.dig("error.message"),
            occurred_at: span.start_time
          }
        end
      end

      def format_cost_results(traces, parsed_query)
        # This would integrate with the cost manager
        traces.map do |trace|
          {
            trace_id: trace.trace_id,
            workflow_name: trace.workflow_name,
            estimated_cost: 0.0, # Would calculate actual cost
            token_usage: 0
          }
        end
      end

      def apply_aggregation(data, aggregation_type)
        case aggregation_type
        when :count
          { count: data.size }
        when :sum
          { sum: data.sum { |item| item[:duration_ms] || 0 } }
        when :average
          { average: data.sum { |item| item[:duration_ms] || 0 } / data.size }
        else
          data
        end
      end

      def determine_query_type(parsed_query)
        if parsed_query[:aggregation]
          :aggregation
        elsif parsed_query[:filters][:status] == "error"
          :error_analysis
        elsif parsed_query[:filters][:include_cost_breakdown]
          :cost_analysis
        else
          :search
        end
      end

      def generate_error_suggestions(error, parsed_query)
        suggestions = []

        case error.message
        when /no results/i
          suggestions << "Try expanding your time range"
          suggestions << "Check if the workflow name is correct"
        when /invalid/i
          suggestions << "Check your query syntax"
          suggestions << "Try one of the suggested queries"
        else
          suggestions << "Try a simpler query"
          suggestions << "Check the documentation for query examples"
        end

        suggestions
      end

      # Helper methods for parsing

      def parse_time_reference(reference)
        case reference.downcase
        when /yesterday/ then 1.day
        when /today/ then Time.current.beginning_of_day..Time.current
        when /last hour/ then 1.hour
        when /last day/ then 1.day
        when /last week/ then 1.week
        when /last month/ then 1.month
        else 24.hours
        end
      end

      def parse_duration(amount, unit)
        case unit.downcase
        when /hour/ then amount.hours
        when /day/ then amount.days
        when /week/ then amount.weeks
        when /month/ then amount.months
        else amount.hours
        end
      end

      def parse_time_string(time_str)
        return nil if time_str.blank?

        # Handle relative times
        case time_str.downcase.strip
        when "now", "today"
          Time.current
        when "yesterday"
          1.day.ago
        else
          begin
            Time.parse(time_str)
          rescue StandardError
            nil
          end
        end
      end

      def parse_duration_to_ms(amount, unit)
        amount = amount.to_f
        case unit.downcase
        when /ms/ then amount
        when /sec/ then amount * 1000
        when /min/ then amount * 60 * 1000
        else amount * 1000 # default to seconds
        end
      end

      def normalize_component_type(type)
        case type.downcase
        when /agent/ then "agent"
        when /llm|model/ then "llm"
        when /tool/ then "tool"
        when /function/ then "function"
        else type
        end
      end

      def setup_ai_client
        return unless @config[:openai_api_key]

        OpenAI::Client.new(
          access_token: @config[:openai_api_key],
          request_timeout: 10
        )
      end

      def generate_sql_explanation(parsed_query)
        # Generate a pseudo-SQL explanation of what the query would do
        filters = parsed_query[:filters]

        sql_parts = ["SELECT * FROM traces"]

        where_clauses = []
        where_clauses << "status = '#{filters[:status]}'" if filters[:status]
        where_clauses << "workflow_name = '#{filters[:workflow_name]}'" if filters[:workflow_name]
        where_clauses << "duration_ms > #{filters[:min_duration_ms]}" if filters[:min_duration_ms]
        where_clauses << "duration_ms < #{filters[:max_duration_ms]}" if filters[:max_duration_ms]

        if filters[:timeframe]
          where_clauses << if filters[:timeframe].is_a?(Range)
                             "started_at BETWEEN '#{filters[:timeframe].begin}' AND '#{filters[:timeframe].end}'"
                           else
                             "started_at > '#{Time.current - filters[:timeframe]}'"
                           end
        end

        sql_parts << "WHERE #{where_clauses.join(" AND ")}" if where_clauses.any?

        if parsed_query[:sorting]
          direction = parsed_query[:sorting][:direction].to_s.upcase
          sql_parts << "ORDER BY #{parsed_query[:sorting][:field]} #{direction}"
        end

        sql_parts << "LIMIT #{parsed_query[:limit]}" if parsed_query[:limit]

        sql_parts.join(" ")
      end

      def extract_filters_explanation(parsed_query)
        filters = parsed_query[:filters]
        explanations = []

        explanations << "Time range: #{describe_timeframe(filters)}" if filters[:timeframe] || filters[:start_time]
        explanations << "Status: #{filters[:status]}" if filters[:status]
        explanations << "Workflow: #{filters[:workflow_name]}" if filters[:workflow_name]
        if filters[:min_duration_ms] || filters[:max_duration_ms]
          explanations << "Duration: #{describe_duration_filter(filters)}"
        end
        explanations << "Tenant: #{filters[:tenant_id]}" if filters[:tenant_id]

        explanations
      end

      def describe_timeframe(filters)
        if filters[:start_time] && filters[:end_time]
          "#{filters[:start_time]} to #{filters[:end_time]}"
        elsif filters[:start_time]
          "since #{filters[:start_time]}"
        elsif filters[:timeframe]
          "last #{filters[:timeframe] / 1.hour} hours"
        else
          "last 24 hours"
        end
      end

      def describe_duration_filter(filters)
        if filters[:min_duration_ms] && filters[:max_duration_ms]
          "between #{filters[:min_duration_ms]}ms and #{filters[:max_duration_ms]}ms"
        elsif filters[:min_duration_ms]
          "longer than #{filters[:min_duration_ms]}ms"
        elsif filters[:max_duration_ms]
          "shorter than #{filters[:max_duration_ms]}ms"
        end
      end

      def estimate_result_count(parsed_query)
        # This would estimate based on historical query patterns
        # For now, return a rough estimate
        case parsed_query[:entity]
        when :traces
          if parsed_query[:filters][:status] == "error"
            "~10-50 results"
          else
            "~100-500 results"
          end
        when :spans
          "~500-2000 results"
        else
          "~50-200 results"
        end
      end

      # Query builder class
      class QueryBuilder
        def initialize(parsed_query)
          @parsed = parsed_query
        end

        def execute
          # Build the actual database query
          query = base_query
          query = apply_filters(query)
          query = apply_sorting(query)
          query = apply_limit(query)

          query.to_a
        end

        private

        def base_query
          case @parsed[:entity]
          when :traces
            if defined?(RubyAIAgentsFactory::Tracing::Trace)
              RubyAIAgentsFactory::Tracing::Trace.all
            else
              []
            end
          when :spans
            if defined?(RubyAIAgentsFactory::Tracing::Span)
              RubyAIAgentsFactory::Tracing::Span.all
            else
              []
            end
          else
            []
          end
        end

        def apply_filters(query)
          return query unless query.respond_to?(:where)

          filters = @parsed[:filters]

          # Time filters
          if filters[:timeframe].is_a?(ActiveSupport::Duration)
            query = query.where("started_at > ?", Time.current - filters[:timeframe])
          elsif filters[:start_time] && filters[:end_time]
            query = query.where(started_at: filters[:start_time]..filters[:end_time])
          elsif filters[:start_time]
            query = query.where("started_at > ?", filters[:start_time])
          end

          # Status filters
          query = query.where(status: filters[:status]) if filters[:status]

          # Workflow filters
          query = query.where(workflow_name: filters[:workflow_name]) if filters[:workflow_name]

          # Duration filters
          query = query.where("duration_ms > ?", filters[:min_duration_ms]) if filters[:min_duration_ms]
          query = query.where("duration_ms < ?", filters[:max_duration_ms]) if filters[:max_duration_ms]

          # Tenant filters
          if filters[:tenant_id] && query.respond_to?(:joins)
            # This would need to join with metadata or use JSON queries
          end

          query
        end

        def apply_sorting(query)
          return query unless query.respond_to?(:order)

          sorting = @parsed[:sorting]
          return query unless sorting

          field = sorting[:field]
          direction = sorting[:direction]

          query.order(field => direction)
        end

        def apply_limit(query)
          return query unless query.respond_to?(:limit)

          limit = @parsed[:limit]
          return query unless limit

          query.limit(limit)
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
