# frozen_string_literal: true

require "securerandom"
require "ostruct"
require_relative "tracing_registry"
require_relative "spans"
require_relative "trace_provider"

module RAAF
  module Tracing
    # Rails middleware for automatic RAAF tracing integration.
    #
    # This middleware creates request-level trace boundaries for Rails applications,
    # automatically setting up tracer context for all RAAF operations within each request.
    # It integrates with Rails conventions and provides request-specific metadata.
    #
    # ## Features
    #
    # - **Request isolation**: Each request gets its own tracer context
    # - **Automatic span creation**: Creates request spans with HTTP metadata
    # - **Rails integration**: Uses Rails request information and routing
    # - **Thread safety**: Proper isolation across concurrent requests
    # - **Exception handling**: Traces errors and ensures cleanup
    # - **Performance monitoring**: Tracks request timing and status
    #
    # ## Installation
    #
    # Add to your Rails application configuration:
    #
    # ```ruby
    # # config/application.rb
    # config.middleware.use RAAF::Tracing::RailsMiddleware
    # ```
    #
    # Or with custom tracer configuration:
    #
    # ```ruby
    # # config/application.rb
    # tracer = RAAF::Tracing::SpanTracer.new
    # tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)
    # config.middleware.use RAAF::Tracing::RailsMiddleware, tracer: tracer
    # ```
    #
    # ## Request Span Attributes
    #
    # The middleware automatically adds Rails-specific attributes to request spans:
    #
    # - `http.method` - HTTP method (GET, POST, etc.)
    # - `http.url` - Full request URL
    # - `http.route` - Rails route pattern
    # - `http.controller` - Controller class name
    # - `http.action` - Controller action name
    # - `http.status_code` - HTTP response status
    # - `http.user_agent` - Client user agent
    # - `rails.request_id` - Rails request ID for correlation
    #
    # ## Integration with RAAF Components
    #
    # Once installed, all RAAF operations within request processing automatically
    # use the request tracer:
    #
    # ```ruby
    # class AgentsController < ApplicationController
    #   def create
    #     # This automatically uses the request tracer set up by middleware
    #     runner = RAAF::Runner.new(agent: agent)
    #     result = runner.run(params[:message])
    #   end
    # end
    # ```
    #
    # ## Thread Safety
    #
    # The middleware uses TracingRegistry.with_tracer to provide thread-local
    # context isolation, ensuring each request maintains its own trace boundaries
    # even in multi-threaded server environments.
    #
    # @example Basic installation
    #   # config/application.rb
    #   config.middleware.use RAAF::Tracing::RailsMiddleware
    #
    # @example With custom tracer
    #   # config/initializers/raaf_tracing.rb
    #   tracer = RAAF::Tracing::SpanTracer.new
    #   tracer.add_processor(MyCustomProcessor.new)
    #   
    #   Rails.application.configure do
    #     config.middleware.use RAAF::Tracing::RailsMiddleware, tracer: tracer
    #   end
    #
    # @example Conditional tracing
    #   # Only trace in production
    #   if Rails.env.production?
    #     config.middleware.use RAAF::Tracing::RailsMiddleware
    #   end
    #
    class RailsMiddleware
      # Initialize the Rails middleware with optional tracer configuration.
      #
      # @param app [Object] The Rack application
      # @param tracer [Object, nil] Optional tracer to use for all requests.
      #   If not provided, uses the global TraceProvider.tracer.
      def initialize(app, tracer: nil)
        @app = app
        @tracer = tracer
      end

      # Process a Rails request with tracing context.
      #
      # This method sets up request-level tracing context and creates a span
      # that encompasses the entire request processing lifecycle. All RAAF
      # operations within the request automatically inherit this context.
      #
      # @param env [Hash] Rack environment hash
      # @return [Array] Rack response array [status, headers, body]
      def call(env)
        # Skip tracing for health checks and assets to reduce noise
        return @app.call(env) if skip_tracing?(env)

        request_tracer = @tracer || TraceProvider.tracer
        
        # Use TracingRegistry to set request-scoped tracer context
        TracingRegistry.with_tracer(request_tracer) do
          # Create request span with Rails-specific metadata
          request_span = create_request_span(env, request_tracer)
          
          begin
            # Process the request within the tracing context
            status, headers, body = @app.call(env)
            
            # Update span with response information
            update_span_with_response(request_span, env, status, headers)
            
            [status, headers, body]
          rescue Exception => e
            # Mark span as error and re-raise
            request_span.set_status(:error, description: e.message)
            request_span.add_event("request.error", {
              "error.type" => e.class.name,
              "error.message" => e.message
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
        
        # Skip common non-business logic endpoints
        path_info.start_with?("/assets/") ||
          path_info.start_with?("/health") ||
          path_info.start_with?("/favicon.ico") ||
          path_info.start_with?("/ping")
      end

      # Create a new request span with Rails metadata.
      #
      # @param env [Hash] Rack environment hash
      # @param tracer [Object] Tracer instance to create span with
      # @return [Span] Created request span
      def create_request_span(env, tracer)
        request = build_request_object(env)
        
        span = tracer.agent_span(
          "rails.request",
          trace_id: generate_trace_id(env),
          parent_id: nil # Request spans are root spans
        )
        
        # Add basic HTTP attributes
        span.set_attribute("http.method", request.request_method)
        span.set_attribute("http.url", request.url)
        span.set_attribute("http.user_agent", request.user_agent) if request.user_agent
        span.set_attribute("http.remote_addr", request.remote_ip) if request.remote_ip
        
        # Add Rails-specific attributes
        add_rails_attributes(span, env)
        
        # Add request start event
        span.add_event("request.start", {
          "request.size" => env["CONTENT_LENGTH"]&.to_i || 0
        })
        
        span
      end

      # Update span with response information after request processing.
      #
      # @param span [Span] Request span to update
      # @param env [Hash] Rack environment hash
      # @param status [Integer] HTTP status code
      # @param headers [Hash] Response headers
      def update_span_with_response(span, env, status, headers)
        # Set HTTP status
        span.set_attribute("http.status_code", status)
        
        # Set span status based on HTTP status
        if status >= 400
          span.set_status(:error, description: "HTTP #{status}")
        else
          span.set_status(:ok)
        end
        
        # Add response metadata
        span.add_event("request.complete", {
          "response.status" => status,
          "response.content_type" => headers["Content-Type"] || headers["content-type"]
        })
        
        # Add Rails routing information if available
        add_routing_info(span, env)
      end

      # Add Rails-specific attributes to the request span.
      #
      # @param span [Span] Span to add attributes to
      # @param env [Hash] Rack environment hash
      def add_rails_attributes(span, env)
        # Rails request ID for log correlation
        if env["action_dispatch.request_id"]
          span.set_attribute("rails.request_id", env["action_dispatch.request_id"])
        end
        
        # Session information (if available and safe)
        if env["rack.session"] && env["rack.session"]["session_id"]
          span.set_attribute("rails.session_id", env["rack.session"]["session_id"])
        end
      end

      # Add routing information to span after request processing.
      #
      # @param span [Span] Span to update
      # @param env [Hash] Rack environment hash with routing info
      def add_routing_info(span, env)
        # Rails route information (available after routing)
        if env["action_controller.instance"]
          controller = env["action_controller.instance"]
          span.set_attribute("http.controller", controller.class.name)
          span.set_attribute("http.action", controller.action_name)
        end
        
        # Route pattern if available
        if env["action_dispatch.route"] && env["action_dispatch.route"].path
          route_spec = env["action_dispatch.route"].path.spec.to_s
          span.set_attribute("http.route", route_spec) unless route_spec.empty?
        end
      end

      # Generate or extract trace ID for the request.
      #
      # @param env [Hash] Rack environment hash
      # @return [String] Trace ID for this request
      def generate_trace_id(env)
        # Use Rails request ID as basis if available
        request_id = env["action_dispatch.request_id"]
        
        if request_id && request_id.match?(/\A[a-f0-9-]+\z/)
          # Convert Rails UUID format to trace format
          "trace_#{request_id.gsub('-', '')}"
        else
          # Generate new trace ID
          "trace_#{SecureRandom.hex(16)}"
        end
      end

      # Build request object from Rack environment.
      #
      # @param env [Hash] Rack environment hash
      # @return [Object] Request-like object with needed methods
      def build_request_object(env)
        # Create minimal request object to avoid Rails dependencies
        OpenStruct.new(
          request_method: env["REQUEST_METHOD"] || "GET",
          url: build_full_url(env),
          user_agent: env["HTTP_USER_AGENT"],
          remote_ip: extract_remote_ip(env)
        )
      end

      # Build full URL from Rack environment.
      #
      # @param env [Hash] Rack environment hash
      # @return [String] Full request URL
      def build_full_url(env)
        scheme = env["rack.url_scheme"] || "http"
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
        env["HTTP_X_FORWARDED_FOR"]&.split(",")&.first&.strip ||
          env["HTTP_X_REAL_IP"] ||
          env["REMOTE_ADDR"]
      end
    end
  end
end