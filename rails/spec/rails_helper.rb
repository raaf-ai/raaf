# frozen_string_literal: true

require_relative "spec_helper"

# Load Capybara for feature specs
begin
  require "capybara/rspec"
  require "capybara/rails" if defined?(::Rails)
rescue LoadError
  # Capybara not available in minimal test environments
end

# Create support directory helpers
Dir[File.join(__dir__, "support/**/*.rb")].sort.each { |f| require f }

# Configure RSpec for Rails-style testing
RSpec.configure do |config|
  # Infer spec type from file location
  config.infer_spec_type_from_file_location!

  # Include URL helpers for request specs
  config.include TestHelpers

  # Configuration for feature specs
  config.before(:each, type: :feature) do
    # Reset any test state
  end
end

# Mock route helpers for request specs
module RAAF
  module Rails
    module RouteHelpers
      # Continuous evaluation routes
      def raaf_rails_continuous_policies_path(options = {})
        "/raaf/rails/continuous/policies"
      end

      def raaf_rails_continuous_policy_path(policy, options = {})
        id = policy.respond_to?(:id) ? policy.id : policy
        "/raaf/rails/continuous/policies/#{id}"
      end

      def new_raaf_rails_continuous_policy_path(options = {})
        "/raaf/rails/continuous/policies/new"
      end

      def edit_raaf_rails_continuous_policy_path(policy, options = {})
        id = policy.respond_to?(:id) ? policy.id : policy
        "/raaf/rails/continuous/policies/#{id}/edit"
      end

      def activate_raaf_rails_continuous_policy_path(policy, options = {})
        id = policy.respond_to?(:id) ? policy.id : policy
        "/raaf/rails/continuous/policies/#{id}/activate"
      end

      def deactivate_raaf_rails_continuous_policy_path(policy, options = {})
        id = policy.respond_to?(:id) ? policy.id : policy
        "/raaf/rails/continuous/policies/#{id}/deactivate"
      end

      def duplicate_raaf_rails_continuous_policy_path(policy, options = {})
        id = policy.respond_to?(:id) ? policy.id : policy
        "/raaf/rails/continuous/policies/#{id}/duplicate"
      end

      # Queue routes
      def raaf_rails_continuous_queue_index_path(options = {})
        "/raaf/rails/continuous/queue"
      end

      def raaf_rails_continuous_queue_path(item, options = {})
        id = item.respond_to?(:id) ? item.id : item
        "/raaf/rails/continuous/queue/#{id}"
      end

      def retry_raaf_rails_continuous_queue_path(item, options = {})
        id = item.respond_to?(:id) ? item.id : item
        "/raaf/rails/continuous/queue/#{id}/retry"
      end

      def cancel_raaf_rails_continuous_queue_path(item, options = {})
        id = item.respond_to?(:id) ? item.id : item
        "/raaf/rails/continuous/queue/#{id}/cancel"
      end

      def retry_failed_raaf_rails_continuous_queue_index_path(options = {})
        "/raaf/rails/continuous/queue/retry_failed"
      end

      def clear_completed_raaf_rails_continuous_queue_index_path(options = {})
        "/raaf/rails/continuous/queue/clear_completed"
      end

      # Results routes
      def raaf_rails_continuous_results_path(options = {})
        "/raaf/rails/continuous/results"
      end

      def raaf_rails_continuous_result_path(result, options = {})
        id = result.respond_to?(:id) ? result.id : result
        "/raaf/rails/continuous/results/#{id}"
      end

      # Analytics routes
      def raaf_rails_continuous_analytics_path(options = {})
        "/raaf/rails/continuous/analytics"
      end

      def pass_rate_data_raaf_rails_continuous_analytics_path(options = {})
        "/raaf/rails/continuous/analytics/pass_rate_data"
      end

      def score_distribution_data_raaf_rails_continuous_analytics_path(options = {})
        "/raaf/rails/continuous/analytics/score_distribution_data"
      end

      def model_comparison_data_raaf_rails_continuous_analytics_path(options = {})
        "/raaf/rails/continuous/analytics/model_comparison_data"
      end

      def failure_analysis_data_raaf_rails_continuous_analytics_path(options = {})
        "/raaf/rails/continuous/analytics/failure_analysis_data"
      end

      # Evaluators routes
      def raaf_rails_continuous_evaluators_path(options = {})
        "/raaf/rails/continuous/evaluators"
      end

      def raaf_rails_continuous_evaluator_path(evaluator, options = {})
        id = evaluator.respond_to?(:id) ? evaluator.id : evaluator
        "/raaf/rails/continuous/evaluators/#{id}"
      end
    end
  end
end

# Include route helpers
RSpec.configure do |config|
  config.include RAAF::Rails::RouteHelpers
end

