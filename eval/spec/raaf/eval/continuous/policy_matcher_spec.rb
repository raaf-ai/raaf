# frozen_string_literal: true

RSpec.describe RAAF::Eval::Continuous::PolicyMatcher do
  let(:span_data) do
    {
      span_id: SecureRandom.uuid,
      trace_id: SecureRandom.uuid,
      agent_name: "TestAgent",
      environment: "production",
      model: "gpt-4o",
      version: "1.0"
    }
  end

  let(:span) { double("SpanRecord", **span_data) }

  describe "#initialize" do
    it "accepts a span" do
      matcher = described_class.new(span)
      expect(matcher.span).to eq(span)
    end
  end

  describe "#matching_policies" do
    before do
      # Clean up any existing policies from other tests
      RAAF::Eval::Models::EvaluationPolicy.delete_all if defined?(RAAF::Eval::Models::EvaluationPolicy)
    end

    context "with a matching policy" do
      let!(:policy) do
        create(:evaluation_policy,
               agent_name: "TestAgent",
               environment: "production",
               model_pattern: "gpt-*",
               active: true,
               sampling_mode: "all")
      end

      it "returns matching active policies" do
        matcher = described_class.new(span)
        policies = matcher.matching_policies
        expect(policies).to include(policy)
      end
    end

    context "with non-matching agent_name" do
      let!(:policy) do
        create(:evaluation_policy,
               agent_name: "OtherAgent",
               active: true)
      end

      it "does not return the policy" do
        matcher = described_class.new(span)
        policies = matcher.matching_policies
        expect(policies).not_to include(policy)
      end
    end

    context "with wildcard agent_name" do
      let!(:policy) do
        create(:evaluation_policy,
               agent_name: "Test*",
               environment: "all",
               model_pattern: "all",
               active: true,
               sampling_mode: "all")
      end

      it "returns the policy when wildcard matches" do
        matcher = described_class.new(span)
        policies = matcher.matching_policies
        expect(policies).to include(policy)
      end
    end

    context "with non-matching environment" do
      let!(:policy) do
        create(:evaluation_policy,
               agent_name: "TestAgent",
               environment: "staging",
               active: true)
      end

      it "does not return the policy" do
        matcher = described_class.new(span)
        policies = matcher.matching_policies
        expect(policies).not_to include(policy)
      end
    end

    context "with environment set to 'all'" do
      let!(:policy) do
        create(:evaluation_policy,
               agent_name: "TestAgent",
               environment: "all",
               model_pattern: "all",
               active: true,
               sampling_mode: "all")
      end

      it "returns the policy for any environment" do
        matcher = described_class.new(span)
        policies = matcher.matching_policies
        expect(policies).to include(policy)
      end
    end

    context "with inactive policy" do
      let!(:policy) do
        create(:evaluation_policy,
               agent_name: "TestAgent",
               environment: "production",
               active: false)
      end

      it "does not return inactive policies" do
        matcher = described_class.new(span)
        policies = matcher.matching_policies
        expect(policies).not_to include(policy)
      end
    end

    context "with model_pattern wildcard" do
      let!(:policy) do
        create(:evaluation_policy,
               agent_name: "TestAgent",
               environment: "all",
               model_pattern: "gpt-*",
               active: true,
               sampling_mode: "all")
      end

      it "matches when model fits pattern" do
        matcher = described_class.new(span)
        policies = matcher.matching_policies
        expect(policies).to include(policy)
      end

      it "does not match when model does not fit pattern" do
        different_span = double("SpanRecord", **span_data.merge(model: "claude-3"))
        matcher = described_class.new(different_span)
        policies = matcher.matching_policies
        expect(policies).not_to include(policy)
      end
    end
  end

  describe "#should_evaluate?" do
    context "with every_n sampling" do
      let!(:every_n_policy) do
        create(:evaluation_policy,
               agent_name: "TestAgent",
               environment: "all",
               model_pattern: "all",
               active: true,
               sampling_mode: "every_n",
               sample_every_n: 5,
               sample_counter: 0)
      end

      it "samples every Nth span" do
        matcher = described_class.new(span)

        results = 10.times.map { matcher.should_evaluate?(every_n_policy) }
        expect(results.count(true)).to eq(2) # Should sample 2 out of 10
      end
    end

    context "with all sampling" do
      let!(:all_policy) do
        create(:evaluation_policy,
               agent_name: "TestAgent",
               environment: "all",
               model_pattern: "all",
               active: true,
               sampling_mode: "all")
      end

      it "always returns true" do
        matcher = described_class.new(span)
        10.times { expect(matcher.should_evaluate?(all_policy)).to be true }
      end
    end

    context "with daily limit" do
      let!(:limited_policy) do
        create(:evaluation_policy,
               agent_name: "TestAgent",
               environment: "all",
               model_pattern: "all",
               active: true,
               sampling_mode: "all",
               max_daily_evaluations: 10,
               today_evaluation_count: 10)
      end

      it "returns false when at daily limit" do
        matcher = described_class.new(span)
        expect(matcher.should_evaluate?(limited_policy)).to be false
      end

      it "returns true when under daily limit" do
        limited_policy.update!(today_evaluation_count: 5)
        matcher = described_class.new(span)
        expect(matcher.should_evaluate?(limited_policy)).to be true
      end
    end
  end

  describe "#policies_to_evaluate" do
    let!(:policy1) do
      create(:evaluation_policy,
             name: "Policy1",
             agent_name: "TestAgent",
             environment: "all",
             model_pattern: "all",
             active: true,
             sampling_mode: "all",
             priority: 80)
    end

    let!(:policy2) do
      create(:evaluation_policy,
             name: "Policy2",
             agent_name: "TestAgent",
             environment: "all",
             model_pattern: "all",
             active: true,
             sampling_mode: "all",
             priority: 50)
    end

    it "returns policies that should be evaluated" do
      matcher = described_class.new(span)
      policies = matcher.policies_to_evaluate
      expect(policies).to include(policy1, policy2)
    end

    it "returns policies ordered by priority" do
      matcher = described_class.new(span)
      policies = matcher.policies_to_evaluate
      expect(policies.first.priority).to be >= policies.last.priority
    end

    context "with evaluation-generated spans" do
      let(:eval_span_data) do
        {
          span_id: SecureRandom.uuid,
          trace_id: SecureRandom.uuid,
          agent_name: "TestAgent",
          environment: "production",
          model: "gpt-4o",
          version: "1.0",
          source: "evaluation_run"
        }
      end

      let(:eval_span) { double("EvaluationSpan", **eval_span_data) }

      it "returns empty array to prevent recursive evaluation" do
        matcher = described_class.new(eval_span)
        policies = matcher.policies_to_evaluate
        expect(policies).to be_empty
      end

      it "does not count eval spans toward policy sample rate" do
        # Production span should match
        prod_span = double("SpanRecord", **span_data.merge(source: "production_trace"))
        prod_matcher = described_class.new(prod_span)
        expect(prod_matcher.policies_to_evaluate).not_to be_empty

        # Eval span should be skipped entirely
        eval_matcher = described_class.new(eval_span)
        expect(eval_matcher.policies_to_evaluate).to be_empty
      end
    end

    context "with production spans" do
      let(:prod_span_data) do
        {
          span_id: SecureRandom.uuid,
          trace_id: SecureRandom.uuid,
          agent_name: "TestAgent",
          environment: "production",
          model: "gpt-4o",
          version: "1.0",
          source: "production_trace"
        }
      end

      let(:prod_span) { double("SpanRecord", **prod_span_data) }

      it "returns matching policies for production spans" do
        matcher = described_class.new(prod_span)
        policies = matcher.policies_to_evaluate
        expect(policies).to include(policy1, policy2)
      end
    end
  end

  describe "#extract_span_attributes" do
    it "extracts relevant attributes from span for matching" do
      matcher = described_class.new(span)
      attrs = matcher.send(:extract_span_attributes)

      expect(attrs[:agent_name]).to eq("TestAgent")
      expect(attrs[:environment]).to eq("production")
      expect(attrs[:model]).to eq("gpt-4o")
    end

    context "with span having span_data hash" do
      let(:span_with_data) do
        double("SpanRecord",
               span_id: SecureRandom.uuid,
               span_data: { "agent_name" => "DataAgent", "model" => "claude-3" })
      end

      it "extracts from span_data if attributes not directly available" do
        # Skip this test if the span doesn't respond to these methods
        allow(span_with_data).to receive(:respond_to?).with(:agent_name).and_return(false)
        allow(span_with_data).to receive(:respond_to?).with(:environment).and_return(false)
        allow(span_with_data).to receive(:respond_to?).with(:model).and_return(false)
        allow(span_with_data).to receive(:respond_to?).with(:version).and_return(false)
        allow(span_with_data).to receive(:respond_to?).with(:span_data).and_return(true)

        matcher = described_class.new(span_with_data)
        attrs = matcher.send(:extract_span_attributes)

        expect(attrs[:agent_name]).to eq("DataAgent")
        expect(attrs[:model]).to eq("claude-3")
      end
    end
  end
end
