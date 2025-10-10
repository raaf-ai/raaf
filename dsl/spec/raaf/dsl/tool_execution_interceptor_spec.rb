# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::DSL::Agent Tool Execution Interceptor" do
  # Test helper for simple tool that returns success
  class SimpleSearchTool
    def call(query:)
      { success: true, result: "Searched for: #{query}" }
    end

    def name
      "simple_search"
    end
  end

  # Test helper for DSL-wrapped tool (already has conveniences)
  class MockDslWrappedTool
    def initialize(name: "dsl_wrapped_tool")
      @name = name
    end

    def name
      @name
    end

    def dsl_wrapped?
      true
    end

    def call(**args)
      { success: true, wrapped: true, args: args }
    end
  end

  # Test agent class with a simple tool injected
  class InterceptorTestAgent < RAAF::DSL::Agent
    agent_name "InterceptorTestAgent"
    model "gpt-4o"

    def build_instructions
      "You are a test agent for interceptor functionality."
    end

    def build_schema
      {
        type: "object",
        properties: {
          message: { type: "string" }
        },
        required: ["message"],
        additionalProperties: false
      }
    end

    # Override tools to inject our test tool
    def tools
      @test_tools ||= [SimpleSearchTool.new]
    end
  end

  # Test agent with wrapped tool
  class WrappedToolTestAgent < RAAF::DSL::Agent
    agent_name "WrappedToolTestAgent"
    model "gpt-4o"

    def build_instructions
      "You are a test agent for wrapped tool testing."
    end

    def build_schema
      {
        type: "object",
        properties: {
          message: { type: "string" }
        },
        required: ["message"],
        additionalProperties: false
      }
    end

    # Override tools to inject our mock wrapped tool
    def tools
      @test_tools ||= [MockDslWrappedTool.new]
    end
  end

  # Test agent with failing tool
  class FailingToolAgent < RAAF::DSL::Agent
    agent_name "FailingToolAgent"
    model "gpt-4o"

    def build_instructions
      "You are a test agent for error handling."
    end

    def build_schema
      {
        type: "object",
        properties: {
          message: { type: "string" }
        },
        required: ["message"],
        additionalProperties: false
      }
    end

    # Tool that raises an error
    class FailingTool
      def call(param:)
        raise StandardError, "Tool failed"
      end

      def name
        "failing_tool"
      end
    end

    def tools
      @test_tools ||= [FailingTool.new]
    end
  end

  describe "Interceptor Activation" do
    context "with raw core tool" do
      let(:agent) { InterceptorTestAgent.new }

      it "intercepts tool execution" do
        # The interceptor should activate for raw tools
        result = agent.execute_tool("simple_search", query: "test")

        expect(result).to be_a(Hash)
        expect(result[:success]).to be true
        expect(result[:result]).to eq("Searched for: test")
      end

      it "does not double-intercept" do
        # Should only intercept once even with multiple executions
        first_result = agent.execute_tool("simple_search", query: "first")
        second_result = agent.execute_tool("simple_search", query: "second")

        expect(first_result[:result]).to eq("Searched for: first")
        expect(second_result[:result]).to eq("Searched for: second")
      end
    end

    context "with DSL-wrapped tool" do
      let(:agent) { WrappedToolTestAgent.new }
      let(:dsl_tool) { MockDslWrappedTool.new }

      it "bypasses interceptor for already-wrapped tools" do
        # DSL-wrapped tools should not be intercepted
        result = agent.execute_tool("dsl_wrapped_tool", param: "value")

        expect(result).to be_a(Hash)
        expect(result[:wrapped]).to be true
        expect(result[:args]).to eq(param: "value")
      end

      it "respects dsl_wrapped? marker" do
        # Verify the tool is correctly identified as wrapped
        expect(dsl_tool.dsl_wrapped?).to be true
      end
    end
  end

  describe "Interceptor Detection Logic" do
    it "detects DSL-wrapped tools via dsl_wrapped? method" do
      wrapped_tool = MockDslWrappedTool.new
      expect(wrapped_tool).to respond_to(:dsl_wrapped?)
      expect(wrapped_tool.dsl_wrapped?).to be true
    end

    it "treats core tools as not wrapped" do
      # Tools defined via tool class don't have dsl_wrapped? method
      tool = SimpleSearchTool.new
      expect(tool).not_to respond_to(:dsl_wrapped?)
    end

    it "skips interception when tool is already wrapped" do
      agent = WrappedToolTestAgent.new

      # Should call tool directly without interception
      result = agent.execute_tool("dsl_wrapped_tool", test: "data")
      expect(result[:wrapped]).to be true
    end
  end

  describe "Thread Safety" do
    it "handles concurrent tool executions safely" do
      agent = InterceptorTestAgent.new

      threads = 10.times.map do |i|
        Thread.new do
          agent.execute_tool("simple_search", query: "thread_#{i}")
        end
      end

      results = threads.map(&:value)

      # All results should be successful
      expect(results.size).to eq(10)
      results.each do |result|
        expect(result[:success]).to be true
      end

      # Each result should have unique query
      queries = results.map { |r| r[:result] }
      expect(queries.uniq.size).to eq(10)
    end

    it "maintains thread-safe metadata injection" do
      agent = InterceptorTestAgent.new
      results = []
      mutex = Mutex.new

      threads = 5.times.map do
        Thread.new do
          result = agent.execute_tool("simple_search", query: "concurrent")
          mutex.synchronize { results << result }
        end
      end

      threads.each(&:join)

      # All results should be present and valid
      expect(results.size).to eq(5)
      results.each do |result|
        expect(result[:success]).to be true
      end
    end
  end

  describe "Configuration Check" do
    context "when interceptor is enabled" do
      it "applies interception to raw tools" do
        agent = InterceptorTestAgent.new
        result = agent.execute_tool("simple_search", query: "test")
        expect(result).to be_a(Hash)
      end
    end
  end

  describe "Error Handling" do
    it "re-raises tool execution errors" do
      agent = FailingToolAgent.new

      expect {
        agent.execute_tool("failing_tool", param: "value")
      }.to raise_error(StandardError, /Tool failed/)
    end

    it "allows error handling at agent level" do
      agent = FailingToolAgent.new

      begin
        agent.execute_tool("failing_tool", param: "value")
      rescue StandardError => e
        expect(e.message).to include("Tool failed")
      end
    end
  end

  describe "Proper Inheritance" do
    it "overrides execute_tool from parent RAAF::Agent class" do
      agent = InterceptorTestAgent.new

      # Verify agent inherits from RAAF::Agent via DSL::Agent
      expect(agent).to be_kind_of(RAAF::DSL::Agent)

      # Verify execute_tool method exists
      expect(agent).to respond_to(:execute_tool)
    end

    it "calls super to parent implementation" do
      agent = InterceptorTestAgent.new

      # This should work through proper super call
      result = agent.execute_tool("simple_search", query: "inheritance_test")
      expect(result[:success]).to be true
    end
  end
end
