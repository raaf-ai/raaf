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

    it "derives confidence from the distance to a coin flip" do
      expect(question.parse("noul" => 0.5).confidence).to eq(0.0)
      expect(question.parse("noul" => 1.0).confidence).to eq(1.0)
      expect(question.parse("noul" => 0.75).confidence).to eq(0.5)
    end

    it "prefers a confidence the provider reports" do
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
      RAAF::Models::Decision::Choice.new(instructions: "Which team?", options: %w[billing eng success])
    end

    it "reads the option and its distribution" do
      answer = question.parse(
        "choice" => "billing",
        "probabilities" => { "billing" => 0.8, "eng" => 0.15, "success" => 0.05 },
        "confidence" => 0.8
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
      expect { question.parse("choice" => "legal") }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /not one of/)
    end

    it "rejects an answer with neither a choice nor probabilities" do
      expect { question.parse("type" => "choice") }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /missing choice/)
    end
  end

  describe RAAF::Models::Decision::Answers::Score do
    let(:question) do
      RAAF::Models::Decision::Score.new(instructions: "How bad?", levels: %w[low medium high critical])
    end

    it "reads the score, level and distribution" do
      answer = question.parse(
        "score" => 2.4,
        "level" => "high",
        "distribution" => { "low" => 0.05, "medium" => 0.2, "high" => 0.6, "critical" => 0.15 }
      )

      expect(answer.score).to eq(2.4)
      expect(answer.level).to eq("high")
      expect(answer.confidence).to eq(0.6)
    end

    it "falls back to the most probable level" do
      answer = question.parse("score" => 1.1, "distribution" => { "low" => 0.1, "medium" => 0.9 })

      expect(answer.level).to eq("medium")
    end

    it "falls back to rounding the score onto the rubric" do
      expect(question.parse("score" => 2.6).level).to eq("critical")
      expect(question.parse("score" => 0.2).level).to eq("low")
    end

    it "clamps a score that runs past the rubric" do
      expect(question.parse("score" => 99).level).to eq("critical")
      expect(question.parse("score" => -5).level).to eq("low")
    end

    it "rejects a missing or non-numeric score" do
      expect { question.parse("type" => "score") }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /missing score/)
      expect { question.parse("score" => "high") }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /not a number/)
    end
  end
end
