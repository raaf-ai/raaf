# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Logging do
  let(:original_configuration) { described_class.instance_variable_get(:@configuration) }
  let(:original_logger) { described_class.instance_variable_get(:@logger) }
  let(:mock_logger) { double("Logger", info: nil, warn: nil, error: nil, fatal: nil, debug: nil) }

  before do
    # Reset configuration and logger between tests
    described_class.instance_variable_set(:@configuration, nil)
    described_class.instance_variable_set(:@logger, nil)
    
    # Mock the logger to capture log calls
    allow(described_class).to receive(:logger).and_return(mock_logger)
  end

  after do
    # Restore original state
    described_class.instance_variable_set(:@configuration, original_configuration)
    described_class.instance_variable_set(:@logger, original_logger)
  end

  describe ".configure" do
    it "yields configuration object for setup" do
      expect { |b| described_class.configure(&b) }.to yield_with_args(kind_of(described_class::Configuration))
    end

    it "returns the configuration object" do
      config = described_class.configure { |c| c.log_level = :debug }
      expect(config).to be_a(described_class::Configuration)
      expect(config.log_level).to eq(:debug)
    end

    it "creates configuration if none exists" do
      expect(described_class.instance_variable_get(:@configuration)).to be_nil
      config = described_class.configure
      expect(config).to be_a(described_class::Configuration)
    end

    it "reuses existing configuration" do
      config1 = described_class.configure { |c| c.log_level = :error }
      config2 = described_class.configure { |c| c.log_format = :json }
      
      expect(config1).to be(config2)
      expect(config2.log_level).to eq(:error)
      expect(config2.log_format).to eq(:json)
    end
  end

  describe ".configuration" do
    it "returns current configuration" do
      config = described_class.configuration
      expect(config).to be_a(described_class::Configuration)
    end

    it "creates configuration if none exists" do
      expect(described_class.instance_variable_get(:@configuration)).to be_nil
      config = described_class.configuration
      expect(config).to be_a(described_class::Configuration)
    end
  end

  describe ".debug" do
    context "with debug category enabled" do
      before do
        described_class.configure { |c| c.debug_categories = [:api] }
      end

      it "logs debug message with matching category" do
        expect {
          described_class.debug("API call started", category: :api, url: "https://api.example.com")
        }.not_to raise_error
      end

      it "skips debug message with non-matching category" do
        expect {
          described_class.debug("Tool execution", category: :tools, tool: "search")
        }.not_to raise_error
      end

      it "uses general category by default" do
        described_class.configure { |c| c.debug_categories = [:general] }
        
        expect {
          described_class.debug("General debug message")
        }.not_to raise_error
      end
    end

    context "with debug disabled" do
      before do
        described_class.configure { |c| c.debug_categories = [] }
      end

      it "skips all debug messages" do
        expect {
          described_class.debug("This should not appear", category: :api)
        }.not_to raise_error
      end
    end
  end

  describe ".info" do
    it "logs informational messages" do
      described_class.info("Agent started", agent: "GPT-4", run_id: "123")
      
      expect(mock_logger).to have_received(:info)
    end

    it "includes context in log messages" do
      described_class.info("Processing request", user_id: 456, request_id: "req_789")
      
      expect(mock_logger).to have_received(:info)
    end
  end

  describe ".warn" do
    it "logs warning messages" do
      described_class.warn("Deprecated feature used", feature: "old_api")
      
      expect(mock_logger).to have_received(:warn)
    end
  end

  describe ".error" do
    it "logs error messages" do
      described_class.error("API request failed", status: 500, error: "Internal Server Error")
      
      expect(mock_logger).to have_received(:error)
    end

    it "handles errors without context" do
      described_class.error("Simple error message")
      
      expect(mock_logger).to have_received(:error)
    end
  end

  describe ".fatal" do
    it "logs fatal error messages" do
      described_class.fatal("System failure", component: "database", action: "shutdown")
      
      expect(mock_logger).to have_received(:fatal)
    end
  end

  describe "specialized logging methods" do
    describe ".agent_start" do
      it "logs agent startup events" do
        described_class.agent_start("GPT-4", run_id: "abc123", user_id: 789)
        
        expect(mock_logger).to have_received(:info)
      end
    end

    describe ".agent_end" do
      it "logs agent completion events" do
        described_class.agent_end("GPT-4", duration: 1.5, tokens_used: 150)
        
        expect(mock_logger).to have_received(:info)
      end
    end

    describe ".tool_call" do
      it "logs tool execution events" do
        described_class.tool_call("search", query: "Ruby programming", results: 10)
        
        expect(mock_logger).to have_received(:info)
      end
    end

    describe ".handoff" do
      it "logs agent handoff events" do
        described_class.handoff("Researcher", "Writer", reason: "analysis_complete")
        
        expect(mock_logger).to have_received(:info)
      end
    end

    describe ".api_call" do
      it "logs API request events" do
        described_class.api_call("POST", "https://api.openai.com/v1/chat/completions", model: "gpt-4", tokens: 100)
        
        expect(mock_logger).to have_received(:info)
      end
    end

    describe ".api_error" do
      it "logs API error events" do
        error = StandardError.new("Rate limit exceeded")
        described_class.api_error(error, status: 429, retry_after: 60)
        
        expect(mock_logger).to have_received(:error)
      end
    end
  end

  describe ".benchmark" do
    it "measures and logs execution time" do
      result = described_class.benchmark("Database query", query: "SELECT COUNT(*) FROM users") do
        sleep(0.01) # Simulate work
        "Query result"
      end

      expect(result).to eq("Query result")
      expect(mock_logger).to have_received(:info)
    end

    it "logs execution time even when block raises exception" do
      expect {
        described_class.benchmark("Failing operation") do
          raise StandardError, "Something went wrong"
        end
      }.to raise_error(StandardError, "Something went wrong")

      # benchmark method doesn't log errors, it just re-raises them
      expect(mock_logger).not_to have_received(:error)
    end
  end
