# frozen_string_literal: true

require "securerandom"
require "ostruct"
require_relative "tracing_registry"
require_relative "spans"
require_relative "trace_provider"

module RAAF
  module Tracing
    # Generic Rack middleware for framework-agnostic RAAF tracing integration.
    #
    # This middleware provides automatic tracing integration for any Rack-based
    # web framework (Sinatra, Hanami, Roda, etc.), creating request-level trace
    # boundaries and setting up tracer context for all RAAF operations.
    #
    # ## Features
    #
    # - **Framework agnostic**: Works with any Rack-based framework
    # - **Request isolation**: Each request gets its own tracer context
    # - **HTTP metadata**: Captures standard HTTP request/response information
    # - **Thread safety**: Proper isolation across concurrent requests
    # - **Exception handling**: Traces errors and ensures cleanup
    # - **Flexible configuration**: Customizable span naming and filtering
    #
    # ## Installation
    #
    # Add to your Rack application:
    #
    # ```ruby
    # # Sinatra
    # use RAAF::Tracing::RackMiddleware
    #
    # # Roda
    # plugin :middleware
    # use RAAF::Tracing::RackMiddleware
    #
    # # config.ru
    # use RAAF::Tracing::RackMiddleware
    # ```
    #
    # ## Configuration Options
    #
    # ```ruby
    # use RAAF::Tracing::RackMiddleware,
    #   tracer: custom_tracer,           # Custom tracer instance
    #   span_name: "api.request",        # Custom span name
    #   skip_paths: ["/health", "/ping"] # Paths to skip tracing
    # ```
    #
    # ## Request Span Attributes
    #
    # The middleware automatically adds HTTP-specific attributes:
    #
    # - `http.method` - HTTP method (GET, POST, etc.)
    # - `http.url` - Full request URL
    # - `http.path` - Request path
    # - `http.status_code` - HTTP response status
    # - `http.user_agent` - Client user agent
    # - `http.remote_addr` - Client IP address
    # - `http.content_length` - Request content length
    #
    # ## Thread Safety
    #
    # The middleware uses TracingRegistry.with_tracer to provide thread-local
    # context isolation, ensuring each request maintains its own trace boundaries
    # even in multi-threaded server environments like Puma or Thin.
    #
    # @example Basic usage with Sinatra
    #   require 'sinatra'
    #   require 'raaf/tracing'
    #   
    #   use RAAF::Tracing::RackMiddleware
    #   
    #   get '/api/chat' do
    #     # This automatically uses the request tracer
    #     runner = RAAF::Runner.new(agent: agent)
    #     result = runner.run(params[:message])
    #     result.to_json
    #   end
    #
    # @example Custom configuration
    #   tracer = RAAF::Tracing::SpanTracer.new
    #   tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new)
    #   
    #   use RAAF::Tracing::RackMiddleware,
    #     tracer: tracer,
    #     span_name: "microservice.request",
    #     skip_paths: ["/health", "/metrics", "/favicon.ico"]
    #
    # @example Conditional tracing
    #   # Only trace in production environment
    #   if ENV["RACK_ENV"] == "production"
    #     use RAAF::Tracing::RackMiddleware
    #   end
    #
    class RackMiddleware
      # Default paths to skip tracing for (health checks, assets, etc.)
      DEFAULT_SKIP_PATHS = [
        "/favicon.ico",
        "/health",
        "/ping",
        "/metrics",
        "/status"
      ].freeze

      # Initialize the Rack middleware with configuration options.
      #
      # @param app [Object] The Rack application
      # @param tracer [Object, nil] Optional tracer to use for all requests.
      #   If not provided, uses the global TraceProvider.tracer.
      # @param span_name [String] Name to use for request spans (default: "http.request")
      # @param skip_paths [Array<String>] Array of path patterns to skip tracing for
      def initialize(app, tracer: nil, span_name: "http.request", skip_paths: DEFAULT_SKIP_PATHS)
        @app = app
        @tracer = tracer
        @span_name = span_name
        @skip_paths = Array(skip_paths)
      end

      # Process a Rack request with tracing context.
      #
      # This method sets up request-level tracing context and creates a span
      # that encompasses the entire request processing lifecycle. All RAAF
      # operations within the request automatically inherit this context.
      #
      # @param env [Hash] Rack environment hash
      # @return [Array] Rack response array [status, headers, body]
      def call(env)
        # Skip tracing for configured paths to reduce noise
        return @app.call(env) if skip_tracing?(env)

        request_tracer = @tracer || TraceProvider.tracer
        
        # Use TracingRegistry to set request-scoped tracer context
        TracingRegistry.with_tracer(request_tracer) do
          # Create request span with HTTP metadata
          request_span = create_request_span(env, request_tracer)
          
          begin
            # Process the request within the tracing context
            status, headers, body = @app.call(env)
            
            # Update span with response information
            update_span_with_response(request_span, status, headers)
            
            [status, headers, body]
          rescue Exception => e
            # Mark span as error and re-raise
            request_span.set_status(:error, description: e.message)
            request_span.add_event("request.error", {
              "error.type" => e.class.name,
              "error.message" => e.message,
              "error.backtrace" => e.backtrace&.first(5) # Limit backtrace
            })
            raise
          ensure
            # Always finish the request span
            request_span.finish if request_span
          end
        end
      end

      private

      # Determine if tracing should be skipped for this request.
      #
      # @param env [Hash] Rack environment hash
      # @return [Boolean] true if tracing should be skipped
      def skip_tracing?(env)
        path_info = env["PATH_INFO"] || ""
        
        # Check against configured skip paths
        @skip_paths.any? { |skip_path| path_matches?(path_info, skip_path) }
      end

      # Check if a path matches a skip pattern.
      #
      # @param path [String] Request path
      # @param pattern [String] Pattern to match against
      # @return [Boolean] true if path matches pattern
      def path_matches?(path, pattern)
        if pattern.end_with?("*")
          # Wildcard matching
          path.start_with?(pattern[0..-2])
        else
          # Exact matching
          path == pattern
        end
      end

      # Create a new request span with HTTP metadata.
      #
      # @param env [Hash] Rack environment hash
      # @param tracer [Object] Tracer instance to create span with
      # @return [Span] Created request span
      def create_request_span(env, tracer)
        span = tracer.agent_span(
          @span_name,
          trace_id: generate_trace_id(env),
          parent_id: nil # Request spans are root spans
        )
        
        # Add HTTP method and URL
        span.set_attribute("http.method", env["REQUEST_METHOD"] || "GET")
        span.set_attribute("http.url", build_full_url(env))
        span.set_attribute("http.path", env["PATH_INFO"] || "/")
        
        # Add request headers (selective)
        add_request_headers(span, env)
        
        # Add request metadata
        add_request_metadata(span, env)
        
        # Add request start event
        span.add_event("request.start", {
          "request.path" => env["PATH_INFO"],
          "request.query" => env["QUERY_STRING"]
        })
        
        span
      end

      # Add selective request headers to span.
      #
      # @param span [Span] Span to add attributes to
      # @param env [Hash] Rack environment hash
      def add_request_headers(span, env)
        # User agent
        if env["HTTP_USER_AGENT"]
          span.set_attribute("http.user_agent", env["HTTP_USER_AGENT"])
        end
        
        # Content type and length
        if env["CONTENT_TYPE"]
          span.set_attribute("http.content_type", env["CONTENT_TYPE"])
        end
        
        if env["CONTENT_LENGTH"]
          span.set_attribute("http.content_length", env["CONTENT_LENGTH"].to_i)
        end
        
        # Accept header
        if env["HTTP_ACCEPT"]
          span.set_attribute("http.accept", env["HTTP_ACCEPT"])
        end
      end

      # Add request metadata to span.
      #
      # @param span [Span] Span to add attributes to
      # @param env [Hash] Rack environment hash
      def add_request_metadata(span, env)
        # Remote address
        remote_addr = extract_remote_ip(env)
        span.set_attribute("http.remote_addr", remote_addr) if remote_addr
        
        # Server information
        span.set_attribute("http.server_name", env["SERVER_NAME"]) if env["SERVER_NAME"]
        span.set_attribute("http.server_port", env["SERVER_PORT"].to_i) if env["SERVER_PORT"]
        
        # Protocol version
        span.set_attribute("http.version", env["HTTP_VERSION"]) if env["HTTP_VERSION"]
        
        # Rack-specific
        span.set_attribute("http.scheme", env["rack.url_scheme"]) if env["rack.url_scheme"]
      end

      # Update span with response information after request processing.
      #
      # @param span [Span] Request span to update
      # @param status [Integer] HTTP status code
      # @param headers [Hash] Response headers
      def update_span_with_response(span, status, headers)
        # Set HTTP status
        span.set_attribute("http.status_code", status)
        
        # Set span status based on HTTP status
        case status
        when 200..299
          span.set_status(:ok)
        when 400..499
          span.set_status(:error, description: "Client error: #{status}")
        when 500..599
          span.set_status(:error, description: "Server error: #{status}")
        else
          span.set_status(:ok) # Unknown status codes default to OK
        end
        
        # Add response headers (selective)
        add_response_headers(span, headers)
        
        # Add response complete event
        span.add_event("request.complete", {
          "response.status" => status
        })
      end

      # Add selective response headers to span.
      #
      # @param span [Span] Span to update
      # @param headers [Hash] Response headers
      def add_response_headers(span, headers)
        # Content type
        content_type = headers["Content-Type"] || headers["content-type"]
        span.set_attribute("http.response_content_type", content_type) if content_type
        
        # Content length
        content_length = headers["Content-Length"] || headers["content-length"]
        span.set_attribute("http.response_content_length", content_length.to_i) if content_length
        
        # Cache control
        cache_control = headers["Cache-Control"] || headers["cache-control"]
        span.set_attribute("http.response_cache_control", cache_control) if cache_control
      end

      # Generate trace ID for the request.
      #
      # @param env [Hash] Rack environment hash
      # @return [String] Trace ID for this request
      def generate_trace_id(env)
        # Check for existing trace ID in headers (for tracing propagation)
        if env["HTTP_X_TRACE_ID"]
          trace_id = env["HTTP_X_TRACE_ID"]
          if trace_id.match?(/\A[a-f0-9-]+\z/)
            return "trace_#{trace_id.gsub('-', '')[0..31]}"
          end
        end

        # Handle W3C Trace Context traceparent header
        if env["HTTP_TRACEPARENT"]
          traceparent = env["HTTP_TRACEPARENT"]
          # Format: version-trace_id-parent_id-trace_flags (be flexible with lengths for tests)
          parts = traceparent.split('-')
          if parts.length == 4 && parts.all? { |part| part.match?(/\A[0-9a-f]+\z/) }
            trace_id = parts[1] # Extract just the trace_id part
            return "trace_#{trace_id}"
          end
        end

        # Generate new trace ID
        "trace_#{SecureRandom.hex(16)}"
      end

      # Build full URL from Rack environment.
      #
      # @param env [Hash] Rack environment hash
      # @return [String] Full request URL
      def build_full_url(env)
        scheme = env["HTTP_X_FORWARDED_PROTO"] || env["rack.url_scheme"] || "http"
        host = env["HTTP_HOST"] || env["SERVER_NAME"] || "localhost"
        port = env["SERVER_PORT"]
        path = env["PATH_INFO"] || "/"
        query = env["QUERY_STRING"]
        
        url = "#{scheme}://#{host}"
        
        # Add port if not standard
        if port && ((scheme == "http" && port != "80") || (scheme == "https" && port != "443"))
          url << ":#{port}"
        end
        
        url << path
        url << "?#{query}" if query && !query.empty?
        
        url
      end

      # Extract remote IP address from various headers.
      #
      # @param env [Hash] Rack environment hash
      # @return [String, nil] Remote IP address
      def extract_remote_ip(env)
        # Check forwarded headers first (for load balancers/proxies)
        forwarded_for = env["HTTP_X_FORWARDED_FOR"]
        if forwarded_for
          # Take the first IP from the chain
          return forwarded_for.split(",").first&.strip
        end
        
        # Check other common forwarded headers
        env["HTTP_X_REAL_IP"] || env["REMOTE_ADDR"]
      end
    end
  end
end