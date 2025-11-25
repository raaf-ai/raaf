# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-11-25-continuous-evaluation-database-system/spec.md

> Created: 2025-11-25
> Version: 1.0.0

## Test Coverage Overview

The continuous evaluation system requires comprehensive testing across:
- Model validations and business logic
- Background job processing
- Controller actions and responses
- D3.js chart rendering (JavaScript)
- Integration workflows

## Unit Tests

### Models

#### EvaluationPolicy

```ruby
# spec/models/raaf/eval/evaluation_policy_spec.rb
RSpec.describe RAAF::Eval::EvaluationPolicy, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
    it { should validate_presence_of(:agent_name) }
    it { should validate_inclusion_of(:sampling_mode).in_array(%w[percentage every_n all]) }
    it { should validate_numericality_of(:sample_rate).is_greater_than_or_equal_to(1).is_less_than_or_equal_to(100) }
    it { should validate_numericality_of(:priority).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
  end

  describe 'associations' do
    it { should have_many(:evaluation_results) }
    it { should have_many(:evaluation_queue_items).class_name('EvaluationQueue') }
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns only active policies' do
        active = create(:evaluation_policy, active: true)
        inactive = create(:evaluation_policy, active: false)

        expect(described_class.active).to include(active)
        expect(described_class.active).not_to include(inactive)
      end
    end

    describe '.where_matches_span' do
      let(:span) { create(:span_record, span_attributes: { 'agent' => { 'name' => 'DmuDiscovery' } }) }

      it 'matches exact agent name' do
        policy = create(:evaluation_policy, agent_name: 'DmuDiscovery')
        expect(described_class.where_matches_span(span)).to include(policy)
      end

      it 'matches wildcard agent name' do
        policy = create(:evaluation_policy, agent_name: 'Dmu*')
        expect(described_class.where_matches_span(span)).to include(policy)
      end

      it 'does not match non-matching agent' do
        policy = create(:evaluation_policy, agent_name: 'OtherAgent')
        expect(described_class.where_matches_span(span)).not_to include(policy)
      end
    end
  end

  describe '#should_evaluate?' do
    context 'with percentage sampling' do
      let(:policy) { create(:evaluation_policy, sampling_mode: 'percentage', sample_rate: 50) }

      it 'returns true approximately sample_rate% of the time' do
        results = 1000.times.map { policy.should_evaluate? }
        true_count = results.count(true)

        # Allow 10% variance
        expect(true_count).to be_between(400, 600)
      end
    end

    context 'with every_n sampling' do
      let(:policy) { create(:evaluation_policy, sampling_mode: 'every_n', sample_every_n: 5) }

      it 'returns true every Nth call' do
        results = 10.times.map { policy.should_evaluate? }
        expect(results).to eq([false, false, false, false, true, false, false, false, false, true])
      end
    end

    context 'with daily limit' do
      let(:policy) { create(:evaluation_policy, max_daily_evaluations: 10, today_evaluation_count: 10) }

      it 'returns false when limit reached' do
        expect(policy.should_evaluate?).to be false
      end
    end
  end

  describe '#increment_evaluation_count!' do
    let(:policy) { create(:evaluation_policy, today_evaluation_count: 5) }

    it 'increments the counter' do
      expect { policy.increment_evaluation_count! }
        .to change { policy.reload.today_evaluation_count }.from(5).to(6)
    end
  end

  describe '#reset_daily_count!' do
    let(:policy) { create(:evaluation_policy, today_evaluation_count: 100) }

    it 'resets counter to zero' do
      expect { policy.reset_daily_count! }
        .to change { policy.reload.today_evaluation_count }.from(100).to(0)
    end

    it 'updates count_reset_date' do
      policy.reset_daily_count!
      expect(policy.reload.count_reset_date).to eq(Date.current)
    end
  end

  describe '#evaluators_config' do
    let(:policy) { create(:evaluation_policy, evaluators: [{ 'type' => 'rule_based', 'name' => 'test' }]) }

    it 'returns evaluators with indifferent access' do
      expect(policy.evaluators_config.first[:type]).to eq('rule_based')
      expect(policy.evaluators_config.first['type']).to eq('rule_based')
    end
  end
end
```

