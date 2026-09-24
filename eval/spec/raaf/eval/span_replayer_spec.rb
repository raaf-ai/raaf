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

  describe "model settings" do
    subject(:settings) { replayer.send(:extract_model_settings) }

    context "when the agent ran at temperature zero" do
      let(:attributes) do
        {
          "agent.model" => "gemini-2.5-flash",
          "agent.temperature" => 0,
          "agent.top_p" => "N/A",
          "agent.max_tokens" => "N/A"
        }
      end

      # The bug this pins: temperature 0 was coerced to 0.0 and then dropped
      # by a blanket "reject every zero" rule, so the replay ran at the
      # provider default and every rerun consistency check read the agent as
      # disagreeing with itself on identical input.
      it "keeps the zero, because it is a setting rather than an absent value" do
        expect(settings).to include(temperature: 0.0)
      end

      it "drops the settings recorded as N/A rather than coercing them to zero" do
        expect(settings.keys).not_to include(:top_p, :max_tokens)
      end
    end

    context "when the settings carry ordinary numbers" do
      let(:attributes) do
        {
          "agent.model" => "gemini-2.5-flash",
          "agent.temperature" => "0.7",
          "agent.top_p" => 0.95,
          "agent.max_tokens" => "2048"
        }
      end

      it "reads them whether they were recorded as strings or numbers" do
        expect(settings).to include(temperature: 0.7, top_p: 0.95, max_tokens: 2048)
      end
    end

    context "when a token budget of zero was recorded" do
      let(:attributes) do
        { "agent.model" => "gemini-2.5-flash", "agent.max_tokens" => 0 }
      end

      it "drops it, since zero is not a budget" do
        expect(settings).not_to have_key(:max_tokens)
      end
    end

    context "when model_settings_json carries settings of its own" do
      let(:attributes) do
        {
          "agent.model" => "gemini-2.5-flash",
          "agent.model_settings_json" => JSON.generate(temperature: 0.9, top_p: 0.5),
          "agent.temperature" => 0,
          "agent.top_p" => "N/A"
        }
      end

      it "lets a recorded number override it and leaves the rest alone" do
        expect(settings).to include(temperature: 0.0, top_p: 0.5)
      end
    end
  end
end
