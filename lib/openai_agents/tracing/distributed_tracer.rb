# frozen_string_literal: true

module OpenAIAgents
  module Tracing
    class DistributedTracer
      # Enhanced tracing with distributed system support
      # Correlates traces across multiple services, processes, and applications

      TRACE_HEADER = "X-OpenAI-Agents-Trace-Id"
      SPAN_HEADER = "X-OpenAI-Agents-Span-Id"
      PARENT_SPAN_HEADER = "X-OpenAI-Agents-Parent-Span-Id"
      BAGGAGE_HEADER = "X-OpenAI-Agents-Baggage"

      def initialize(config = {})
        @config = {
          # Service identification
          service_name: config[:service_name] || determine_service_name,
          service_version: config[:service_version] || determine_service_version,

          # Correlation settings
          auto_correlate_http: config[:auto_correlate_http] != false,
          auto_correlate_jobs: config[:auto_correlate_jobs] != false,

          # Sampling for distributed traces
          distributed_sampling_rate: config[:distributed_sampling_rate] || 0.1,

          # Cross-service propagation
          propagate_baggage: config[:propagate_baggage] != false,
          max_baggage_size: config[:max_baggage_size] || 512,

          # Enhanced debugging
          capture_stack_traces: config[:capture_stack_traces] || false,
          capture_local_variables: config[:capture_local_variables] || false,
          capture_method_args: config[:capture_method_args] || false
        }

        @baggage_context = {}
        @trace_correlations = {}

        setup_middleware if @config[:auto_correlate_http]
        setup_job_integration if @config[:auto_correlate_jobs]
      end

      def start_distributed_trace(name, headers: {}, parent_context: nil, **metadata)
        # Extract or create trace context
        trace_id = extract_trace_id(headers) || generate_trace_id
        parent_span_id = extract_parent_span_id(headers)
        baggage = extract_baggage(headers)

        # Merge baggage with current context
        @baggage_context = @baggage_context.merge(baggage) if baggage.any?

        # Start the trace with distributed context
        OpenAIAgents.trace(name, trace_id: trace_id) do |trace|
          # Add distributed tracing metadata
          trace.metadata.merge!(
            service_name: @config[:service_name],
            service_version: @config[:service_version],
            parent_span_id: parent_span_id,
            baggage: @baggage_context.dup,
            distributed: true,
            **metadata
          )

          # Store correlation data
          store_trace_correlation(trace_id, trace)

          yield trace if block_given?
        end
      end

      def continue_trace(trace_id, span_name, **metadata)
        existing_trace = find_trace_by_id(trace_id)
        return unless existing_trace

        # Create child span in existing trace context
        span = create_child_span(existing_trace, span_name, **metadata)

        # Enhanced debugging capture
        span.attributes["debug.stack_trace"] = capture_stack_trace if @config[:capture_stack_traces]

        span.attributes["debug.local_variables"] = capture_local_variables if @config[:capture_local_variables]

        span
      end

      def create_outbound_headers(current_trace = nil)
        current_trace ||= OpenAIAgents.current_trace
        return {} unless current_trace

        headers = {
          TRACE_HEADER => current_trace.trace_id,
          SPAN_HEADER => current_trace.current_span&.span_id || current_trace.trace_id
        }

        # Add parent span if available
        headers[PARENT_SPAN_HEADER] = current_trace.current_span.span_id if current_trace.current_span

        # Add baggage if enabled
        if @config[:propagate_baggage] && @baggage_context.any?
          baggage_string = encode_baggage(@baggage_context)
          headers[BAGGAGE_HEADER] = baggage_string if baggage_string.length <= @config[:max_baggage_size]
        end

        headers
      end

      def add_baggage(key, value)
        @baggage_context[key.to_s] = value.to_s
      end

      def get_baggage(key = nil)
        return @baggage_context.dup if key.nil?

        @baggage_context[key.to_s]
      end

      def clear_baggage
        @baggage_context.clear
      end

      def correlate_with_external_service(service_name, operation, headers: {})
        current_trace = OpenAIAgents.current_trace
        return yield if current_trace.nil?

        # Create span for external service call
        span = current_trace.start_span("external.#{service_name}.#{operation}")
        span.attributes.merge!(
          "external_service.name" => service_name,
          "external_service.operation" => operation,
          "external_service.headers" => sanitize_headers(headers)
        )

        # Add distributed tracing headers
        outbound_headers = create_outbound_headers(current_trace)
        final_headers = headers.merge(outbound_headers)

        begin
          result = yield final_headers
          span.set_status("ok")
          result
        rescue StandardError => e
          span.set_status("error")
          span.record_exception(e)
          raise
        ensure
          span.end
        end
      end

      def get_trace_topology(trace_id)
        # Build a graph of related traces across services
        trace = find_trace_by_id(trace_id)
        return nil unless trace

        topology = {
          root_trace: trace_summary(trace),
          services: build_service_graph(trace),
          spans: build_span_hierarchy(trace),
          external_calls: find_external_calls(trace),
          correlations: find_correlated_traces(trace_id)
        }

        # Add performance analysis
        topology[:performance] = analyze_distributed_performance(topology)
        topology[:bottlenecks] = identify_bottlenecks(topology)

        topology
      end

      def replay_trace(trace_id, options = {})
        # Advanced debugging: replay a trace for investigation
        trace = find_trace_by_id(trace_id)
        return { error: "Trace not found" } unless trace

        replay_result = {
          original_trace: trace_summary(trace),
          replay_trace: nil,
          differences: [],
          success: false
        }

        begin
          # Create replay context
          replay_context = create_replay_context(trace, options)

          # Execute replay
          replay_trace = execute_replay(replay_context)
          replay_result[:replay_trace] = trace_summary(replay_trace)

          # Compare results
          replay_result[:differences] = compare_traces(trace, replay_trace)
          replay_result[:success] = true
        rescue StandardError => e
          replay_result[:error] = e.message
          replay_result[:stack_trace] = e.backtrace if options[:include_stack_trace]
        end

        replay_result
      end

      def analyze_trace_performance(trace_id)
        trace = find_trace_by_id(trace_id)
        return nil unless trace

        analysis = {
          trace_id: trace_id,
          total_duration: trace.duration_ms,
          span_count: trace.spans.count,
          service_breakdown: {},
          critical_path: [],
          bottlenecks: [],
          recommendations: []
        }

        # Service-level breakdown
        trace.spans.group_by { |s| s.attributes["service.name"] || @config[:service_name] }.each do |service, spans|
          total_time = spans.sum(&:duration_ms)
          analysis[:service_breakdown][service] = {
            span_count: spans.size,
            total_time_ms: total_time,
            percentage: (total_time.to_f / trace.duration_ms * 100).round(2),
            avg_span_time: (total_time.to_f / spans.size).round(2)
          }
        end

        # Critical path analysis
        analysis[:critical_path] = find_critical_path(trace)

        # Identify bottlenecks
        analysis[:bottlenecks] = identify_performance_bottlenecks(trace)

        # Generate recommendations
        analysis[:recommendations] = generate_performance_recommendations(analysis)

        analysis
      end

      def create_profiling_span(name, **metadata)
        # Enhanced span with profiling capabilities
        span = OpenAIAgents.current_trace&.start_span(name)
        return yield unless span

        # Capture method information
        if @config[:capture_method_args]
          caller_info = caller_locations(1, 1).first
          span.attributes["method.file"] = caller_info.path
          span.attributes["method.line"] = caller_info.lineno
          span.attributes["method.name"] = caller_info.label
        end

        # Start profiling
        start_memory = get_memory_usage if @config[:capture_local_variables]
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)

        begin
          result = yield
          span.set_status("ok")
          result
        rescue StandardError => e
          span.set_status("error")
          span.record_exception(e)

          # Capture error context
          span.attributes["error.local_variables"] = capture_error_context(e) if @config[:capture_local_variables]

          raise
        ensure
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)

          # Add profiling data
          span.attributes["profiling.cpu_time_ns"] = end_time - start_time

          if start_memory
            end_memory = get_memory_usage
            span.attributes["profiling.memory_delta"] = end_memory - start_memory
          end

          span.end
        end
      end

      private

      def determine_service_name
        if defined?(Rails)
          Rails.application.class.module_parent_name.underscore
        else
          File.basename($0, ".rb")
        end
      end

      def determine_service_version
        if defined?(Rails)
          begin
            Rails.application.config.version
          rescue StandardError
            "1.0.0"
          end
        else
          "1.0.0"
        end
      end

      def setup_middleware
        return unless defined?(Rails)

        Rails.application.config.middleware.use DistributedTracingMiddleware
      end

      def setup_job_integration
        return unless defined?(ActiveJob)

        ActiveJob::Base.include(DistributedJobTracing)
      end

      def extract_trace_id(headers)
        headers[TRACE_HEADER] || headers[TRACE_HEADER.downcase] || headers[TRACE_HEADER.upcase]
      end

      def extract_parent_span_id(headers)
        headers[SPAN_HEADER] || headers[SPAN_HEADER.downcase] || headers[SPAN_HEADER.upcase]
      end

      def extract_baggage(headers)
        baggage_header = headers[BAGGAGE_HEADER] || headers[BAGGAGE_HEADER.downcase] || headers[BAGGAGE_HEADER.upcase]
        return {} unless baggage_header

        decode_baggage(baggage_header)
      end

      def encode_baggage(baggage)
        baggage.map { |k, v| "#{CGI.escape(k)}=#{CGI.escape(v)}" }.join(",")
      end

      def decode_baggage(baggage_string)
        return {} if baggage_string.nil? || baggage_string.empty?

        baggage = {}
        baggage_string.split(",").each do |pair|
          key, value = pair.split("=", 2)
          next unless key && value

          baggage[CGI.unescape(key)] = CGI.unescape(value)
        end
        baggage
      rescue StandardError
        {}
      end

      def generate_trace_id
        SecureRandom.hex(16)
      end

      def store_trace_correlation(trace_id, trace)
        @trace_correlations[trace_id] = {
          trace: trace,
          service: @config[:service_name],
          started_at: Time.current,
          baggage: @baggage_context.dup
        }
      end

      def find_trace_by_id(trace_id)
        # Try local correlation first
        correlation = @trace_correlations[trace_id]
        return correlation[:trace] if correlation

        # Fall back to database lookup
        return unless defined?(OpenAIAgents::Tracing::Trace)

        OpenAIAgents::Tracing::Trace.find_by(trace_id: trace_id)
      end

      def create_child_span(trace, name, **metadata)
        span = trace.start_span(name)
        span.attributes.merge!(metadata)
        span.attributes["service.name"] = @config[:service_name]
        span.attributes["service.version"] = @config[:service_version]
        span
      end

      def capture_stack_trace
        caller_locations(2, 20).map do |location|
          "#{location.path}:#{location.lineno}:in `#{location.label}'"
        end.join("\n")
      end

      def capture_local_variables
        # This is a simplified version - real implementation would need
        # more sophisticated variable capture
        binding.local_variables.to_h do |var|
          value = binding.local_variable_get(var)
          [var, sanitize_variable_value(value)]
        rescue StandardError
          [var, "<unavailable>"]
        end
      end

      def sanitize_variable_value(value)
        case value
        when String
          value.length > 100 ? "#{value[0..97]}..." : value
        when Numeric, TrueClass, FalseClass, NilClass
          value
        when Array
          value.length > 10 ? "Array(#{value.length})" : value.map { |v| sanitize_variable_value(v) }
        when Hash
          if value.keys.length > 10
            "Hash(#{value.keys.length})"
          else
            value.transform_values do |v|
              sanitize_variable_value(v)
            end
          end
        else
          value.class.name
        end
      end

      def sanitize_headers(headers)
        sensitive_headers = %w[authorization cookie x-api-key]

        headers.transform_keys(&:downcase).to_h do |key, value|
          if sensitive_headers.any? { |sensitive| key.include?(sensitive) }
            [key, "[REDACTED]"]
          else
            [key, value.to_s.length > 100 ? "#{value.to_s[0..97]}..." : value.to_s]
          end
        end
      end

      def build_service_graph(trace)
        services = {}

        trace.spans.each do |span|
          service_name = span.attributes["service.name"] || @config[:service_name]
          external_service = span.attributes["external_service.name"]

          services[service_name] ||= {
            name: service_name,
            spans: 0,
            total_time: 0,
            external_calls: []
          }

          services[service_name][:spans] += 1
          services[service_name][:total_time] += span.duration_ms

          next unless external_service

          services[service_name][:external_calls] << {
            service: external_service,
            operation: span.attributes["external_service.operation"],
            duration: span.duration_ms
          }
        end

        services
      end

      def build_span_hierarchy(trace)
        spans_by_parent = trace.spans.group_by(&:parent_span_id)
        root_spans = spans_by_parent[nil] || []

        build_span_tree(root_spans, spans_by_parent)
      end

      def build_span_tree(spans, spans_by_parent)
        spans.map do |span|
          children = spans_by_parent[span.span_id] || []
          {
            span_id: span.span_id,
            name: span.name,
            kind: span.kind,
            duration_ms: span.duration_ms,
            status: span.status,
            attributes: span.attributes,
            children: build_span_tree(children, spans_by_parent)
          }
        end
      end

      def find_external_calls(trace)
        trace.spans
             .select { |s| s.attributes["external_service.name"] }
             .map do |span|
               {
                 service: span.attributes["external_service.name"],
                 operation: span.attributes["external_service.operation"],
                 duration_ms: span.duration_ms,
                 status: span.status,
                 span_id: span.span_id
               }
             end
      end

      def find_correlated_traces(trace_id)
        # Find other traces that share baggage or correlation IDs
        # This would require more sophisticated correlation tracking
        []
      end

      def analyze_distributed_performance(topology)
        {
          total_services: topology[:services].keys.size,
          external_calls: topology[:external_calls].size,
          longest_service_chain: calculate_longest_chain(topology),
          service_utilization: calculate_service_utilization(topology)
        }
      end

      def identify_bottlenecks(topology)
        bottlenecks = []

        # Service-level bottlenecks
        topology[:services].each do |service_name, service_data|
          next unless service_data[:total_time] > topology[:root_trace][:duration_ms] * 0.3

          bottlenecks << {
            type: "service_bottleneck",
            service: service_name,
            impact: "high",
            duration_ms: service_data[:total_time],
            percentage: (service_data[:total_time].to_f / topology[:root_trace][:duration_ms] * 100).round(2)
          }
        end

        # External call bottlenecks
        topology[:external_calls].each do |call|
          next unless call[:duration_ms] > 1000 # > 1 second

          bottlenecks << {
            type: "external_call_bottleneck",
            service: call[:service],
            operation: call[:operation],
            impact: call[:duration_ms] > 5000 ? "critical" : "moderate",
            duration_ms: call[:duration_ms]
          }
        end

        bottlenecks
      end

      def get_memory_usage
        if defined?(GC.stat)
          GC.stat[:heap_allocated_pages] * GC::INTERNAL_CONSTANTS[:HEAP_PAGE_SIZE]
        else
          0
        end
      end

      def capture_error_context(error)
        {
          error_class: error.class.name,
          error_message: error.message,
          backtrace: error.backtrace&.first(10)
        }
      end

      def trace_summary(trace)
        {
          trace_id: trace.trace_id,
          workflow_name: trace.workflow_name,
          status: trace.status,
          duration_ms: trace.duration_ms,
          span_count: trace.spans.count,
          service: @config[:service_name]
        }
      end

      def create_replay_context(trace, options)
        {
          original_trace: trace,
          replay_mode: true,
          capture_differences: true,
          options: options
        }
      end

      def execute_replay(context)
        # This would need to be implemented based on specific replay requirements
        # Placeholder for actual replay logic
        nil
      end

      def compare_traces(original, replay)
        # Compare two traces and identify differences
        []
      end

      def find_critical_path(trace)
        # Identify the critical path through the trace
        []
      end

      def identify_performance_bottlenecks(trace)
        []
      end

      def generate_performance_recommendations(analysis)
        []
      end

      def calculate_longest_chain(topology)
        0
      end

      def calculate_service_utilization(topology)
        {}
      end

      # Middleware for HTTP request correlation
      class DistributedTracingMiddleware
        def initialize(app)
          @app = app
        end

        def call(env)
          request = ActionDispatch::Request.new(env)

          # Extract tracing headers
          headers = extract_tracing_headers(request.headers)

          if headers.any?
            # Continue existing trace
            tracer = OpenAIAgents::Tracing::DistributedTracer.new
            tracer.start_distributed_trace("http.request", headers: headers) do
              @app.call(env)
            end
          else
            @app.call(env)
          end
        end

        private

        def extract_tracing_headers(headers)
          tracing_headers = {}

          %w[X-OpenAI-Agents-Trace-Id X-OpenAI-Agents-Span-Id X-OpenAI-Agents-Parent-Span-Id
             X-OpenAI-Agents-Baggage].each do |header|
            value = headers[header]
            tracing_headers[header] = value if value
          end

          tracing_headers
        end
      end

      # Job integration module
      module DistributedJobTracing
        extend ActiveSupport::Concern

        included do
          around_perform :wrap_with_distributed_tracing
        end

        private

        def wrap_with_distributed_tracing(&)
          # Extract trace context from job arguments or serialized data
          trace_context = extract_trace_context_from_job

          if trace_context
            tracer = OpenAIAgents::Tracing::DistributedTracer.new
            tracer.start_distributed_trace("job.#{self.class.name}", headers: trace_context, &)
          else
            yield
          end
        end

        def extract_trace_context_from_job
          # Look for trace context in job metadata
          {}
        end
      end
    end
  end
end
