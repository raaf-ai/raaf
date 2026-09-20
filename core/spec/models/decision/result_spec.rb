# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::Decision::Result do
  subject(:result) do
    described_class.new(
      answers: { "urgent" => urgent },
      model: "jev-latest",
      provider: "Jev",
      raw: { "urgent" => { "noul" => 0.9 } },
      usage: { "tokens" => 12 }
    )
  end

  let(:urgent) { RAAF::Models::Decision::Noul.new(instructions: "It is urgent").parse("noul" => 0.9) }

  it "looks answers up by String or Symbol" do
    expect(result[:urgent]).to be(urgent)
    expect(result["urgent"]).to be(urgent)
    expect(result[:missing]).to be_nil
  end

  it "raises on fetch for an unanswered question" do
    expect { result.fetch(:missing) }.to raise_error(KeyError)
  end

  it "exposes the response metadata" do
    expect(result.model).to eq("jev-latest")
    expect(result.provider).to eq("Jev")
    expect(result.usage).to eq("tokens" => 12)
    expect(result.names).to eq(["urgent"])
  end

  it "enumerates its answers" do
    expect(result.map { |name, _answer| name }).to eq(["urgent"])
  end

  it "renders itself as plain Hashes" do
    expect(result.to_h).to eq("urgent" => { type: "noul", confidence: 0.8, probability: 0.9 })
  end
end
