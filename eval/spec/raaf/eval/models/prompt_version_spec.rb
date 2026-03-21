# frozen_string_literal: true

RSpec.describe RAAF::Eval::Models::PromptVersion, type: :model do
  describe "validations" do
    it "requires content" do
      version = build(:prompt_version, content: nil)
      expect(version).not_to be_valid
    end

    it "requires version_number" do
      version = build(:prompt_version, version_number: nil)
      expect(version).not_to be_valid
    end

    it "requires valid status" do
      version = build(:prompt_version, status: "invalid")
      expect(version).not_to be_valid
    end

    it "accepts valid status values" do
      %w[draft published archived].each do |status|
        version = build(:prompt_version, status: status)
        expect(version).to be_valid
      end
    end

    it "enforces unique version per prompt" do
      prompt = create(:prompt)
      create(:prompt_version, prompt: prompt, version_number: 1)
      duplicate = build(:prompt_version, prompt: prompt, version_number: 1)
      expect(duplicate).not_to be_valid
    end
  end

  describe "#publish!" do
    let(:prompt) { create(:prompt) }

    it "publishes the version and archives previous published version" do
      v1 = create(:prompt_version, prompt: prompt, version_number: 1, status: "published")
      v2 = create(:prompt_version, prompt: prompt, version_number: 2, status: "draft")

      v2.publish!

      expect(v2.reload.status).to eq("published")
      expect(v1.reload.status).to eq("archived")
    end
  end

  describe "#archive!" do
    it "archives the version" do
      version = create(:prompt_version, status: "published")
      version.archive!
      expect(version.status).to eq("archived")
    end
  end

  describe "status predicates" do
    it "checks published?" do
      expect(build(:prompt_version, status: "published")).to be_published
    end

    it "checks draft?" do
      expect(build(:prompt_version, status: "draft")).to be_draft
    end

    it "checks archived?" do
      expect(build(:prompt_version, status: "archived")).to be_archived
    end
  end

  describe "#content_length" do
    it "returns content length" do
      version = build(:prompt_version, content: "Hello world")
      expect(version.content_length).to eq(11)
    end
  end

  describe "#summary" do
    it "returns a formatted summary" do
      version = build(:prompt_version, version_number: 3, status: "draft", commit_message: "Fix typo")
      expect(version.summary).to eq("v3 (draft) - Fix typo")
    end
  end

  describe "scopes" do
    let(:prompt) { create(:prompt) }

    it "filters published versions" do
      create(:prompt_version, prompt: prompt, version_number: 1, status: "published")
      create(:prompt_version, prompt: prompt, version_number: 2, status: "draft")

      expect(described_class.published.count).to eq(1)
    end
  end
end
