# frozen_string_literal: true

require "rails_helper"

# Three of the four controls on this screen did nothing: "New Version" linked
# to the page you were already on, and "Publish" and "Archive" were anchors
# pointing at routes the routes file declares post only.
RSpec.describe RAAF::Rails::Eval::PromptShow, type: :component do
  let(:prompt) do
    RAAF::Eval::Models::Prompt.create!(name: "support_reply", agent_name: "SupportAgent")
  end

  def version(number:, status: "draft", content: "hello")
    RAAF::Eval::Models::PromptVersion.create!(
      prompt: prompt, version_number: number, content: content,
      status: status, model: "gpt-4o"
    )
  end

  def screen(versions, active: nil)
    described_class.new(prompt: prompt, versions: versions, active_version: active)
  end

  describe "New version" do
    it "goes to a form rather than back to this page" do
      path = screen([]).send(:new_version_path)

      expect(path).to end_with("/versions/new")
      expect(path).not_to eq("/raaf/eval/prompts/#{prompt.id}")
    end
  end

  describe "Publish and Archive" do
    it "posts, which is the only verb their routes declare" do
      draft = version(number: 2)

      actions = screen([draft]).send(:row_actions, draft, 0)
                               .instance_variable_get(:@actions)

      expect(actions.map { |action| action[:method] }).to all(eq(:post))
      expect(actions.map { |action| action[:label] }).to eq(%w[Publish Archive])
    end

    it "offers no publish for a version that is already published" do
      published = version(number: 2, status: "published")

      labels = screen([published]).send(:row_actions, published, 0)
                                  .instance_variable_get(:@actions).map { |action| action[:label] }

      expect(labels).to eq(%w[Archive])
    end

    it "offers nothing to archive twice" do
      archived = version(number: 2, status: "archived")

      labels = screen([archived]).send(:row_actions, archived, 0)
                                 .instance_variable_get(:@actions).map { |action| action[:label] }

      expect(labels).to be_empty
    end
  end

  describe "the diff" do
    # Nothing in the console linked diff_eval_prompt_path before this.
    it "compares a version against the one before it" do
      newer = version(number: 3)
      older = version(number: 2)

      diff = screen([newer, older]).send(:row_actions, newer, 0)
                                   .instance_variable_get(:@actions)
                                   .find { |action| action[:label] == "Diff" }

      expect(diff[:href]).to include("from=2", "to=3")
    end

    it "offers no diff on the oldest version, which has nothing before it" do
      oldest = version(number: 1)

      labels = screen([oldest]).send(:row_actions, oldest, 0)
                               .instance_variable_get(:@actions).map { |action| action[:label] }

      expect(labels).not_to include("Diff")
    end
  end
end