#### EvaluationQueue

```ruby
# spec/models/raaf/eval/evaluation_queue_spec.rb
RSpec.describe RAAF::Eval::EvaluationQueue, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:span_id) }
    it { should validate_presence_of(:trace_id) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[pending running completed failed cancelled]) }
  end

  describe 'associations' do
    it { should belong_to(:evaluation_policy).optional }
    it { should have_many(:evaluation_results) }
  end

  describe 'state transitions' do
    let(:queue_item) { create(:evaluation_queue, status: 'pending') }

    describe '#mark_running!' do
      it 'updates status to running' do
        queue_item.mark_running!
        expect(queue_item.status).to eq('running')
        expect(queue_item.started_at).to be_present
      end
    end

    describe '#mark_completed!' do
      before { queue_item.update!(status: 'running') }

      it 'updates status to completed' do
        queue_item.mark_completed!
        expect(queue_item.status).to eq('completed')
        expect(queue_item.completed_at).to be_present
      end
    end

    describe '#mark_failed!' do
      before { queue_item.update!(status: 'running') }

      it 'updates status and records error' do
        queue_item.mark_failed!('Test error')
        expect(queue_item.status).to eq('failed')
        expect(queue_item.error_message).to eq('Test error')
        expect(queue_item.attempts).to eq(1)
      end
    end
  end

  describe 'scopes' do
    describe '.pending_ordered' do
      it 'orders by priority desc, then created_at asc' do
        low = create(:evaluation_queue, priority: 10, created_at: 1.hour.ago)
        high = create(:evaluation_queue, priority: 90, created_at: 1.minute.ago)
        medium = create(:evaluation_queue, priority: 50, created_at: 2.hours.ago)

        expect(described_class.pending_ordered).to eq([high, medium, low])
      end
    end
  end
end
```

#### EvaluationResult

```ruby
# spec/models/raaf/eval/evaluation_result_spec.rb
RSpec.describe RAAF::Eval::EvaluationResult, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:span_id) }
    it { should validate_presence_of(:trace_id) }
    it { should validate_presence_of(:evaluator_name) }
    it { should validate_presence_of(:evaluator_type) }
    it { should validate_presence_of(:agent_name) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[passed failed warning error]) }
    it { should validate_inclusion_of(:evaluator_type).in_array(%w[rule_based statistical llm_judge]) }
    it { should validate_numericality_of(:score).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(1).allow_nil }
  end

  describe 'associations' do
    it { should belong_to(:evaluation_policy).optional }
    it { should belong_to(:queue_item).class_name('EvaluationQueue').optional }
  end

  describe 'scopes' do
    describe '.recent' do
      it 'orders by created_at desc' do
        old = create(:evaluation_result, created_at: 1.day.ago)
        new = create(:evaluation_result, created_at: 1.hour.ago)

        expect(described_class.recent.first).to eq(new)
      end
    end

    describe '.by_agent' do
      it 'filters by agent name' do
        dmu = create(:evaluation_result, agent_name: 'DmuDiscovery')
        other = create(:evaluation_result, agent_name: 'OtherAgent')

        expect(described_class.by_agent('DmuDiscovery')).to include(dmu)
        expect(described_class.by_agent('DmuDiscovery')).not_to include(other)
      end
    end
  end

  describe '#passed?' do
    it 'returns true for passed status' do
      result = build(:evaluation_result, status: 'passed')
      expect(result.passed?).to be true
    end

    it 'returns false for failed status' do
      result = build(:evaluation_result, status: 'failed')
      expect(result.passed?).to be false
    end
  end

  describe '#failed?' do
    it 'returns true for failed status' do
      result = build(:evaluation_result, status: 'failed')
      expect(result.failed?).to be true
    end
  end
end
```

#### EvaluationMetric

