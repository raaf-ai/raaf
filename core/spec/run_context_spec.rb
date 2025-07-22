# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::RunContext do
  let(:messages) do
    [
      { role: "user", content: "Hello" },
      { role: "assistant", content: "Hi there!" },
      { role: "user", content: "How are you?" }
    ]
  end
  let(:metadata) { { user_id: 123, session_id: "sess_abc" } }
  let(:trace_id) { "trace_xyz789" }
  let(:group_id) { "group_123" }
  let(:agent) { create_test_agent(name: "TestAgent") }

  describe "#initialize" do
    it "initializes with default values" do
      context = described_class.new

      expect(context.messages).to eq([])
      expect(context.metadata).to eq({})
      expect(context.trace_id).to be_nil
      expect(context.group_id).to be_nil
      expect(context.current_agent).to be_nil
      expect(context.current_turn).to eq(0)
      expect(context.custom_data).to eq({})
    end

    it "initializes with provided values" do
      context = described_class.new(
        messages: messages,
        metadata: metadata,
        trace_id: trace_id,
        group_id: group_id
      )

      expect(context.messages).to eq(messages)
      expect(context.metadata).to eq(metadata)
      expect(context.trace_id).to eq(trace_id)
      expect(context.group_id).to eq(group_id)
    end

    it "allows setting agent and turn information" do
      context = described_class.new
      context.current_agent = agent
      context.current_turn = 5

      expect(context.current_agent).to eq(agent)
      expect(context.current_turn).to eq(5)
    end
  end

  describe "#input_messages" do
    it "returns user messages before first assistant response" do
      messages_with_multi_user = [
        { role: "system", content: "System prompt" },
        { role: "user", content: "First question" },
        { role: "user", content: "Second question" },
        { role: "assistant", content: "Response" },
        { role: "user", content: "Third question" }
      ]

      context = described_class.new(messages: messages_with_multi_user)
      input = context.input_messages

      expect(input).to eq([
                            { role: "user", content: "First question" },
                            { role: "user", content: "Second question" }
                          ])
    end

    it "returns empty array when no user messages before assistant" do
      messages_assistant_first = [
        { role: "assistant", content: "Hello!" },
        { role: "user", content: "Hi" }
      ]

      context = described_class.new(messages: messages_assistant_first)
      expect(context.input_messages).to eq([])
    end

    it "returns all user messages when no assistant responses" do
      user_only_messages = [
        { role: "user", content: "Question 1" },
        { role: "user", content: "Question 2" }
      ]

      context = described_class.new(messages: user_only_messages)
      expect(context.input_messages).to eq(user_only_messages)
    end

    it "ignores system messages in input detection" do
      mixed_messages = [
        { role: "system", content: "System message" },
        { role: "user", content: "User question" },
        { role: "assistant", content: "Assistant response" }
      ]

      context = described_class.new(messages: mixed_messages)
      expect(context.input_messages).to eq([{ role: "user", content: "User question" }])
    end
  end

  describe "#generated_messages" do
    it "returns messages from first assistant response onward" do
      context = described_class.new(messages: messages)
      generated = context.generated_messages

      expect(generated).to eq([
                                { role: "assistant", content: "Hi there!" },
                                { role: "user", content: "How are you?" }
                              ])
    end

    it "returns empty array when no assistant messages" do
      user_only = [
        { role: "user", content: "Hello" },
        { role: "user", content: "Anyone there?" }
      ]

      context = described_class.new(messages: user_only)
      expect(context.generated_messages).to eq([])
    end

    it "includes tool messages in generated content" do
      messages_with_tools = [
        { role: "user", content: "What's the weather?" },
        { role: "assistant", content: "Let me check", tool_calls: [{ id: "call_1", function: { name: "get_weather" } }] },
        { role: "tool", content: "Sunny, 72°F", tool_call_id: "call_1" },
        { role: "assistant", content: "It's sunny and 72°F!" }
      ]

      context = described_class.new(messages: messages_with_tools)
      generated = context.generated_messages

      expect(generated).to have(3).items
      expect(generated[0][:role]).to eq("assistant")
      expect(generated[1][:role]).to eq("tool")
      expect(generated[2][:role]).to eq("assistant")
    end
  end

  describe "#last_message" do
    it "returns the last message in the conversation" do
      context = described_class.new(messages: messages)
      expect(context.last_message).to eq({ role: "user", content: "How are you?" })
    end

    it "returns nil when no messages" do
      context = described_class.new
      expect(context.last_message).to be_nil
    end
  end

  describe "#messages_for_agent" do
    let(:multi_agent_messages) do
      [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi from Agent1", agent_name: "Agent1" },
        { role: "assistant", content: "Greetings from Agent2", agent_name: "Agent2" },
        { role: "user", content: "Thanks" },
        { role: "assistant", content: "You're welcome", agent_name: "Agent1" }
      ]
    end

    it "filters messages by agent name" do
      context = described_class.new(messages: multi_agent_messages)
      agent1_messages = context.messages_for_agent("Agent1")

      expect(agent1_messages).to have(2).items
      expect(agent1_messages[0][:content]).to eq("Hi from Agent1")
      expect(agent1_messages[1][:content]).to eq("You're welcome")
    end

    it "returns empty array for unknown agent" do
      context = described_class.new(messages: multi_agent_messages)
      expect(context.messages_for_agent("UnknownAgent")).to eq([])
    end

    it "handles messages without agent_name" do
      context = described_class.new(messages: messages)
      expect(context.messages_for_agent("AnyAgent")).to eq([])
    end
  end

  describe "data storage" do
    let(:context) { described_class.new }

    describe "#store and #fetch" do
      it "stores and retrieves custom data" do
        data = { preference: "dark_mode", language: "en" }
        context.store(:user_prefs, data)

        expect(context.fetch(:user_prefs)).to eq(data)
      end

      it "returns default value for missing key" do
        expect(context.fetch(:missing_key, "default")).to eq("default")
      end

      it "returns nil for missing key without default" do
        expect(context.fetch(:missing_key)).to be_nil
      end

      it "handles string and symbol keys" do
        context.store("string_key", "string_value")
        context.store(:symbol_key, "symbol_value")

        expect(context.fetch("string_key")).to eq("string_value")
        expect(context.fetch(:symbol_key)).to eq("symbol_value")
      end
    end

    describe "#key?" do
      it "returns true for existing keys" do
        context.store(:existing, "value")
        expect(context.key?(:existing)).to be true
      end

      it "returns false for non-existing keys" do
        expect(context.key?(:non_existing)).to be false
      end
    end
  end

  describe "#add_message" do
    let(:context) { described_class.new }

    it "adds message to the conversation" do
      message = { role: "assistant", content: "Hello!" }
      context.add_message(message)

      expect(context.messages).to include(message)
    end

    it "adds agent name when current_agent is set" do
      context.current_agent = agent
      message = { role: "assistant", content: "Response from agent" }

      context.add_message(message)
      added_message = context.messages.last

      expect(added_message[:agent_name]).to eq("TestAgent")
      expect(added_message[:role]).to eq("assistant")
      expect(added_message[:content]).to eq("Response from agent")
    end

    it "does not override existing agent_name" do
      context.current_agent = agent
      message = { role: "assistant", content: "Response", agent_name: "ExistingAgent" }

      context.add_message(message)
      added_message = context.messages.last

      expect(added_message[:agent_name]).to eq("ExistingAgent")
    end

    it "works without current_agent set" do
      message = { role: "user", content: "User input" }
      context.add_message(message)

      expect(context.messages.last).to eq(message)
    end
  end

  describe "#dup" do
    let(:original_context) do
      context = described_class.new(
        messages: messages,
        metadata: metadata,
        trace_id: trace_id,
        group_id: group_id
      )
      context.current_agent = agent
      context.current_turn = 3
      context.custom_data[:test_data] = "test_value"
      context.store(:stored_data, "stored_value")
      context
    end

    it "creates a deep copy of the context" do
      copied_context = original_context.dup

      expect(copied_context).to be_a(described_class)
      expect(copied_context).not_to be(original_context)
    end

    it "copies all basic attributes" do
      copied_context = original_context.dup

      expect(copied_context.messages).to eq(original_context.messages)
      expect(copied_context.metadata).to eq(original_context.metadata)
      expect(copied_context.trace_id).to eq(original_context.trace_id)
      expect(copied_context.group_id).to eq(original_context.group_id)
      expect(copied_context.current_agent).to eq(original_context.current_agent)
      expect(copied_context.current_turn).to eq(original_context.current_turn)
    end

    it "creates independent copies of mutable data" do
      copied_context = original_context.dup

      # Modify original messages
      original_context.messages << { role: "user", content: "New message" }

      # Copied messages should be unchanged
      expect(copied_context.messages).not_to include(role: "user", content: "New message")
    end

    it "copies custom data independently" do
      copied_context = original_context.dup

      # Modify original custom data
      original_context.custom_data[:new_key] = "new_value"

      # Copied custom data should not have the new key
      expect(copied_context.custom_data).not_to have_key(:new_key)
    end

    it "copies stored data independently" do
      copied_context = original_context.dup

      # Stored data from original should exist in copy
      expect(copied_context.fetch(:stored_data)).to eq("stored_value")

      # New stored data in original should not affect copy
      original_context.store(:new_stored, "new_stored_value")
      expect(copied_context.fetch(:new_stored)).to be_nil
    end
  end

  describe "#to_h" do
    let(:context) do
      ctx = described_class.new(
        messages: messages,
        metadata: metadata,
        trace_id: trace_id,
        group_id: group_id
      )
      ctx.current_turn = 2
      ctx.custom_data[:test] = "value"
      ctx
    end

    it "converts context to hash representation" do
      hash = context.to_h

      expect(hash).to be_a(Hash)
      expect(hash[:messages]).to eq(messages)
      expect(hash[:metadata]).to eq(metadata)
      expect(hash[:trace_id]).to eq(trace_id)
      expect(hash[:group_id]).to eq(group_id)
      expect(hash[:current_turn]).to eq(2)
      expect(hash[:custom_data]).to eq({ test: "value" })
    end

    it "includes all expected keys" do
      hash = context.to_h

      expected_keys = %i[messages metadata trace_id group_id current_turn custom_data]
      expect(hash.keys).to match_array(expected_keys)
    end
  end
