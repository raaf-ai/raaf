# frozen_string_literal: true

RSpec.describe RAAF::Eval::Models::EvaluationPolicy, type: :model do
  describe "validations" do
    it "requires name" do
      policy = build(:evaluation_policy, name: nil)
      expect(policy).not_to be_valid
      expect(policy.errors[:name]).to include("can't be blank")
    end

    it "requires unique name" do
      create(:evaluation_policy, name: "UniquePolicy")
      policy = build(:evaluation_policy, name: "UniquePolicy")
      expect(policy).not_to be_valid
      expect(policy.errors[:name]).to include("has already been taken")
    end

    it "requires agent_name" do
      policy = build(:evaluation_policy, agent_name: nil)
      expect(policy).not_to be_valid
      expect(policy.errors[:agent_name]).to include("can't be blank")
    end

    it "requires valid sampling_mode" do
      policy = build(:evaluation_policy, sampling_mode: "invalid")
      expect(policy).not_to be_valid
      expect(policy.errors[:sampling_mode]).to be_present
    end

    it "accepts valid sampling_mode values" do
      %w[every_n all].each do |mode|
        policy = build(:evaluation_policy, sampling_mode: mode)
        policy.sample_every_n = 5 if mode == "every_n"
        expect(policy).to be_valid, "Expected sampling_mode '#{mode}' to be valid"
      end
    end

    it "requires sample_every_n for every_n mode" do
      policy = build(:evaluation_policy, sampling_mode: "every_n", sample_every_n: nil)
      expect(policy).not_to be_valid
      expect(policy.errors[:sample_every_n]).to be_present
    end

    it "validates sample_every_n is positive" do
      policy = build(:evaluation_policy, sampling_mode: "every_n", sample_every_n: 0)
      expect(policy).not_to be_valid

      policy.sample_every_n = 5
      expect(policy).to be_valid
    end

    it "validates priority is between 0 and 100" do
      policy = build(:evaluation_policy, priority: -1)
      expect(policy).not_to be_valid

      policy.priority = 101
      expect(policy).not_to be_valid

      policy.priority = 50
      expect(policy).to be_valid
    end

    it "validates evaluators is an array" do
      policy = build(:evaluation_policy, evaluators: "not an array")
      expect(policy).not_to be_valid
    end

    it "validates evaluator structure" do
      policy = build(:evaluation_policy, evaluators: [{ "invalid" => "structure" }])
      expect(policy).not_to be_valid
    end

    it "accepts valid evaluator structure" do
      policy = build(:evaluation_policy, evaluators: [
        { "type" => "rule_based", "name" => "token_limit", "config" => {} }
      ])
      expect(policy).to be_valid
    end
  end

  describe "scopes" do
    before do
      create(:evaluation_policy, name: "Active1", active: true, agent_name: "AgentA")
      create(:evaluation_policy, name: "Active2", active: true, agent_name: "AgentB")
      create(:evaluation_policy, name: "Inactive", active: false, agent_name: "AgentA")
    end

    it "returns active policies" do
      expect(described_class.active.count).to eq(2)
    end

    it "returns inactive policies" do
      expect(described_class.inactive.count).to eq(1)
    end

    it "filters by agent_name" do
      expect(described_class.for_agent("AgentA").count).to eq(2)
      expect(described_class.for_agent("AgentB").count).to eq(1)
    end

    it "orders by priority descending" do
      create(:evaluation_policy, name: "HighPriority", priority: 90)
      create(:evaluation_policy, name: "LowPriority", priority: 10)

      policies = described_class.by_priority
      expect(policies.first.priority).to be > policies.last.priority
    end
  end

  describe "#matches_span?" do
    let(:policy) { create(:evaluation_policy, agent_name: "TestAgent", environment: "production", model_pattern: "gpt-*") }

    it "matches span with exact agent name" do
      span_data = { agent_name: "TestAgent", environment: "production", model: "gpt-4o" }
      expect(policy.matches_span?(span_data)).to be true
    end

    it "matches span with wildcard agent name" do
      policy.update!(agent_name: "Test*")
      span_data = { agent_name: "TestAgent", environment: "production", model: "gpt-4o" }
      expect(policy.matches_span?(span_data)).to be true
    end

    context "with comma-separated agent names" do
      it "matches when span agent matches any of the comma-separated names" do
        policy.update!(agent_name: "AgentA, TestAgent, AgentC")
        span_data = { agent_name: "TestAgent", environment: "production", model: "gpt-4o" }
        expect(policy.matches_span?(span_data)).to be true
      end

      it "matches first agent in comma-separated list" do
        policy.update!(agent_name: "TestAgent, AgentB, AgentC")
        span_data = { agent_name: "TestAgent", environment: "production", model: "gpt-4o" }
        expect(policy.matches_span?(span_data)).to be true
      end

      it "matches last agent in comma-separated list" do
        policy.update!(agent_name: "AgentA, AgentB, TestAgent")
        span_data = { agent_name: "TestAgent", environment: "production", model: "gpt-4o" }
        expect(policy.matches_span?(span_data)).to be true
      end

      it "does not match when span agent is not in the list" do
        policy.update!(agent_name: "AgentA, AgentB, AgentC")
        span_data = { agent_name: "TestAgent", environment: "production", model: "gpt-4o" }
        expect(policy.matches_span?(span_data)).to be false
      end

      it "supports wildcards in comma-separated names" do
        policy.update!(agent_name: "Other*, Test*, Final*")
        span_data = { agent_name: "TestAgent", environment: "production", model: "gpt-4o" }
        expect(policy.matches_span?(span_data)).to be true
      end

      it "handles spaces around commas" do
        policy.update!(agent_name: "AgentA,TestAgent,AgentC") # No spaces
        span_data = { agent_name: "TestAgent", environment: "production", model: "gpt-4o" }
        expect(policy.matches_span?(span_data)).to be true

        policy.update!(agent_name: "AgentA ,  TestAgent  , AgentC") # Extra spaces
        expect(policy.matches_span?(span_data)).to be true
      end
    end

    it "does not match different agent" do
      span_data = { agent_name: "OtherAgent", environment: "production", model: "gpt-4o" }
      expect(policy.matches_span?(span_data)).to be false
    end

    it "matches any environment when set to all" do
      policy.update!(environment: "all")
      span_data = { agent_name: "TestAgent", environment: "staging", model: "gpt-4o" }
      expect(policy.matches_span?(span_data)).to be true
    end

    it "does not match different environment when specified" do
      span_data = { agent_name: "TestAgent", environment: "staging", model: "gpt-4o" }
      expect(policy.matches_span?(span_data)).to be false
    end

    it "matches model with wildcard pattern" do
      span_data = { agent_name: "TestAgent", environment: "production", model: "gpt-4o-mini" }
      expect(policy.matches_span?(span_data)).to be true

      span_data[:model] = "claude-3"
      expect(policy.matches_span?(span_data)).to be false
    end

    it "matches any model when set to all" do
      policy.update!(model_pattern: "all")
      span_data = { agent_name: "TestAgent", environment: "production", model: "claude-3" }
      expect(policy.matches_span?(span_data)).to be true
    end
  end

  describe "#should_sample?" do
    context "with every_n sampling" do
      let(:policy) { create(:evaluation_policy, :every_n_sampling, sample_every_n: 5) }

      it "samples every Nth span" do
        results = 10.times.map { policy.should_sample? }
        expect(results.count(true)).to eq(2) # Should sample 2 out of 10
      end

      it "increments counter correctly" do
        expect { policy.should_sample? }.to change { policy.reload.sample_counter }
      end
    end

    context "with all sampling" do
      let(:policy) { create(:evaluation_policy, :all_spans) }

      it "always samples" do
        10.times { expect(policy.should_sample?).to be true }
      end
    end

    context "with daily limit" do
      let(:policy) { create(:evaluation_policy, sampling_mode: "all", max_daily_evaluations: 10, today_evaluation_count: 5) }

      it "samples when under limit" do
        expect(policy.should_sample?).to be true
      end

      it "does not sample when at limit" do
        policy.update!(today_evaluation_count: 10)
        expect(policy.should_sample?).to be false
      end
    end
  end

  describe "#increment_evaluation_count!" do
    let(:policy) { create(:evaluation_policy) }

    it "increments today_evaluation_count" do
      expect { policy.increment_evaluation_count! }
        .to change { policy.reload.today_evaluation_count }.by(1)
    end

    it "resets counter if date has changed" do
      policy.update!(today_evaluation_count: 50, count_reset_date: Date.yesterday)
      policy.increment_evaluation_count!

      expect(policy.reload.today_evaluation_count).to eq(1)
      expect(policy.count_reset_date).to eq(Date.current)
    end
  end

  describe "#reset_daily_counter!" do
    let(:policy) { create(:evaluation_policy, today_evaluation_count: 50) }

    it "resets counter to zero" do
      policy.reset_daily_counter!
      expect(policy.reload.today_evaluation_count).to eq(0)
    end

    it "updates reset date" do
      policy.update!(count_reset_date: Date.yesterday)
      policy.reset_daily_counter!
      expect(policy.reload.count_reset_date).to eq(Date.current)
    end
  end

  describe "#at_daily_limit?" do
    it "returns false when no limit set" do
      policy = create(:evaluation_policy, max_daily_evaluations: nil)
      expect(policy.at_daily_limit?).to be false
    end

    it "returns true when at limit" do
      policy = create(:evaluation_policy, :at_daily_limit)
      expect(policy.at_daily_limit?).to be true
    end

    it "returns false when under limit" do
      policy = create(:evaluation_policy, max_daily_evaluations: 10, today_evaluation_count: 5)
      expect(policy.at_daily_limit?).to be false
    end
  end

  describe "#evaluator_configs" do
    let(:policy) { create(:evaluation_policy, :with_multiple_evaluators) }

    it "returns evaluator configurations" do
      configs = policy.evaluator_configs
      expect(configs.length).to eq(3)
      expect(configs.first).to include("type" => "rule_based", "name" => "token_limit")
    end
  end

  describe "associations" do
    let(:policy) { create(:evaluation_policy) }

    it "has many queue items" do
      queue_item = create(:evaluation_queue_item, evaluation_policy: policy)
      expect(policy.evaluation_queue_items).to include(queue_item)
    end

    it "has many evaluation results" do
      result = create(:continuous_evaluation_result, evaluation_policy: policy)
      expect(policy.continuous_evaluation_results).to include(result)
    end
  end
end
