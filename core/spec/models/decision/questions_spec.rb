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
      choice = described_class.build(type: "choice", instructions: "Which team?", criteria: { a: nil, b: nil })
      score = described_class.build(type: :score, instructions: "How bad?", criteria: %w[calm angry])

      expect(noul).to be_a(RAAF::Models::Decision::Noul)
      expect(choice).to be_a(RAAF::Models::Decision::Choice)
      expect(score).to be_a(RAAF::Models::Decision::Score)
    end

    it "keeps fields it does not model and sends them on" do
      question = described_class.build(type: :noul, instructions: "It is urgent", weight: 2)

      expect(question.to_request).to eq("type" => "noul", "instructions" => "It is urgent", "weight" => 2)
    end

    it "rejects an unknown type" do
      expect { described_class.build(type: :vibes, instructions: "x") }
        .to raise_error(ArgumentError, /unknown question type/)
    end

    it "rejects a value that is not a Question or Hash" do
      expect { described_class.build("noul") }.to raise_error(ArgumentError, /must be a Question or Hash/)
    end

    it "rejects a choice with no criteria" do
      expect { described_class.build(type: :choice, instructions: "Which team?") }
        .to raise_error(ArgumentError, /criteria/)
    end
  end

  describe RAAF::Models::Decision::Noul do
    it "sends instructions alone" do
      question = described_class.new(instructions: "It is urgent")

      expect(question.to_request).to eq("type" => "noul", "instructions" => "It is urgent")
    end

    it "sends criteria describing a true and a false answer" do
      question = described_class.new(
        instructions: "Is this spam?",
        criteria: { "true" => "Unsolicited advertising", "false" => "A real conversation" }
      )

      expect(question.to_request).to eq(
        "type" => "noul",
        "instructions" => "Is this spam?",
        "criteria" => { "true" => "Unsolicited advertising", "false" => "A real conversation" }
      )
    end

    it "takes criteria without instructions" do
      question = described_class.new(criteria: { "true" => "yes", "false" => "no" })

      expect(question.to_request).not_to have_key("instructions")
    end

    it "rejects a question that asks nothing" do
      expect { described_class.new }.to raise_error(ArgumentError, /needs instructions or criteria/)
    end

    it "rejects criteria that are not a Hash" do
      expect { described_class.new(instructions: "x", criteria: %w[yes no]) }
        .to raise_error(ArgumentError, /must be a Hash/)
    end
  end

  describe RAAF::Models::Decision::Choice do
    it "sends its options and their descriptions" do
      question = described_class.new(
        instructions: "Which team?",
        criteria: { billing: "Payment issues", engineering: "Bugs" }
      )

      expect(question.to_request).to eq(
        "type" => "choice",
        "instructions" => "Which team?",
        "criteria" => { "billing" => "Payment issues", "engineering" => "Bugs" }
      )
    end

    it "takes an Array of option names as shorthand" do
      question = described_class.new(instructions: "What is the tone?", criteria: %w[calm angry])

      expect(question.to_request["criteria"]).to eq("calm" => nil, "angry" => nil)
      expect(question.options).to eq(%w[calm angry])
    end

    it "allows a description of nil where the name speaks for itself" do
      question = described_class.new(criteria: { calm: nil, angry: "Shouting or threats" })

      expect(question.options).to eq(%w[calm angry])
    end

    it "requires at least two options" do
      expect { described_class.new(criteria: { only: nil }) }
        .to raise_error(ArgumentError, /at least 2 options/)
    end

    it "requires criteria to be a Hash or Array" do
      expect { described_class.new(criteria: "billing") }
        .to raise_error(ArgumentError, /must be a Hash/)
    end
  end

  describe RAAF::Models::Decision::Score do
    it "sends its levels in order" do
      question = described_class.new(
        instructions: "How frustrated?",
        criteria: ["Calm", "Frustrated but civil", "Very angry"]
      )

      expect(question.to_request).to eq(
        "type" => "score",
        "instructions" => "How frustrated?",
        "criteria" => ["Calm", "Frustrated but civil", "Very angry"]
      )
    end

    it "numbers its levels from zero" do
      question = described_class.new(criteria: ["Can wait", "This week", "Today"])

      expect(question.levels).to eq(["Can wait", "This week", "Today"])
    end

    it "requires at least two levels" do
      expect { described_class.new(criteria: ["only"]) }
        .to raise_error(ArgumentError, /at least 2 levels/)
    end

    it "requires criteria to be an Array" do
      expect { described_class.new(criteria: { low: "x", high: "y" }) }
        .to raise_error(ArgumentError, /must be an Array/)
    end
  end
end