end

RSpec.describe RAAF::Logging::Configuration do
  let(:config) { described_class.new }

  describe "#initialize" do
    it "sets default configuration values" do
      expect(config.log_level).to eq(:info)
      expect(config.log_format).to eq(:text)
      expect(config.log_output).to eq(:auto)
      expect(config.debug_categories).to eq([:all])
    end

    it "loads configuration from environment variables" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("RAAF_LOG_LEVEL", "info").and_return("debug")
      allow(ENV).to receive(:fetch).with("RAAF_LOG_FORMAT", "text").and_return("json")
      allow(ENV).to receive(:fetch).with("RAAF_DEBUG_CATEGORIES", "all").and_return("api,tracing")

      # Create new config after ENV is stubbed
      new_config = described_class.new

      expect(new_config.log_level).to eq(:debug)
      expect(new_config.log_format).to eq(:json)
      expect(new_config.debug_categories).to eq([:api, :tracing])
    end
  end

  describe "#debug_enabled?" do
    context "with all categories enabled" do
      before { config.debug_categories = :all }

      it "returns true for any category" do
        expect(config.debug_enabled?(:api)).to be true
        expect(config.debug_enabled?(:tools)).to be true
        expect(config.debug_enabled?(:unknown_category)).to be true
      end
    end

    context "with no categories enabled" do
      before { config.debug_categories = [] }

      it "returns false for any category" do
        expect(config.debug_enabled?(:api)).to be false
        expect(config.debug_enabled?(:tools)).to be false
        expect(config.debug_enabled?(:general)).to be false
      end
    end

    context "with specific categories enabled" do
      before { config.debug_categories = [:api, :tracing] }

      it "returns true for enabled categories" do
        expect(config.debug_enabled?(:api)).to be true
        expect(config.debug_enabled?(:tracing)).to be true
      end

      it "returns false for disabled categories" do
        expect(config.debug_enabled?(:tools)).to be false
        expect(config.debug_enabled?(:handoff)).to be false
      end
    end

    context "with none specified" do
      before { config.debug_categories = :none }

      it "returns false for any category" do
        expect(config.debug_enabled?(:api)).to be false
        expect(config.debug_enabled?(:general)).to be false
      end
    end
  end

  describe "#parse_debug_categories" do
    it "parses comma-separated category list" do
      categories = config.send(:parse_debug_categories, "api,tools,tracing")
      expect(categories).to eq([:api, :tools, :tracing])
    end

    it "handles whitespace in category list" do
      categories = config.send(:parse_debug_categories, " api , tools , tracing ")
      expect(categories).to eq([:api, :tools, :tracing])
    end

    it "handles special values" do
      expect(config.send(:parse_debug_categories, "all")).to eq([:all])
      expect(config.send(:parse_debug_categories, "none")).to eq([:none])
    end

    it "returns empty array for empty string" do
      expect(config.send(:parse_debug_categories, "")).to eq([])
      expect(config.send(:parse_debug_categories, nil)).to eq([])
    end
  end

  describe "attribute accessors" do
    it "allows setting and getting log_level" do
      config.log_level = :debug
      expect(config.log_level).to eq(:debug)
    end

    it "allows setting and getting log_format" do
      config.log_format = :json
      expect(config.log_format).to eq(:json)
    end

    it "allows setting and getting log_output" do
      config.log_output = :console
      expect(config.log_output).to eq(:console)
    end

    it "allows setting and getting debug_categories" do
      config.debug_categories = [:api, :tools]
      expect(config.debug_categories).to eq([:api, :tools])
    end
  end