```ruby
# spec/models/raaf/eval/evaluation_metric_spec.rb
RSpec.describe RAAF::Eval::EvaluationMetric, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:agent_name) }
    it { should validate_presence_of(:period_type) }
    it { should validate_presence_of(:period_start) }
    it { should validate_inclusion_of(:period_type).in_array(%w[hourly daily weekly]) }
  end

  describe '.upsert_metric' do
    let(:attrs) do
      {
        agent_name: 'TestAgent',
        period_type: 'daily',
        period_start: Date.current.beginning_of_day,
        total_evaluations: 100,
        passed_count: 85
      }
    end

    it 'creates a new record if not exists' do
      expect { described_class.upsert_metric(attrs) }
        .to change { described_class.count }.by(1)
    end

    it 'updates existing record' do
      described_class.upsert_metric(attrs)
      described_class.upsert_metric(attrs.merge(total_evaluations: 200))

      expect(described_class.count).to eq(1)
      expect(described_class.first.total_evaluations).to eq(200)
    end
  end

  describe '#pass_rate' do
    let(:metric) { build(:evaluation_metric, total_evaluations: 100, passed_count: 85) }

    it 'calculates pass rate percentage' do
      expect(metric.pass_rate).to eq(85.0)
    end

    it 'returns 0 when no evaluations' do
      metric.total_evaluations = 0
      expect(metric.pass_rate).to eq(0)
    end
  end
end
```

### Services

#### PolicyMatcher

```ruby
# spec/services/raaf/eval/continuous/policy_matcher_spec.rb
RSpec.describe RAAF::Eval::Continuous::PolicyMatcher do
  let(:span) do
    create(:span_record,
      span_attributes: {
        'agent' => { 'name' => 'DmuDiscovery' },
        'llm' => { 'request' => { 'model' => 'gemini-2.5-flash' } }
      }
    )
  end

  describe '#matching_policies' do
    it 'returns empty array when no policies exist' do
      expect(described_class.new(span).matching_policies).to be_empty
    end

    it 'returns matching active policies' do
      policy = create(:evaluation_policy, agent_name: 'DmuDiscovery', active: true)
      expect(described_class.new(span).matching_policies).to include(policy)
    end

    it 'excludes inactive policies' do
      policy = create(:evaluation_policy, agent_name: 'DmuDiscovery', active: false)
      expect(described_class.new(span).matching_policies).not_to include(policy)
    end

    it 'respects environment filter' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      prod_policy = create(:evaluation_policy, agent_name: 'DmuDiscovery', environment: 'production')
      staging_policy = create(:evaluation_policy, agent_name: 'DmuDiscovery', environment: 'staging')

      results = described_class.new(span).matching_policies
      expect(results).to include(prod_policy)
      expect(results).not_to include(staging_policy)
    end

    it 'respects model pattern filter' do
      gemini_policy = create(:evaluation_policy, agent_name: 'DmuDiscovery', model_pattern: 'gemini-*')
      gpt_policy = create(:evaluation_policy, agent_name: 'DmuDiscovery', model_pattern: 'gpt-*')

      results = described_class.new(span).matching_policies
      expect(results).to include(gemini_policy)
      expect(results).not_to include(gpt_policy)
    end
  end
end
```

#### EvaluatorDiscovery

Discovers and provides information about evaluators registered in the DSL registry. This includes both built-in evaluators and custom evaluators defined in end-user applications.

