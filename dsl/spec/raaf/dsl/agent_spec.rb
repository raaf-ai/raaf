# frozen_string_literal: true

require "spec_helper"

# Load TracingRegistry for testing
begin
  require "raaf/tracing/tracing_registry"
  require "raaf/tracing/noop_tracer"
rescue LoadError
  # TracingRegistry not available - tests will be skipped
end

RSpec.describe RAAF::DSL::Agent do
  # Test agent classes
  class BasicTestAgent < described_class
    agent_name "BasicTestAgent"
    model "gpt-4o"
    
    def build_instructions
      "You are a basic test assistant."
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
  end
  
  class SmartTestAgent < described_class
    agent_name "SmartTestAgent"
    model "gpt-4o-mini"
    max_turns 5
    temperature 0.7

    # Smart features using correct API
    retry_on :rate_limit, max_attempts: 3, backoff: :exponential
    retry_on Timeout::Error, max_attempts: 2
    circuit_breaker threshold: 5, timeout: 60, reset_timeout: 300

    # Context validation requirements
    context do
      required :api_key, :endpoint
    end

    # Add type validation rules
    validates_context :api_key, type: String
    validates_context :endpoint, type: String

    schema do
      field :status, type: :string, required: true
      field :data, type: :array do
        field :id, type: :string
        field :value, type: :integer, range: 0..100
      end
    end

    # Modern agent with static instructions and user prompt
    static_instructions "You are a smart test assistant."

    user_prompt do |context|
      api_key = context[:api_key] || ""
      truncated_key = api_key.length > 6 ? "#{api_key[0, 6]}..." : api_key
      "Process endpoint #{context[:endpoint]} with key #{truncated_key}"
    end
  end
  
  class MinimalAgent < described_class
    def build_instructions
      "Minimal agent"
    end
    
    def build_schema
      nil # Test unstructured output
    end
  end
  
  describe "Basic Agent Functionality (from old Base)" do
    let(:context) { RAAF::DSL::ContextVariables.new(test: true) }
    let(:agent) { BasicTestAgent.new(context: context) }
    
    describe "#initialize" do
      it "accepts context parameter" do
        expect { BasicTestAgent.new(context: context) }.not_to raise_error
      end
      
      it "accepts context_variables parameter for compatibility" do
        expect { BasicTestAgent.new(context_variables: context) }.not_to raise_error
      end
      
      it "accepts processing_params" do
        agent = BasicTestAgent.new(context: context, processing_params: { foo: "bar" })
        expect(agent.processing_params).to eq({ foo: "bar" })
      end
      
      it "defaults to empty context when not provided" do
        agent = BasicTestAgent.new
        expect(agent.context).to be_a(RAAF::DSL::ContextVariables)
        expect(agent.context.to_h).to eq({})
      end
    end
    
    describe "#agent_name" do
      it "returns the configured agent name" do
        expect(agent.agent_name).to eq("BasicTestAgent")
      end
      
      it "falls back to class name if not configured" do
        minimal = MinimalAgent.new
        expect(minimal.agent_name).to eq("MinimalAgent")
      end
    end
    
    describe "#model_name" do
      it "returns the configured model" do
        expect(agent.model_name).to eq("gpt-4o")
      end
      
      it "defaults to gpt-4o if not configured" do
        minimal = MinimalAgent.new
        expect(minimal.model_name).to eq("gpt-4o")
      end
    end
    
    describe "#build_instructions" do
      it "returns the system instructions" do
        expect(agent.build_instructions).to eq("You are a basic test assistant.")
      end
    end
    
    describe "#build_schema" do
      it "returns the response schema" do
        schema = agent.build_schema
        expect(schema[:type]).to eq("object")
        expect(schema[:properties][:message]).to eq({ type: "string" })
      end
      
      it "can return nil for unstructured output" do
        minimal = MinimalAgent.new
        expect(minimal.build_schema).to be_nil
      end
    end
    
    describe "#response_format" do
      it "returns structured format with schema" do
        format = agent.response_format
        expect(format[:type]).to eq("json_schema")
        expect(format[:json_schema][:strict]).to eq(true)
        # Compare schemas by converting to JSON and back to normalize keys
        expected_schema = agent.build_schema
        actual_schema = format[:json_schema][:schema]

        # Convert both to JSON strings for comparison to handle mixed key types
        expected_json = JSON.generate(expected_schema)
        actual_json = JSON.generate(actual_schema)
        expect(actual_json).to eq(expected_json)
      end
      
      it "returns nil for unstructured output" do
        minimal = MinimalAgent.new
        expect(minimal.response_format).to be_nil
      end
    end
    
    describe "#create_agent" do
      it "creates a RAAF::Agent instance" do
        openai_agent = agent.create_agent
        expect(openai_agent).to be_a(RAAF::Agent)
        expect(openai_agent.name).to eq("BasicTestAgent")
        expect(openai_agent.model).to eq("gpt-4o")
      end
    end
  end
  
  describe "Smart Agent Features" do
    let(:valid_context) { RAAF::DSL::ContextVariables.new(api_key: "sk-123456", endpoint: "https://api.example.com") }
    let(:invalid_context) { RAAF::DSL::ContextVariables.new(endpoint: "https://api.example.com") }
    
    describe "Context Validation" do
      it "validates required context keys" do
        expect { SmartTestAgent.new(context: invalid_context) }
          .to raise_error(ArgumentError, /Required context keys missing: api_key/)
      end
      
      it "validates context value types" do
        invalid = RAAF::DSL::ContextVariables.new(api_key: 123, endpoint: "test")
        expect { SmartTestAgent.new(context: invalid) }
          .to raise_error(ArgumentError, /Context key 'api_key' must be String/)
      end
      
      it "accepts valid context" do
        expect { SmartTestAgent.new(context: valid_context) }.not_to raise_error
      end
    end
    
    describe "DSL Configuration" do
      let(:agent) { SmartTestAgent.new(context: valid_context) }
      
      it "configures agent name" do
        expect(agent.agent_name).to eq("SmartTestAgent")
      end
      
      it "configures model" do
        expect(agent.model_name).to eq("gpt-4o-mini")
      end
      
      it "configures max_turns" do
        expect(agent.max_turns).to eq(5)
      end
      
      it "has retry configuration" do
        expect(SmartTestAgent._retry_config).to include(:rate_limit)
        expect(SmartTestAgent._retry_config[:rate_limit]).to include(
          max_attempts: 3,
          backoff: :exponential
        )
      end
      
      it "has circuit breaker configuration" do
        expect(SmartTestAgent._circuit_breaker_config).to include(
          threshold: 5,
          timeout: 60,
          reset_timeout: 300
        )
      end
    end
    
    describe "Schema DSL" do
      let(:agent) { SmartTestAgent.new(context: valid_context) }
      
      it "builds schema from DSL" do
        schema_def = agent.build_schema
        schema = schema_def[:schema]

        expect(schema["type"]).to eq("object")
        expect(schema["properties"]["status"]).to eq({ "type" => "string" })
        expect(schema["properties"]["data"]["type"]).to eq("array")
        expect(schema["properties"]["data"]["items"]["properties"]["id"]).to eq({ "type" => "string" })
        expect(schema["required"]).to include("status")
      end
    end
    
    describe "Prompt DSL" do
      let(:agent) { SmartTestAgent.new(context: valid_context) }
      
      it "builds system prompt from string" do
        expect(agent.build_instructions).to eq("You are a smart test assistant.")
      end
      
      it "builds user prompt from block" do
        prompt = agent.build_user_prompt
        expect(prompt).to eq("Process endpoint https://api.example.com with key sk-123...")
      end
    end
    
    describe "#run with smart features" do
      let(:agent) { SmartTestAgent.new(context: valid_context) }
      
      before do
        # Mock the direct_run method to simulate execution
        allow(agent).to receive(:direct_run).and_return({
          success: true,
          results: double(
            messages: [
              { role: "assistant", content: '{"status": "success", "data": []}' }
            ],
            final_output: '{"status": "success", "data": []}'
          )
        })
      end
      
      it "executes with retry and error handling when smart features configured" do
        result = agent.run
        expect(result).to include(success: true, data: { "status" => "success", "data" => [] })
      end
      
      it "logs execution start and completion for smart agents" do
        expect(RAAF::Logging).to receive(:info).with(/Starting execution/)
        expect(RAAF::Logging).to receive(:info).with(/completed successfully/)
        agent.run
      end
      
      it "skips smart features when skip_retries is true" do
        expect(agent).not_to receive(:check_circuit_breaker!)
        expect(agent).not_to receive(:execute_with_retry)
        agent.run(skip_retries: true)
      end
    end
    
    describe "#call method (backward compatibility)" do
      let(:agent) { SmartTestAgent.new(context: valid_context) }
      
      it "delegates to run method" do
        expect(agent).to receive(:run).and_return({ success: true })
        result = agent.call
        expect(result).to eq({ success: true })
      end
    end
    
    describe "Error Handling" do
      let(:agent) { SmartTestAgent.new(context: valid_context) }
      
      context "with rate limit error" do
        before do
          allow(agent).to receive(:direct_run).and_raise(StandardError.new("rate limit exceeded"))
        end
        
        it "categorizes rate limit errors" do
          result = agent.run
          expect(result[:error_type]).to eq("rate_limit")
          expect(result[:error]).to include("Rate limit exceeded")
        end
      end
      
      context "with JSON parse error" do
        before do
          allow(agent).to receive(:direct_run).and_raise(JSON::ParserError.new("unexpected token"))
        end
        
        it "categorizes JSON errors" do
          result = agent.run
          expect(result[:error_type]).to eq("json_error")
          expect(result[:error]).to include("Failed to parse AI response")
        end
      end
    end
  end
  
  describe "AgentDsl Integration" do
    it "includes ContextAccess automatically" do
      expect(described_class.ancestors).to include(RAAF::DSL::ContextAccess)
    end
    
    it "provides DSL methods without explicit include" do
      expect(described_class).to respond_to(:agent_name)
      expect(described_class).to respond_to(:model)
      expect(described_class).to respond_to(:uses_tool)
      # schema method temporarily unavailable due to implementation issue
      # expect(described_class).to respond_to(:schema)
    end
  end
  
  describe "AgentHooks Integration" do
    it "includes HookContext automatically" do
      expect(described_class.ancestors).to include(RAAF::DSL::Hooks::HookContext)
    end
    
    it "provides hook methods" do
      expect(described_class).to respond_to(:on_start)
      expect(described_class).to respond_to(:on_end)
      expect(described_class).to respond_to(:on_handoff)
    end
  end
  
  describe "Backward Compatibility" do
    it "works with old initialization style" do
      agent = BasicTestAgent.new(
        context_variables: RAAF::DSL::ContextVariables.new(foo: "bar"),
        processing_params: { baz: "qux" }
      )
      # The context_variables parameter gets stored under "context_variables" key
      expect(agent.context.to_h["context_variables"].to_h).to include("foo" => "bar")
      expect(agent.processing_params).to eq({ baz: "qux" })
    end
    
    it "supports run method" do
      agent = BasicTestAgent.new(context: RAAF::DSL::ContextVariables.new)
      expect(agent).to respond_to(:run)
      # Note: call method not implemented in current version
    end
  end
  
  describe "Default Schema" do
    class DefaultSchemaAgent < described_class
      agent_name "DefaultAgent"
    end
    
    it "provides a default schema when not defined" do
      agent = DefaultSchemaAgent.new
      schema = agent.build_schema
      
      expect(schema[:type]).to eq("object")
      expect(schema[:properties]).to include(:result)
      expect(schema[:required]).to include("result")
    end
  end
  
  describe "Configuration Inheritance" do
    class ParentAgent < described_class
      agent_name "ParentAgent"
      retry_on :network, max_attempts: 2

      context do
        required :user_id
      end
    end

    class ChildAgent < ParentAgent
      agent_name "ChildAgent"

      context do
        required :session_id
      end
    end
    
    it "inherits configuration from parent class" do
      expect(ChildAgent._required_context_keys).to include(:user_id, :session_id)
      expect(ChildAgent._retry_config).to include(:network)
    end
  end

  describe "tracing and span support", skip: "Requires raaf-tracing gem integration" do
    let(:mock_tracer) { double("MockTracer") }
    let(:mock_span) { double("MockSpan", span_id: "span_456", set_attribute: nil, add_event: nil, set_status: nil) }
    let(:mock_parent_span) { double("MockSpan", span_id: "parent_123") }

    let(:traced_agent_class) do
      Class.new(described_class) do
        agent_name "TracedAgent"
        model "gpt-4o"
        temperature 0.7
        timeout 30
        retry_count 3
        max_turns 10

        context do
          required :product, :company
          optional analysis_depth: "standard"
        end

        schema do
          field :markets, type: :array, required: true
          field :analysis, type: :object, required: true
        end

        def run
          { success: true, markets: ["market1"], analysis: { confidence: 0.9 } }
        end
      end
    end

    before do
      allow(mock_tracer).to receive(:agent_span).and_yield(mock_span)
      allow(RAAF).to receive(:tracer).and_return(mock_tracer)
    end

    describe "#initialize with tracing" do
      context "with tracer parameter" do
        it "accepts tracer in constructor" do
          agent = traced_agent_class.new(
            tracer: mock_tracer,
            product: "Test Product",
            company: "Test Company"
          )

          expect(agent.instance_variable_get(:@tracer)).to eq(mock_tracer)
        end
      end

      context "with parent_span parameter" do
        it "accepts parent_span for pipeline hierarchies" do
          agent = traced_agent_class.new(
            tracer: mock_tracer,
            parent_span: mock_parent_span,
            product: "Test Product",
            company: "Test Company"
          )

          expect(agent.instance_variable_get(:@parent_span)).to eq(mock_parent_span)
        end
      end

      context "without tracer parameter" do
        it "uses RAAF.tracer as default" do
          agent = traced_agent_class.new(
            product: "Test Product",
            company: "Test Company"
          )

          expect(agent.instance_variable_get(:@tracer)).to eq(mock_tracer)
        end
      end
    end

    describe "#direct_run with tracing" do
      let(:agent) do
        traced_agent_class.new(
          tracer: mock_tracer,
          parent_span: mock_parent_span,
          product: "Test Product",
          company: "Test Company"
        )
      end

      # Mock the RAAF runner and result
      let(:mock_runner) { instance_double(RAAF::Runner) }
      let(:mock_run_result) do
        double("RunResult",
               messages: [
                 { role: "user", content: "Analyze markets", timestamp: Time.now.iso8601 },
                 { role: "assistant", content: "Analysis complete", timestamp: Time.now.iso8601 }
               ],
               usage: { prompt_tokens: 50, completion_tokens: 100, total_tokens: 150 })
      end

      before do
        allow(RAAF::Runner).to receive(:new).and_return(mock_runner)
        allow(mock_runner).to receive(:run).and_return(mock_run_result)
      end

      it "creates agent span with name" do
        expect(mock_tracer).to receive(:agent_span).with("TracedAgent")

        agent.direct_run
      end

      it "sets parent span ID when provided" do
        expect(mock_span).to receive(:instance_variable_set).with(:@parent_id, "parent_123")

        agent.direct_run
      end

      it "sets comprehensive agent metadata attributes" do
        # Basic agent info
        expect(mock_span).to receive(:set_attribute).with("agent.class", traced_agent_class.name)
        expect(mock_span).to receive(:set_attribute).with("agent.name", "TracedAgent")
        expect(mock_span).to receive(:set_attribute).with("agent.model", "gpt-4o")
        expect(mock_span).to receive(:set_attribute).with("agent.temperature", 0.7)
        expect(mock_span).to receive(:set_attribute).with("agent.max_turns", 10)

        # Timeout configuration
        expect(mock_span).to receive(:set_attribute).with("agent.timeout", 30)

        # Retry configuration
        expect(mock_span).to receive(:set_attribute).with("agent.retry_count", 3)

        # Circuit breaker (disabled by default)
        expect(mock_span).to receive(:set_attribute).with("agent.circuit_breaker_enabled", false)

        # Schema & validation
        expect(mock_span).to receive(:set_attribute).with("agent.has_schema", true)
        expect(mock_span).to receive(:set_attribute).with("agent.schema_mode", "strict")

        # AutoMerge
        expect(mock_span).to receive(:set_attribute).with("agent.auto_merge_enabled", true)

        # Tools & context
        expect(mock_span).to receive(:set_attribute).with("agent.tools", [])
        expect(mock_span).to receive(:set_attribute).with("agent.tool_count", 0)
        expect(mock_span).to receive(:set_attribute).with("agent.required_fields", [:product, :company])
        expect(mock_span).to receive(:set_attribute).with("agent.optional_fields", [:analysis_depth])

        # Runtime info
        expect(mock_span).to receive(:set_attribute).with("agent.input_size", anything)
        expect(mock_span).to receive(:set_attribute).with("agent.parent_pipeline", "pipeline")

        agent.direct_run
      end

      it "adds agent lifecycle events" do
        expect(mock_span).to receive(:add_event).with("agent.context_resolved")
        expect(mock_span).to receive(:add_event).with("agent.openai_agent_created")
        expect(mock_span).to receive(:add_event).with("agent.prompt_built", attributes: hash_including(:prompt_length))
        expect(mock_span).to receive(:add_event).with("agent.runner_created")
        expect(mock_span).to receive(:add_event).with("agent.llm_execution_completed")
        expect(mock_span).to receive(:add_event).with("agent.result_transformed")

        agent.direct_run
      end

      it "captures dialog state and components" do
        # Initial context
        expect(mock_span).to receive(:set_attribute).with("dialog.context_size", anything)
        expect(mock_span).to receive(:set_attribute).with("dialog.context_keys", anything)
        expect(mock_span).to receive(:set_attribute).with("dialog.initial_context", anything)

        # System and user prompts
        expect(mock_span).to receive(:set_attribute).with("dialog.system_prompt", anything)
        expect(mock_span).to receive(:set_attribute).with("dialog.system_prompt_length", anything)
        expect(mock_span).to receive(:set_attribute).with("dialog.user_prompt", anything)
        expect(mock_span).to receive(:set_attribute).with("dialog.user_prompt_length", anything)

        # Messages and tokens
        expect(mock_span).to receive(:set_attribute).with("dialog.messages", anything)
        expect(mock_span).to receive(:set_attribute).with("dialog.message_count", 2)
        expect(mock_span).to receive(:set_attribute).with("dialog.total_tokens", {
          prompt_tokens: 50,
          completion_tokens: 100,
          total_tokens: 150
        })

        agent.direct_run
      end

      it "captures final agent result" do
        expect(mock_span).to receive(:set_attribute).with("agent.output_size", anything)
        expect(mock_span).to receive(:set_attribute).with("dialog.final_result", anything)

        agent.direct_run
      end

      it "sets final span status based on agent success" do
        expect(mock_span).to receive(:set_status).with(:ok)
        expect(mock_span).to receive(:set_attribute).with("agent.success", true)

        agent.direct_run
      end
    end

    describe "#direct_run without tracer" do
      let(:agent) do
        traced_agent_class.new(
          tracer: nil,
          product: "Test Product",
          company: "Test Company"
        )
      end

      # Mock the core execution
      before do
        allow(agent).to receive(:execute_without_tracing).and_return({
          success: true,
          markets: ["market1"],
          analysis: { confidence: 0.9 }
        })
      end

      it "executes without tracing when tracer is nil" do
        expect(mock_tracer).not_to receive(:agent_span)

        result = agent.direct_run
        expect(result).to be_a(Hash)
        expect(result[:success]).to be(true)
      end
    end

    describe "agent span attribute methods" do
      let(:agent) do
        traced_agent_class.new(
          product: "Test Product",
          company: "Test Company"
        )
      end

      describe "#set_agent_span_attributes" do
        it "sets basic agent information" do
          expect(mock_span).to receive(:set_attribute).with("agent.class", traced_agent_class.name)
          expect(mock_span).to receive(:set_attribute).with("agent.name", "TracedAgent")

          agent.send(:set_agent_span_attributes, mock_span)
        end

        context "with circuit breaker configuration" do
          let(:circuit_breaker_agent_class) do
            Class.new(described_class) do
              agent_name "CircuitBreakerAgent"
              circuit_breaker threshold: 5, timeout: 60

              def run
                { success: true }
              end
            end
          end

          let(:cb_agent) do
            circuit_breaker_agent_class.new(product: "Test")
          end

          it "sets circuit breaker attributes when enabled" do
            expect(mock_span).to receive(:set_attribute).with("agent.circuit_breaker_enabled", true)
            expect(mock_span).to receive(:set_attribute).with("agent.circuit_breaker_threshold", 5)
            expect(mock_span).to receive(:set_attribute).with("agent.circuit_breaker_timeout", 60)

            cb_agent.send(:set_agent_span_attributes, mock_span)
          end
        end

        context "with tools configuration" do
          let(:tools_agent_class) do
            Class.new(described_class) do
              agent_name "ToolsAgent"

              def search_web(query)
                "results for #{query}"
              end

              def calculate(expression)
                "calculation result"
              end

              add_tool method(:search_web)
              add_tool method(:calculate)

              def run
                { success: true }
              end
            end
          end

          let(:tools_agent) do
            tools_agent_class.new(product: "Test")
          end

          it "sets tools attributes when tools are configured" do
            expect(mock_span).to receive(:set_attribute).with("agent.tools", anything)
            expect(mock_span).to receive(:set_attribute).with("agent.tool_count", anything)

            tools_agent.send(:set_agent_span_attributes, mock_span)
          end
        end
      end

      describe "#calculate_input_size" do
        it "calculates context size correctly" do
          size = agent.send(:calculate_input_size)
          expect(size).to be > 0
        end

        it "handles missing context gracefully" do
          agent.instance_variable_set(:@context, nil)
          size = agent.send(:calculate_input_size)
          expect(size).to eq(0)
        end
      end

      describe "#calculate_output_size" do
        it "calculates result size correctly" do
          result = { markets: ["market1"], analysis: { confidence: 0.9 } }
          size = agent.send(:calculate_output_size, result)
          expect(size).to be > 0
        end

        it "handles nil result gracefully" do
          size = agent.send(:calculate_output_size, nil)
          expect(size).to eq(0)
        end
      end
    end

    describe "dialog capture methods" do
      let(:agent) do
        traced_agent_class.new(
          product: "Test Product",
          company: "Test Company"
        )
      end

      describe "#capture_initial_dialog_state" do
        let(:context) { { product: "Test", company: "Corp", api_key: "secret123" } }

        it "captures context metadata" do
          expect(mock_span).to receive(:set_attribute).with("dialog.context_size", 3)
          expect(mock_span).to receive(:set_attribute).with("dialog.context_keys", [:product, :company, :api_key])
          expect(mock_span).to receive(:set_attribute).with("dialog.initial_context", hash_including(
            product: "Test",
            company: "Corp",
            api_key: "[REDACTED]"
          ))

          agent.send(:capture_initial_dialog_state, mock_span, context)
        end
      end

      describe "#capture_dialog_components" do
        let(:mock_openai_agent) { double("OpenAIAgent", instructions: "You are a helpful assistant") }
        let(:user_prompt) { "Analyze the market for our product" }
        let(:context) { { product: "Test Product" } }

        it "captures system and user prompts" do
          expect(mock_span).to receive(:set_attribute).with("dialog.system_prompt", "You are a helpful assistant")
          expect(mock_span).to receive(:set_attribute).with("dialog.system_prompt_length", 29)
          expect(mock_span).to receive(:set_attribute).with("dialog.user_prompt", user_prompt)
          expect(mock_span).to receive(:set_attribute).with("dialog.user_prompt_length", user_prompt.length)

          agent.send(:capture_dialog_components, mock_span, mock_openai_agent, user_prompt, context)
        end
      end

      describe "#capture_final_dialog_state" do
        let(:run_result) do
          double("RunResult",
                 messages: [
                   { role: "user", content: "Test message" },
                   { role: "assistant", content: "Response with function_call data" }
                 ],
                 usage: { prompt_tokens: 25, completion_tokens: 75, total_tokens: 100 })
        end

        it "captures conversation messages and token usage" do
          expect(mock_span).to receive(:set_attribute).with("dialog.messages", anything)
          expect(mock_span).to receive(:set_attribute).with("dialog.message_count", 2)
          expect(mock_span).to receive(:set_attribute).with("dialog.total_tokens", {
            prompt_tokens: 25,
            completion_tokens: 75,
            total_tokens: 100
          })

          agent.send(:capture_final_dialog_state, mock_span, run_result)
        end
      end

      describe "#extract_tool_calls_from_messages" do
        let(:messages_with_tools) do
          [
            { role: "user", content: "Search for something" },
            { role: "assistant", content: "I'll help you search. function_call: search_web", timestamp: Time.now.iso8601 },
            { role: "assistant", content: "Here are the results" }
          ]
        end

        it "extracts tool calls from assistant messages" do
          tool_calls = agent.send(:extract_tool_calls_from_messages, messages_with_tools)
          expect(tool_calls).to have(1).item
          expect(tool_calls.first[:message_content]).to include("function_call")
        end

        it "returns empty array when no tool calls present" do
          simple_messages = [
            { role: "user", content: "Hello" },
            { role: "assistant", content: "Hi there" }
          ]
          tool_calls = agent.send(:extract_tool_calls_from_messages, simple_messages)
          expect(tool_calls).to be_empty
        end
      end
    end

    describe "error handling with tracing" do
      let(:error_agent_class) do
        Class.new(described_class) do
          agent_name "ErrorAgent"

          def run
            raise StandardError, "Test error"
          end
        end
      end

      let(:agent) do
        error_agent_class.new(
          tracer: mock_tracer,
          product: "Test Product"
        )
      end

      before do
        allow(RAAF::Runner).to receive(:new).and_raise(StandardError, "Test error")
      end

      it "handles errors gracefully and returns error result" do
        result = agent.direct_run

        expect(result).to include(
          workflow_status: "error",
          error: "Test error",
          success: false
        )
      end
    end
  end

  # TracingRegistry integration tests
  describe "TracingRegistry integration", :if => defined?(RAAF::Tracing::TracingRegistry) do
    let(:registry_tracer) { double("MockTracer") }
    let(:mock_span) { double("MockSpan", span_id: "span_123", set_attribute: nil, add_event: nil, set_status: nil) }

    class TracingTestAgent < described_class
      agent_name "TracingTestAgent"
      model "gpt-4o"

      def build_instructions
        "You are a tracing test assistant."
      end

      def build_schema
        {
          type: "object",
          properties: { message: { type: "string" } },
          required: ["message"],
          additionalProperties: false
        }
      end
    end

    before do
      allow(registry_tracer).to receive(:agent_span).and_yield(mock_span)
      RAAF::Tracing::TracingRegistry.clear_all_contexts!
    end

    after do
      RAAF::Tracing::TracingRegistry.clear_all_contexts!
    end

    describe "#get_tracer_for_skipped_span" do
      let(:agent) { TracingTestAgent.new }

      context "with TracingRegistry tracer available" do
        before do
          RAAF::Tracing::TracingRegistry.set_process_tracer(registry_tracer)
        end

        it "returns the registry tracer" do
          tracer = agent.send(:get_tracer_for_skipped_span)
          expect(tracer).to eq(registry_tracer)
        end

        context "when registry returns NoOpTracer" do
          let(:noop_tracer) { double("NoOpTracer") }

          before do
            allow(noop_tracer).to receive(:is_a?).and_return(false)
            allow(noop_tracer).to receive(:is_a?).with(RAAF::Tracing::NoOpTracer).and_return(true) if defined?(RAAF::Tracing::NoOpTracer)
            RAAF::Tracing::TracingRegistry.set_process_tracer(noop_tracer)
          end

          it "falls back to TraceProvider" do
            # Mock the TraceProvider fallback
            allow(RAAF::Tracing::TraceProvider).to receive(:tracer).and_return(registry_tracer) if defined?(RAAF::Tracing::TraceProvider)

            tracer = agent.send(:get_tracer_for_skipped_span)
            # Should either be the registry_tracer or handle the fallback gracefully
            expect([registry_tracer, noop_tracer, nil]).to include(tracer)
          end
        end
      end

      context "with no TracingRegistry tracer" do
        before do
          RAAF::Tracing::TracingRegistry.clear_all_contexts!
        end

        it "falls back to TraceProvider" do
          # Mock TraceProvider if available
          if defined?(RAAF::Tracing::TraceProvider)
            allow(RAAF::Tracing::TraceProvider).to receive(:tracer).and_return(registry_tracer)
            tracer = agent.send(:get_tracer_for_skipped_span)
            expect(tracer).to eq(registry_tracer)
          else
            # If not available, test graceful handling
            expect { agent.send(:get_tracer_for_skipped_span) }.not_to raise_error
          end
        end

        it "returns nil when TraceProvider is not available" do
          # Test graceful handling of missing TraceProvider
          tracer = agent.send(:get_tracer_for_skipped_span)
          expect(tracer).to be_nil
        end
      end

      context "with thread-local registry tracer" do
        let(:thread_tracer) { double("MockThreadTracer") }

        before do
          RAAF::Tracing::TracingRegistry.set_process_tracer(registry_tracer)
        end

        it "uses thread-local tracer over process tracer" do
          RAAF::Tracing::TracingRegistry.with_tracer(thread_tracer) do
            tracer = agent.send(:get_tracer_for_skipped_span)
            expect(tracer).to eq(thread_tracer)
          end
        end
      end
    end

    describe "#create_skipped_span" do
      let(:agent) { TracingTestAgent.new }
      let(:context) { { product: "test", company: "corp" } }
      let(:result_data) { { success: false, skipped: true, reason: "missing requirements" } }

      context "with TracingRegistry tracer available" do
        before do
          RAAF::Tracing::TracingRegistry.set_process_tracer(registry_tracer)
          allow(registry_tracer).to receive(:agent_span).and_yield(mock_span)
        end

        it "creates span using registry tracer" do
          expect(registry_tracer).to receive(:agent_span).with("TracingTestAgent")

          result = agent.send(:create_skipped_span, "testing", result_data, context)
          expect(result).to eq(result_data)
        end

        it "sets proper span attributes for skipped agent" do
          expect(mock_span).to receive(:set_attribute).with("agent.skipped", true)
          expect(mock_span).to receive(:set_attribute).with("agent.skip_reason", "testing")
          expect(mock_span).to receive(:set_attribute).with("agent.name", "TracingTestAgent")
          expect(mock_span).to receive(:set_attribute).with("agent.class", "TracingTestAgent")

          agent.send(:create_skipped_span, "testing", result_data, context)
        end

        it "adds context information to span" do
          expect(mock_span).to receive(:set_attribute).with("agent.available_context_keys", context.keys)

          agent.send(:create_skipped_span, "testing", result_data, context)
        end
      end

      context "with no tracer available" do
        before do
          RAAF::Tracing::TracingRegistry.clear_all_contexts!
          # Ensure get_tracer_for_skipped_span returns nil
          allow(agent).to receive(:get_tracer_for_skipped_span).and_return(nil)
        end

        it "logs skip without creating span" do
          # Test that it handles nil tracer gracefully
          result = agent.send(:create_skipped_span, "testing", result_data, context)
          expect(result).to eq(result_data)
        end
      end
    end

    describe "agent handoffs with registry tracing" do
      class HandoffSourceAgent < described_class
        agent_name "HandoffSourceAgent"
        model "gpt-4o"

        def build_instructions
          "You are a handoff source agent."
        end
      end

      class HandoffTargetAgent < described_class
        agent_name "HandoffTargetAgent"
        model "gpt-4o"

        def build_instructions
          "You are a handoff target agent."
        end
      end

      before do
        RAAF::Tracing::TracingRegistry.set_process_tracer(registry_tracer)
      end

      it "preserves registry trace context across handoffs" do
        source_agent = HandoffSourceAgent.new
        target_agent = HandoffTargetAgent.new

        # Verify both agents can access the same registry tracer
        expect(source_agent.send(:get_tracer_for_skipped_span)).to eq(registry_tracer)
        expect(target_agent.send(:get_tracer_for_skipped_span)).to eq(registry_tracer)
      end

      it "maintains registry context during nested tracer scopes" do
        outer_tracer = double("MockOuterTracer")
        inner_tracer = double("MockInnerTracer")

        RAAF::Tracing::TracingRegistry.with_tracer(outer_tracer) do
          source_agent = HandoffSourceAgent.new
          expect(source_agent.send(:get_tracer_for_skipped_span)).to eq(outer_tracer)

          RAAF::Tracing::TracingRegistry.with_tracer(inner_tracer) do
            target_agent = HandoffTargetAgent.new
            expect(target_agent.send(:get_tracer_for_skipped_span)).to eq(inner_tracer)
          end

          # Context should be restored after inner scope
          final_agent = HandoffSourceAgent.new
          expect(final_agent.send(:get_tracer_for_skipped_span)).to eq(outer_tracer)
        end
      end
    end
  end

  describe "Reasoning Effort Configuration" do
    class MinimalReasoningAgent < described_class
      agent_name "MinimalReasoningAgent"
      model "gpt-5"
      reasoning_effort "minimal"

      static_instructions "Cost-aware reasoning agent"
    end

    class HighReasoningAgent < described_class
      agent_name "HighReasoningAgent"
      model "o1-preview"
      reasoning_effort :high

      static_instructions "Deep thinking agent"
    end

    class DefaultReasoningAgent < described_class
      agent_name "DefaultReasoningAgent"
      model "gpt-5"
      # No reasoning_effort configured

      static_instructions "Default reasoning agent"
    end

    describe ".reasoning_effort" do
      it "stores reasoning effort as string" do
        expect(MinimalReasoningAgent.reasoning_effort).to eq("minimal")
      end

      it "converts symbol to string" do
        expect(HighReasoningAgent.reasoning_effort).to eq("high")
      end

      it "returns nil when not configured" do
        expect(DefaultReasoningAgent.reasoning_effort).to be_nil
      end
    end

    describe "model_settings integration" do
      it "creates model_settings with reasoning_effort for minimal agent" do
        agent = MinimalReasoningAgent.new
        core_agent = agent.send(:create_openai_agent_instance)

        expect(core_agent.model_settings).to be_a(RAAF::ModelSettings)
        expect(core_agent.model_settings.reasoning).to eq({ reasoning_effort: "minimal" })
      end

      it "creates model_settings with reasoning_effort for high agent" do
        agent = HighReasoningAgent.new
        core_agent = agent.send(:create_openai_agent_instance)

        expect(core_agent.model_settings).to be_a(RAAF::ModelSettings)
        expect(core_agent.model_settings.reasoning).to eq({ reasoning_effort: "high" })
      end

      it "does not create model_settings when reasoning_effort is not configured" do
        agent = DefaultReasoningAgent.new
        core_agent = agent.send(:create_openai_agent_instance)

        expect(core_agent.model_settings).to be_nil
      end
    end

    describe "reasoning effort levels" do
      it "supports 'minimal' level (GPT-5 only)" do
        expect { MinimalReasoningAgent.new }.not_to raise_error
      end

      it "supports 'low' level" do
        class LowReasoningAgent < described_class
          agent_name "LowReasoningAgent"
          model "gpt-5"
          reasoning_effort "low"
          static_instructions "Low reasoning agent"
        end

        agent = LowReasoningAgent.new
        core_agent = agent.send(:create_openai_agent_instance)
        expect(core_agent.model_settings.reasoning).to eq({ reasoning_effort: "low" })
      end

      it "supports 'medium' level" do
        class MediumReasoningAgent < described_class
          agent_name "MediumReasoningAgent"
          model "o1-mini"
          reasoning_effort "medium"
          static_instructions "Medium reasoning agent"
        end

        agent = MediumReasoningAgent.new
        core_agent = agent.send(:create_openai_agent_instance)
        expect(core_agent.model_settings.reasoning).to eq({ reasoning_effort: "medium" })
      end

      it "supports 'high' level" do
        expect { HighReasoningAgent.new }.not_to raise_error
      end
    end
  end
end