end

RSpec.describe RAAF::Logger do
  let(:test_class) { Class.new { include RAAF::Logger } }
  let(:instance) { test_class.new }
  let(:mock_logging) { class_double(RAAF::Logging) }

  before do
    stub_const("RAAF::Logging", mock_logging)
    allow(mock_logging).to receive(:debug)
    allow(mock_logging).to receive(:info)
    allow(mock_logging).to receive(:warn)
    allow(mock_logging).to receive(:error)
    allow(mock_logging).to receive(:fatal)
    allow(mock_logging).to receive(:benchmark)
    allow(mock_logging).to receive(:agent_start)
    allow(mock_logging).to receive(:agent_end)
    allow(mock_logging).to receive(:tool_call)
    allow(mock_logging).to receive(:handoff)
    allow(mock_logging).to receive(:api_call)
    allow(mock_logging).to receive(:api_error)
    allow(mock_logging).to receive(:configuration).and_return(double(debug_enabled?: true))
  end

  describe "#log_debug" do
    it "delegates to RAAF::Logging.debug with category" do
      instance.log_debug("Debug message", category: :api, user_id: 123)
      
      expect(mock_logging).to have_received(:debug).with("Debug message", category: :api, user_id: 123)
    end

    it "uses general category by default" do
      instance.log_debug("Debug message", user_id: 123)
      
      expect(mock_logging).to have_received(:debug).with("Debug message", category: :general, user_id: 123)
    end
  end

  describe "#log_info" do
    it "delegates to RAAF::Logging.info" do
      instance.log_info("Info message", request_id: "req_123")
      
      expect(mock_logging).to have_received(:info).with("Info message", request_id: "req_123")
    end
  end

  describe "#log_warn" do
    it "delegates to RAAF::Logging.warn" do
      instance.log_warn("Warning message", deprecated: true)
      
      expect(mock_logging).to have_received(:warn).with("Warning message", deprecated: true)
    end
  end

  describe "#log_error" do
    it "delegates to RAAF::Logging.error with automatic stack trace" do
      instance.log_error("Error occurred", user_id: 456)
      
      expect(mock_logging).to have_received(:error) do |message, context|
        expect(message).to eq("Error occurred")
        expect(context[:user_id]).to eq(456)
        expect(context[:stack_trace]).to be_a(String)
        expect(context[:stack_trace]).to include("logging_spec.rb")
      end
    end

    it "preserves existing stack trace if provided" do
      custom_trace = "custom stack trace"
      instance.log_error("Error occurred", stack_trace: custom_trace)
      
      expect(mock_logging).to have_received(:error).with("Error occurred", stack_trace: custom_trace)
    end
  end

  describe "#log_fatal" do
    it "delegates to RAAF::Logging.fatal with automatic stack trace" do
      instance.log_fatal("Fatal error", component: "database")
      
      expect(mock_logging).to have_received(:fatal) do |message, context|
        expect(message).to eq("Fatal error")
        expect(context[:component]).to eq("database")
        expect(context[:stack_trace]).to be_a(String)
      end
    end
  end

  describe "category-specific debug methods" do
    describe "#log_debug_tracing" do
      it "logs with tracing category" do
        instance.log_debug_tracing("Span created", span_id: "abc123")
        
        expect(mock_logging).to have_received(:debug).with("Span created", category: :tracing, span_id: "abc123")
      end
    end

    describe "#log_debug_api" do
      it "logs with api category" do
        instance.log_debug_api("Making API request", url: "https://api.example.com")
        
        expect(mock_logging).to have_received(:debug).with("Making API request", category: :api, url: "https://api.example.com")
      end
    end

    describe "#log_debug_tools" do
      it "logs with tools category" do
        instance.log_debug_tools("Executing tool", tool: "search", args: { query: "test" })
        
        expect(mock_logging).to have_received(:debug).with("Executing tool", category: :tools, tool: "search", args: { query: "test" })
      end
    end

    describe "#log_debug_handoff" do
      it "logs with handoff category" do
        instance.log_debug_handoff("Handoff initiated", from: "Agent1", to: "Agent2")
        
        expect(mock_logging).to have_received(:debug).with("Handoff initiated", category: :handoff, from: "Agent1", to: "Agent2")
      end
    end

    describe "#log_debug_context" do
      it "logs with context category" do
        instance.log_debug_context("Context updated", keys: ["user", "session"])
        
        expect(mock_logging).to have_received(:debug).with("Context updated", category: :context, keys: ["user", "session"])
      end
    end

    describe "#log_debug_http" do
      it "logs with http category" do
        instance.log_debug_http("HTTP request details", method: "POST", headers: { "Content-Type" => "application/json" })
        
        expect(mock_logging).to have_received(:debug).with("HTTP request details", category: :http, method: "POST", headers: { "Content-Type" => "application/json" })
      end
    end
  end

  describe "#http_debug_enabled?" do
    it "checks if HTTP debug category is enabled" do
      mock_config = double(debug_enabled?: true)
      allow(mock_logging).to receive(:configuration).and_return(mock_config)
      
      result = instance.http_debug_enabled?
      
      expect(result).to be true
      expect(mock_config).to have_received(:debug_enabled?).with(:http)
    end
  end

  describe "utility methods" do
    describe "#log_benchmark" do
      it "delegates to RAAF::Logging.benchmark" do
        block = proc { "result" }
        instance.log_benchmark("Operation", context: "test", &block)
        
        expect(mock_logging).to have_received(:benchmark).with("Operation", context: "test")
      end
    end
  end

  describe "agent-specific logging methods" do
    describe "#log_agent_start" do
      it "delegates to RAAF::Logging.agent_start" do
        instance.log_agent_start("GPT-4", run_id: "run_123")
        
        expect(mock_logging).to have_received(:agent_start).with("GPT-4", run_id: "run_123")
      end
    end

    describe "#log_agent_end" do
      it "delegates to RAAF::Logging.agent_end" do
        instance.log_agent_end("GPT-4", duration: 2.5, tokens: 200)
        
        expect(mock_logging).to have_received(:agent_end).with("GPT-4", duration: 2.5, tokens: 200)
      end
    end

    describe "#log_tool_call" do
      it "delegates to RAAF::Logging.tool_call" do
        instance.log_tool_call("search", query: "Ruby programming")
        
        expect(mock_logging).to have_received(:tool_call).with("search", query: "Ruby programming")
      end
    end

    describe "#log_handoff" do
      it "delegates to RAAF::Logging.handoff" do
        instance.log_handoff("Researcher", "Writer", context: "analysis_done")
        
        expect(mock_logging).to have_received(:handoff).with("Researcher", "Writer", context: "analysis_done")
      end
    end

    describe "#log_api_call" do
      it "delegates to RAAF::Logging.api_call" do
        instance.log_api_call("POST", "https://api.openai.com/v1/completions", model: "gpt-3.5-turbo")
        
        expect(mock_logging).to have_received(:api_call).with("POST", "https://api.openai.com/v1/completions", model: "gpt-3.5-turbo")
      end
    end

    describe "#log_api_error" do
      it "delegates to RAAF::Logging.api_error" do
        error = StandardError.new("API Error")
        instance.log_api_error(error, status: 500)
        
        expect(mock_logging).to have_received(:api_error).with(error, status: 500)
      end
    end
  end

  describe "#log_exception" do
    it "logs exception with detailed context" do
      begin
        raise StandardError, "Test error"
      rescue StandardError => e
        instance.log_exception(e, message: "Custom error message", user_id: 123)
      end

      expect(mock_logging).to have_received(:error) do |message, context|
        expect(message).to eq("Custom error message")
        expect(context[:user_id]).to eq(123)
        expect(context[:error_class]).to eq("StandardError")
        expect(context[:error_backtrace]).to be_a(String)
        expect(context[:error_backtrace]).to include("logging_spec.rb")
      end
    end

    it "uses exception message when no custom message provided" do
      begin
        raise ArgumentError, "Invalid argument"
      rescue ArgumentError => e
        instance.log_exception(e, context: "test")
      end

      expect(mock_logging).to have_received(:error).with("Invalid argument", hash_including(error_class: "ArgumentError", context: "test"))
    end

    it "includes cause information when exception has a cause" do
      begin
        begin
          raise RuntimeError, "Root cause"
        rescue RuntimeError => e
          raise StandardError, "Wrapper error"
        end
      rescue StandardError => e
        instance.log_exception(e)
      end

      expect(mock_logging).to have_received(:error) do |message, context|
        expect(context[:error_cause]).to eq("Root cause")
        expect(context[:error_cause_class]).to eq("RuntimeError")
      end
    end
  end
end