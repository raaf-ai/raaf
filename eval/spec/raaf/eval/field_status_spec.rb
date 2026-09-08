# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval::FieldStatus do
  describe ".for" do
    # An evaluator says what good means for the thing it measures. These are
    # the three shapes that were being overruled in production: a judge's 75%,
    # a latency check naming its own breach, and an envelope check failing at
    # a score the fixed bands call good.
    context "with a verdict the evaluator gave" do
      it "keeps good at a score the bands call average" do
        expect(described_class.for(label: "good", score: 0.75)).to eq("good")
      end

      it "keeps bad at a score the bands call average" do
        expect(described_class.for(label: "bad", score: 0.53)).to eq("bad")
      end

      it "keeps bad at a score the bands call good" do
        expect(described_class.for(label: "bad", score: 0.857)).to eq("bad")
      end

      it "keeps average at a score the bands call good" do
        expect(described_class.for(label: "average", score: 0.95)).to eq("average")
      end

      # A stored result comes back from JSON with string keys, and re-stamping
      # an old row has to reach the same answer as writing a new one.
      it "reads a verdict that came back from stored JSON" do
        expect(described_class.for("label" => "good", "score" => 0.75)).to eq("good")
      end
    end

    # status holds four verdicts and the model validates them, so a label
    # outside them is not something this column can carry.
    context "with a verdict the column cannot hold" do
      it "falls back to the score bands" do
        expect(described_class.for(label: "excellent", score: 0.95)).to eq("good")
      end

      it "falls back to the score bands for a blank label" do
        expect(described_class.for(label: "", score: 0.6)).to eq("average")
      end
    end

    context "with no verdict at all" do
      it "derives good from the score" do
        expect(described_class.for(score: 0.8)).to eq("good")
      end

      it "derives average from the score" do
        expect(described_class.for(score: 0.5)).to eq("average")
      end

      it "derives bad from the score" do
        expect(described_class.for(score: 0.49)).to eq("bad")
      end

      # Neither a verdict nor a measurement. Nothing about that can be called
      # good.
      it "derives bad from a missing score" do
        expect(described_class.for({})).to eq("bad")
      end
    end

    # A crashed check combines to "bad" because the stand-in it contributes
    # scores zero, but it reached no verdict at all.
    context "with a check that errored" do
      it "outranks the label built around the failure" do
        expect(described_class.for(label: "bad", score: 0.0, error: true)).to eq("error")
      end

      it "outranks a good label" do
        expect(described_class.for(label: "good", score: 0.9, error: true)).to eq("error")
      end
    end

    it "treats a nil result as bad" do
      expect(described_class.for(nil)).to eq("bad")
    end
  end
end