```ruby
# spec/services/raaf/eval/continuous/evaluator_discovery_spec.rb
RSpec.describe RAAF::Eval::Continuous::EvaluatorDiscovery do
  # Register a test evaluator for these specs
  before do
    # Create a test evaluator class
    stub_const('TestCustomEvaluator', Class.new do
      include RAAF::Eval::DSL::Evaluator

      def self.description
        'A test evaluator for specs'
      end

      def self.evaluator_type
        'rule_based'
      end

      def self.configurable_options
        [
          { name: 'threshold', type: 'float', default: 0.8 }
        ]
      end

      def evaluate(field_context, **options)
        # Test implementation
      end
    end)

    RAAF::Eval::DSL::EvaluatorRegistry.instance.register(:test_custom, TestCustomEvaluator)
  end

  describe '.available_evaluators' do
    it 'returns array of evaluator names' do
      names = described_class.available_evaluators
      expect(names).to be_an(Array)
      expect(names).to include(:test_custom)
    end

    it 'includes built-in evaluators' do
      names = described_class.available_evaluators
      # Built-in evaluators should be present after auto_register_built_ins
      expect(names.length).to be > 0
    end
  end

  describe '.evaluator_details' do
    it 'returns array of evaluator detail hashes' do
      details = described_class.evaluator_details
      expect(details).to be_an(Array)
      expect(details.first).to include(:name, :class_name, :type)
    end

    it 'includes description when available' do
      details = described_class.evaluator_details
      test_eval = details.find { |d| d[:name] == 'test_custom' }

      expect(test_eval[:description]).to eq('A test evaluator for specs')
    end

    it 'includes configurable options when available' do
      details = described_class.evaluator_details
      test_eval = details.find { |d| d[:name] == 'test_custom' }

      expect(test_eval[:configurable_options]).to include(
        hash_including(name: 'threshold', type: 'float')
      )
    end

    it 'determines evaluator type correctly' do
      details = described_class.evaluator_details
      test_eval = details.find { |d| d[:name] == 'test_custom' }

      expect(test_eval[:type]).to eq('rule_based')
    end
  end

  describe '.build' do
    it 'builds evaluator instance from config' do
      config = { name: 'test_custom', config: { threshold: 0.9 } }
      evaluator = described_class.build(config)

      expect(evaluator).to be_a(TestCustomEvaluator)
    end

    it 'raises error for unknown evaluator' do
      config = { name: 'nonexistent_evaluator', config: {} }

      expect { described_class.build(config) }
        .to raise_error(RAAF::Eval::Continuous::UnknownEvaluatorError)
    end

    it 'works with string or symbol name' do
      config_sym = { name: :test_custom, config: {} }
      config_str = { name: 'test_custom', config: {} }

      expect(described_class.build(config_sym)).to be_a(TestCustomEvaluator)
      expect(described_class.build(config_str)).to be_a(TestCustomEvaluator)
    end
  end
end
```

### Jobs

#### EvaluationJob

```ruby
# spec/jobs/raaf/eval/continuous/evaluation_job_spec.rb
RSpec.describe RAAF::Eval::Continuous::EvaluationJob, type: :job do
  include ActiveJob::TestHelper

  let(:span) { create(:span_record) }
  let(:policy) do
    create(:evaluation_policy,
      evaluators: [{ 'type' => 'rule_based', 'name' => 'token_limit', 'config' => { 'max_tokens' => 4000 } }]
    )
  end

  describe '#perform' do
    it 'creates queue item and runs evaluators' do
      expect {
        described_class.new.perform(span_id: span.span_id, policy_id: policy.id)
      }.to change { RAAF::Eval::EvaluationQueue.count }.by(1)
       .and change { RAAF::Eval::EvaluationResult.count }.by(1)
    end

    it 'marks queue item as completed on success' do
      described_class.new.perform(span_id: span.span_id, policy_id: policy.id)

      queue_item = RAAF::Eval::EvaluationQueue.last
      expect(queue_item.status).to eq('completed')
    end

    it 'marks queue item as failed on error' do
      allow_any_instance_of(RAAF::Eval::Continuous::RuleBasedEvaluator)
        .to receive(:evaluate).and_raise(StandardError, 'Test error')

      expect {
        described_class.new.perform(span_id: span.span_id, policy_id: policy.id)
      }.to raise_error(StandardError)

      queue_item = RAAF::Eval::EvaluationQueue.last
      expect(queue_item.status).to eq('failed')
      expect(queue_item.error_message).to eq('Test error')
    end

    it 'discards job when span not found' do
      expect {
        described_class.new.perform(span_id: 'nonexistent', policy_id: policy.id)
      }.not_to raise_error
    end

    it 'retries on transient errors' do
      perform_enqueued_jobs do
        assert_performed_jobs 3 do
          described_class.perform_later(span_id: span.span_id, policy_id: policy.id)
        end
      end
    end
  end
end
```

#### MetricsAggregationJob