end

RSpec.describe RAAF::RunContextWrapper do
  let(:base_context) do
    RAAF::RunContext.new(
      messages: [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi!" }
      ],
      metadata: { user_id: 123 }
    )
  end
  let(:wrapper) { described_class.new(base_context) }
  let(:agent1) { create_test_agent(name: "Agent1") }
  let(:agent2) { create_test_agent(name: "Agent2") }

  describe "#initialize" do
    it "wraps the provided context" do
      expect(wrapper.context).to eq(base_context)
    end
  end

  describe "delegation methods" do
    it "delegates basic context methods to wrapped context" do
      expect(wrapper.messages).to eq(base_context.messages)
      expect(wrapper.metadata).to eq(base_context.metadata)
      expect(wrapper.input_messages).to eq(base_context.input_messages)
      expect(wrapper.generated_messages).to eq(base_context.generated_messages)
    end

    it "delegates data storage methods" do
      wrapper.store(:test_key, "test_value")
      expect(wrapper.fetch(:test_key)).to eq("test_value")
      expect(base_context.fetch(:test_key)).to eq("test_value")
    end

    it "delegates message addition" do
      new_message = { role: "user", content: "New message" }
      wrapper.add_message(new_message)

      expect(wrapper.messages).to include(new_message)
      expect(base_context.messages).to include(new_message)
    end
  end

  describe "agent stack management" do
    describe "#agent_stack" do
      it "returns empty array initially" do
        expect(wrapper.agent_stack).to eq([])
      end

      it "returns stored agent stack" do
        wrapper.store(:agent_stack, [agent1, agent2])
        expect(wrapper.agent_stack).to eq([agent1, agent2])
      end
    end

    describe "#push_agent and #pop_agent" do
      it "manages agent stack like a stack data structure" do
        wrapper.push_agent(agent1)
        expect(wrapper.agent_stack).to eq([agent1])

        wrapper.push_agent(agent2)
        expect(wrapper.agent_stack).to eq([agent1, agent2])

        wrapper.pop_agent
        expect(wrapper.agent_stack).to eq([agent1])
      end

      it "persists agent stack in context storage" do
        wrapper.push_agent(agent1)
        wrapper.push_agent(agent2)

        # Stack should be accessible through context storage
        expect(wrapper.fetch(:agent_stack)).to eq([agent1, agent2])
      end
    end
  end

  describe "tool call tracking" do
    describe "#tool_calls" do
      it "returns empty array initially" do
        expect(wrapper.tool_calls).to eq([])
      end
    end

    describe "#add_tool_call" do
      it "tracks tool calls with metadata" do
        freeze_time = Time.parse("2024-01-01 12:00:00")
        allow(Time).to receive(:now).and_return(freeze_time)

        wrapper.add_tool_call("get_weather", { location: "NYC" }, "Sunny, 72°F")

        tool_calls = wrapper.tool_calls
        expect(tool_calls).to have(1).item

        call = tool_calls.first
        expect(call[:tool_name]).to eq("get_weather")
        expect(call[:arguments]).to eq({ location: "NYC" })
        expect(call[:result]).to eq("Sunny, 72°F")
        expect(call[:timestamp]).to eq(freeze_time)
      end

      it "accumulates multiple tool calls" do
        wrapper.add_tool_call("tool1", {}, "result1")
        wrapper.add_tool_call("tool2", {}, "result2")

        expect(wrapper.tool_calls).to have(2).items
        expect(wrapper.tool_calls.map { |c| c[:tool_name] }).to eq(%w[tool1 tool2])
      end
    end
  end

  describe "handoff tracking" do
    let(:base_context_with_turn) do
      ctx = RAAF::RunContext.new
      ctx.current_turn = 5
      ctx
    end
    let(:wrapper_with_turn) { described_class.new(base_context_with_turn) }

    describe "#handoffs" do
      it "returns empty array initially" do
        expect(wrapper.handoffs).to eq([])
      end
    end

    describe "#add_handoff" do
      it "tracks handoffs with metadata" do
        freeze_time = Time.parse("2024-01-01 12:00:00")
        allow(Time).to receive(:now).and_return(freeze_time)

        wrapper_with_turn.add_handoff(agent1, agent2)

        handoffs = wrapper_with_turn.handoffs
        expect(handoffs).to have(1).item

        handoff = handoffs.first
        expect(handoff[:from]).to eq("Agent1")
        expect(handoff[:to]).to eq("Agent2")
        expect(handoff[:turn]).to eq(5)
        expect(handoff[:timestamp]).to eq(freeze_time)
      end

      it "accumulates multiple handoffs" do
        agent3 = create_test_agent(name: "Agent3")

        wrapper_with_turn.add_handoff(agent1, agent2)
        wrapper_with_turn.add_handoff(agent2, agent3)

        handoffs = wrapper_with_turn.handoffs
        expect(handoffs).to have(2).items
        expect(handoffs[0][:from]).to eq("Agent1")
        expect(handoffs[0][:to]).to eq("Agent2")
        expect(handoffs[1][:from]).to eq("Agent2")
        expect(handoffs[1][:to]).to eq("Agent3")
      end
    end
  end
