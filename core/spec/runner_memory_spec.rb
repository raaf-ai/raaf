# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Runner do
  describe "memory integration", skip: "Memory functionality is in raaf-memory gem" do
    let(:agent) do
      RAAF::Agent.new(
        name: "TestAgent",
        instructions: "You are a helpful assistant",
        model: "gpt-4o"
      )
    end

    let(:memory_store) { RAAF::Memory.create(:in_memory) }
    let(:memory_manager) { RAAF::MemoryManager.new(store: memory_store) }
    let(:session) { RAAF::Session.new }

    let(:runner) do
      described_class.new(
        agent: agent,
        memory_manager: memory_manager
      )
    end

    describe "#process_session with memory" do
      it "adds relevant memory context to the conversation" do
        # Store some memories
        memory_manager.add_memory(
          "Q: What is Ruby?\nA: Ruby is a dynamic programming language.",
          metadata: { topic: "programming" }
        )
        memory_manager.add_memory(
          "Q: Who created Ruby?\nA: Yukihiro Matsumoto created Ruby in 1995.",
          metadata: { topic: "history" }
        )

        # Process new messages
        messages = [
          { role: "user", content: "Tell me about Ruby programming" }
        ]

        # Mock the provider to capture the messages sent
        allow(runner.instance_variable_get(:@provider)).to receive(:call) do |params|
          # Check that memory context was added
          sent_messages = params[:messages]
          memory_message = sent_messages.find { |m| m[:role] == "system" && m[:content].include?("Relevant context from memory") }

          expect(memory_message).not_to be_nil
          expect(memory_message[:content]).to include("Ruby is a dynamic programming language")

          # Return a mock response
          {
            choices: [{
              message: {
                role: "assistant",
                content: "Ruby is a wonderful language!"
              }
            }],
            usage: { total_tokens: 100 }
          }
        end

        runner.run(messages, session: session)
      end
    end

    describe "#update_session_with_result with memory" do
      it "stores Q&A pairs in memory after execution" do
        result = RAAF::Result.new(
          status: :success,
          messages: [
            { role: "user", content: "What is Rails?" },
            { role: "assistant", content: "Rails is a web framework for Ruby." }
          ],
          last_agent: agent,
          usage: { total_tokens: 50 }
        )

        # Update session with result
        runner.send(:update_session_with_result, session, result)

        # Check that memory was stored
        memories = memory_store.list
        expect(memories.size).to eq(1)
        expect(memories.first[:content]).to include("Q: What is Rails?")
        expect(memories.first[:content]).to include("A: Rails is a web framework for Ruby.")
        expect(memories.first[:metadata][:agent]).to eq("TestAgent")
      end

      it "handles multiple Q&A pairs in a single result" do
        result = RAAF::Result.new(
          status: :success,
          messages: [
            { role: "user", content: "What is Rails?" },
            { role: "assistant", content: "Rails is a web framework." },
            { role: "user", content: "What about Sinatra?" },
            { role: "assistant", content: "Sinatra is a lightweight web framework." }
          ],
          last_agent: agent,
          usage: { total_tokens: 100 }
        )

        runner.send(:update_session_with_result, session, result)

        memories = memory_store.list
        expect(memories.size).to eq(2)
        expect(memories[0][:content]).to include("Q: What is Rails?")
        expect(memories[1][:content]).to include("Q: What about Sinatra?")
      end
    end

    describe "end-to-end memory usage" do
      it "uses memory across multiple conversations" do
        # Mock provider responses
        call_count = 0
        allow(runner.instance_variable_get(:@provider)).to receive(:call) do |params|
          call_count += 1

          if call_count == 1
            # First conversation - no memory yet
            {
              choices: [{
                message: {
                  role: "assistant",
                  content: "Ruby was created by Yukihiro Matsumoto in 1995."
                }
              }],
              usage: { total_tokens: 50 }
            }
          else
            # Second conversation - should have memory context
            sent_messages = params[:messages]
            memory_message = sent_messages.find { |m| m[:role] == "system" && m[:content].include?("Relevant context") }

            expect(memory_message).not_to be_nil
            expect(memory_message[:content]).to include("Yukihiro Matsumoto")

            {
              choices: [{
                message: {
                  role: "assistant",
                  content: "As I mentioned, Matz created Ruby."
                }
              }],
              usage: { total_tokens: 50 }
            }
          end
        end

        # First conversation
        runner.run([{ role: "user", content: "Who created Ruby?" }], session: session)

        # Second conversation - should use memory from first
        new_session = RAAF::Session.new
        runner.run([{ role: "user", content: "Tell me more about Ruby's creator" }], session: new_session)
      end
    end

    describe "backward compatibility" do
      it "works without memory manager" do
        runner_without_memory = described_class.new(agent: agent)

        allow(runner_without_memory.instance_variable_get(:@provider)).to receive(:call) do |params|
          # Should not have memory context
          memory_message = params[:messages].find { |m| m[:role] == "system" && m[:content].include?("Relevant context") }
          expect(memory_message).to be_nil

          {
            choices: [{
              message: {
                role: "assistant",
                content: "Hello!"
              }
            }],
            usage: { total_tokens: 20 }
          }
        end

        result = runner_without_memory.run([{ role: "user", content: "Hi" }], session: session)
        expect(result.status).to eq(:success)
      end
    end
  end
end