```ruby
# spec/jobs/raaf/eval/continuous/metrics_aggregation_job_spec.rb
RSpec.describe RAAF::Eval::Continuous::MetricsAggregationJob, type: :job do
  describe '#perform' do
    before do
      create_list(:evaluation_result, 10, agent_name: 'TestAgent', status: 'passed', created_at: 1.hour.ago)
      create_list(:evaluation_result, 5, agent_name: 'TestAgent', status: 'failed', created_at: 1.hour.ago)
    end

    context 'hourly aggregation' do
      it 'creates hourly metric records' do
        expect {
          described_class.new.perform(period_type: 'hourly')
        }.to change { RAAF::Eval::EvaluationMetric.where(period_type: 'hourly').count }.by_at_least(1)
      end

      it 'calculates correct totals' do
        described_class.new.perform(period_type: 'hourly')

        metric = RAAF::Eval::EvaluationMetric.find_by(agent_name: 'TestAgent', period_type: 'hourly')
        expect(metric.total_evaluations).to eq(15)
        expect(metric.passed_count).to eq(10)
        expect(metric.failed_count).to eq(5)
      end
    end

    context 'daily aggregation' do
      it 'aggregates results by day' do
        described_class.new.perform(period_type: 'daily')

        metric = RAAF::Eval::EvaluationMetric.find_by(agent_name: 'TestAgent', period_type: 'daily')
        expect(metric).to be_present
        expect(metric.period_start).to eq(Date.current.beginning_of_day)
      end
    end
  end
end
```

## Integration Tests

### Controller Tests

#### EvaluatorsController

```ruby
# spec/requests/raaf/rails/evaluation/evaluators_spec.rb
RSpec.describe 'RAAF::Rails::Evaluation::Evaluators', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in(user)

    # Register a test evaluator
    stub_const('TestEvaluator', Class.new do
      include RAAF::Eval::DSL::Evaluator

      def self.description
        'Test evaluator for specs'
      end

      def self.evaluator_type
        'rule_based'
      end

      def self.configurable_options
        [{ name: 'min_score', type: 'float', default: 0.7 }]
      end

      def evaluate(field_context, **options)
        # Implementation
      end
    end)

    RAAF::Eval::DSL::EvaluatorRegistry.instance.register(:test_evaluator, TestEvaluator)
  end

  describe 'GET /raaf/rails/evaluation/evaluators' do
    it 'returns success' do
      get raaf_rails_evaluation_evaluators_path
      expect(response).to have_http_status(:success)
    end

    it 'lists all registered evaluators' do
      get raaf_rails_evaluation_evaluators_path
      expect(response.body).to include('test_evaluator')
    end

    context 'with JSON format' do
      it 'returns evaluator details as JSON' do
        get raaf_rails_evaluation_evaluators_path, headers: { 'Accept' => 'application/json' }

        expect(response.content_type).to include('application/json')

        data = JSON.parse(response.body)
        expect(data).to be_an(Array)

        test_eval = data.find { |e| e['name'] == 'test_evaluator' }
        expect(test_eval).to include(
          'name' => 'test_evaluator',
          'type' => 'rule_based',
          'description' => 'Test evaluator for specs'
        )
        expect(test_eval['configurable_options']).to include(
          hash_including('name' => 'min_score', 'type' => 'float')
        )
      end
    end
  end

  describe 'GET /raaf/rails/evaluation/evaluators/:id' do
    it 'returns evaluator details' do
      get raaf_rails_evaluation_evaluator_path('test_evaluator')
      expect(response).to have_http_status(:success)
      expect(response.body).to include('test_evaluator')
    end

    it 'returns 404 for unknown evaluator' do
      get raaf_rails_evaluation_evaluator_path('nonexistent')
      expect(response).to have_http_status(:not_found)
    end

    context 'with JSON format' do
      it 'returns evaluator details as JSON' do
        get raaf_rails_evaluation_evaluator_path('test_evaluator'),
            headers: { 'Accept' => 'application/json' }

        data = JSON.parse(response.body)
        expect(data['name']).to eq('test_evaluator')
        expect(data['configurable_options']).to be_an(Array)
      end
    end
  end
end
```

#### PoliciesController