# Model aliases for specs (using mock models from spec_helper)
EvaluationPolicy = Class.new(ActiveRecord::Base) do
  class << self
    attr_accessor :records

    def table_name
      "raaf_evaluation_policies"
    end

    def create!(attrs = {})
      @records ||= []
      record = new(attrs)
      record.instance_variable_set(:@id, @records.length + 1)
      record.instance_variable_set(:@created_at, Time.current)
      record.instance_variable_set(:@updated_at, Time.current)
      @records << record
      record
    end

    def find(id)
      @records&.find { |r| r.id == id.to_i }
    end

    def last
      @records&.last
    end

    def all
      @records || []
    end

    def count
      @records&.length || 0
    end
  end

  attr_accessor :name, :description, :agent_name, :environment, :model_pattern, :version_pattern,
                :sampling_mode, :sample_rate, :sample_every_n, :max_daily_evaluations,
                :today_evaluation_count, :priority, :queue_name, :max_concurrent_evaluations,
                :max_retries, :retention_days, :retention_count, :evaluators, :metadata, :active

  def initialize(attrs = {})
    attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
    @active = true if @active.nil?
    @evaluators ||= []
  end

  def id
    @id
  end

  def created_at
    @created_at
  end

  def updated_at
    @updated_at
  end

  def reload
    self
  end

  def update!(attrs)
    attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
    @updated_at = Time.current
    true
  end

  def update(attrs)
    update!(attrs)
  rescue StandardError
    false
  end

  def save!
    @id ||= (self.class.records&.length || 0) + 1
    @created_at ||= Time.current
    @updated_at = Time.current
    self.class.records ||= []
    self.class.records << self unless self.class.records.include?(self)
    true
  end

  def save
    save!
  rescue StandardError
    false
  end

  def destroy
    self.class.records&.delete(self)
    true
  end

  def dup
    self.class.new(
      name: name,
      description: description,
      agent_name: agent_name,
      environment: environment,
      model_pattern: model_pattern,
      version_pattern: version_pattern,
      sampling_mode: sampling_mode,
      sample_rate: sample_rate,
      sample_every_n: sample_every_n,
      max_daily_evaluations: max_daily_evaluations,
      priority: priority,
      queue_name: queue_name,
      max_concurrent_evaluations: max_concurrent_evaluations,
      max_retries: max_retries,
      retention_days: retention_days,
      retention_count: retention_count,
      evaluators: evaluators&.dup,
      metadata: metadata&.dup,
      active: active
    )
  end

  def evaluation_results
    EvaluationResult.where(evaluation_policy_id: id)
  end

  def today_stats
    { total: 10, passed: 8, failed: 2 }
  end
end unless defined?(EvaluationPolicy)

EvaluationQueue = Class.new(ActiveRecord::Base) do
  class << self
    attr_accessor :records

    def table_name
      "raaf_evaluation_queue"
    end

    def create!(attrs = {})
      @records ||= []
      record = new(attrs)
      record.instance_variable_set(:@id, @records.length + 1)
      record.instance_variable_set(:@created_at, Time.current)
      record.instance_variable_set(:@updated_at, Time.current)
      @records << record
      record
    end

    def find(id)
      @records&.find { |r| r.id == id.to_i }
    end

    def all
      @records || []
    end

    def count
      @records&.length || 0
    end
  end

  attr_accessor :evaluation_policy, :evaluation_policy_id, :span_id, :trace_id, :status,
                :priority, :attempts, :max_attempts, :scheduled_at, :started_at,
                :completed_at, :next_retry_at, :error_message, :error_class, :metadata

  def initialize(attrs = {})
    attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
    @status ||= 'pending'
    @attempts ||= 0
    @max_attempts ||= 3
  end

  def id
    @id
  end

  def created_at
    @created_at
  end

  def updated_at
    @updated_at
  end

  def reload
    self
  end

  def update!(attrs)
    attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
    @updated_at = Time.current
    true
  end
end unless defined?(EvaluationQueue)

EvaluationResult = Class.new(ActiveRecord::Base) do
  class << self
    attr_accessor :records

    def table_name
      "raaf_evaluation_results"
    end

    def create!(attrs = {})
      @records ||= []
      record = new(attrs)
      record.instance_variable_set(:@id, @records.length + 1)
      record.instance_variable_set(:@created_at, Time.current)
      @records << record
      record
    end

    def find(id)
      @records&.find { |r| r.id == id.to_i }
    end

    def all
      @records || []
    end

    def count
      @records&.length || 0
    end

    def average(_field)
      0.85
    end

    def distinct
      self
    end

    def pluck(field)
      @records&.map { |r| r.send(field) }&.compact&.uniq || []
    end

    def first
      @records&.first
    end
  end

  attr_accessor :evaluation_queue, :evaluation_policy, :evaluation_policy_id, :span_id, :trace_id,
                :agent_name, :model, :provider, :environment, :evaluator_name, :evaluator_type,
                :evaluator_version, :status, :score, :scores, :metrics, :reasoning, :details,
                :evaluation_duration_ms

  def initialize(attrs = {})
    attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
    @status ||= 'passed'
  end

  def id
    @id
  end

  def created_at
    @created_at
  end
end unless defined?(EvaluationResult)

EvaluationMetric = Class.new(ActiveRecord::Base) do
  class << self
    attr_accessor :records

    def table_name
      "raaf_evaluation_metrics"
    end

    def create!(attrs = {})
      @records ||= []
      record = new(attrs)
      record.instance_variable_set(:@id, @records.length + 1)
      @records << record
      record
    end

    def find(id)
      @records&.find { |r| r.id == id.to_i }
    end

    def all
      @records || []
    end
  end

  attr_accessor :agent_name, :environment, :model, :evaluator_name, :period_type,
                :period_start, :period_end, :total_evaluations, :passed_count, :failed_count,
                :warning_count, :error_count, :avg_score, :min_score, :max_score,
                :stddev_score, :p50_score, :p90_score, :p95_score, :score_distribution,
                :avg_evaluation_duration_ms, :total_evaluation_cost, :additional_metrics

  def initialize(attrs = {})
    attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
  end

  def id
    @id
  end
end unless defined?(EvaluationMetric)

# Clear records between tests
RSpec.configure do |config|
  config.before(:each) do
    EvaluationPolicy.records = []
    EvaluationQueue.records = []
    EvaluationResult.records = []
    EvaluationMetric.records = []
  end
end
