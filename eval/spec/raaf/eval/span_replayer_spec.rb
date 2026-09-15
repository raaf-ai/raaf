# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval::SpanReplayer do
  let(:span) do
    instance_double(
      "RAAF::Rails::Tracing::SpanRecord",
      span_id: "span_abc123",
      span_attributes: attributes
    )
  end

  let(:replayer) { described_class.new(span) }

  describe "#original_messages" do
    context "when the span records the answer the agent produced" do
      let(:attributes) do
        {
          "agent.model" => "gemini-2.5-flash",
          "agent.conversation_messages" => JSON.generate([
                                                           { role: "system", content: "Score the prospect" },
                                                           { role: "user", content: "<input_data>...</input_data>" },
                                                           { role: "assistant", content: '{"score":80}' }
                                                         ])
        }
      end

      it "stops at the last user turn so the model answers again instead of continuing" do
        expect(replayer.original_messages).to eq([
                                                   { role: "system", content: "Score the prospect" },
                                                   { role: "user", content: "<input_data>...</input_data>" }
                                                 ])
      end
    end

    context "when the recorded answer is a structured content array" do
      let(:attributes) do
        {
          "agent.model" => "gemini-2.5-flash",
          "agent.conversation_messages" => JSON.generate([
                                                           { role: "user", content: "Score it" },
                                                           { role: "assistant",
                                                             content: [{ type: "text", text: '{"score":80}' }] }
                                                         ])
        }
      end

      it "drops it rather than sending a content object where a string belongs" do
        expect(replayer.original_messages).to eq([{ role: "user", content: "Score it" }])
      end
    end

    context "when assistant and tool turns sit before the last user turn" do
      let(:attributes) do
        {
          "agent.model" => "gemini-2.5-flash",
          "agent.conversation_messages" => JSON.generate([
                                                           { role: "user", content: "First question" },
                                                           { role: "assistant", content: "First answer" },
                                                           { role: "user", content: "Second question" }
                                                         ])
        }
      end

      it "keeps them, because they are part of the prompt" do
        expect(replayer.original_messages.map { |msg| msg[:role] }).to eq(%w[user assistant user])
      end
    end

    context "when no user turn was recorded" do
      let(:attributes) do
        {
          "agent.model" => "gemini-2.5-flash",
          "agent.conversation_messages" => JSON.generate([{ role: "system", content: "Score the prospect" }])
        }
      end

      it "leaves the conversation alone" do
        expect(replayer.original_messages).to eq([{ role: "system", content: "Score the prospect" }])
      end
    end
  end

  describe "#replayable?" do
    let(:attributes) do
      {
        "agent.model" => "gemini-2.5-flash",
        "agent.conversation_messages" => JSON.generate([
                                                         { role: "user", content: "Score it" },
                                                         { role: "assistant", content: '{"score":80}' }
                                                       ])
      }
    end

    it "stays replayable once the recorded answer is dropped" do
      expect(replayer).to be_replayable
    end
  end
end