```ruby
# spec/requests/raaf/rails/evaluation/policies_spec.rb
RSpec.describe 'RAAF::Rails::Evaluation::Policies', type: :request do
  let(:user) { create(:user, :admin) }

  before { sign_in(user) }

  describe 'GET /raaf/rails/evaluation/policies' do
    it 'returns success' do
      get raaf_rails_evaluation_policies_path
      expect(response).to have_http_status(:success)
    end

    it 'lists all policies' do
      policies = create_list(:evaluation_policy, 3)
      get raaf_rails_evaluation_policies_path

      policies.each do |policy|
        expect(response.body).to include(policy.name)
      end
    end

    it 'filters by active status' do
      active = create(:evaluation_policy, active: true)
      inactive = create(:evaluation_policy, active: false)

      get raaf_rails_evaluation_policies_path, params: { active: 'true' }

      expect(response.body).to include(active.name)
      expect(response.body).not_to include(inactive.name)
    end
  end

  describe 'POST /raaf/rails/evaluation/policies' do
    let(:valid_params) do
      {
        evaluation_policy: {
          name: 'Test Policy',
          agent_name: 'TestAgent',
          sampling_mode: 'percentage',
          sample_rate: 10,
          evaluators: [{ type: 'rule_based', name: 'test' }]
        }
      }
    end

    it 'creates a new policy' do
      expect {
        post raaf_rails_evaluation_policies_path, params: valid_params
      }.to change { RAAF::Eval::EvaluationPolicy.count }.by(1)

      expect(response).to redirect_to(raaf_rails_evaluation_policy_path(RAAF::Eval::EvaluationPolicy.last))
    end

    it 'returns errors for invalid params' do
      post raaf_rails_evaluation_policies_path, params: { evaluation_policy: { name: '' } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /raaf/rails/evaluation/policies/:id/activate' do
    let(:policy) { create(:evaluation_policy, active: false) }

    it 'activates the policy' do
      post activate_raaf_rails_evaluation_policy_path(policy)

      expect(policy.reload.active).to be true
      expect(response).to redirect_to(raaf_rails_evaluation_policies_path)
    end
  end

  describe 'POST /raaf/rails/evaluation/policies/:id/deactivate' do
    let(:policy) { create(:evaluation_policy, active: true) }

    it 'deactivates the policy' do
      post deactivate_raaf_rails_evaluation_policy_path(policy)

      expect(policy.reload.active).to be false
    end
  end
end
```

#### AnalyticsController

```ruby
# spec/requests/raaf/rails/evaluation/analytics_spec.rb
RSpec.describe 'RAAF::Rails::Evaluation::Analytics', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in(user)

    # Create test data
    create(:evaluation_metric,
      agent_name: 'TestAgent',
      period_type: 'daily',
      period_start: 1.day.ago.beginning_of_day,
      total_evaluations: 100,
      passed_count: 85,
      failed_count: 15
    )
  end

  describe 'GET /raaf/rails/evaluation/analytics' do
    it 'returns success' do
      get raaf_rails_evaluation_analytics_path
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /raaf/rails/evaluation/analytics/pass_rate_data' do
    it 'returns JSON data for chart' do
      get pass_rate_data_raaf_rails_evaluation_analytics_path,
          params: { agent: 'TestAgent', from: 7.days.ago.to_date, to: Date.current },
          headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include('application/json')

      data = JSON.parse(response.body)
      expect(data).to be_an(Array)
      expect(data.first).to include('date', 'pass_rate', 'total', 'passed', 'failed')
    end
  end

  describe 'GET /raaf/rails/evaluation/analytics/model_comparison_data' do
    before do
      create(:evaluation_result, agent_name: 'TestAgent', model: 'gpt-4', status: 'passed')
      create(:evaluation_result, agent_name: 'TestAgent', model: 'claude-3', status: 'failed')
    end

    it 'returns model comparison data' do
      get model_comparison_data_raaf_rails_evaluation_analytics_path,
          params: { agent: 'TestAgent' },
          headers: { 'Accept' => 'application/json' }

      data = JSON.parse(response.body)
      expect(data.map { |d| d['model'] }).to include('gpt-4', 'claude-3')
    end
  end
end
```

### Feature Tests

#### Policy Management Workflow