end

RSpec.describe RAAF::TypedRunContextWrapper do
  let(:base_context) { RAAF::RunContext.new }

  # Test type class
  class TestUserContext

    attr_accessor :user_id, :name, :preferences

    def initialize(user_id:, name: nil, preferences: {})
      @user_id = user_id
      @name = name
      @preferences = preferences
    end

    def to_h
      {
        user_id: @user_id,
        name: @name,
        preferences: @preferences
      }
    end

    def update(updates)
      updates.each { |key, value| send("#{key}=", value) if respond_to?("#{key}=") }
    end

  end

  describe "#initialize" do
    it "initializes with context and type class" do
      wrapper = described_class.new(base_context, TestUserContext)

      expect(wrapper.context).to eq(base_context)
      expect(wrapper.type_class).to eq(TestUserContext)
      expect(wrapper.typed_context).to be_nil
    end

    it "works without type class" do
      wrapper = described_class.new(base_context)

      expect(wrapper.type_class).to be_nil
    end
  end

  describe "#typed_context=" do
    let(:wrapper) { described_class.new(base_context, TestUserContext) }
    let(:user_context) { TestUserContext.new(user_id: 123, name: "Alice") }

    it "sets typed context of correct type" do
      wrapper.typed_context = user_context
      expect(wrapper.typed_context).to eq(user_context)
    end

    it "allows setting to nil" do
      wrapper.typed_context = user_context
      wrapper.typed_context = nil
      expect(wrapper.typed_context).to be_nil
    end

    it "raises TypeError for incorrect type" do
      expect do
        wrapper.typed_context = "not_correct_type"
      end.to raise_error(TypeError, "Expected TestUserContext, got String")
    end

    it "accepts any type when no type class specified" do
      untyped_wrapper = described_class.new(base_context)

      expect do
        untyped_wrapper.typed_context = "any_value"
        untyped_wrapper.typed_context = 123
        untyped_wrapper.typed_context = { any: "hash" }
      end.not_to raise_error
    end
  end

  describe "typed context query methods" do
    let(:wrapper) { described_class.new(base_context, TestUserContext) }
    let(:user_context) { TestUserContext.new(user_id: 456, name: "Bob") }

    describe "#typed_context?" do
      it "returns false when typed context is not set" do
        expect(wrapper.typed_context?).to be false
      end

      it "returns true when typed context is set" do
        wrapper.typed_context = user_context
        expect(wrapper.typed_context?).to be true
      end
    end

    describe "#typed_context!" do
      it "returns typed context when set" do
        wrapper.typed_context = user_context
        expect(wrapper.typed_context!).to eq(user_context)
      end

      it "raises error when typed context is not set" do
        expect do
          wrapper.typed_context!
        end.to raise_error(RuntimeError, "Typed context not set")
      end
    end

    describe "#typed_context_or" do
      it "returns typed context when set" do
        wrapper.typed_context = user_context
        expect(wrapper.typed_context_or("default")).to eq(user_context)
      end

      it "returns default when typed context is not set" do
        default_value = "fallback_value"
        expect(wrapper.typed_context_or(default_value)).to eq(default_value)
      end
    end
  end

  describe "#update_typed_context" do
    let(:wrapper) { described_class.new(base_context, TestUserContext) }
    let(:user_context) { TestUserContext.new(user_id: 789, name: "Charlie") }

    it "updates typed context using update method" do
      wrapper.typed_context = user_context

      wrapper.update_typed_context({ name: "Updated Charlie", user_id: 999 })

      expect(wrapper.typed_context.name).to eq("Updated Charlie")
      expect(wrapper.typed_context.user_id).to eq(999)
    end

    it "updates typed context using setter methods when update not available" do
      # Create object without update method
      simple_object = Object.new
      def simple_object.name=(value)
        @name = value
      end
      
      def simple_object.name
        @name
      end

      untyped_wrapper = described_class.new(base_context)
      untyped_wrapper.typed_context = simple_object

      untyped_wrapper.update_typed_context({ name: "Set Name" })
      expect(simple_object.name).to eq("Set Name")
    end

    it "returns nil when typed context is not set" do
      result = wrapper.update_typed_context({ name: "Should Not Work" })
      expect(result).to be_nil
    end
  end

  describe "#typed_context_to_h" do
    let(:wrapper) { described_class.new(base_context, TestUserContext) }
    let(:user_context) { TestUserContext.new(user_id: 321, name: "Diana", preferences: { theme: "dark" }) }

    it "converts typed context to hash using to_h method" do
      wrapper.typed_context = user_context
      hash = wrapper.typed_context_to_h

      expect(hash).to eq({
                           user_id: 321,
                           name: "Diana",
                           preferences: { theme: "dark" }
                         })
    end

    it "handles objects with to_hash method" do
      object_with_to_hash = Object.new
      def object_with_to_hash.to_hash
        { converted: "via_to_hash" }
      end

      untyped_wrapper = described_class.new(base_context)
      untyped_wrapper.typed_context = object_with_to_hash

      hash = untyped_wrapper.typed_context_to_h
      expect(hash).to eq({ converted: "via_to_hash" })
    end

    it "extracts instance variables as fallback" do
      simple_object = Object.new
      simple_object.instance_variable_set(:@id, 123)
      simple_object.instance_variable_set(:@status, "active")

      untyped_wrapper = described_class.new(base_context)
      untyped_wrapper.typed_context = simple_object

      hash = untyped_wrapper.typed_context_to_h
      expect(hash).to eq({ id: 123, status: "active" })
    end

    it "returns nil when typed context is not set" do
      expect(wrapper.typed_context_to_h).to be_nil
    end
  end

  describe "class methods" do
    let(:regular_wrapper) { RAAF::RunContextWrapper.new(base_context) }

    describe ".from_wrapper" do
      it "creates typed wrapper from regular wrapper" do
        typed_wrapper = described_class.from_wrapper(regular_wrapper, TestUserContext)

        expect(typed_wrapper).to be_a(described_class)
        expect(typed_wrapper.context).to eq(base_context)
        expect(typed_wrapper.type_class).to eq(TestUserContext)
      end
    end

    describe ".create_with_context" do
      it "creates typed wrapper with initial typed context" do
        user_context = TestUserContext.new(user_id: 555, name: "Eve")

        typed_wrapper = described_class.create_with_context(
          base_context,
          TestUserContext,
          user_context
        )

        expect(typed_wrapper.typed_context).to eq(user_context)
        expect(typed_wrapper.type_class).to eq(TestUserContext)
      end
    end
  end

  describe "string representations" do
    let(:wrapper) { described_class.new(base_context, TestUserContext) }
    let(:user_context) { TestUserContext.new(user_id: 777) }

    describe "#to_s and #inspect" do
      it "shows type and unset status when typed context is not set" do
        str = wrapper.to_s
        expect(str).to include("TypedRunContextWrapper")
        expect(str).to include("TestUserContext")
        expect(str).to include("[UNSET]")
      end

      it "shows type and set status when typed context is set" do
        wrapper.typed_context = user_context
        str = wrapper.to_s

        expect(str).to include("TypedRunContextWrapper")
        expect(str).to include("TestUserContext")
        expect(str).to include("[SET]")
      end

      it "handles wrapper without type class" do
        untyped_wrapper = described_class.new(base_context)
        str = untyped_wrapper.to_s

        expect(str).to include("TypedRunContextWrapper")
        expect(str).to include("[UNSET]")
        expect(str).not_to include("TestUserContext")
      end

      it "inspect returns same as to_s" do
        expect(wrapper.inspect).to eq(wrapper.to_s)
      end
    end
  end
