# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Logging do
  let(:original_configuration) { described_class.instance_variable_get(:@configuration) }
  let(:original_logger) { described_class.instance_variable_get(:@logger) }

  before do
    # Reset state between tests
    described_class.instance_variable_set(:@configuration, nil)
    described_class.instance_variable_set(:@logger, nil)
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

  describe "logging methods" do
    it "handles debug messages without errors" do
      expect {
        described_class.debug("Debug message", category: :api, url: "test.com")
      }.not_to raise_error
    end

    it "handles info messages without errors" do
      expect {
        described_class.info("Info message", user_id: 123)
      }.not_to raise_error
    end

    it "handles warn messages without errors" do
      expect {
        described_class.warn("Warning message", deprecated: true)
      }.not_to raise_error
    end

    it "handles error messages without errors" do
      expect {
        described_class.error("Error message", status: 500)
      }.not_to raise_error
    end

    it "handles fatal messages without errors" do
      expect {
        described_class.fatal("Fatal message", component: "database")
      }.not_to raise_error
    end
  end

  describe "specialized logging methods" do
    it "handles agent_start without errors" do
      expect {
        described_class.agent_start("GPT-4", run_id: "abc123")
      }.not_to raise_error
    end

    it "handles agent_end without errors" do
      expect {
        described_class.agent_end("GPT-4", duration: 1.5)
      }.not_to raise_error
    end

    it "handles tool_call without errors" do
      expect {
        described_class.tool_call("search", query: "test")
      }.not_to raise_error
    end

    it "handles handoff without errors" do
      expect {
        described_class.handoff("Agent1", "Agent2", reason: "complete")
      }.not_to raise_error
    end

    it "handles api_call without errors" do
      expect {
        described_class.api_call("POST", "https://api.test.com")
      }.not_to raise_error
    end

    it "handles api_error without errors" do
      error = StandardError.new("API Error")
      expect {
        described_class.api_error(error, status: 500)
      }.not_to raise_error
    end
  end

  describe ".benchmark" do
    it "measures execution time and returns block result" do
      result = described_class.benchmark("Test operation") do
        sleep(0.001)
        "operation result"
      end

      expect(result).to eq("operation result")
    end

    it "handles exceptions in benchmarked block" do
      expect {
        described_class.benchmark("Failing operation") do
          raise StandardError, "Test error"
        end
      }.to raise_error(StandardError, "Test error")
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
      expect(config.debug_categories).to eq([:all])  # Default is :all, not :general
    end

    context "with environment variables" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("RAAF_LOG_LEVEL", "info").and_return("debug")
        allow(ENV).to receive(:fetch).with("RAAF_LOG_FORMAT", "text").and_return("json")
        allow(ENV).to receive(:fetch).with("RAAF_DEBUG_CATEGORIES", "all").and_return("api,tracing")
        allow(ENV).to receive(:fetch).with("RAAF_LOG_OUTPUT", "auto").and_call_original
        allow(ENV).to receive(:fetch).with("RAAF_LOG_FILE", "log/raaf.log").and_call_original
      end

      it "loads configuration from environment variables" do
        config = described_class.new

        expect(config.log_level).to eq(:debug)
        expect(config.log_format).to eq(:json)
        expect(config.debug_categories).to eq([:api, :tracing])
      end
    end
  end

  describe "#debug_enabled?" do
    context "with all categories enabled" do
      before { config.debug_categories = [:all] }

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
      before { config.debug_categories = [:none] }

      it "returns false for any category" do
        expect(config.debug_enabled?(:api)).to be false
        expect(config.debug_enabled?(:general)).to be false
      end
    end
  end

  describe "private methods" do
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
      end
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

  describe "logging mixin methods" do
    it "provides log_debug method" do
      expect(instance).to respond_to(:log_debug)
      expect {
        instance.log_debug("Debug message", category: :api)
      }.not_to raise_error
    end

    it "provides log_info method" do
      expect(instance).to respond_to(:log_info)
      expect {
        instance.log_info("Info message", user_id: 123)
      }.not_to raise_error
    end

    it "provides log_warn method" do
      expect(instance).to respond_to(:log_warn)
      expect {
        instance.log_warn("Warning message")
      }.not_to raise_error
    end

    it "provides log_error method" do
      expect(instance).to respond_to(:log_error)
      expect {
        instance.log_error("Error message")
      }.not_to raise_error
    end

    it "provides log_fatal method" do
      expect(instance).to respond_to(:log_fatal)
      expect {
        instance.log_fatal("Fatal message")
      }.not_to raise_error
    end
  end

  describe "category-specific debug methods" do
    it "provides category-specific debug logging methods" do
      expect(instance).to respond_to(:log_debug_tracing)
      expect(instance).to respond_to(:log_debug_api)
      expect(instance).to respond_to(:log_debug_tools)
      expect(instance).to respond_to(:log_debug_handoff)
      expect(instance).to respond_to(:log_debug_context)
      expect(instance).to respond_to(:log_debug_http)
    end

    it "handles category-specific logging without errors" do
      expect {
        instance.log_debug_tracing("Trace message")
        instance.log_debug_api("API message")
        instance.log_debug_tools("Tools message")
        instance.log_debug_handoff("Handoff message")
        instance.log_debug_context("Context message")
        instance.log_debug_http("HTTP message")
      }.not_to raise_error
    end
  end

  describe "#http_debug_enabled?" do
    it "returns boolean value" do
      result = instance.http_debug_enabled?
      expect([true, false]).to include(result)
    end
  end

  describe "utility methods" do
    it "provides log_benchmark method" do
      expect(instance).to respond_to(:log_benchmark)
      result = instance.log_benchmark("Test operation") { "test result" }
      expect(result).to eq("test result")
    end
  end

  describe "agent-specific logging methods" do
    it "provides agent lifecycle logging methods" do
      expect(instance).to respond_to(:log_agent_start)
      expect(instance).to respond_to(:log_agent_end)
      expect(instance).to respond_to(:log_tool_call)
      expect(instance).to respond_to(:log_handoff)
      expect(instance).to respond_to(:log_api_call)
      expect(instance).to respond_to(:log_api_error)
    end

    it "handles agent logging without errors" do
      error = StandardError.new("Test error")
      expect {
        instance.log_agent_start("GPT-4")
        instance.log_agent_end("GPT-4")
        instance.log_tool_call("search")
        instance.log_handoff("Agent1", "Agent2")
        instance.log_api_call("POST", "https://api.test.com")
        instance.log_api_error(error)
      }.not_to raise_error
    end
  end

  describe "#log_exception" do
    it "logs exception with details" do
      begin
        raise StandardError, "Test error"
      rescue StandardError => e
        expect {
          instance.log_exception(e, message: "Custom message", user_id: 123)
        }.not_to raise_error
      end
    end

    it "uses exception message when no custom message provided" do
      begin
        raise ArgumentError, "Invalid argument"
      rescue ArgumentError => e
        expect {
          instance.log_exception(e, context: "test")
        }.not_to raise_error
      end
    end

    it "handles exceptions with causes" do
      begin
        begin
          raise RuntimeError, "Root cause"
        rescue RuntimeError => e
          raise StandardError, "Wrapper error"
        end
      rescue StandardError => e
        expect {
          instance.log_exception(e)
        }.not_to raise_error
      end
    end
  end
end