```ruby
# spec/features/evaluation_policy_management_spec.rb
RSpec.describe 'Evaluation Policy Management', type: :feature, js: true do
  let(:user) { create(:user, :admin) }

  before { sign_in(user) }

  scenario 'user creates a new evaluation policy' do
    visit raaf_rails_evaluation_policies_path

    click_link 'New Policy'

    fill_in 'Name', with: 'Production Quality Check'
    fill_in 'Agent name', with: 'DmuDiscovery'
    select 'production', from: 'Environment'
    fill_in 'Sample rate', with: '10'
    fill_in 'Max daily evaluations', with: '1000'

    # Select evaluators from the list of registered evaluators
    within '#evaluators-selection' do
      # Available evaluators are shown with checkboxes/multi-select
      check 'token_limit'
      check 'company_quality'
    end

    # Configure selected evaluator (optional)
    within '#evaluator-config-token_limit' do
      fill_in 'Max tokens', with: '4000'
    end

    click_button 'Create Policy'

    expect(page).to have_content('Policy created successfully')
    expect(page).to have_content('Production Quality Check')
  end

  scenario 'user sees available evaluators from the registry' do
    # These evaluators are defined in the end-user app (e.g., ProspectsRadar)
    # and registered with RAAF::Eval::DSL::EvaluatorRegistry

    visit new_raaf_rails_evaluation_policy_path

    # The form should display available evaluators
    within '#evaluators-selection' do
      expect(page).to have_content('Available Evaluators')
      # Built-in evaluators
      expect(page).to have_content('token_limit')
      # Custom evaluators from end-user app should also appear
      # (registered during Rails boot)
    end
  end

  scenario 'user activates and deactivates a policy' do
    policy = create(:evaluation_policy, name: 'Test Policy', active: false)

    visit raaf_rails_evaluation_policies_path

    within("#policy-#{policy.id}") do
      click_button 'Activate'
    end

    expect(page).to have_content('Policy activated')
    expect(policy.reload.active).to be true

    within("#policy-#{policy.id}") do
      click_button 'Pause'
    end

    expect(page).to have_content('Policy deactivated')
    expect(policy.reload.active).to be false
  end
end
```

#### Analytics Dashboard

```ruby
# spec/features/evaluation_analytics_spec.rb
RSpec.describe 'Evaluation Analytics Dashboard', type: :feature, js: true do
  let(:user) { create(:user) }

  before do
    sign_in(user)

    # Create test metrics
    30.times do |i|
      create(:evaluation_metric,
        agent_name: 'TestAgent',
        period_type: 'daily',
        period_start: i.days.ago.beginning_of_day,
        total_evaluations: rand(80..120),
        passed_count: rand(70..100),
        failed_count: rand(5..20)
      )
    end
  end

  scenario 'user views pass rate chart' do
    visit raaf_rails_evaluation_analytics_path

    select 'TestAgent', from: 'Agent'
    click_button 'Apply Filters'

    # D3 chart should be rendered
    expect(page).to have_css('#pass-rate-chart svg')

    # Chart should have data points
    expect(page).to have_css('#pass-rate-chart path') # Line
  end

  scenario 'user filters by date range' do
    visit raaf_rails_evaluation_analytics_path

    fill_in 'From', with: 7.days.ago.to_date.to_s
    fill_in 'To', with: Date.current.to_s
    click_button 'Apply Filters'

    expect(page).to have_current_path(include('from='))
  end

  scenario 'user views model comparison' do
    create(:evaluation_result, agent_name: 'TestAgent', model: 'gpt-4', status: 'passed')
    create(:evaluation_result, agent_name: 'TestAgent', model: 'claude-3', status: 'passed')

    visit raaf_rails_evaluation_analytics_path

    expect(page).to have_css('table')
    expect(page).to have_content('gpt-4')
    expect(page).to have_content('claude-3')
  end
end
```

## JavaScript Tests

### D3 Chart Controller

