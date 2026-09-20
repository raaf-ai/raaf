# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::Decision::Question do
  describe ".build" do
    it "passes a Question through untouched" do
      question = RAAF::Models::Decision::Noul.new(instructions: "It is urgent")

      expect(described_class.build(question)).to be(question)
    end

    it "builds each type from its Hash form" do
      noul = described_class.build(type: :noul, instructions: "It is urgent")
      choice = described_class.build(type: "choice", instructions: "Which team?", options: %w[a b])
      score = described_class.build(type: :score, instructions: "How bad?", levels: %w[low high])

      expect(noul).to be_a(RAAF::Models::Decision::Noul)
      expect(choice).to be_a(RAAF::Models::Decision::Choice)
      expect(score).to be_a(RAAF::Models::Decision::Score)
    end

    it "rejects an unknown type" do
      expect { described_class.build(type: :vibes, instructions: "x") }
        .to raise_error(ArgumentError, /unknown question type/)
    end

    it "rejects a value that is not a Question or Hash" do
      expect { described_class.build("noul") }.to raise_error(ArgumentError, /must be a Question or Hash/)
    end
  end

  describe "validation" do
    it "requires instructions" do
      expect { RAAF::Models::Decision::Noul.new(instructions: "  ") }
        .to raise_error(ArgumentError, /non-empty String/)
    end

    it "requires at least two distinct choice options" do
      expect { RAAF::Models::Decision::Choice.new(instructions: "x", options: %w[only]) }
        .to raise_error(ArgumentError, /at least 2 options/)
      expect { RAAF::Models::Decision::Choice.new(instructions: "x", options: %w[a a]) }
        .to raise_error(ArgumentError, /distinct/)
    end

    it "requires at least two distinct score levels" do
      expect { RAAF::Models::Decision::Score.new(instructions: "x", levels: %w[low]) }
        .to raise_error(ArgumentError, /at least 2 levels/)
      expect { RAAF::Models::Decision::Score.new(instructions: "x", levels: %w[low low]) }
        .to raise_error(ArgumentError, /distinct/)
    end
  end

  describe "#to_request" do
    it "renders a noul" do
      question = RAAF::Models::Decision::Noul.new(instructions: "It is urgent")

      expect(question.to_request).to eq(type: "noul", instructions: "It is urgent")
    end

    it "renders a choice with its options" do
      question = RAAF::Models::Decision::Choice.new(instructions: "Which team?", options: %w[billing eng])

      expect(question.to_request).to eq(type: "choice", instructions: "Which team?", options: %w[billing eng])
    end

    it "renders a score with its levels" do
      question = RAAF::Models::Decision::Score.new(instructions: "How bad?", levels: %w[low high])

      expect(question.to_request).to eq(type: "score", instructions: "How bad?", levels: %w[low high])
    end
  end
end
