# frozen_string_literal: true

RSpec.describe RAAF::Eval::Models::Prompt, type: :model do
  describe "validations" do
    it "requires name" do
      prompt = build(:prompt, name: nil)
      expect(prompt).not_to be_valid
    end

    it "enforces unique name" do
      create(:prompt, name: "unique_prompt")
      duplicate = build(:prompt, name: "unique_prompt")
      expect(duplicate).not_to be_valid
    end
  end

  describe "#create_version!" do
    let(:prompt) { create(:prompt) }

    it "creates a new version with incremented number" do
      v1 = prompt.create_version!(content: "Version 1 content", commit_message: "Initial")
      expect(v1.version_number).to eq(1)
      expect(prompt.reload.latest_version).to eq(1)

      v2 = prompt.create_version!(content: "Version 2 content", commit_message: "Update")
      expect(v2.version_number).to eq(2)
      expect(prompt.reload.latest_version).to eq(2)
    end

    it "sets version as draft by default" do
      version = prompt.create_version!(content: "Content")
      expect(version.status).to eq("draft")
    end
  end

  describe "#active_version" do
    let(:prompt) { create(:prompt) }

    it "returns the published version" do
      v1 = prompt.create_version!(content: "V1")
      v1.publish!
      prompt.create_version!(content: "V2 draft")

      expect(prompt.active_version).to eq(v1)
    end

    it "returns nil when no published version" do
      prompt.create_version!(content: "Draft")
      expect(prompt.active_version).to be_nil
    end
  end

  describe "#version" do
    let(:prompt) { create(:prompt) }

    it "retrieves a specific version" do
      prompt.create_version!(content: "V1")
      v2 = prompt.create_version!(content: "V2")

      expect(prompt.version(2)).to eq(v2)
    end
  end

  describe "#diff" do
    let(:prompt) { create(:prompt) }

    before do
      prompt.create_version!(content: "Original prompt", model: "gpt-4o")
      prompt.create_version!(content: "Updated prompt", model: "gpt-4o-mini")
    end

    it "shows differences between versions" do
      diff = prompt.diff(1, 2)

      expect(diff[:content_changed]).to be true
      expect(diff[:model_changed]).to be true
      expect(diff[:from][:content]).to eq("Original prompt")
      expect(diff[:to][:content]).to eq("Updated prompt")
    end
  end

  describe "#history" do
    let(:prompt) { create(:prompt) }

    before do
      v1 = prompt.create_version!(content: "V1", commit_message: "Initial")
      v1.publish!
      prompt.create_version!(content: "V2", commit_message: "Update tone")
    end

    it "returns version summaries in descending order" do
      history = prompt.history
      expect(history.length).to eq(2)
      expect(history.first[:version]).to eq(2)
      expect(history.first[:commit_message]).to eq("Update tone")
      expect(history.last[:status]).to eq("published")
    end
  end

  describe "scopes" do
    it "filters by agent name" do
      create(:prompt, agent_name: "AgentA")
      create(:prompt, agent_name: "AgentB")

      expect(described_class.for_agent("AgentA").count).to eq(1)
    end
  end
end