```javascript
// spec/javascript/controllers/pass_rate_chart_controller_spec.js
import { Application } from "@hotwired/stimulus"
import PassRateChartController from "controllers/pass_rate_chart_controller"

describe("PassRateChartController", () => {
  let application

  beforeEach(() => {
    document.body.innerHTML = `
      <div id="chart"
           data-controller="pass-rate-chart"
           data-pass-rate-chart-data-value='[
             {"date": "2025-11-01T00:00:00Z", "pass_rate": 85.5, "total": 100},
             {"date": "2025-11-02T00:00:00Z", "pass_rate": 88.2, "total": 110}
           ]'>
      </div>
    `

    application = Application.start()
    application.register("pass-rate-chart", PassRateChartController)
  })

  afterEach(() => {
    application.stop()
  })

  it("renders SVG element", () => {
    const svg = document.querySelector("#chart svg")
    expect(svg).not.toBeNull()
  })

  it("renders line path", () => {
    const path = document.querySelector("#chart path")
    expect(path).not.toBeNull()
    expect(path.getAttribute("d")).toBeTruthy()
  })

  it("renders axes", () => {
    const xAxis = document.querySelector("#chart .x-axis")
    const yAxis = document.querySelector("#chart .y-axis")
    expect(xAxis).not.toBeNull()
    expect(yAxis).not.toBeNull()
  })

  it("renders target line at 85%", () => {
    const targetLine = document.querySelector("#chart .target-line")
    expect(targetLine).not.toBeNull()
  })
})
```

## Mocking Requirements

### External Services

| Service | Mock Strategy |
|---------|---------------|
| LLM API (for LLM judges) | VCR cassettes or WebMock stubs |
| Solid Queue | Use `perform_enqueued_jobs` in tests |

### Time-Based Tests

```ruby
# Use Timecop or Rails time helpers
RSpec.describe 'Daily counter reset' do
  it 'resets counter at midnight' do
    policy = create(:evaluation_policy, today_evaluation_count: 100)

    travel_to(Date.tomorrow) do
      RAAF::Eval::Continuous::ResetDailyCountersJob.new.perform
      expect(policy.reload.today_evaluation_count).to eq(0)
    end
  end
end
```

### Database Transactions

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  config.use_transactional_fixtures = true

  # For feature specs with JS
  config.before(:each, type: :feature, js: true) do
    self.use_transactional_tests = false
    DatabaseCleaner.strategy = :truncation
  end
end
```

## Factory Definitions

```ruby
# spec/factories/evaluation_policies.rb
FactoryBot.define do
  factory :evaluation_policy, class: 'RAAF::Eval::EvaluationPolicy' do
    sequence(:name) { |n| "Policy #{n}" }
    agent_name { 'TestAgent' }
    environment { 'all' }
    model_pattern { 'all' }
    sampling_mode { 'percentage' }
    sample_rate { 100 }
    priority { 50 }
    retention_days { 90 }
    active { true }
    evaluators { [] }

    trait :with_evaluators do
      evaluators do
        [
          { 'type' => 'rule_based', 'name' => 'token_limit', 'config' => { 'max_tokens' => 4000 } }
        ]
      end
    end

    trait :inactive do
      active { false }
    end
  end

  factory :evaluation_queue, class: 'RAAF::Eval::EvaluationQueue' do
    span_id { "span_#{SecureRandom.hex(12)}" }
    trace_id { "trace_#{SecureRandom.hex(16)}" }
    status { 'pending' }
    priority { 50 }
    association :evaluation_policy
  end

  factory :evaluation_result, class: 'RAAF::Eval::EvaluationResult' do
    span_id { "span_#{SecureRandom.hex(12)}" }
    trace_id { "trace_#{SecureRandom.hex(16)}" }
    evaluation_type { 'automated' }
    evaluator_name { 'token_limit' }
    evaluator_type { 'rule_based' }
    agent_name { 'TestAgent' }
    environment { 'test' }
    status { 'passed' }
    score { 0.85 }

    trait :failed do
      status { 'failed' }
      score { 0.3 }
    end
  end

  factory :evaluation_metric, class: 'RAAF::Eval::EvaluationMetric' do
    agent_name { 'TestAgent' }
    period_type { 'daily' }
    period_start { Date.current.beginning_of_day }
    total_evaluations { 100 }
    passed_count { 85 }
    failed_count { 15 }
    avg_score { 0.85 }
  end
end
```

## Test Coverage Requirements

| Component | Minimum Coverage |
|-----------|------------------|
| Models | 95% |
| Controllers | 90% |
| Jobs | 90% |
| Services | 95% |
| Feature specs | Key workflows |

Run coverage with:
```bash
COVERAGE=true bundle exec rspec
```
