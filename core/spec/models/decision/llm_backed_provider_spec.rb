# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::Decision::LLMBackedProvider do
  subject(:provider) { described_class.new(runner: runner) }

  let(:runner) { instance_double(RAAF::Runner) }
  let(:reply) do
    {
      "urgent" => { "type" => "noul", "noul" => 0.93 },
      "team" => {
        "type" => "choice",
        "choice" => "billing",
        "probabilities" => { "billing" => 0.8, "eng" => 0.2 },
        "confidence" => 0.8
      }
    }.to_json
  end

  def stub_reply(content)
    allow(runner).to receive(:run).and_return(
      instance_double(RAAF::RunResult, messages: [{ role: "assistant", content: content }])
    )
  end

  describe "#decide" do
    before { stub_reply(reply) }

    it "answers every question" do
      result = provider.decide(
        state: "Stripe has been failing for three days",
        questions: {
          urgent: RAAF::Models::Decision::Noul.new(instructions: "The message conveys urgency"),
          team: { type: :choice, instructions: "Which team?", options: %w[billing eng] }
        }
      )

      expect(result[:urgent].probability).to eq(0.93)
      expect(result[:team].option).to eq("billing")
      expect(result.provider).to eq("LLMBacked")
      expect(result.model).to eq("gpt-4o")
    end

    it "puts the state, the instructions and the options in the prompt" do
      provider.decide(
        state: "Stripe has been failing",
        questions: { team: { type: :choice, instructions: "Which team?", options: %w[billing eng] } }
      )

      expect(runner).to have_received(:run) do |prompt, **_kwargs|
        expect(prompt).to include("Stripe has been failing")
        expect(prompt).to include("Which team?")
        expect(prompt).to include("billing, eng")
      end
    end

    it "serialises a structured state as JSON" do
      provider.decide(
        state: { input: "2+2=?", output: "4" },
        questions: { urgent: { type: :noul, instructions: "The answer is correct" } }
      )

      expect(runner).to have_received(:run) do |prompt, **_kwargs|
        expect(prompt).to include('"input": "2+2=?"')
      end
    end

    it "judges at temperature zero for repeatability" do
      provider.decide(state: "x", questions: { urgent: { type: :noul, instructions: "y" } })

      expect(runner).to have_received(:run).with(anything, hash_including(temperature: 0.0))
    end
  end

  describe "malformed replies" do
    it "repairs JSON wrapped in a markdown block" do
      stub_reply("```json\n{\"urgent\": {\"type\": \"noul\", \"noul\": 0.4}}\n```")

      result = provider.decide(state: "x", questions: { urgent: { type: :noul, instructions: "y" } })

      expect(result[:urgent].probability).to eq(0.4)
    end

    it "raises when the reply holds no JSON" do
      stub_reply("I am not able to answer that.")

      expect { provider.decide(state: "x", questions: { urgent: { type: :noul, instructions: "y" } }) }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /did not return JSON/)
    end

    it "raises when a question goes unanswered" do
      stub_reply({ "other" => { "type" => "noul", "noul" => 0.4 } }.to_json)

      expect { provider.decide(state: "x", questions: { urgent: { type: :noul, instructions: "y" } }) }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /did not answer question "urgent"/)
    end
  end

  describe "#noul" do
    it "returns the single answer directly" do
      stub_reply({ "answer" => { "type" => "noul", "noul" => 0.61 } }.to_json)

      answer = provider.noul(state: "x", instructions: "The output is correct")

      expect(answer).to be_a(RAAF::Models::Decision::Answers::Noul)
      expect(answer.probability).to eq(0.61)
    end
  end

  describe "argument validation" do
    it "rejects an empty state" do
      expect { provider.decide(state: "", questions: { a: { type: :noul, instructions: "y" } }) }
        .to raise_error(ArgumentError, /state cannot be empty/)
    end

    it "rejects a missing state" do
      expect { provider.decide(state: nil, questions: { a: { type: :noul, instructions: "y" } }) }
        .to raise_error(ArgumentError, /state is required/)
    end

    it "rejects an empty question set" do
      expect { provider.decide(state: "x", questions: {}) }
        .to raise_error(ArgumentError, /at least one question/)
    end

    it "names the offending question when one is malformed" do
      expect { provider.decide(state: "x", questions: { team: { type: :choice, instructions: "y" } }) }
        .to raise_error(ArgumentError, /question :team/)
    end
  end
end
