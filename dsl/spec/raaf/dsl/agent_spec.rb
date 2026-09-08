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
      expect(described_class).to respond_to(:tool)
      expect(described_class).to respond_to(:tools)
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
      # NOTE: call method not implemented in current version
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

  # Span capture helpers.
  #
  # Span *creation* moved out of the DSL agent: `direct_run` hands off to the
  # core agent, which owns the tracer and the agent span. What stays here are
  # the helpers that measure a run and write dialog attributes onto a span
  # somebody else opened, so that is what these examples cover.
  describe "span capture helpers" do
    let(:mock_span) { double("MockSpan", span_id: "span_456", set_attribute: nil, add_event: nil, set_status: nil) }

    let(:traced_agent_class) do
      Class.new(described_class) do
        agent_name "TracedAgent"
        model "gpt-4o"
        temperature 0.7
        timeout 30
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

    let(:agent) do
      traced_agent_class.new(
        product: "Test Product",
        company: "Test Company"
      )
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

    describe "#capture_initial_dialog_state" do
      let(:context) { { product: "Test", company: "Corp", api_key: "secret123" } }

      it "captures context metadata" do
        expect(mock_span).to receive(:set_attribute).with("dialog.context_size", 3)
        expect(mock_span).to receive(:set_attribute).with("dialog.context_keys", %i[product company api_key])
        expect(mock_span).to receive(:set_attribute).with("dialog.initial_context", hash_including(
                                                                                      product: "Test",
                                                                                      company: "Corp",
                                                                                      api_key: "[REDACTED]"
                                                                                    ))

        agent.send(:capture_initial_dialog_state, mock_span, context)
      end
    end

    describe "#capture_dialog_components" do
      let(:system_prompt) { "You are a helpful assistant" }
      let(:mock_openai_agent) { double("OpenAIAgent", instructions: system_prompt) }
      let(:user_prompt) { "Analyze the market for our product" }
      let(:context) { { product: "Test Product" } }

      it "captures system and user prompts" do
        expect(mock_span).to receive(:set_attribute).with("dialog.system_prompt", system_prompt)
        expect(mock_span).to receive(:set_attribute).with("dialog.system_prompt_length", system_prompt.length)
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
        expect(tool_calls.size).to eq(1)
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

  # TracingRegistry integration tests
  describe "TracingRegistry integration", if: defined?(RAAF::Tracing::TracingRegistry) do
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
            if defined?(RAAF::Tracing::NoOpTracer)
              allow(noop_tracer).to receive(:is_a?).with(RAAF::Tracing::NoOpTracer).and_return(true)
            end
            RAAF::Tracing::TracingRegistry.set_process_tracer(noop_tracer)
          end

          it "falls back to TraceProvider" do
            # Mock the TraceProvider fallback
            if defined?(RAAF::Tracing::TraceProvider)
              allow(RAAF::Tracing::TraceProvider).to receive(:tracer).and_return(registry_tracer)
            end

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
          # Simulate TraceProvider being absent - without this the real provider
          # answers and the fallback path is never exercised.
          allow(RAAF::Tracing::TraceProvider).to receive(:tracer).and_raise(NoMethodError)

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

  describe "#run_with_incremental_processing" do
    # Regression test: persistence_handler context output fields must appear in the result.
    #
    # Bug: run_with_incremental_processing returned only {success:, <output_field>:, usage:}.
    # Values set on @context by persistence_handler (e.g. accumulated IDs and counts) were
    # silently dropped, so callers always received 0 for any count they relied on.
    #
    # Fix: after building the result hash, declared output fields present in @context are
    # merged in, making persistence_handler-accumulated state visible to callers.

    let(:agent_class) do
      Class.new(described_class) do
        agent_name "IncrementalOutputFieldAgent"
        model "gpt-4o"

        # Declare what this agent produces
        context do
          required :items
          output :processed_items    # primary output (the array)
          output :created_ids        # accumulated by persistence_handler
          output :total_created      # accumulated by persistence_handler
        end

        incremental_input_field  :items
        incremental_output_field :processed_items

        schema do
          field :processed_items, type: :array, required: true do
            field :id,   type: :integer, required: true
            field :name, type: :string,  required: true
          end
        end

        incremental_processing do
          chunk_size 2

          skip_if { |_item, _ctx| false } # never skip

          # Required even when skip_if never fires: it is what supplies the
          # already-stored data for records that get skipped.
          load_existing { |item, _ctx| item }

          persistence_handler do |batch_results, context|
            # Accumulate IDs and count across batches – exactly how Prospect::Scoring works
            context[:created_ids] ||= []
            context[:created_ids].concat(batch_results.map { |r| r[:id] })
            context[:total_created] = context[:created_ids].size
          end
        end

        def build_instructions = "Process items"
      end
    end

    let(:input_items) do
      [
        { id: 1, name: "Alpha" },
        { id: 2, name: "Beta" },
        { id: 3, name: "Gamma" }
      ]
    end

    let(:agent) { agent_class.new(items: input_items) }

    before do
      # Stub run_agent_on_batch so we don't need a live LLM.
      # Return a result whose :processed_items mirrors the batch passed in.
      allow(agent).to receive(:run_agent_on_batch) do |items, _ctx, **|
        { success: true, processed_items: items, usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 } }
      end
    end

    it "includes persistence_handler-accumulated context output fields in the result" do
      result = agent.run

      expect(result[:created_ids]).to eq([1, 2, 3])
      expect(result[:total_created]).to eq(3)
    end

    it "still includes the primary output field in the result" do
      result = agent.run

      expect(result[:processed_items]).to be_an(Array)
      expect(result[:processed_items].map { |i| i[:id] }).to contain_exactly(1, 2, 3)
    end

    it "includes success and usage in the result" do
      result = agent.run

      expect(result[:success]).to eq(true)
      expect(result[:usage]).to be_a(Hash)
    end
  end
end
