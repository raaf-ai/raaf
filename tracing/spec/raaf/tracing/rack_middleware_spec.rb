# frozen_string_literal: true

require "spec_helper"
require "raaf/tracing/rack_middleware"
require "raaf/tracing/tracing_registry"
require "raaf/tracing/spans"
require "raaf/tracing/trace_provider"

RSpec.describe RAAF::Tracing::RackMiddleware do
  let(:app) { double("app") }
  let(:tracer) { double("tracer") }
  let(:span) { double("span") }
  let(:middleware) { described_class.new(app, tracer: tracer) }
  let(:env) do
    {
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => "/api/chat",
      "QUERY_STRING" => "format=json",
      "HTTP_HOST" => "api.example.com",
      "HTTP_USER_AGENT" => "ChatBot/1.0",
      "HTTP_X_FORWARDED_FOR" => "203.0.113.1",
      "HTTP_ACCEPT" => "application/json",
      "CONTENT_TYPE" => "application/json",
      "CONTENT_LENGTH" => "256",
      "SERVER_NAME" => "api.example.com",
      "SERVER_PORT" => "443",
      "HTTP_VERSION" => "HTTP/1.1",
      "rack.url_scheme" => "https",
      "REMOTE_ADDR" => "192.168.1.10"
    }
  end

  before do
    allow(tracer).to receive(:agent_span).and_return(span)
    allow(span).to receive(:set_attribute)
    allow(span).to receive(:add_event)
    allow(span).to receive(:set_status)
    allow(span).to receive(:finish)
  end

  describe "#initialize" do
    context "with default options" do
      let(:middleware) { described_class.new(app) }

      it "uses default span name" do
        expect(middleware.instance_variable_get(:@span_name)).to eq("http.request")
      end

      it "uses default skip paths" do
        skip_paths = middleware.instance_variable_get(:@skip_paths)
        expect(skip_paths).to include("/favicon.ico", "/health", "/ping")
      end

      it "stores nil for tracer" do
        expect(middleware.instance_variable_get(:@tracer)).to be_nil
      end
    end

    context "with custom options" do
      let(:custom_tracer) { double("custom_tracer") }
      let(:custom_skip_paths) { ["/status", "/metrics"] }
      let(:middleware) do
        described_class.new(
          app,
          tracer: custom_tracer,
          span_name: "microservice.request",
          skip_paths: custom_skip_paths
        )
      end

      it "stores custom tracer" do
        expect(middleware.instance_variable_get(:@tracer)).to eq(custom_tracer)
      end

      it "uses custom span name" do
        expect(middleware.instance_variable_get(:@span_name)).to eq("microservice.request")
      end

      it "uses custom skip paths" do
        expect(middleware.instance_variable_get(:@skip_paths)).to eq(custom_skip_paths)
      end
    end
  end

  describe "#call" do
    let(:response) { [201, { "Content-Type" => "application/json", "Content-Length" => "123" }, ['{"success": true}']] }

    before do
      allow(app).to receive(:call).and_return(response)
    end

    context "normal request processing" do
      it "sets up tracing context using TracingRegistry" do
        expect(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).with(tracer).and_yield
        
        middleware.call(env)
      end

      it "creates request span with HTTP metadata" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(tracer).to receive(:agent_span).with(
          "http.request",
          hash_including(
            trace_id: match(/\Atrace_[a-f0-9]+\z/),
            parent_id: nil
          )
        ).and_return(span)
        
        middleware.call(env)
      end

      it "adds HTTP attributes to span" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("http.method", "POST")
        expect(span).to receive(:set_attribute).with("http.url", "https://api.example.com/api/chat?format=json")
        expect(span).to receive(:set_attribute).with("http.path", "/api/chat")
        expect(span).to receive(:set_attribute).with("http.user_agent", "ChatBot/1.0")
        expect(span).to receive(:set_attribute).with("http.content_type", "application/json")
        expect(span).to receive(:set_attribute).with("http.content_length", 256)
        expect(span).to receive(:set_attribute).with("http.accept", "application/json")
        
        middleware.call(env)
      end

      it "adds request metadata" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("http.remote_addr", "203.0.113.1")
        expect(span).to receive(:set_attribute).with("http.server_name", "api.example.com")
        expect(span).to receive(:set_attribute).with("http.server_port", 443)
        expect(span).to receive(:set_attribute).with("http.version", "HTTP/1.1")
        expect(span).to receive(:set_attribute).with("http.scheme", "https")
        
        middleware.call(env)
      end

      it "adds request start event" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:add_event).with("request.start", {
          "request.path" => "/api/chat",
          "request.query" => "format=json"
        })
        
        middleware.call(env)
      end

      it "processes the request through the app" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(app).to receive(:call).with(env).and_return(response)
        
        result = middleware.call(env)
        expect(result).to eq(response)
      end

      it "updates span with response information" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("http.status_code", 201)
        expect(span).to receive(:set_attribute).with("http.response_content_type", "application/json")
        expect(span).to receive(:set_attribute).with("http.response_content_length", 123)
        expect(span).to receive(:set_status).with(:ok)
        
        middleware.call(env)
      end

      it "adds request complete event" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:add_event).with("request.complete", {
          "response.status" => 201
        })
        
        middleware.call(env)
      end

      it "finishes the span" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:finish)
        
        middleware.call(env)
      end
    end

    context "with custom span name" do
      let(:middleware) { described_class.new(app, tracer: tracer, span_name: "api.request") }

      it "uses custom span name" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(tracer).to receive(:agent_span).with(
          "api.request",
          hash_including(trace_id: match(/\Atrace_[a-f0-9]+\z/))
        )
        
        middleware.call(env)
      end
    end

    context "error handling" do
      let(:error) { RuntimeError.new("API Error") }
      let(:backtrace) { [
        "/app/controllers/api_controller.rb:42:in `create'",
        "/app/middleware/auth.rb:15:in `call'",
        "/app/config/application.rb:120:in `run'"
      ] }

      before do
        allow(error).to receive(:backtrace).and_return(backtrace)
        allow(app).to receive(:call).and_raise(error)
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
      end

      it "marks span as error with details and re-raises exception" do
        expect(span).to receive(:set_status).with(:error, description: "API Error")
        expect(span).to receive(:add_event).with("request.error", {
          "error.type" => "RuntimeError",
          "error.message" => "API Error",
          "error.backtrace" => backtrace.first(5)
        })
        expect(span).to receive(:finish)
        
        expect { middleware.call(env) }.to raise_error(RuntimeError, "API Error")
      end
    end

    context "HTTP status error handling" do
      [
        [400, "Client error: 400"],
        [401, "Client error: 401"],
        [404, "Client error: 404"],
        [422, "Client error: 422"],
        [500, "Server error: 500"],
        [502, "Server error: 502"],
        [503, "Server error: 503"]
      ].each do |status_code, expected_description|
        context "with #{status_code} response" do
          let(:error_response) { [status_code, { "Content-Type" => "text/plain" }, ["Error"]] }

          before do
            allow(app).to receive(:call).and_return(error_response)
            allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
          end

          it "marks span as error" do
            expect(span).to receive(:set_attribute).with("http.status_code", status_code)
            expect(span).to receive(:set_status).with(:error, description: expected_description)
            
            middleware.call(env)
          end
        end
      end

      context "with successful 2xx response" do
        [200, 201, 202, 204].each do |status_code|
          context "with #{status_code} response" do
            let(:success_response) { [status_code, {}, ["OK"]] }

            before do
              allow(app).to receive(:call).and_return(success_response)
              allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
            end

            it "marks span as ok" do
              expect(span).to receive(:set_attribute).with("http.status_code", status_code)
              expect(span).to receive(:set_status).with(:ok)
              
              middleware.call(env)
            end
          end
        end
      end

      context "with unknown status code" do
        let(:unknown_response) { [999, {}, ["Unknown"]] }

        before do
          allow(app).to receive(:call).and_return(unknown_response)
          allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        end

        it "defaults to ok status" do
          expect(span).to receive(:set_attribute).with("http.status_code", 999)
          expect(span).to receive(:set_status).with(:ok)
          
          middleware.call(env)
        end
      end
    end

    context "skipped paths" do
      described_class::DEFAULT_SKIP_PATHS.each do |path|
        it "skips tracing for #{path}" do
          env["PATH_INFO"] = path
          
          expect(RAAF::Tracing::TracingRegistry).not_to receive(:with_tracer)
          expect(tracer).not_to receive(:agent_span)
          
          middleware.call(env)
        end
      end
    end

    context "custom skip paths" do
      let(:custom_skip_paths) { ["/status", "/admin/*", "/internal/health"] }
      let(:middleware) { described_class.new(app, tracer: tracer, skip_paths: custom_skip_paths) }

      it "skips exact path matches" do
        env["PATH_INFO"] = "/status"
        
        expect(RAAF::Tracing::TracingRegistry).not_to receive(:with_tracer)
        
        middleware.call(env)
      end

      it "skips wildcard path matches" do
        env["PATH_INFO"] = "/admin/users"
        
        expect(RAAF::Tracing::TracingRegistry).not_to receive(:with_tracer)
        
        middleware.call(env)
      end

      it "processes non-matching paths" do
        env["PATH_INFO"] = "/api/agents"
        
        expect(RAAF::Tracing::TracingRegistry).to receive(:with_tracer)
        
        middleware.call(env)
      end
    end

    context "without custom tracer" do
      let(:global_tracer) { double("global_tracer") }
      let(:middleware) { described_class.new(app) }

      before do
        allow(RAAF::Tracing::TraceProvider).to receive(:tracer).and_return(global_tracer)
        allow(global_tracer).to receive(:agent_span).and_return(span)
      end

      it "uses global tracer from TraceProvider" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).with(global_tracer)
        
        middleware.call(env)
      end
    end
  end

  describe "URL building" do
    let(:response) { [200, { "Content-Type" => "application/json" }, ["{}"]]}

    before do
      allow(app).to receive(:call).and_return(response)
      allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
    end

    context "with standard ports" do
      it "omits port for HTTP on 80" do
        env.merge!("rack.url_scheme" => "http", "HTTP_HOST" => "example.com", "SERVER_PORT" => "80")
        
        expect(span).to receive(:set_attribute).with("http.url", "http://example.com/api/chat?format=json")
        
        middleware.call(env)
      end

      it "omits port for HTTPS on 443" do
        env.merge!("rack.url_scheme" => "https", "HTTP_HOST" => "example.com", "SERVER_PORT" => "443")
        
        expect(span).to receive(:set_attribute).with("http.url", "https://example.com/api/chat?format=json")
        
        middleware.call(env)
      end
    end

    context "with non-standard ports" do
      it "includes port for HTTP on non-80" do
        env.merge!("rack.url_scheme" => "http", "HTTP_HOST" => "example.com", "SERVER_PORT" => "8080")
        
        expect(span).to receive(:set_attribute).with("http.url", "http://example.com:8080/api/chat?format=json")
        
        middleware.call(env)
      end

      it "includes port for HTTPS on non-443" do
        env.merge!("rack.url_scheme" => "https", "HTTP_HOST" => "example.com", "SERVER_PORT" => "8443")
        
        expect(span).to receive(:set_attribute).with("http.url", "https://example.com:8443/api/chat?format=json")
        
        middleware.call(env)
      end
    end

    context "with forwarded protocol" do
      it "uses X-Forwarded-Proto header" do
        env.merge!(
          "rack.url_scheme" => "http",
          "HTTP_X_FORWARDED_PROTO" => "https",
          "HTTP_HOST" => "example.com"
        )
        
        expect(span).to receive(:set_attribute).with("http.url", "https://example.com/api/chat?format=json")
        
        middleware.call(env)
      end
    end

    context "without query string" do
      before { env["QUERY_STRING"] = "" }

      it "builds URL without query parameter" do
        expect(span).to receive(:set_attribute).with("http.url", "https://api.example.com/api/chat")
        
        middleware.call(env)
      end
    end
  end

  describe "IP address extraction" do
    let(:response) { [200, { "Content-Type" => "application/json" }, ["{}"]]}

    before do
      allow(app).to receive(:call).and_return(response)
      allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
    end

    context "with X-Forwarded-For header" do
      it "extracts first IP from forwarded chain" do
        env["HTTP_X_FORWARDED_FOR"] = "203.0.113.1, 192.168.1.100, 10.0.0.1"
        
        expect(span).to receive(:set_attribute).with("http.remote_addr", "203.0.113.1")
        
        middleware.call(env)
      end

      it "handles whitespace in forwarded chain" do
        env["HTTP_X_FORWARDED_FOR"] = " 203.0.113.1 , 192.168.1.100 "
        
        expect(span).to receive(:set_attribute).with("http.remote_addr", "203.0.113.1")
        
        middleware.call(env)
      end
    end

    context "with X-Real-IP header" do
      before do
        env.delete("HTTP_X_FORWARDED_FOR")
        env["HTTP_X_REAL_IP"] = "203.0.113.2"
      end

      it "uses X-Real-IP when no X-Forwarded-For" do
        expect(span).to receive(:set_attribute).with("http.remote_addr", "203.0.113.2")
        
        middleware.call(env)
      end
    end

    context "with REMOTE_ADDR only" do
      before do
        env.delete("HTTP_X_FORWARDED_FOR")
        env.delete("HTTP_X_REAL_IP")
        env["REMOTE_ADDR"] = "192.168.1.50"
      end

      it "falls back to REMOTE_ADDR" do
        expect(span).to receive(:set_attribute).with("http.remote_addr", "192.168.1.50")
        
        middleware.call(env)
      end
    end

    context "without any IP headers" do
      before do
        env.delete("HTTP_X_FORWARDED_FOR")
        env.delete("HTTP_X_REAL_IP")
        env.delete("REMOTE_ADDR")
      end

      it "does not set remote address attribute" do
        expect(span).not_to receive(:set_attribute).with("http.remote_addr", anything)
        
        middleware.call(env)
      end
    end
  end

  describe "trace ID generation" do
    let(:response) { [200, { "Content-Type" => "application/json" }, ["{}"]]}

    before do
      allow(app).to receive(:call).and_return(response)
      allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
    end

    context "with trace ID in X-Trace-ID header" do
      it "uses provided trace ID" do
        env["HTTP_X_TRACE_ID"] = "abc123def456"
        
        expect(tracer).to receive(:agent_span).with(
          "http.request",
          hash_including(trace_id: "trace_abc123def456")
        )
        
        middleware.call(env)
      end
    end

    context "with trace ID in Traceparent header" do
      it "uses traceparent trace ID" do
        env["HTTP_TRACEPARENT"] = "00-abc123def456789-def456-01"
        
        expect(tracer).to receive(:agent_span).with(
          "http.request",
          hash_including(trace_id: "trace_abc123def456789")
        )
        
        middleware.call(env)
      end
    end

    context "without trace headers" do
      it "generates new trace ID" do
        expect(tracer).to receive(:agent_span).with(
          "http.request",
          hash_including(trace_id: match(/\Atrace_[a-f0-9]{32}\z/))
        )
        
        middleware.call(env)
      end
    end

    context "with invalid trace header" do
      it "generates new trace ID for invalid format" do
        env["HTTP_X_TRACE_ID"] = "invalid@#$%"
        
        expect(tracer).to receive(:agent_span).with(
          "http.request",
          hash_including(trace_id: match(/\Atrace_[a-f0-9]{32}\z/))
        )
        
        middleware.call(env)
      end
    end
  end

  describe "thread safety and request isolation" do
    let(:response) { [200, {}, ["OK"]] }
    let(:tracer1) { double("tracer1") }
    let(:tracer2) { double("tracer2") }
    let(:span1) { double("span1") }
    let(:span2) { double("span2") }
    let(:middleware1) { described_class.new(app, tracer: tracer1) }
    let(:middleware2) { described_class.new(app, tracer: tracer2) }

    before do
      allow(tracer1).to receive(:agent_span).and_return(span1)
      allow(tracer2).to receive(:agent_span).and_return(span2)
      [span1, span2].each do |span|
        allow(span).to receive(:set_attribute)
        allow(span).to receive(:add_event)
        allow(span).to receive(:set_status)
        allow(span).to receive(:finish)
      end
    end

    it "isolates tracer context across concurrent requests" do
      allow(app).to receive(:call) do |request_env|
        # Simulate some processing time
        sleep(0.01)
        [200, {}, [request_env["PATH_INFO"]]]
      end
      
      env1 = env.merge("PATH_INFO" => "/request1")
      env2 = env.merge("PATH_INFO" => "/request2")
      
      threads = []
      results = []
      
      threads << Thread.new do
        results << middleware1.call(env1)
      end
      
      threads << Thread.new do
        results << middleware2.call(env2)
      end
      
      threads.each(&:join)
      
      expect(results.size).to eq(2)
      expect(results[0][2]).to eq(["/request1"])
      expect(results[1][2]).to eq(["/request2"])
      
      # Verify each middleware used its own tracer
      expect(tracer1).to have_received(:agent_span).once
      expect(tracer2).to have_received(:agent_span).once
    end
  end

  describe "response header handling" do
    let(:response) do
      [
        200,
        {
          "Content-Type" => "application/json; charset=utf-8",
          "Content-Length" => "456",
          "Cache-Control" => "no-cache, private"
        },
        ['{\'data\': \'test\'}']
      ]
    end

    before do
      allow(app).to receive(:call).and_return(response)
      allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
    end

    it "adds response content type" do
      expect(span).to receive(:set_attribute).with("http.response_content_type", "application/json; charset=utf-8")
      
      middleware.call(env)
    end

    it "adds response content length" do
      expect(span).to receive(:set_attribute).with("http.response_content_length", 456)
      
      middleware.call(env)
    end

    it "adds cache control header" do
      expect(span).to receive(:set_attribute).with("http.response_cache_control", "no-cache, private")
      
      middleware.call(env)
    end
  end

  describe "integration with RAAF components" do
    let(:response) { [200, {}, ["OK"]] }
    let(:raaf_runner) { double("RAAF::Runner") }
    let(:agent) { double("agent") }

    before do
      # Mock RAAF components that would be called within the app
      allow(app).to receive(:call) do |env|
        # Simulate using RAAF::Runner within the request
        # It should automatically pick up the tracer from TracingRegistry
        current_tracer = RAAF::Tracing::TracingRegistry.current_tracer
        
        # Verify the tracer is available
        expect(current_tracer).to eq(tracer)
        
        response
      end
      
      allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_call_original
    end

    it "makes tracer available to RAAF components through registry" do
      middleware.call(env)
    end
  end
end