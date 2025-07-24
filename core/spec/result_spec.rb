# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF Result Types" do
  describe RAAF::Result do
    describe "#initialize" do
      it "creates result with all parameters" do
        metadata = { user_id: 123, operation: "test" }
        result = described_class.new(
          success: true,
          data: "test data",
          error: "test error",
          metadata: metadata
        )

        expect(result.success).to be true
        expect(result.data).to eq("test data")
        expect(result.error).to eq("test error")
        expect(result.metadata).to eq(metadata)
        expect(result.timestamp).to be_a(Time)
      end

      it "duplicates metadata hash to prevent external modification" do
        original_metadata = { key: "value" }
        result = described_class.new(success: true, metadata: original_metadata)

        result.metadata[:key] = "modified"
        expect(original_metadata[:key]).to eq("value")
      end

      it "sets timestamp to current UTC time" do
        before_time = Time.now.utc
        result = described_class.new(success: true)
        after_time = Time.now.utc

        expect(result.timestamp).to be >= before_time
        expect(result.timestamp).to be <= after_time
        expect(result.timestamp.utc?).to be true
      end
    end

    describe "#success?" do
      it "returns true for successful results" do
        result = described_class.new(success: true)
        expect(result.success?).to be true
      end

      it "returns false for failed results" do
        result = described_class.new(success: false)
        expect(result.success?).to be false
      end
    end

    describe "#failure?" do
      it "returns false for successful results" do
        result = described_class.new(success: true)
        expect(result.failure?).to be false
      end

      it "returns true for failed results" do
        result = described_class.new(success: false)
        expect(result.failure?).to be true
      end
    end

    describe "#error?" do
      it "returns false for successful results even with error set" do
        result = described_class.new(success: true, error: "some error")
        expect(result).not_to be_error
      end

      it "returns truthy for failed results with error" do
        result = described_class.new(success: false, error: "error message")
        expect(result).to be_error
      end

      it "returns false for failed results without error" do
        result = described_class.new(success: false)
        expect(result).not_to be_error
      end
    end

    describe "#to_h" do
      it "converts result to hash with all fields" do
        timestamp = Time.parse("2024-01-01T12:00:00Z")
        allow(Time).to receive(:now).and_return(timestamp)

        metadata = { user_id: 123 }
        result = described_class.new(
          success: true,
          data: "test data",
          error: "test error",
          metadata: metadata
        )

        hash = result.to_h

        expect(hash).to eq({
                             success: true,
                             data: "test data",
                             error: "test error",
                             metadata: metadata,
                             timestamp: timestamp.iso8601
                           })
      end
    end

    describe "#to_json" do
      it "converts result to JSON string" do
        result = described_class.new(success: true, data: { message: "hello" })
        json_string = result.to_json
        parsed = JSON.parse(json_string)

        expect(parsed).to include(
          "success" => true,
          "data" => { "message" => "hello" }
        )
        expect(parsed).to have_key("timestamp")
      end

      it "passes additional arguments to JSON.generate" do
        result = described_class.new(success: true, data: { key: "value" })
        json_string = result.to_json(pretty: true)

        expect(json_string).to be_a(String)
        parsed = JSON.parse(json_string)
        expect(parsed).to include("data" => { "key" => "value" })
      end
    end

    describe ".success" do
      it "creates successful result with data" do
        data = { message: "success" }
        metadata = { operation: "test" }
        result = described_class.success(data, metadata: metadata)

        expect(result.success?).to be true
        expect(result.failure?).to be false
        expect(result.data).to eq(data)
        expect(result.error).to be_nil
        expect(result.metadata).to eq(metadata)
      end

      it "creates successful result with nil data" do
        result = described_class.success

        expect(result.success?).to be true
        expect(result.data).to be_nil
        expect(result.metadata).to eq({})
      end
    end

    describe ".failure" do
      it "creates failure result with error message" do
        error_msg = "Something went wrong"
        metadata = { context: "test" }
        result = described_class.failure(error_msg, metadata: metadata)

        expect(result.success?).to be false
        expect(result.failure?).to be true
        expect(result.error).to eq(error_msg)
        expect(result.data).to be_nil
        expect(result.metadata).to eq(metadata)
      end

      it "creates failure result with exception" do
        exception = StandardError.new("Test error")
        result = described_class.failure(exception)

        expect(result.failure?).to be true
        expect(result.error).to eq(exception)
      end
    end
  end

  describe RAAF::AgentResult do
    describe "#initialize" do
      it "creates agent result with all parameters" do
        messages = [{ role: "user", content: "Hello" }]
        handoffs = [{ from: "Agent1", to: "Agent2" }]
        tool_calls = %w[search calculate]

        result = described_class.new(
          success: true,
          agent_name: "TestAgent",
          messages: messages,
          turns: 5,
          handoffs: handoffs,
          tool_calls: tool_calls,
          data: "agent data"
        )

        expect(result.agent_name).to eq("TestAgent")
        expect(result.messages).to eq(messages)
        expect(result.turns).to eq(5)
        expect(result.handoffs).to eq(handoffs)
        expect(result.tool_calls).to eq(tool_calls)
        expect(result.data).to eq("agent data")
      end

      it "duplicates arrays to prevent external modification" do
        original_messages = [{ role: "user", content: "test" }]
        original_handoffs = [{ from: "A", to: "B" }]
        original_tools = ["tool1"]

        result = described_class.new(
          success: true,
          agent_name: "Test",
          messages: original_messages,
          handoffs: original_handoffs,
          tool_calls: original_tools
        )

        result.messages << { role: "assistant", content: "response" }
        result.handoffs << { from: "B", to: "C" }
        result.tool_calls << "tool2"

        expect(original_messages.length).to eq(1)
        expect(original_handoffs.length).to eq(1)
        expect(original_tools.length).to eq(1)
      end

      it "defaults empty arrays for optional parameters" do
        result = described_class.new(success: true, agent_name: "Test")

        expect(result.messages).to eq([])
        expect(result.turns).to eq(0)
        expect(result.handoffs).to eq([])
        expect(result.tool_calls).to eq([])
      end
    end

    describe "#final_message" do
      it "returns last message when messages exist" do
        messages = [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi there" }
        ]
        result = described_class.new(success: true, agent_name: "Test", messages: messages)

        expect(result.final_message).to eq({ role: "assistant", content: "Hi there" })
      end

      it "returns nil when no messages" do
        result = described_class.new(success: true, agent_name: "Test")

        expect(result.final_message).to be_nil
      end
    end

    describe "#assistant_messages" do
      it "returns only assistant messages" do
        messages = [
          { role: "user", content: "Question" },
          { role: "assistant", content: "Answer 1" },
          { role: "user", content: "Follow-up" },
          { role: "assistant", content: "Answer 2" },
          { role: "tool", content: "Tool result" }
        ]
        result = described_class.new(success: true, agent_name: "Test", messages: messages)

        assistant_msgs = result.assistant_messages
        expect(assistant_msgs.length).to eq(2)
        expect(assistant_msgs[0][:content]).to eq("Answer 1")
        expect(assistant_msgs[1][:content]).to eq("Answer 2")
      end

      it "returns empty array when no assistant messages" do
        messages = [{ role: "user", content: "Hello" }]
        result = described_class.new(success: true, agent_name: "Test", messages: messages)

        expect(result.assistant_messages).to eq([])
      end
    end

    describe "#user_messages" do
      it "returns only user messages" do
        messages = [
          { role: "user", content: "Question 1" },
          { role: "assistant", content: "Answer" },
          { role: "user", content: "Question 2" }
        ]
        result = described_class.new(success: true, agent_name: "Test", messages: messages)

        user_msgs = result.user_messages
        expect(user_msgs.length).to eq(2)
        expect(user_msgs[0][:content]).to eq("Question 1")
        expect(user_msgs[1][:content]).to eq("Question 2")
      end
    end

    describe "#tool_messages" do
      it "returns only tool messages" do
        messages = [
          { role: "user", content: "Question" },
          { role: "tool", content: "Tool result 1" },
          { role: "assistant", content: "Answer" },
          { role: "tool", content: "Tool result 2" }
        ]
        result = described_class.new(success: true, agent_name: "Test", messages: messages)

        tool_msgs = result.tool_messages
        expect(tool_msgs.length).to eq(2)
        expect(tool_msgs[0][:content]).to eq("Tool result 1")
        expect(tool_msgs[1][:content]).to eq("Tool result 2")
      end
    end

    describe "#conversation_length" do
      it "returns total message count" do
        messages = [
          { role: "user", content: "Q1" },
          { role: "assistant", content: "A1" },
          { role: "user", content: "Q2" }
        ]
        result = described_class.new(success: true, agent_name: "Test", messages: messages)

        expect(result.conversation_length).to eq(3)
      end

      it "returns zero for empty messages" do
        result = described_class.new(success: true, agent_name: "Test")
        expect(result.conversation_length).to eq(0)
      end
    end

    describe "#total_handoffs" do
      it "returns handoff count" do
        handoffs = [{ from: "A", to: "B" }, { from: "B", to: "C" }]
        result = described_class.new(success: true, agent_name: "Test", handoffs: handoffs)

        expect(result.total_handoffs).to eq(2)
      end

      it "returns zero when no handoffs" do
        result = described_class.new(success: true, agent_name: "Test")
        expect(result.total_handoffs).to eq(0)
      end
    end

    describe "#total_tool_calls" do
      it "returns tool call count" do
        tool_calls = %w[search calculate format]
        result = described_class.new(success: true, agent_name: "Test", tool_calls: tool_calls)

        expect(result.total_tool_calls).to eq(3)
      end

      it "returns zero when no tool calls" do
        result = described_class.new(success: true, agent_name: "Test")
        expect(result.total_tool_calls).to eq(0)
      end
    end

    describe "#to_h" do
      it "includes agent-specific fields and stats" do
        result = described_class.new(
          success: true,
          agent_name: "TestAgent",
          messages: [{ role: "user", content: "test" }],
          turns: 2,
          handoffs: [{ from: "A", to: "B" }],
          tool_calls: %w[tool1 tool2]
        )

        hash = result.to_h

        expect(hash[:agent_name]).to eq("TestAgent")
        expect(hash[:messages]).to eq([{ role: "user", content: "test" }])
        expect(hash[:turns]).to eq(2)
        expect(hash[:handoffs]).to eq([{ from: "A", to: "B" }])
        expect(hash[:tool_calls]).to eq(%w[tool1 tool2])
        expect(hash[:stats]).to eq({
                                     conversation_length: 1,
                                     total_handoffs: 1,
                                     total_tool_calls: 2
                                   })
      end
    end

    describe ".success" do
      it "creates successful agent result" do
        result = described_class.success(
          agent_name: "TestAgent",
          messages: [{ role: "assistant", content: "Success" }],
          turns: 3
        )

        expect(result.success?).to be true
        expect(result.agent_name).to eq("TestAgent")
        expect(result.messages).to eq([{ role: "assistant", content: "Success" }])
        expect(result.turns).to eq(3)
      end
    end

    describe ".failure" do
      it "creates failed agent result" do
        result = described_class.failure(
          agent_name: "TestAgent",
          error: "Agent failed",
          turns: 2
        )

        expect(result.failure?).to be true
        expect(result.agent_name).to eq("TestAgent")
        expect(result.error).to eq("Agent failed")
        expect(result.turns).to eq(2)
      end
    end
  end

  describe RAAF::ToolResult do
    describe "#initialize" do
      it "creates tool result with all parameters" do
        input_args = { query: "test", limit: 10 }
        result = described_class.new(
          success: true,
          tool_name: "search_tool",
          input_args: input_args,
          execution_time: 1.5,
          data: "search results"
        )

        expect(result.tool_name).to eq("search_tool")
        expect(result.input_args).to eq(input_args)
        expect(result.execution_time).to eq(1.5)
        expect(result.data).to eq("search results")
      end

      it "duplicates input_args to prevent external modification" do
        original_args = { key: "value" }
        result = described_class.new(success: true, tool_name: "test", input_args: original_args)

        result.input_args[:key] = "modified"
        expect(original_args[:key]).to eq("value")
      end

      it "defaults empty hash for input_args" do
        result = described_class.new(success: true, tool_name: "test")
        expect(result.input_args).to eq({})
      end

      it "handles nil execution_time" do
        result = described_class.new(success: true, tool_name: "test")
        expect(result.execution_time).to be_nil
      end
    end

    describe "#execution_time_ms" do
      it "converts seconds to milliseconds" do
        result = described_class.new(success: true, tool_name: "test", execution_time: 1.234)
        expect(result.execution_time_ms).to eq(1234.0)
      end

      it "rounds to 2 decimal places" do
        result = described_class.new(success: true, tool_name: "test", execution_time: 0.123456)
        expect(result.execution_time_ms).to eq(123.46)
      end

      it "returns nil when execution_time is nil" do
        result = described_class.new(success: true, tool_name: "test")
        expect(result.execution_time_ms).to be_nil
      end
    end

    describe "#to_h" do
      it "includes tool-specific fields" do
        result = described_class.new(
          success: true,
          tool_name: "calculator",
          input_args: { a: 5, b: 3 },
          execution_time: 0.05,
          data: 8
        )

        hash = result.to_h
        expect(hash[:tool_name]).to eq("calculator")
        expect(hash[:input_args]).to eq({ a: 5, b: 3 })
        expect(hash[:execution_time_ms]).to eq(50.0)
        expect(hash[:data]).to eq(8)
      end
    end

    describe ".success" do
      it "creates successful tool result" do
        result = described_class.success(
          tool_name: "search",
          data: "results",
          input_args: { query: "test" }
        )

        expect(result.success?).to be true
        expect(result.tool_name).to eq("search")
        expect(result.data).to eq("results")
        expect(result.input_args).to eq({ query: "test" })
      end

      it "handles nil data" do
        result = described_class.success(tool_name: "cleanup")
        expect(result.data).to be_nil
      end
    end

    describe ".failure" do
      it "creates failed tool result" do
        result = described_class.failure(
          tool_name: "broken_tool",
          error: "Connection timeout",
          input_args: { url: "http://example.com" }
        )

        expect(result.failure?).to be true
        expect(result.tool_name).to eq("broken_tool")
        expect(result.error).to eq("Connection timeout")
        expect(result.input_args).to eq({ url: "http://example.com" })
      end
    end
  end

  describe RAAF::StreamingResult do
    describe "#initialize" do
      it "creates streaming result with default parameters" do
        result = described_class.new

        expect(result.success?).to be true
        expect(result.chunks).to eq([])
        expect(result.complete?).to be false
      end

      it "creates streaming result with initial chunks" do
        initial_chunks = [
          { content: "Hello", timestamp: "2024-01-01T12:00:00Z" }
        ]
        result = described_class.new(chunks: initial_chunks, complete: true)

        expect(result.chunks).to eq(initial_chunks)
        expect(result.complete?).to be true
      end

      it "duplicates chunks array to prevent external modification" do
        original_chunks = [{ content: "test", timestamp: "2024-01-01" }]
        result = described_class.new(chunks: original_chunks)

        result.chunks << { content: "new", timestamp: "2024-01-02" }
        expect(original_chunks.length).to eq(1)
      end
    end

    describe "#add_chunk" do
      it "adds chunk with content and timestamp" do
        result = described_class.new

        result.add_chunk("Hello")

        expect(result.chunks.length).to eq(1)
        chunk = result.chunks.first
        expect(chunk[:content]).to eq("Hello")
        expect(chunk[:timestamp]).to be_a(String)
        expect(Time.parse(chunk[:timestamp])).to be_a(Time)
      end

      it "adds multiple chunks in order" do
        result = described_class.new

        result.add_chunk("First")
        result.add_chunk("Second")
        result.add_chunk("Third")

        expect(result.chunks.length).to eq(3)
        expect(result.chunks[0][:content]).to eq("First")
        expect(result.chunks[1][:content]).to eq("Second")
        expect(result.chunks[2][:content]).to eq("Third")
      end
    end

    describe "#complete!" do
      it "marks stream as complete" do
        result = described_class.new
        expect(result.complete?).to be false

        result.complete!
        expect(result.complete?).to be true
      end
    end

    describe "#complete?" do
      it "returns completion status" do
        result = described_class.new
        expect(result.complete?).to be false

        result = described_class.new(complete: true)
        expect(result.complete?).to be true
      end
    end

    describe "#full_content" do
      it "joins all chunk content" do
        result = described_class.new
        result.add_chunk("Hello")
        result.add_chunk(" ")
        result.add_chunk("world")

        expect(result.full_content).to eq("Hello world")
      end

      it "returns empty string for no chunks" do
        result = described_class.new
        expect(result.full_content).to eq("")
      end
    end

    describe "#chunk_count" do
      it "returns number of chunks" do
        result = described_class.new
        expect(result.chunk_count).to eq(0)

        result.add_chunk("chunk1")
        result.add_chunk("chunk2")
        expect(result.chunk_count).to eq(2)
      end
    end

    describe "#to_h" do
      it "includes streaming-specific fields" do
        result = described_class.new
        result.add_chunk("test")
        result.complete!

        hash = result.to_h
        expect(hash[:chunks]).to be_an(Array)
        expect(hash[:complete]).to be true
        expect(hash[:full_content]).to eq("test")
        expect(hash[:chunk_count]).to eq(1)
      end
    end
  end

  describe RAAF::HandoffResult do
    describe "#initialize" do
      it "creates handoff result with all parameters" do
        handoff_data = { context: "user needs help", priority: "high" }
        result = described_class.new(
          success: true,
          from_agent: "Assistant",
          to_agent: "Specialist",
          reason: "Requires expertise",
          handoff_data: handoff_data
        )

        expect(result.from_agent).to eq("Assistant")
        expect(result.to_agent).to eq("Specialist")
        expect(result.reason).to eq("Requires expertise")
        expect(result.handoff_data).to eq(handoff_data)
      end

      it "duplicates handoff_data to prevent external modification" do
        original_data = { context: "test" }
        result = described_class.new(
          success: true,
          from_agent: "A",
          to_agent: "B",
          handoff_data: original_data
        )

        result.handoff_data[:context] = "modified"
        expect(original_data[:context]).to eq("test")
      end

      it "defaults empty hash for handoff_data" do
        result = described_class.new(success: true, from_agent: "A", to_agent: "B")
        expect(result.handoff_data).to eq({})
      end

      it "handles nil reason" do
        result = described_class.new(success: true, from_agent: "A", to_agent: "B")
        expect(result.reason).to be_nil
      end
    end

    describe "#to_h" do
      it "includes handoff-specific fields" do
        result = described_class.new(
          success: true,
          from_agent: "Bot",
          to_agent: "Human",
          reason: "Escalation needed",
          handoff_data: { ticket_id: "12345" }
        )

        hash = result.to_h
        expect(hash[:from_agent]).to eq("Bot")
        expect(hash[:to_agent]).to eq("Human")
        expect(hash[:reason]).to eq("Escalation needed")
        expect(hash[:handoff_data]).to eq({ ticket_id: "12345" })
      end
    end

    describe ".success" do
      it "creates successful handoff result" do
        result = described_class.success(
          from_agent: "A",
          to_agent: "B",
          reason: "Task complete"
        )

        expect(result.success?).to be true
        expect(result.from_agent).to eq("A")
        expect(result.to_agent).to eq("B")
        expect(result.reason).to eq("Task complete")
      end
    end

    describe ".failure" do
      it "creates failed handoff result" do
        result = described_class.failure(
          from_agent: "A",
          to_agent: "B",
          error: "Target agent unavailable"
        )

        expect(result.failure?).to be true
        expect(result.from_agent).to eq("A")
        expect(result.to_agent).to eq("B")
        expect(result.error).to eq("Target agent unavailable")
      end
    end
  end

  describe RAAF::ValidationResult do
    describe "#initialize" do
      it "creates validation result with all parameters" do
        schema = { type: "object", required: ["name"] }
        violations = [
          { field: "name", message: "is required" },
          { field: "age", message: "must be positive" }
        ]

        result = described_class.new(
          success: false,
          schema: schema,
          violations: violations
        )

        expect(result.schema).to eq(schema)
        expect(result.violations).to eq(violations)
      end

      it "duplicates violations array to prevent external modification" do
        original_violations = [{ field: "test", message: "error" }]
        result = described_class.new(success: false, violations: original_violations)

        result.violations << { field: "new", message: "new error" }
        expect(original_violations.length).to eq(1)
      end

      it "defaults empty array for violations" do
        result = described_class.new(success: true)
        expect(result.violations).to eq([])
      end
    end

    describe "#valid?" do
      it "returns true when successful and no violations" do
        result = described_class.new(success: true, violations: [])
        expect(result.valid?).to be true
      end

      it "returns false when unsuccessful" do
        result = described_class.new(success: false, violations: [])
        expect(result.valid?).to be false
      end

      it "returns false when has violations even if successful" do
        result = described_class.new(success: true, violations: [{ message: "error" }])
        expect(result.valid?).to be false
      end
    end

    describe "#invalid?" do
      it "returns opposite of valid?" do
        valid_result = described_class.new(success: true, violations: [])
        invalid_result = described_class.new(success: false, violations: [{ message: "error" }])

        expect(valid_result.invalid?).to be false
        expect(invalid_result.invalid?).to be true
      end
    end

    describe "#violation_count" do
      it "returns number of violations" do
        violations = [
          { field: "name", message: "required" },
          { field: "email", message: "invalid" }
        ]
        result = described_class.new(success: false, violations: violations)

        expect(result.violation_count).to eq(2)
      end

      it "returns zero for no violations" do
        result = described_class.new(success: true)
        expect(result.violation_count).to eq(0)
      end
    end

    describe "#violation_messages" do
      it "extracts messages from violation objects" do
        violations = [
          { field: "name", message: "is required" },
          { field: "age", message: "must be positive" }
        ]
        result = described_class.new(success: false, violations: violations)

        expect(result.violation_messages).to eq(["is required", "must be positive"])
      end

      it "handles hash violations with message keys" do
        violations = [
          { message: "first error" },
          { message: "second error" }
        ]
        result = described_class.new(success: false, violations: violations)

        expect(result.violation_messages).to eq(["first error", "second error"])
      end

      it "returns empty array for no violations" do
        result = described_class.new(success: true)
        expect(result.violation_messages).to eq([])
      end
    end

    describe "#to_h" do
      it "includes validation-specific fields" do
        schema = { type: "string" }
        violations = [{ message: "invalid" }]
        result = described_class.new(success: false, schema: schema, violations: violations)

        hash = result.to_h
        expect(hash[:schema]).to eq(schema)
        expect(hash[:violations]).to eq(violations)
        expect(hash[:valid]).to be false
        expect(hash[:violation_count]).to eq(1)
      end
    end

    describe ".valid" do
      it "creates valid validation result" do
        data = { name: "John", age: 30 }
        schema = { type: "object" }
        result = described_class.valid(data: data, schema: schema)

        expect(result.valid?).to be true
        expect(result.data).to eq(data)
        expect(result.schema).to eq(schema)
        expect(result.violations).to eq([])
      end
    end

    describe ".invalid" do
      it "creates invalid validation result" do
        violations = [{ field: "name", message: "required" }]
        schema = { type: "object" }
        result = described_class.invalid(violations: violations, schema: schema)

        expect(result.invalid?).to be true
        expect(result.violations).to eq(violations)
        expect(result.schema).to eq(schema)
      end
    end
  end

  describe RAAF::BatchResult do
    describe "#initialize" do
      it "creates empty batch result" do
        result = described_class.new

        expect(result.results).to eq([])
        expect(result.total_count).to eq(0)
        expect(result.success_count).to eq(0)
        expect(result.failure_count).to eq(0)
        expect(result.success?).to be true # No failures means overall success
      end

      it "creates batch result with initial results" do
        results = [
          RAAF::Result.success("op1"),
          RAAF::Result.failure("error1"),
          RAAF::Result.success("op3")
        ]
        batch = described_class.new(results: results)

        expect(batch.results).to eq(results)
        expect(batch.total_count).to eq(3)
        expect(batch.success_count).to eq(2)
        expect(batch.failure_count).to eq(1)
        expect(batch.success?).to be false # Has failures
      end

      it "duplicates results array to prevent external modification" do
        original_results = [RAAF::Result.success("test")]
        batch = described_class.new(results: original_results)

        batch.results << RAAF::Result.success("new")
        expect(original_results.length).to eq(1)
      end
    end

    describe "#add_result" do
      it "adds result and updates counts" do
        batch = described_class.new
        expect(batch.success?).to be true

        batch.add_result(RAAF::Result.success("op1"))
        expect(batch.total_count).to eq(1)
        expect(batch.success_count).to eq(1)
        expect(batch.failure_count).to eq(0)
        expect(batch.success?).to be true

        batch.add_result(RAAF::Result.failure("error"))
        expect(batch.total_count).to eq(2)
        expect(batch.success_count).to eq(1)
        expect(batch.failure_count).to eq(1)
        expect(batch.success?).to be false
      end

      it "maintains correct overall success status" do
        batch = described_class.new

        # All successes = overall success
        batch.add_result(RAAF::Result.success("op1"))
        batch.add_result(RAAF::Result.success("op2"))
        expect(batch.success?).to be true

        # Add failure = overall failure
        batch.add_result(RAAF::Result.failure("error"))
        expect(batch.success?).to be false
      end
    end

    describe "#success_rate" do
      it "calculates percentage for mixed results" do
        results = [
          RAAF::Result.success("op1"),
          RAAF::Result.success("op2"),
          RAAF::Result.failure("error1")
        ]
        batch = described_class.new(results: results)

        expect(batch.success_rate).to eq(66.67)
      end

      it "returns 100% for all successful results" do
        results = [
          RAAF::Result.success("op1"),
          RAAF::Result.success("op2")
        ]
        batch = described_class.new(results: results)

        expect(batch.success_rate).to eq(100.0)
      end

      it "returns 0% for all failed results" do
        results = [
          RAAF::Result.failure("error1"),
          RAAF::Result.failure("error2")
        ]
        batch = described_class.new(results: results)

        expect(batch.success_rate).to eq(0.0)
      end

      it "returns 0% for empty results" do
        batch = described_class.new
        expect(batch.success_rate).to eq(0.0)
      end
    end

    describe "#successful_results" do
      it "returns only successful results" do
        success1 = RAAF::Result.success("op1")
        failure1 = RAAF::Result.failure("error1")
        success2 = RAAF::Result.success("op2")

        batch = described_class.new(results: [success1, failure1, success2])
        successful = batch.successful_results

        expect(successful).to eq([success1, success2])
      end

      it "returns empty array when no successes" do
        results = [RAAF::Result.failure("error1")]
        batch = described_class.new(results: results)

        expect(batch.successful_results).to eq([])
      end
    end

    describe "#failed_results" do
      it "returns only failed results" do
        success1 = RAAF::Result.success("op1")
        failure1 = RAAF::Result.failure("error1")
        failure2 = RAAF::Result.failure("error2")

        batch = described_class.new(results: [success1, failure1, failure2])
        failed = batch.failed_results

        expect(failed).to eq([failure1, failure2])
      end

      it "returns empty array when no failures" do
        results = [RAAF::Result.success("op1")]
        batch = described_class.new(results: results)

        expect(batch.failed_results).to eq([])
      end
    end

    describe "#each_result" do
      it "iterates over all results" do
        results = [
          RAAF::Result.success("op1"),
          RAAF::Result.failure("error1"),
          RAAF::Result.success("op2")
        ]
        batch = described_class.new(results: results)

        iterated_results = []
        batch.each_result { |result| iterated_results << result }

        expect(iterated_results).to eq(results)
      end
    end

    describe "#[]" do
      it "returns result at given index" do
        results = [
          RAAF::Result.success("first"),
          RAAF::Result.success("second"),
          RAAF::Result.failure("third")
        ]
        batch = described_class.new(results: results)

        expect(batch[0]).to eq(results[0])
        expect(batch[1]).to eq(results[1])
        expect(batch[2]).to eq(results[2])
      end

      it "returns nil for out of bounds index" do
        batch = described_class.new
        expect(batch[0]).to be_nil
        expect(batch[99]).to be_nil
      end
    end

    describe "#to_h" do
      it "includes batch-specific fields" do
        results = [
          RAAF::Result.success("op1"),
          RAAF::Result.failure("error1")
        ]
        batch = described_class.new(results: results)

        hash = batch.to_h
        expect(hash[:results]).to be_an(Array)
        expect(hash[:results].length).to eq(2)
        expect(hash[:total_count]).to eq(2)
        expect(hash[:success_count]).to eq(1)
        expect(hash[:failure_count]).to eq(1)
        expect(hash[:success_rate]).to eq(50.0)
      end
    end
  end

  describe RAAF::RunResult do
    let(:mock_agent) { double("Agent", name: "TestAgent") }

    describe "#initialize" do
      it "creates run result with all parameters" do
        messages = [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi there" }
        ]
        usage = { total_tokens: 150, prompt_tokens: 100, completion_tokens: 50 }
        tool_results = %w[search_result calc_result]

        result = described_class.new(
          success: true,
          messages: messages,
          last_agent: mock_agent,
          turns: 2,
          last_response_id: "resp_123",
          usage: usage,
          tool_results: tool_results
        )

        expect(result.messages).to eq(messages)
        expect(result.last_agent).to eq(mock_agent)
        expect(result.turns).to eq(2)
        expect(result.last_response_id).to eq("resp_123")
        expect(result.usage).to eq(usage)
        expect(result.tool_results).to eq(tool_results)
        expect(result.final_output).to eq("Hi there")
      end

      it "duplicates arrays to prevent external modification" do
        original_messages = [{ role: "user", content: "test" }]
        original_tools = ["tool1"]

        result = described_class.new(
          messages: original_messages,
          tool_results: original_tools
        )

        result.messages << { role: "assistant", content: "response" }
        result.tool_results << "tool2"

        expect(original_messages.length).to eq(1)
        expect(original_tools.length).to eq(1)
      end

      it "defaults empty arrays and nil values" do
        result = described_class.new

        expect(result.messages).to eq([])
        expect(result.turns).to eq(0)
        expect(result.last_agent).to be_nil
        expect(result.last_response_id).to be_nil
        expect(result.usage).to be_nil
        expect(result.tool_results).to eq([])
      end
    end

    describe "#agent_name" do
      it "returns agent name when agent exists" do
        result = described_class.new(last_agent: mock_agent)
        expect(result.agent_name).to eq("TestAgent")
      end

      it "returns 'unknown' when agent is nil" do
        result = described_class.new(last_agent: nil)
        expect(result.agent_name).to eq("unknown")
      end
    end

    describe "#to_input_list" do
      it "returns copy of messages array" do
        messages = [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi" }
        ]
        result = described_class.new(messages: messages)

        input_list = result.to_input_list
        expect(input_list).to eq(messages)
        expect(input_list).not_to be(messages) # Different object
      end
    end

    describe "#final_output_as" do
      let(:result) do
        messages = [{ role: "assistant", content: '{"result": "success", "count": 5}' }]
        described_class.new(messages: messages)
      end

      it "returns string format" do
        output = result.final_output_as(:string)
        expect(output).to eq('{"result": "success", "count": 5}')
      end

      it "returns string format for string parameter" do
        output = result.final_output_as("string")
        expect(output).to eq('{"result": "success", "count": 5}')
      end

      it "parses JSON format" do
        output = result.final_output_as(:json)
        expect(output).to eq({ "result" => "success", "count" => 5 })
      end

      it "returns original for invalid JSON" do
        messages = [{ role: "assistant", content: "not json" }]
        invalid_result = described_class.new(messages: messages)

        output = invalid_result.final_output_as(:json)
        expect(output).to eq("not json")
      end

      it "returns original for unknown format" do
        output = result.final_output_as(:unknown)
        expect(output).to eq('{"result": "success", "count": 5}')
      end
    end

    describe "#to_h" do
      it "includes run-specific fields" do
        messages = [{ role: "user", content: "test" }]
        usage = { tokens: 100 }

        result = described_class.new(
          messages: messages,
          last_agent: mock_agent,
          turns: 1,
          last_response_id: "resp_456",
          usage: usage,
          tool_results: ["result1"]
        )

        hash = result.to_h
        expect(hash[:messages]).to eq(messages)
        expect(hash[:last_agent]).to eq(mock_agent)
        expect(hash[:turns]).to eq(1)
        expect(hash[:final_output]).to eq("")
        expect(hash[:last_response_id]).to eq("resp_456")
        expect(hash[:usage]).to eq(usage)
        expect(hash[:tool_results]).to eq(["result1"])
      end
    end

    describe ".success" do
      it "creates successful run result" do
        messages = [{ role: "assistant", content: "Success" }]
        usage = { tokens: 50 }

        result = described_class.success(
          messages: messages,
          last_agent: mock_agent,
          turns: 1,
          usage: usage
        )

        expect(result.success?).to be true
        expect(result.messages).to eq(messages)
        expect(result.last_agent).to eq(mock_agent)
        expect(result.turns).to eq(1)
        expect(result.usage).to eq(usage)
      end
    end

    describe ".failure" do
      it "creates failed run result" do
        messages = [{ role: "user", content: "Failed request" }]

        result = described_class.failure(
          error: "API error",
          messages: messages,
          last_agent: mock_agent,
          turns: 0
        )

        expect(result.failure?).to be true
        expect(result.error).to eq("API error")
        expect(result.messages).to eq(messages)
        expect(result.last_agent).to eq(mock_agent)
        expect(result.turns).to eq(0)
      end
    end

    describe "private #extract_final_output" do
      it "extracts content from last assistant message" do
        messages = [
          { role: "user", content: "Question" },
          { role: "assistant", content: "First response" },
          { role: "user", content: "Follow up" },
          { role: "assistant", content: "Final response" }
        ]

        result = described_class.new(messages: messages)
        expect(result.final_output).to eq("Final response")
      end

      it "returns empty string when no assistant messages" do
        messages = [{ role: "user", content: "Question" }]
        result = described_class.new(messages: messages)
        expect(result.final_output).to eq("")
      end

      it "returns empty string for empty messages" do
        result = described_class.new(messages: [])
        expect(result.final_output).to eq("")
      end

      it "handles assistant message with nil content" do
        messages = [{ role: "assistant", content: nil }]
        result = described_class.new(messages: messages)
        expect(result.final_output).to eq("")
      end
    end
  end

  describe RAAF::ResultBuilder do
    describe "#initialize" do
      it "initializes with empty metadata and start time" do
        before_time = Time.now.utc
        builder = described_class.new
        after_time = Time.now.utc

        expect(builder.instance_variable_get(:@metadata)).to eq({})
        start_time = builder.instance_variable_get(:@start_time)
        expect(start_time).to be >= before_time
        expect(start_time).to be <= after_time
      end
    end

    describe "#add_metadata" do
      it "adds metadata key-value pairs" do
        builder = described_class.new
        result = builder.add_metadata(:user_id, 123)

        expect(result).to be(builder) # Returns self for chaining
        expect(builder.instance_variable_get(:@metadata)).to eq({ user_id: 123 })
      end

      it "allows chaining metadata additions" do
        builder = described_class.new
        builder.add_metadata(:user_id, 123)
               .add_metadata(:operation, "search")
               .add_metadata(:context, "test")

        metadata = builder.instance_variable_get(:@metadata)
        expect(metadata).to eq({
                                 user_id: 123,
                                 operation: "search",
                                 context: "test"
                               })
      end

      it "overwrites existing keys" do
        builder = described_class.new
        builder.add_metadata(:key, "original")
               .add_metadata(:key, "updated")

        expect(builder.instance_variable_get(:@metadata)[:key]).to eq("updated")
      end
    end

    describe "#merge_metadata" do
      it "merges hash of metadata" do
        builder = described_class.new
        builder.add_metadata(:existing, "value")

        result = builder.merge_metadata({ user_id: 123, operation: "test" })

        expect(result).to be(builder) # Returns self for chaining
        metadata = builder.instance_variable_get(:@metadata)
        expect(metadata).to eq({
                                 existing: "value",
                                 user_id: 123,
                                 operation: "test"
                               })
      end

      it "overwrites existing keys during merge" do
        builder = described_class.new
        builder.add_metadata(:key, "original")
        builder.merge_metadata({ key: "merged" })

        expect(builder.instance_variable_get(:@metadata)[:key]).to eq("merged")
      end
    end

    describe "#build_success" do
      it "builds successful result with timing metadata" do
        builder = described_class.new
        builder.add_metadata(:user_id, 123)

        # Add small delay to ensure duration > 0
        sleep(0.001)

        result = builder.build_success("success data")

        expect(result).to be_a(RAAF::Result)
        expect(result.success?).to be true
        expect(result.data).to eq("success data")
        expect(result.metadata[:user_id]).to eq(123)
        expect(result.metadata[:duration_ms]).to be_positive
        expect(result.metadata[:duration_ms]).to be_a(Float)
      end

      it "builds with default result class when none specified" do
        builder = described_class.new

        sleep(0.001)

        result = builder.build_success("data")

        expect(result).to be_a(RAAF::Result)
        expect(result.data).to eq("data")
        expect(result.metadata[:duration_ms]).to be_positive
      end
    end

    describe "#build_failure" do
      it "builds failure result with timing metadata" do
        builder = described_class.new
        builder.add_metadata(:context, "test")

        sleep(0.001)

        result = builder.build_failure("error occurred")

        expect(result).to be_a(RAAF::Result)
        expect(result.failure?).to be true
        expect(result.error).to eq("error occurred")
        expect(result.metadata[:context]).to eq("test")
        expect(result.metadata[:duration_ms]).to be_positive
      end
    end

    describe "#build_agent_success" do
      it "builds successful agent result" do
        builder = described_class.new
        builder.add_metadata(:run_id, "run_123")

        sleep(0.001)

        result = builder.build_agent_success(
          agent_name: "TestAgent",
          messages: [{ role: "assistant", content: "Hello" }],
          turns: 1
        )

        expect(result).to be_a(RAAF::AgentResult)
        expect(result.success?).to be true
        expect(result.agent_name).to eq("TestAgent")
        expect(result.messages).to eq([{ role: "assistant", content: "Hello" }])
        expect(result.turns).to eq(1)
        expect(result.metadata[:run_id]).to eq("run_123")
        expect(result.metadata[:duration_ms]).to be_positive
      end
    end

    describe "#build_agent_failure" do
      it "builds failed agent result" do
        builder = described_class.new
        builder.add_metadata(:attempt, 1)

        sleep(0.001)

        result = builder.build_agent_failure(
          agent_name: "TestAgent",
          error: "Agent failed",
          turns: 0
        )

        expect(result).to be_a(RAAF::AgentResult)
        expect(result.failure?).to be true
        expect(result.agent_name).to eq("TestAgent")
        expect(result.error).to eq("Agent failed")
        expect(result.turns).to eq(0)
        expect(result.metadata[:attempt]).to eq(1)
        expect(result.metadata[:duration_ms]).to be_positive
      end
    end

    describe "#build_tool_success" do
      it "builds successful tool result with execution time" do
        builder = described_class.new
        builder.add_metadata(:version, "1.0")

        sleep(0.001)

        result = builder.build_tool_success(
          tool_name: "calculator",
          data: 42,
          input_args: { a: 6, b: 7 }
        )

        expect(result).to be_a(RAAF::ToolResult)
        expect(result.success?).to be true
        expect(result.tool_name).to eq("calculator")
        expect(result.data).to eq(42)
        expect(result.input_args).to eq({ a: 6, b: 7 })
        expect(result.execution_time).to be_positive
        expect(result.metadata[:version]).to eq("1.0")
        expect(result.metadata[:duration_ms]).to be_positive
      end
    end

    describe "#build_tool_failure" do
      it "builds failed tool result with execution time" do
        builder = described_class.new
        builder.add_metadata(:retry_count, 3)

        sleep(0.001)

        result = builder.build_tool_failure(
          tool_name: "broken_tool",
          error: "Connection failed",
          input_args: { url: "http://example.com" }
        )

        expect(result).to be_a(RAAF::ToolResult)
        expect(result.failure?).to be true
        expect(result.tool_name).to eq("broken_tool")
        expect(result.error).to eq("Connection failed")
        expect(result.input_args).to eq({ url: "http://example.com" })
        expect(result.execution_time).to be_positive
        expect(result.metadata[:retry_count]).to eq(3)
        expect(result.metadata[:duration_ms]).to be_positive
      end
    end

    describe "timing accuracy" do
      it "measures duration accurately" do
        builder = described_class.new

        sleep(0.01) # 10ms

        result = builder.build_success("data")

        # Should be around 10ms, allowing for some variance
        expect(result.metadata[:duration_ms]).to be >= 8
        expect(result.metadata[:duration_ms]).to be <= 20
      end
    end
  end
end
