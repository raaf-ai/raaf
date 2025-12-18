# frozen_string_literal: true

module RAAF
  module Tracing
    # Lazy loading approach for ActiveRecord models
    def self.const_missing(name)
      if (name == :TraceRecord || name == :SpanRecord) && defined?(::ApplicationRecord)
        case name
        when :TraceRecord
          const_set(:TraceRecord, Class.new(::ApplicationRecord) do
            self.table_name = "raaf_tracing_traces"
            
            # Disable JSON symbolization to prevent method aliasing conflicts
            disable_json_symbolization! if respond_to?(:disable_json_symbolization!)
            
            has_many :spans,
              class_name: "RAAF::Tracing::SpanRecord",
              foreign_key: :trace_id,
              primary_key: :trace_id,
              dependent: :destroy
            
            # Cleanup method for old traces
            def self.cleanup_old_traces(older_than: 30.days)
              where("started_at < ?", Time.current - older_than).delete_all
            end
          end)
        when :SpanRecord
          const_set(:SpanRecord, Class.new(::ApplicationRecord) do
            self.table_name = "raaf_tracing_spans"

            # Disable JSON symbolization to prevent method aliasing conflicts
            disable_json_symbolization! if respond_to?(:disable_json_symbolization!)

            belongs_to :trace,
              class_name: "RAAF::Tracing::TraceRecord",
              foreign_key: :trace_id,
              primary_key: :trace_id

            belongs_to :parent,
              class_name: "RAAF::Tracing::SpanRecord",
              foreign_key: :parent_id,
              primary_key: :span_id,
              optional: true

            has_many :children,
              class_name: "RAAF::Tracing::SpanRecord",
              foreign_key: :parent_id,
              primary_key: :span_id,
              dependent: :destroy

            # Continuous evaluation callback - enqueue evaluation jobs when spans are created
            after_commit :enqueue_continuous_evaluations, on: :create

            private

            # Enqueue continuous evaluation for newly created spans
            # This hook runs after the span is committed to the database
            def enqueue_continuous_evaluations
              # Return early if continuous evaluation is disabled
              return unless defined?(RAAF::Eval::Continuous)
              return unless RAAF::Eval::Continuous.enabled?
              return unless RAAF::Eval::Continuous.configuration.hook_enabled

              # Find matching policies and enqueue evaluation jobs
              begin
                matcher = RAAF::Eval::Continuous::PolicyMatcher.new(self)
                policies = matcher.policies_to_evaluate

                policies.each do |policy|
                  RAAF::Rails::Continuous::EvaluationJob.perform_later(
                    span_id: span_id,
                    policy_id: policy.id
                  )
                end
              rescue StandardError => e
                # Log errors but don't raise - we don't want to break span creation
                ::Rails.logger.warn "[Ruby AI Agents Factory Continuous Eval] Failed to enqueue evaluations: #{e.message}"
              end
            end
          end)
        end
      else
        super
      end
    end
  end
end