end

RSpec.describe RAAF::ContextManager do
  let(:short_messages) do
    [
      { role: "user", content: "Hello" },
      { role: "assistant", content: "Hi there!" }
    ]
  end

  let(:long_messages) do
    # Create messages that would exceed token limit
    (1..50).map do |i|
      [
        { role: "user", content: "This is a long user message number #{i} with lots of content to test token limits and context management functionality." },
        { role: "assistant", content: "This is a long assistant response number #{i} with detailed information that takes up many tokens to test context truncation." }
      ]
    end.flatten
  end

  describe "#initialize" do
    it "initializes with default values" do
      manager = described_class.new

      expect(manager.max_tokens).to be > 0
      expect(manager.preserve_system).to be true
      expect(manager.preserve_recent).to eq(5)
    end

    it "accepts custom configuration" do
      manager = described_class.new(
        model: "gpt-3.5-turbo",
        max_tokens: 2000,
        preserve_system: false,
        preserve_recent: 10
      )

      expect(manager.max_tokens).to eq(2000)
      expect(manager.preserve_system).to be false
      expect(manager.preserve_recent).to eq(10)
    end

    it "handles unknown models gracefully" do
      expect do
        described_class.new(model: "unknown-model")
      end.not_to raise_error
    end
  end

  describe "#count_message_tokens" do
    let(:manager) { described_class.new(model: "gpt-4o") }

    it "counts tokens for simple messages" do
      message = { role: "user", content: "Hello world" }
      tokens = manager.count_message_tokens(message)

      expect(tokens).to be > 0
      expect(tokens).to be < 20 # Simple message should be under 20 tokens
    end

    it "counts tokens for messages with tool calls" do
      message = {
        role: "assistant",
        content: "I'll help you",
        tool_calls: [
          {
            "id" => "call_1",
            "function" => {
              "name" => "get_weather",
              "arguments" => '{"location": "New York"}'
            }
          }
        ]
      }

      tokens = manager.count_message_tokens(message)
      expect(tokens).to be > 10 # Should include tool call overhead
    end

    it "handles messages without content" do
      message = { role: "assistant" }
      tokens = manager.count_message_tokens(message)

      expect(tokens).to be > 0 # Should still have base overhead
    end
  end

  describe "#count_total_tokens" do
    let(:manager) { described_class.new(model: "gpt-4o") }

    it "counts tokens for conversation" do
      tokens = manager.count_total_tokens(short_messages)

      expect(tokens).to be > 0
      expect(tokens).to be > short_messages.sum { |msg| manager.count_message_tokens(msg) }
    end

    it "returns base tokens for empty conversation" do
      tokens = manager.count_total_tokens([])
      expect(tokens).to eq(3) # Base conversation overhead
    end
  end

  describe "#manage_context" do
    context "with messages under token limit" do
      let(:manager) { described_class.new(model: "gpt-4o", max_tokens: 10_000) }

      it "returns messages unchanged when under limit" do
        managed = manager.manage_context(short_messages)
        expect(managed).to eq(short_messages)
      end

      it "handles empty message arrays" do
        managed = manager.manage_context([])
        expect(managed).to eq([])
      end
    end

    context "with messages over token limit" do
      let(:manager) { described_class.new(model: "gpt-4o", max_tokens: 500, preserve_recent: 3) }

      it "reduces message count when over limit" do
        managed = manager.manage_context(long_messages)

        expect(managed.length).to be < long_messages.length
        expect(managed.length).to be > 0
      end

      it "preserves recent messages" do
        recent_messages = long_messages.last(3)
        managed = manager.manage_context(long_messages)

        # Last few messages should be preserved
        expect(managed.last(3)).to eq(recent_messages)
      end

      it "adds truncation notice when messages are removed" do
        managed = manager.manage_context(long_messages)

        truncation_messages = managed.select { |msg| msg[:content]&.include?("truncated") }
        expect(truncation_messages).not_to be_empty
      end
    end

    context "with system message preservation" do
      let(:messages_with_system) do
        [
          { role: "system", content: "You are a helpful assistant" },
          { role: "user", content: "Hello" },
          *long_messages,
          { role: "user", content: "Latest question" }
        ]
      end
      let(:manager) { described_class.new(model: "gpt-4o", max_tokens: 300, preserve_system: true, preserve_recent: 2) }

      it "preserves system messages when preserve_system is true" do
        managed = manager.manage_context(messages_with_system)

        system_messages = managed.select { |msg| msg[:role] == "system" && !msg[:content].include?("truncated") }
        expect(system_messages).to have(1).item
        expect(system_messages.first[:content]).to eq("You are a helpful assistant")
      end

      it "does not preserve system messages when preserve_system is false" do
        manager_no_system = described_class.new(
          model: "gpt-4o",
          max_tokens: 300,
          preserve_system: false,
          preserve_recent: 2
        )

        managed = manager_no_system.manage_context(messages_with_system)

        preserved_system = managed.select { |msg| msg[:role] == "system" && !msg[:content].include?("truncated") }
        expect(preserved_system).to be_empty
      end
    end

    context "with complex conversation scenarios" do
      let(:complex_conversation) do
        [
          { role: "system", content: "You are a coding assistant" },
          { role: "user", content: "Help me debug this code" },
          { role: "assistant", content: "I'll help you debug", tool_calls: [{ "id" => "call_1", "function" => { "name" => "analyze_code" } }] },
          { role: "tool", content: "Analysis results", tool_call_id: "call_1" },
          { role: "assistant", content: "Based on the analysis..." },
          *long_messages, # Add many more messages
          { role: "user", content: "Final question" }
        ]
      end
      let(:manager) { described_class.new(model: "gpt-4o", max_tokens: 400, preserve_recent: 4) }

      it "handles conversations with tool calls" do
        managed = manager.manage_context(complex_conversation)

        # Should have system message, truncation notice, and recent messages
        expect(managed.length).to be > 4
        expect(managed.length).to be < complex_conversation.length

        # Check that recent messages are preserved
        expect(managed.last[:content]).to eq("Final question")
      end

      it "maintains conversation coherence" do
        managed = manager.manage_context(complex_conversation)

        # Should start with system message (or truncation notice)
        first_msg = managed.first
        expect(["system"]).to include(first_msg[:role])

        # Should end with recent user/assistant messages
        last_msg = managed.last
        expect(%w[user assistant tool]).to include(last_msg[:role])
      end
    end
  end

  describe "token limit handling for different models" do
    it "uses appropriate limits for different model types" do
      gpt4_manager = described_class.new(model: "gpt-4o")
      gpt35_manager = described_class.new(model: "gpt-3.5-turbo")
      unknown_manager = described_class.new(model: "unknown-model")

      expect(gpt4_manager.max_tokens).to be > gpt35_manager.max_tokens
      expect(unknown_manager.max_tokens).to be > 1000 # Should have reasonable default
    end

    it "respects explicit max_tokens override" do
      manager = described_class.new(model: "gpt-4o", max_tokens: 1000)
      expect(manager.max_tokens).to eq(1000)
    end
  end

  describe "edge cases and error handling" do
    let(:manager) { described_class.new(model: "gpt-4o", max_tokens: 50) } # Very small limit

    it "handles extremely small token limits" do
      managed = manager.manage_context(long_messages)

      # Should return at least recent messages, even if over limit
      expect(managed).not_to be_empty
    end

    it "handles conversations with no user messages" do
      assistant_only = [
        { role: "assistant", content: "I'm starting the conversation" },
        { role: "assistant", content: "Still talking..." }
      ]

      managed = manager.manage_context(assistant_only)
      expect(managed).not_to be_empty
    end

    it "handles messages with empty content" do
      mixed_messages = [
        { role: "user", content: "" },
        { role: "assistant", content: "Response to empty message" },
        { role: "user", content: "Follow-up question" }
      ]

      managed = manager.manage_context(mixed_messages)
      expect(managed).not_to be_empty
    end
  end
end
