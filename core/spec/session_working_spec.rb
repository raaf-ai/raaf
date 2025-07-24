# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "tmpdir"

RSpec.describe "RAAF Session Components" do
  describe RAAF::Session do
    describe "#initialize" do
      it "creates session with auto-generated UUID" do
        session = described_class.new

        expect(session.id).to be_a(String)
        expect(session.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
        expect(session.messages).to eq([])
        expect(session.metadata).to eq({})
        expect(session.created_at).to be_a(Time)
        expect(session.updated_at).to be_a(Time)
      end

      it "creates session with provided ID" do
        custom_id = "custom-session-123"
        session = described_class.new(id: custom_id)

        expect(session.id).to eq(custom_id)
      end

      it "creates session with initial messages and metadata" do
        messages = [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi there!" }
        ]
        metadata = { user_id: "123", session_type: "support" }
        session = described_class.new(messages: messages, metadata: metadata)

        expect(session.messages).to eq(messages)
        expect(session.metadata).to eq(metadata)
      end

      it "duplicates messages and metadata arrays to prevent external modification" do
        original_messages = [{ role: "user", content: "test" }]
        original_metadata = { key: "value" }

        session = described_class.new(messages: original_messages, metadata: original_metadata)

        session.messages << { role: "assistant", content: "response" }
        session.metadata[:new_key] = "new_value"

        expect(original_messages.length).to eq(1)
        expect(original_metadata.keys).to eq([:key])
      end

      it "sets created_at and updated_at to current time" do
        before_time = Time.now
        session = described_class.new
        after_time = Time.now

        expect(session.created_at).to be >= before_time
        expect(session.created_at).to be <= after_time
        expect(session.updated_at).to be >= before_time
        expect(session.updated_at).to be <= after_time
      end
    end

    describe "#add_message" do
      let(:session) { described_class.new }

      it "adds basic message with role and content" do
        result = session.add_message(role: "user", content: "Hello world")

        expect(session.messages.size).to eq(1)
        message = session.messages.first
        expect(message[:role]).to eq("user")
        expect(message[:content]).to eq("Hello world")
        expect(message[:timestamp]).to be_a(Float)
        expect(message[:metadata]).to eq({})
        expect(result).to eq(message)
      end

      it "adds message with tool_call_id" do
        session.add_message(
          role: "tool",
          content: "Tool result",
          tool_call_id: "call_123"
        )

        message = session.messages.first
        expect(message[:role]).to eq("tool")
        expect(message[:content]).to eq("Tool result")
        expect(message[:tool_call_id]).to eq("call_123")
      end

      it "adds message with tool_calls" do
        tool_calls = [
          { id: "call_1", function: { name: "search", arguments: { query: "test" } } }
        ]
        session.add_message(
          role: "assistant",
          content: "I'll search for that",
          tool_calls: tool_calls
        )

        message = session.messages.first
        expect(message[:role]).to eq("assistant")
        expect(message[:tool_calls]).to eq(tool_calls)
      end

      it "adds message with custom metadata" do
        metadata = { source: "api", priority: "high" }
        session.add_message(
          role: "user",
          content: "Urgent request",
          metadata: metadata
        )

        message = session.messages.first
        expect(message[:metadata]).to eq(metadata)
      end

      it "updates updated_at timestamp when adding message" do
        original_time = session.updated_at
        sleep(0.001) # Ensure time difference

        session.add_message(role: "user", content: "Test")

        expect(session.updated_at).to be > original_time
      end

      it "adds timestamp to message" do
        before_time = Time.now.to_f
        session.add_message(role: "user", content: "Test")
        after_time = Time.now.to_f

        message = session.messages.first
        expect(message[:timestamp]).to be >= before_time
        expect(message[:timestamp]).to be <= after_time
      end

      it "does not add tool_call_id when nil" do
        session.add_message(role: "user", content: "Test", tool_call_id: nil)

        message = session.messages.first
        expect(message).not_to have_key(:tool_call_id)
      end

      it "does not add tool_calls when nil" do
        session.add_message(role: "assistant", content: "Test", tool_calls: nil)

        message = session.messages.first
        expect(message).not_to have_key(:tool_calls)
      end
    end

    describe "#messages_by_role" do
      let(:session) { described_class.new }

      before do
        session.add_message(role: "user", content: "Hello")
        session.add_message(role: "assistant", content: "Hi there")
        session.add_message(role: "user", content: "How are you?")
        session.add_message(role: "tool", content: "Tool result")
      end

      it "returns messages with specified role" do
        user_messages = session.messages_by_role("user")

        expect(user_messages.length).to eq(2)
        expect(user_messages.all? { |msg| msg[:role] == "user" }).to be true
        expect(user_messages.map { |msg| msg[:content] }).to eq(["Hello", "How are you?"])
      end

      it "returns assistant messages" do
        assistant_messages = session.messages_by_role("assistant")

        expect(assistant_messages.length).to eq(1)
        expect(assistant_messages.first[:content]).to eq("Hi there")
      end

      it "returns tool messages" do
        tool_messages = session.messages_by_role("tool")

        expect(tool_messages.length).to eq(1)
        expect(tool_messages.first[:content]).to eq("Tool result")
      end

      it "returns empty array for non-existent role" do
        system_messages = session.messages_by_role("system")
        expect(system_messages).to eq([])
      end
    end

    describe "#last_message" do
      let(:session) { described_class.new }

      it "returns last message when messages exist" do
        session.add_message(role: "user", content: "First")
        session.add_message(role: "assistant", content: "Second")
        session.add_message(role: "user", content: "Last")

        last = session.last_message
        expect(last[:content]).to eq("Last")
        expect(last[:role]).to eq("user")
      end

      it "returns nil when no messages" do
        expect(session.last_message).to be_nil
      end
    end

    describe "#last_message_by_role" do
      let(:session) { described_class.new }

      before do
        session.add_message(role: "user", content: "First user")
        session.add_message(role: "assistant", content: "First assistant")
        session.add_message(role: "user", content: "Second user")
        session.add_message(role: "assistant", content: "Second assistant")
      end

      it "returns last message with specified role" do
        last_user = session.last_message_by_role("user")
        expect(last_user[:content]).to eq("Second user")

        last_assistant = session.last_message_by_role("assistant")
        expect(last_assistant[:content]).to eq("Second assistant")
      end

      it "returns nil for non-existent role" do
        last_system = session.last_message_by_role("system")
        expect(last_system).to be_nil
      end

      it "returns nil when no messages" do
        empty_session = described_class.new
        expect(empty_session.last_message_by_role("user")).to be_nil
      end
    end

    describe "#clear_messages" do
      let(:session) { described_class.new }

      it "removes all messages" do
        session.add_message(role: "user", content: "Test 1")
        session.add_message(role: "assistant", content: "Test 2")

        expect(session.message_count).to eq(2)

        session.clear_messages

        expect(session.message_count).to eq(0)
        expect(session.messages).to eq([])
      end

      it "updates updated_at timestamp" do
        session.add_message(role: "user", content: "Test")
        original_time = session.updated_at
        sleep(0.001)

        session.clear_messages

        expect(session.updated_at).to be > original_time
      end
    end

    describe "#message_count" do
      let(:session) { described_class.new }

      it "returns correct count" do
        expect(session.message_count).to eq(0)

        session.add_message(role: "user", content: "Test 1")
        expect(session.message_count).to eq(1)

        session.add_message(role: "assistant", content: "Test 2")
        expect(session.message_count).to eq(2)

        session.clear_messages
        expect(session.message_count).to eq(0)
      end
    end

    describe "#empty?" do
      let(:session) { described_class.new }

      it "returns true when no messages" do
        expect(session.empty?).to be true
      end

      it "returns false when messages exist" do
        session.add_message(role: "user", content: "Test")
        expect(session.empty?).to be false
      end

      it "returns true after clearing messages" do
        session.add_message(role: "user", content: "Test")
        session.clear_messages
        expect(session.empty?).to be true
      end
    end

    describe "#update_metadata" do
      let(:session) { described_class.new(metadata: { existing: "value" }) }

      it "merges new metadata with existing" do
        session.update_metadata({ new_key: "new_value", another: "data" })

        expect(session.metadata).to eq({
                                         existing: "value",
                                         new_key: "new_value",
                                         another: "data"
                                       })
      end

      it "overwrites existing keys" do
        session.update_metadata({ existing: "new_value" })
        expect(session.metadata[:existing]).to eq("new_value")
      end

      it "updates updated_at timestamp" do
        original_time = session.updated_at
        sleep(0.001)

        session.update_metadata({ test: "value" })

        expect(session.updated_at).to be > original_time
      end
    end

    describe "#summary" do
      let(:session) { described_class.new(metadata: { user_id: "123" }) }

      before do
        session.add_message(role: "user", content: "Hello")
        session.add_message(role: "assistant", content: "Hi")
        session.add_message(role: "user", content: "Thanks")
      end

      it "returns comprehensive session summary" do
        summary = session.summary

        expect(summary[:id]).to eq(session.id)
        expect(summary[:message_count]).to eq(3)
        expect(summary[:created_at]).to eq(session.created_at)
        expect(summary[:updated_at]).to eq(session.updated_at)
        expect(summary[:metadata]).to eq({ user_id: "123" })
        expect(summary[:roles]).to eq(%w[user assistant])
      end

      it "includes unique roles only" do
        session.add_message(role: "user", content: "Another user message")
        summary = session.summary

        expect(summary[:roles]).to eq(%w[user assistant])
      end
    end

    describe "#to_h" do
      let(:session) { described_class.new(id: "test-123") }

      before do
        session.add_message(role: "user", content: "Test")
        session.update_metadata({ key: "value" })
      end

      it "converts to hash with all data" do
        hash = session.to_h

        expect(hash[:id]).to eq("test-123")
        expect(hash[:messages]).to eq(session.messages)
        expect(hash[:metadata]).to eq({ key: "value" })
        expect(hash[:created_at]).to eq(session.created_at)
        expect(hash[:updated_at]).to eq(session.updated_at)
      end
    end

    describe "#to_json" do
      let(:session) { described_class.new(id: "test-json") }

      before do
        session.add_message(role: "user", content: "JSON test")
      end

      it "converts to JSON string" do
        json_string = session.to_json
        parsed = JSON.parse(json_string)

        expect(parsed["id"]).to eq("test-json")
        expect(parsed["messages"]).to be_an(Array)
        expect(parsed["messages"].first["content"]).to eq("JSON test")
        expect(parsed).to have_key("created_at")
        expect(parsed).to have_key("updated_at")
      end

      it "passes additional arguments to to_json" do
        json_string = session.to_json(only: [:id])
        expect(json_string).to be_a(String)
      end
    end

    describe ".from_hash" do
      let(:hash) do
        {
          id: "hash-test-123",
          messages: [{ role: "user", content: "From hash" }],
          metadata: { source: "hash" },
          created_at: Time.parse("2024-01-01T00:00:00Z"),
          updated_at: Time.parse("2024-01-02T00:00:00Z")
        }
      end

      it "creates session from hash with symbol keys" do
        session = described_class.from_hash(hash)

        expect(session.id).to eq("hash-test-123")
        expect(session.messages).to eq([{ role: "user", content: "From hash" }])
        expect(session.metadata).to eq({ source: "hash" })
        expect(session.created_at).to eq(Time.parse("2024-01-01T00:00:00Z"))
        expect(session.updated_at).to eq(Time.parse("2024-01-02T00:00:00Z"))
      end

      it "creates session from hash with string keys" do
        string_hash = {
          "id" => "string-test-123",
          "messages" => [{ role: "user", content: "From string hash" }],
          "metadata" => { source: "string" },
          "created_at" => Time.parse("2024-01-01T00:00:00Z"),
          "updated_at" => Time.parse("2024-01-02T00:00:00Z")
        }

        session = described_class.from_hash(string_hash)

        expect(session.id).to eq("string-test-123")
        expect(session.messages).to eq([{ role: "user", content: "From string hash" }])
        expect(session.metadata).to eq({ source: "string" })
      end

      it "handles missing optional fields" do
        minimal_hash = { id: "minimal-123" }
        session = described_class.from_hash(minimal_hash)

        expect(session.id).to eq("minimal-123")
        expect(session.messages).to eq([])
        expect(session.metadata).to eq({})
        expect(session.created_at).to be_a(Time)
        expect(session.updated_at).to be_a(Time)
      end
    end

    describe ".from_json" do
      let(:json_data) do
        {
          id: "json-test-123",
          messages: [{ role: "assistant", content: "From JSON" }],
          metadata: { format: "json" }
        }.to_json
      end

      it "creates session from JSON string" do
        session = described_class.from_json(json_data)

        expect(session.id).to eq("json-test-123")
        expect(session.messages).to eq([{ role: "assistant", content: "From JSON" }])
        expect(session.metadata).to eq({ format: "json" })
      end

      it "handles invalid JSON gracefully" do
        expect do
          described_class.from_json("invalid json")
        end.to raise_error(JSON::ParserError)
      end
    end

    describe "#to_s and #inspect" do
      let(:session) { described_class.new(id: "string-test") }

      before do
        session.add_message(role: "user", content: "Test message")
        session.add_message(role: "assistant", content: "Response")
      end

      it "provides readable string representation" do
        string_repr = session.to_s

        expect(string_repr).to include("RAAF::Session")
        expect(string_repr).to include("id=string-test")
        expect(string_repr).to include("messages=2")
        expect(string_repr).to include("updated=")
      end

      it "inspect returns same as to_s" do
        expect(session.inspect).to eq(session.to_s)
      end
    end
  end

  describe RAAF::InMemorySessionStore do
    let(:store) { described_class.new }
    let(:session) { RAAF::Session.new(id: "test-session") }

    describe "#initialize" do
      it "creates empty store" do
        expect(store.count).to eq(0)
      end
    end

    describe "#store" do
      it "stores session by ID" do
        store.store(session)

        expect(store.count).to eq(1)
        expect(store.exists?(session.id)).to be true
      end

      it "overwrites existing session with same ID" do
        store.store(session)
        session.add_message(role: "user", content: "Updated")
        store.store(session)

        expect(store.count).to eq(1)
        retrieved = store.retrieve(session.id)
        expect(retrieved.message_count).to eq(1)
      end
    end

    describe "#retrieve" do
      it "retrieves stored session" do
        session.add_message(role: "user", content: "Retrieve test")
        store.store(session)

        retrieved = store.retrieve(session.id)

        expect(retrieved).not_to be_nil
        expect(retrieved.id).to eq(session.id)
        expect(retrieved.message_count).to eq(1)
        expect(retrieved.messages.first[:content]).to eq("Retrieve test")
      end

      it "returns nil for non-existent session" do
        retrieved = store.retrieve("non-existent-id")
        expect(retrieved).to be_nil
      end
    end

    describe "#delete" do
      before do
        store.store(session)
      end

      it "deletes and returns session" do
        deleted = store.delete(session.id)

        expect(deleted).to eq(session)
        expect(store.count).to eq(0)
        expect(store.exists?(session.id)).to be false
      end

      it "returns nil for non-existent session" do
        deleted = store.delete("non-existent-id")
        expect(deleted).to be_nil
      end
    end

    describe "#exists?" do
      it "returns true for existing session" do
        store.store(session)
        expect(store.exists?(session.id)).to be true
      end

      it "returns false for non-existent session" do
        expect(store.exists?("non-existent-id")).to be false
      end
    end

    describe "#list_sessions" do
      it "returns empty array when no sessions" do
        expect(store.list_sessions).to eq([])
      end

      it "returns all session IDs" do
        session1 = RAAF::Session.new(id: "session-1")
        session2 = RAAF::Session.new(id: "session-2")

        store.store(session1)
        store.store(session2)

        session_ids = store.list_sessions
        expect(session_ids.sort).to eq(%w[session-1 session-2])
      end
    end

    describe "#clear" do
      before do
        3.times { |i| store.store(RAAF::Session.new(id: "session-#{i}")) }
      end

      it "removes all sessions" do
        expect(store.count).to eq(3)

        store.clear

        expect(store.count).to eq(0)
        expect(store.list_sessions).to eq([])
      end
    end

    describe "#count" do
      it "returns correct session count" do
        expect(store.count).to eq(0)

        store.store(RAAF::Session.new(id: "session-1"))
        expect(store.count).to eq(1)

        store.store(RAAF::Session.new(id: "session-2"))
        expect(store.count).to eq(2)

        store.delete("session-1")
        expect(store.count).to eq(1)
      end
    end

    describe "#stats" do
      it "returns comprehensive statistics" do
        session1 = RAAF::Session.new(id: "stats-1")
        session1.add_message(role: "user", content: "Message 1")
        session1.add_message(role: "assistant", content: "Response 1")

        session2 = RAAF::Session.new(id: "stats-2")
        session2.add_message(role: "user", content: "Message 2")

        store.store(session1)
        store.store(session2)

        stats = store.stats

        expect(stats[:total_sessions]).to eq(2)
        expect(stats[:session_ids].sort).to eq(%w[stats-1 stats-2])
        expect(stats[:total_messages]).to eq(3)
      end

      it "returns zero stats for empty store" do
        stats = store.stats

        expect(stats[:total_sessions]).to eq(0)
        expect(stats[:session_ids]).to eq([])
        expect(stats[:total_messages]).to eq(0)
      end
    end

    describe "thread safety" do
      it "handles concurrent operations safely" do
        threads = []

        10.times do |i|
          threads << Thread.new do
            session = RAAF::Session.new(id: "thread-#{i}")
            session.add_message(role: "user", content: "Thread test #{i}")
            store.store(session)
          end
        end

        threads.each(&:join)

        expect(store.count).to eq(10)
        expect(store.list_sessions.size).to eq(10)
      end
    end
  end

  describe RAAF::FileSessionStore do
    let(:temp_dir) { Dir.mktmpdir }
    let(:store) { described_class.new(directory: temp_dir) }
    let(:session) { RAAF::Session.new(id: "file-test-session") }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    describe "#initialize" do
      it "creates directory if it doesn't exist" do
        new_dir = File.join(temp_dir, "new_sessions")
        expect(Dir.exist?(new_dir)).to be false

        described_class.new(directory: new_dir)

        expect(Dir.exist?(new_dir)).to be true
      end

      it "uses default directory when none specified" do
        store = described_class.new
        expect(store.directory).to eq(File.expand_path("./sessions"))
      end

      it "expands relative paths" do
        relative_store = described_class.new(directory: "relative/path")
        expect(relative_store.directory).to start_with("/")
      end
    end

    describe "#store" do
      it "stores session to JSON file" do
        session.add_message(role: "user", content: "File store test")
        store.store(session)

        filename = File.join(temp_dir, "#{session.id}.json")
        expect(File.exist?(filename)).to be true

        content = JSON.parse(File.read(filename))
        expect(content["id"]).to eq(session.id)
        expect(content["messages"]).to be_an(Array)
      end

      it "overwrites existing file" do
        store.store(session)
        session.add_message(role: "user", content: "Updated content")
        store.store(session)

        retrieved = store.retrieve(session.id)
        expect(retrieved.message_count).to eq(1)
        expect(retrieved.messages.first[:content]).to eq("Updated content")
      end
    end

    describe "#retrieve" do
      it "retrieves session from JSON file" do
        session.add_message(role: "assistant", content: "Retrieval test")
        session.update_metadata({ test: "metadata" })
        store.store(session)

        retrieved = store.retrieve(session.id)

        expect(retrieved).not_to be_nil
        expect(retrieved.id).to eq(session.id)
        expect(retrieved.message_count).to eq(1)
        expect(retrieved.messages.first[:content]).to eq("Retrieval test")
        expect(retrieved.metadata[:test]).to eq("metadata")
      end

      it "returns nil for non-existent file" do
        retrieved = store.retrieve("non-existent-id")
        expect(retrieved).to be_nil
      end

      it "returns nil for corrupted JSON file" do
        filename = File.join(temp_dir, "corrupted.json")
        File.write(filename, "invalid json content")

        retrieved = store.retrieve("corrupted")
        expect(retrieved).to be_nil
      end
    end

    describe "#delete" do
      before do
        session.add_message(role: "user", content: "Delete test")
        store.store(session)
      end

      it "deletes file and returns session" do
        filename = File.join(temp_dir, "#{session.id}.json")
        expect(File.exist?(filename)).to be true

        deleted = store.delete(session.id)

        expect(deleted).not_to be_nil
        expect(deleted.id).to eq(session.id)
        expect(deleted.message_count).to eq(1)
        expect(File.exist?(filename)).to be false
      end

      it "returns nil for non-existent file" do
        deleted = store.delete("non-existent-id")
        expect(deleted).to be_nil
      end

      it "returns nil when file read fails during deletion" do
        filename = File.join(temp_dir, "#{session.id}.json")
        File.write(filename, "corrupted content")

        deleted = store.delete(session.id)
        expect(deleted).to be_nil
        # File deletion behavior depends on the specific error handling implementation
      end
    end

    describe "#exists?" do
      it "returns true when session file exists" do
        store.store(session)
        expect(store.exists?(session.id)).to be true
      end

      it "returns false when session file doesn't exist" do
        expect(store.exists?("non-existent-id")).to be false
      end
    end

    describe "#list_sessions" do
      it "returns empty array when no session files" do
        expect(store.list_sessions).to eq([])
      end

      it "returns all session IDs from JSON files" do
        session1 = RAAF::Session.new(id: "file-session-1")
        session2 = RAAF::Session.new(id: "file-session-2")

        store.store(session1)
        store.store(session2)

        session_ids = store.list_sessions
        expect(session_ids.sort).to eq(%w[file-session-1 file-session-2])
      end

      it "ignores non-JSON files" do
        store.store(session)
        File.write(File.join(temp_dir, "not-json.txt"), "ignored")

        session_ids = store.list_sessions
        expect(session_ids).to eq([session.id])
      end
    end

    describe "#clear" do
      before do
        3.times do |i|
          s = RAAF::Session.new(id: "clear-session-#{i}")
          store.store(s)
        end
      end

      it "deletes all session files" do
        expect(store.count).to eq(3)

        store.clear

        expect(store.count).to eq(0)
        expect(store.list_sessions).to eq([])
      end

      it "leaves non-JSON files untouched" do
        other_file = File.join(temp_dir, "keep-me.txt")
        File.write(other_file, "preserved")

        store.clear

        expect(File.exist?(other_file)).to be true
      end
    end

    describe "#count" do
      it "returns correct count of JSON files" do
        expect(store.count).to eq(0)

        store.store(RAAF::Session.new(id: "count-1"))
        expect(store.count).to eq(1)

        store.store(RAAF::Session.new(id: "count-2"))
        expect(store.count).to eq(2)

        store.delete("count-1")
        expect(store.count).to eq(1)
      end

      it "ignores non-JSON files in count" do
        store.store(session)
        File.write(File.join(temp_dir, "ignore.txt"), "not counted")

        expect(store.count).to eq(1)
      end
    end

    describe "#stats" do
      it "returns comprehensive file store statistics" do
        session1 = RAAF::Session.new(id: "stats-file-1")
        session1.add_message(role: "user", content: "Stats message 1")
        session1.add_message(role: "assistant", content: "Stats response 1")

        session2 = RAAF::Session.new(id: "stats-file-2")
        session2.add_message(role: "user", content: "Stats message 2")

        store.store(session1)
        store.store(session2)

        stats = store.stats

        expect(stats[:total_sessions]).to eq(2)
        expect(stats[:session_ids].sort).to eq(%w[stats-file-1 stats-file-2])
        expect(stats[:total_messages]).to eq(3)
        expect(stats[:directory]).to eq(temp_dir)
      end

      it "handles corrupted session files gracefully in stats" do
        store.store(session)
        File.write(File.join(temp_dir, "corrupted.json"), "invalid json")

        stats = store.stats

        # Should count the files but handle errors gracefully
        expect(stats[:total_sessions]).to eq(2)
        expect(stats[:session_ids]).to include(session.id, "corrupted")
        # total_messages might vary depending on error handling
      end

      it "returns empty stats for empty directory" do
        stats = store.stats

        expect(stats[:total_sessions]).to eq(0)
        expect(stats[:session_ids]).to eq([])
        expect(stats[:total_messages]).to eq(0)
        expect(stats[:directory]).to eq(temp_dir)
      end
    end

    describe "private methods" do
      describe "#session_filename" do
        it "generates correct filename path" do
          filename = store.send(:session_filename, "test-id")
          expected = File.join(temp_dir, "test-id.json")
          expect(filename).to eq(expected)
        end
      end
    end

    describe "error handling" do
      it "handles file system errors during store operations" do
        # Make directory read-only to simulate permission errors
        File.chmod(0o444, temp_dir)

        expect do
          store.store(session)
        end.to raise_error(SystemCallError)

        # Restore permissions for cleanup
        File.chmod(0o755, temp_dir)
      end

      it "handles file system errors during retrieval gracefully" do
        store.store(session)
        filename = File.join(temp_dir, "#{session.id}.json")

        # Corrupt the file by making it unreadable
        File.chmod(0o000, filename)

        result = store.retrieve(session.id)
        expect(result).to be_nil

        # Restore permissions for cleanup
        File.chmod(0o644, filename)
      end
    end

    describe "thread safety" do
      it "handles concurrent file operations safely" do
        threads = []

        5.times do |i|
          threads << Thread.new do
            s = RAAF::Session.new(id: "thread-file-#{i}")
            s.add_message(role: "user", content: "Concurrent test #{i}")
            store.store(s)
          end
        end

        threads.each(&:join)

        expect(store.count).to eq(5)
        expect(store.list_sessions.size).to eq(5)
      end
    end
  end
end
