# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::Decision::Answers do
  describe RAAF::Models::Decision::Answers::Noul do
    let(:question) { RAAF::Models::Decision::Noul.new(instructions: "It is urgent") }

    it "reads the probability" do
      answer = question.parse("type" => "noul", "noul" => 0.93)

      expect(answer.probability).to eq(0.93)
      expect(answer).to be_true
    end

    it "accepts either String or Symbol keys" do
      expect(question.parse(noul: 0.4).probability).to eq(0.4)
    end

    it "honours a threshold" do
      answer = question.parse("noul" => 0.6)

      expect(answer.true?(threshold: 0.7)).to be(false)
      expect(answer.true?(threshold: 0.5)).to be(true)
    end

    # The API returns the probability alone for a noul, so this is the only
    # confidence signal there is.
    it "derives confidence from the distance to a coin flip" do
      expect(question.parse("noul" => 0.5).confidence).to eq(0.0)
      expect(question.parse("noul" => 1.0).confidence).to eq(1.0)
      expect(question.parse("noul" => 0.75).confidence).to eq(0.5)
    end

    it "prefers a confidence a provider does report" do
      expect(question.parse("noul" => 0.75, "confidence" => 0.2).confidence).to eq(0.2)
    end

    it "rejects a missing or out-of-range probability" do
      expect { question.parse("type" => "noul") }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /missing noul/)
      expect { question.parse("noul" => 1.4) }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /between 0 and 1/)
      expect { question.parse("noul" => "yes") }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /not a number/)
    end
  end

  describe RAAF::Models::Decision::Answers::Choice do
    let(:question) do
      RAAF::Models::Decision::Choice.new(
        instructions: "Which team?",
        criteria: { billing: "Payments", eng: "Bugs", success: "Accounts" }
      )
    end

    it "reads the option, its confidence and its distribution" do
      answer = question.parse(
        "type" => "choice",
        "choice" => "billing",
        "confidence" => 0.8,
        "probabilities" => { "billing" => 0.8, "eng" => 0.15, "success" => 0.05 }
      )

      expect(answer.option).to eq("billing")
      expect(answer.probabilities).to eq("billing" => 0.8, "eng" => 0.15, "success" => 0.05)
      expect(answer.confidence).to eq(0.8)
    end

    it "falls back to the most probable option when none is named" do
      answer = question.parse("probabilities" => { "billing" => 0.2, "eng" => 0.7, "success" => 0.1 })

      expect(answer.option).to eq("eng")
      expect(answer.confidence).to eq(0.7)
    end

    it "rejects an option outside the question's set" do
      expect { question.parse("choice" => "legal", "confidence" => 0.9) }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /not one of/)
    end

    it "rejects an answer with neither a choice nor probabilities" do
      expect { question.parse("type" => "choice") }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /missing choice/)
    end
  end

  describe RAAF::Models::Decision::Answers::Score do
    let(:question) do
      RAAF::Models::Decision::Score.new(
        instructions: "How frustrated?",
        criteria: ["Calm", "Frustrated but civil", "Very angry"]
      )
    end

    # The API keys a score's probabilities and legend by level index, not by
    # the level's text, and the score itself is probability-weighted.
    it "reads the score, confidence, legend and distribution by level index" do
      answer = question.parse(
        "type" => "score",
        "score" => 1.6,
        "confidence" => 0.7,
        "legend" => { "0" => "Calm", "1" => "Frustrated but civil", "2" => "Very angry" },
        "probabilities" => { "0" => 0.05, "1" => 0.3, "2" => 0.65 }
      )

      expect(answer.score).to eq(1.6)
      expect(answer.confidence).to eq(0.7)
      expect(answer.legend).to eq(0 => "Calm", 1 => "Frustrated but civil", 2 => "Very angry")
      expect(answer.probabilities).to eq(0 => 0.05, 1 => 0.3, 2 => 0.65)
    end

    it "lands on the most probable level" do
      answer = question.parse("score" => 1.6, "confidence" => 0.7, "probabilities" => { "1" => 0.3, "2" => 0.65 })

      expect(answer.level_index).to eq(2)
      expect(answer.level).to eq("Very angry")
    end

    it "names the level from the question when the provider sends no legend" do
      answer = question.parse("score" => 0.2, "confidence" => 0.8, "probabilities" => { "0" => 0.9, "1" => 0.1 })

      expect(answer.level).to eq("Calm")
    end

    it "falls back to rounding the score when there is no distribution" do
      expect(question.parse("score" => 1.6, "confidence" => 0.5).level_index).to eq(2)
      expect(question.parse("score" => 0.2, "confidence" => 0.5).level_index).to eq(0)
    end

    it "clamps a rounded score that runs past the rubric" do
      expect(question.parse("score" => 99, "confidence" => 0.5).level_index).to eq(2)
      expect(question.parse("score" => -5, "confidence" => 0.5).level_index).to eq(0)
    end

    it "rejects a missing or non-numeric score" do
      expect { question.parse("type" => "score") }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /missing score/)
      expect { question.parse("score" => "high") }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /not a number/)
    end
  end
end
