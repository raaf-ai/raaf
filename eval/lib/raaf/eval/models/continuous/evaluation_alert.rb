# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # EvaluationAlert represents an alert triggered by the continuous evaluation system.
      # Alerts are generated when quality thresholds are breached, error rates spike,
      # or system health degrades.
      #
      # @example Create a quality degradation alert
      #   EvaluationAlert.trigger!(
      #     alert_type: 'quality_degradation',
      #     severity: 'warning',
      #     agent_name: 'CustomerSupportAgent',
      #     title: 'Quality score dropped below threshold',
      #     message: 'Average score dropped from 0.85 to 0.72 in the last hour',
      #     threshold_value: 0.80,
      #     actual_value: 0.72
      #   )
      #
      # @example Find active critical alerts
      #   EvaluationAlert.active.critical.recent
      #
      class EvaluationAlert < ActiveRecord::Base
        self.table_name = "raaf_evaluation_alerts"

        # Alert types
        ALERT_TYPES = %w[
          quality_degradation
          failure_spike
          queue_backlog
          evaluator_error
          policy_threshold
          cost_exceeded
        ].freeze

        # Severity levels
        SEVERITIES = %w[info warning critical].freeze

        # Status values
        STATUSES = %w[active acknowledged resolved suppressed].freeze

        # Associations
        belongs_to :evaluation_policy,
                   class_name: "RAAF::Eval::Models::EvaluationPolicy",
                   optional: true

        # Validations
        validates :alert_type, presence: true, inclusion: { in: ALERT_TYPES }
        validates :severity, presence: true, inclusion: { in: SEVERITIES }
        validates :status, presence: true, inclusion: { in: STATUSES }
        validates :title, presence: true
        validates :message, presence: true
        validates :triggered_at, presence: true

        # Callbacks
        before_validation :set_defaults
        before_create :generate_fingerprint

        # Scopes - Status
        scope :active, -> { where(status: "active") }
        scope :acknowledged, -> { where(status: "acknowledged") }
        scope :resolved, -> { where(status: "resolved") }
        scope :suppressed, -> { where(status: "suppressed") }
        scope :unresolved, -> { where(status: %w[active acknowledged]) }

        # Scopes - Severity
        scope :info, -> { where(severity: "info") }
        scope :warning, -> { where(severity: "warning") }
        scope :critical, -> { where(severity: "critical") }
        scope :actionable, -> { where(severity: %w[warning critical]) }

        # Scopes - Type
        scope :quality_alerts, -> { where(alert_type: "quality_degradation") }
        scope :failure_alerts, -> { where(alert_type: "failure_spike") }
        scope :system_alerts, -> { where(alert_type: %w[queue_backlog evaluator_error cost_exceeded]) }

        # Scopes - Time
        scope :recent, -> { order(triggered_at: :desc) }
        scope :last_24h, -> { where("triggered_at > ?", 24.hours.ago) }
        scope :last_7d, -> { where("triggered_at > ?", 7.days.ago) }

        # Scopes - Targeting
        scope :for_agent, ->(name) { where(agent_name: name) }
        scope :for_evaluator, ->(name) { where(evaluator_name: name) }
        scope :for_policy, ->(policy_id) { where(evaluation_policy_id: policy_id) }

        ##
        # Trigger a new alert or increment occurrence count if duplicate
        # @param attributes [Hash] Alert attributes
        # @return [EvaluationAlert] Created or updated alert
        def self.trigger!(attributes)
          alert = new(attributes)
          alert.generate_fingerprint

          # Check for existing active alert with same fingerprint
          existing = active.find_by(fingerprint: alert.fingerprint)

          if existing
            existing.increment_occurrence!
            existing
          else
            alert.save!
            alert
          end
        end

        ##
        # Acknowledge this alert
        # @param by [String] User who acknowledged
        def acknowledge!(by: nil)
          update!(
            status: "acknowledged",
            acknowledged_at: Time.current,
            acknowledged_by: by
          )
        end

        ##
        # Resolve this alert
        # @param by [String] User who resolved
        # @param notes [String] Resolution notes
        def resolve!(by: nil, notes: nil)
          update!(
            status: "resolved",
            resolved_at: Time.current,
            resolved_by: by,
            resolution_notes: notes
          )
        end

        ##
        # Suppress this alert (silence without resolving)
        def suppress!
          update!(status: "suppressed")
        end

        ##
        # Reactivate a resolved or suppressed alert
        def reactivate!
          update!(
            status: "active",
            acknowledged_at: nil,
            acknowledged_by: nil,
            resolved_at: nil,
            resolved_by: nil,
            resolution_notes: nil
          )
        end

        ##
        # Increment occurrence count for duplicate alerts
        def increment_occurrence!
          increment!(:occurrence_count)
        end

        ##
        # Check if alert is actionable (warning or critical)
        # @return [Boolean]
        def actionable?
          %w[warning critical].include?(severity)
        end

        ##
        # Check if alert is still active
        # @return [Boolean]
        def active?
          status == "active"
        end

        ##
        # Check if alert has been acknowledged
        # @return [Boolean]
        def acknowledged?
          status == "acknowledged"
        end

        ##
        # Check if alert is resolved
        # @return [Boolean]
        def resolved?
          status == "resolved"
        end

        ##
        # Duration since alert was triggered
        # @return [ActiveSupport::Duration, nil]
        def duration
          return nil unless triggered_at
          end_time = resolved_at || Time.current
          end_time - triggered_at
        end

        ##
        # Format duration as human readable string
        # @return [String]
        def duration_text
          return "Unknown" unless duration
          ActiveSupport::Duration.build(duration).inspect
        end

        ##
        # Generate a summary for display
        # @return [Hash]
        def summary
          {
            id: id,
            type: alert_type,
            severity: severity,
            status: status,
            title: title,
            agent: agent_name,
            triggered_at: triggered_at,
            occurrences: occurrence_count,
            duration: duration_text
          }
        end

        ##
        # Generate fingerprint for deduplication
        def generate_fingerprint
          components = [
            alert_type,
            agent_name,
            environment,
            model,
            evaluator_name,
            metric_name
          ].compact.join("-")

          self.fingerprint = Digest::SHA256.hexdigest(components)[0, 32]
        end

        private

        def set_defaults
          self.triggered_at ||= Time.current
          self.status ||= "active"
          self.severity ||= "warning"
          self.occurrence_count ||= 1
        end
      end
    end
  end
end
