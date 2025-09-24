# frozen_string_literal: true

require "spec_helper"
require "raaf/tracing/rails_middleware"
require "raaf/tracing/tracing_registry"
require "raaf/tracing/spans"
require "raaf/tracing/trace_provider"

RSpec.describe RAAF::Tracing::RailsMiddleware do
  let(:app) { double("app") }
  let(:tracer) { double("tracer") }
  let(:span) { double("span") }
  let(:middleware) { described_class.new(app, tracer: tracer) }
  let(:env) do
    {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/api/agents",
      "QUERY_STRING" => "q=test",
      "HTTP_HOST" => "example.com",
      "HTTP_USER_AGENT" => "Test Agent",
      "HTTP_X_FORWARDED_FOR" => "192.168.1.100",
      "rack.url_scheme" => "https",
      "action_dispatch.request_id" => "abc123def456",
      "CONTENT_LENGTH" => "100"
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
    context "with custom tracer" do
      it "stores the provided tracer" do
        custom_tracer = double("custom_tracer")
        middleware = described_class.new(app, tracer: custom_tracer)
        
        expect(middleware.instance_variable_get(:@tracer)).to eq(custom_tracer)
      end
    end

    context "without custom tracer" do
      it "stores nil for tracer (will use global tracer)" do
        middleware = described_class.new(app)
        
        expect(middleware.instance_variable_get(:@tracer)).to be_nil
      end
    end
  end

  describe "#call" do
    let(:response) { [200, { "Content-Type" => "application/json" }, ["{}"]] }

    before do
      allow(app).to receive(:call).and_return(response)
    end

    context "normal request processing" do
      it "sets up tracing context using TracingRegistry" do
        expect(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).with(tracer).and_yield
        
        middleware.call(env)
      end

      it "creates request span with Rails metadata" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(tracer).to receive(:agent_span).with(
          "rails.request",
          hash_including(
            trace_id: match(/\Atrace_[a-f0-9]+\z/),
            parent_id: nil
          )
        ).and_return(span)
        
        middleware.call(env)
      end

      it "adds HTTP attributes to span" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("http.method", "GET")
        expect(span).to receive(:set_attribute).with("http.url", "https://example.com/api/agents?q=test")
        expect(span).to receive(:set_attribute).with("http.user_agent", "Test Agent")
        expect(span).to receive(:set_attribute).with("http.remote_addr", "192.168.1.100")
        
        middleware.call(env)
      end

      it "adds Rails-specific attributes" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("rails.request_id", "abc123def456")
        
        middleware.call(env)
      end

      it "adds request start event" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:add_event).with("request.start", {
          "request.size" => 100
        })
        
        middleware.call(env)
      end

      it "processes the request through the app" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(app).to receive(:call).with(env).and_return(response)
        
        result = middleware.call(env)
        expect(result).to eq(response)
      end

      it "updates span with response status" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("http.status_code", 200)
        expect(span).to receive(:set_status).with(:ok)
        
        middleware.call(env)
      end

      it "adds request complete event" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:add_event).with("request.complete", {
          "response.status" => 200,
          "response.content_type" => "application/json"
        })
        
        middleware.call(env)
      end

      it "finishes the span" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:finish)
        
        middleware.call(env)
      end
    end

    context "with Rails routing information" do
      before do
        controller = double("controller", class: double(name: "AgentsController"), action_name: "index")
        route = double("route", path: double(spec: double(to_s: "/api/agents")))
        env["action_controller.instance"] = controller
        env["action_dispatch.route"] = route
      end

      it "adds controller and action attributes" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("http.controller", "AgentsController")
        expect(span).to receive(:set_attribute).with("http.action", "index")
        expect(span).to receive(:set_attribute).with("http.route", "/api/agents")
        
        middleware.call(env)
      end
    end

    context "error handling" do
      let(:error) { StandardError.new("Test error") }

      before do
        allow(app).to receive(:call).and_raise(error)
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
      end

      it "marks span as error and re-raises exception" do
        expect(span).to receive(:set_status).with(:error, description: "Test error")
        expect(span).to receive(:add_event).with("request.error", {
          "error.type" => "StandardError",
          "error.message" => "Test error"
        })
        expect(span).to receive(:finish)
        
        expect { middleware.call(env) }.to raise_error(StandardError, "Test error")
      end
    end

    context "HTTP error responses" do
      let(:error_response) { [404, { "Content-Type" => "text/html" }, ["Not Found"]] }

      before do
        allow(app).to receive(:call).and_return(error_response)
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
      end

      it "marks span as error for 4xx status" do
        expect(span).to receive(:set_attribute).with("http.status_code", 404)
        expect(span).to receive(:set_status).with(:error, description: "HTTP 404")
        
        middleware.call(env)
      end
    end

    context "server error responses" do
      let(:server_error_response) { [500, { "Content-Type" => "text/html" }, ["Internal Server Error"]] }

      before do
        allow(app).to receive(:call).and_return(server_error_response)
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
      end

      it "marks span as error for 5xx status" do
        expect(span).to receive(:set_attribute).with("http.status_code", 500)
        expect(span).to receive(:set_status).with(:error, description: "HTTP 500")
        
        middleware.call(env)
      end
    end

    context "skipped paths" do
      ["/assets/application.js", "/health", "/favicon.ico", "/ping"].each do |path|
        it "skips tracing for #{path}" do
          env["PATH_INFO"] = path
          
          expect(RAAF::Tracing::TracingRegistry).not_to receive(:with_tracer)
          expect(tracer).not_to receive(:agent_span)
          
          middleware.call(env)
        end
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

    context "session information" do
      before do
        env["rack.session"] = { "session_id" => "sess_12345" }
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
      end

      it "adds session ID attribute" do
        expect(span).to receive(:set_attribute).with("rails.session_id", "sess_12345")
        
        middleware.call(env)
      end
    end
  end

  describe "URL building" do
    let(:response) { [200, { "Content-Type" => "application/json" }, ["{}"]]}

    before do
      allow(app).to receive(:call).and_return(response)
    end

    context "with standard ports" do
      it "omits port for HTTP on 80" do
        env.merge!("rack.url_scheme" => "http", "HTTP_HOST" => "example.com", "SERVER_PORT" => "80")
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("http.url", "http://example.com/api/agents?q=test")
        
        middleware.call(env)
      end

      it "omits port for HTTPS on 443" do
        env.merge!("rack.url_scheme" => "https", "HTTP_HOST" => "example.com", "SERVER_PORT" => "443")
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("http.url", "https://example.com/api/agents?q=test")
        
        middleware.call(env)
      end
    end

    context "with non-standard ports" do
      it "includes port for HTTP on non-80" do
        env.merge!("rack.url_scheme" => "http", "HTTP_HOST" => "example.com", "SERVER_PORT" => "3000")
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("http.url", "http://example.com:3000/api/agents?q=test")
        
        middleware.call(env)
      end
    end
  end

  describe "IP address extraction" do
    let(:response) { [200, { "Content-Type" => "application/json" }, ["{}"]]}

    before do
      allow(app).to receive(:call).and_return(response)
    end

    context "with X-Forwarded-For header" do
      it "extracts first IP from forwarded chain" do
        env["HTTP_X_FORWARDED_FOR"] = "192.168.1.100, 10.0.0.1, 172.16.0.1"
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("http.remote_addr", "192.168.1.100")
        
        middleware.call(env)
      end
    end

    context "with X-Real-IP header" do
      before do
        env.delete("HTTP_X_FORWARDED_FOR")
        env["HTTP_X_REAL_IP"] = "192.168.1.200"
      end

      it "uses X-Real-IP when no X-Forwarded-For" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("http.remote_addr", "192.168.1.200")
        
        middleware.call(env)
      end
    end

    context "with REMOTE_ADDR only" do
      before do
        env.delete("HTTP_X_FORWARDED_FOR")
        env["REMOTE_ADDR"] = "10.0.0.50"
      end

      it "falls back to REMOTE_ADDR" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(span).to receive(:set_attribute).with("http.remote_addr", "10.0.0.50")
        
        middleware.call(env)
      end
    end
  end

  describe "trace ID generation" do
    let(:response) { [200, { "Content-Type" => "application/json" }, ["{}"]]}

    before do
      allow(app).to receive(:call).and_return(response)
    end

    context "with Rails request ID" do
      it "uses Rails request ID for trace ID" do
        env["action_dispatch.request_id"] = "abc123-def456-789"
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(tracer).to receive(:agent_span).with(
          "rails.request",
          hash_including(trace_id: "trace_abc123def456789")
        )
        
        middleware.call(env)
      end
    end

    context "without Rails request ID" do
      before { env.delete("action_dispatch.request_id") }

      it "generates new trace ID" do
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(tracer).to receive(:agent_span).with(
          "rails.request",
          hash_including(trace_id: match(/\Atrace_[a-f0-9]{32}\z/))
        )
        
        middleware.call(env)
      end
    end

    context "with invalid Rails request ID" do
      it "generates new trace ID for invalid format" do
        env["action_dispatch.request_id"] = "invalid@#$%"
        allow(RAAF::Tracing::TracingRegistry).to receive(:with_tracer).and_yield
        
        expect(tracer).to receive(:agent_span).with(
          "rails.request",
          hash_including(trace_id: match(/\Atrace_[a-f0-9]{32}\z/))
        )
        
        middleware.call(env)
      end
    end
  end

  describe "thread safety" do
    it "isolates tracer context across concurrent requests" do
      tracer1 = double("tracer1")
      tracer2 = double("tracer2")
      span1 = double("span1")
      span2 = double("span2")
      
      allow(tracer1).to receive(:agent_span).and_return(span1)
      allow(tracer2).to receive(:agent_span).and_return(span2)
      allow(span1).to receive(:set_attribute)
      allow(span1).to receive(:add_event)
      allow(span1).to receive(:set_status)
      allow(span1).to receive(:finish)
      allow(span2).to receive(:set_attribute)
      allow(span2).to receive(:add_event)
      allow(span2).to receive(:set_status)
      allow(span2).to receive(:finish)
      
      middleware1 = described_class.new(app, tracer: tracer1)
      middleware2 = described_class.new(app, tracer: tracer2)
      
      threads = []
      results = []
      
      threads << Thread.new do
        results << middleware1.call(env.dup)
      end
      
      threads << Thread.new do
        results << middleware2.call(env.dup)
      end
      
      threads.each(&:join)
      
      expect(results.size).to eq(2)
      expect(results.all? { |r| r == response }).to be true
    end
  end
end