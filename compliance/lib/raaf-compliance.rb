# frozen_string_literal: true

require_relative "raaf/compliance/version"
require_relative "raaf/compliance/audit_trail"
require_relative "raaf/compliance/data_retention"
require_relative "raaf/compliance/gdpr_compliance"
require_relative "raaf/compliance/hipaa_compliance"
require_relative "raaf/compliance/soc2_compliance"
require_relative "raaf/compliance/compliance_checker"
require_relative "raaf/compliance/policy_manager"
require_relative "raaf/compliance/reporting"
require_relative "raaf/compliance/data_classification"
require_relative "raaf/compliance/consent_manager"
require_relative "raaf/compliance/breach_detection"
require_relative "raaf/compliance/export_control"

module RAAF
  ##
  # Regulatory compliance and audit capabilities for Ruby AI Agents Factory
  #
  # The Compliance module provides comprehensive regulatory compliance framework
  # including GDPR, HIPAA, SOC2 compliance, audit trails, data retention policies,
  # and regulatory reporting. It enables organizations to maintain compliance
  # with various regulatory requirements while using AI agents.
  #
  # Key features:
  # - **Audit Trails** - Comprehensive logging and tracking of all activities
  # - **Data Retention** - Automated data lifecycle management
  # - **GDPR Compliance** - European data protection regulation compliance
  # - **HIPAA Compliance** - Healthcare data protection compliance
  # - **SOC2 Compliance** - Security and availability controls
  # - **Policy Management** - Centralized policy configuration and enforcement
  # - **Compliance Reporting** - Automated compliance reports and dashboards
  # - **Data Classification** - Automatic data sensitivity classification
  # - **Consent Management** - User consent tracking and management
  # - **Breach Detection** - Real-time compliance violation detection
  # - **Export Control** - Data export restrictions and controls
  #
  # @example Basic compliance setup
  #   require 'raaf-compliance'
  #   
  #   # Configure compliance framework
  #   RAAF::Compliance.configure do |config|
  #     config.enable_audit_trail = true
  #     config.data_retention_days = 2555 # 7 years
  #     config.gdpr_enabled = true
  #     config.hipaa_enabled = true
  #     config.soc2_enabled = true
  #   end
  #   
  #   # Create compliance-aware agent
  #   agent = RAAF::Agent.new(
  #     name: "ComplianceAgent",
  #     instructions: "You are a compliant assistant",
  #     compliance: true
  #   )
  #
  # @example Audit trail usage
  #   require 'raaf-compliance'
  #   
  #   # Enable audit trail
  #   audit_trail = RAAF::Compliance::AuditTrail.new
  #   
  #   # Log agent activities
  #   audit_trail.log_agent_activity(
  #     agent_id: "agent_123",
  #     action: "message_processed",
  #     user_id: "user_456",
  #     data: { message: "Hello", response: "Hi there!" },
  #     compliance_tags: [:gdpr, :hipaa]
  #   )
  #   
  #   # Query audit logs
  #   logs = audit_trail.query(
  #     start_date: 30.days.ago,
  #     end_date: Time.current,
  #     user_id: "user_456"
  #   )
  #
  # @example Data retention management
  #   require 'raaf-compliance'
  #   
  #   # Configure data retention
  #   retention = RAAF::Compliance::DataRetention.new
  #   
  #   # Set retention policies
  #   retention.add_policy(
  #     data_type: :conversation,
  #     retention_period: 2555.days,
  #     disposal_method: :secure_delete
  #   )
  #   
  #   # Execute retention policies
  #   retention.execute_policies
  #
  # @example GDPR compliance
  #   require 'raaf-compliance'
  #   
  #   # Enable GDPR compliance
  #   gdpr = RAAF::Compliance::GDPRCompliance.new
  #   
  #   # Handle right to be forgotten
  #   gdpr.handle_erasure_request(user_id: "user_123")
  #   
  #   # Handle data portability request
  #   user_data = gdpr.export_user_data(user_id: "user_123")
  #   
  #   # Check processing lawfulness
  #   lawful = gdpr.verify_processing_lawfulness(
  #     user_id: "user_123",
  #     processing_purpose: "customer_support"
  #   )
  #
  # @example Compliance reporting
  #   require 'raaf-compliance'
  #   
  #   # Generate compliance report
  #   reporting = RAAF::Compliance::Reporting.new
  #   
  #   # Generate GDPR compliance report
  #   gdpr_report = reporting.generate_gdpr_report(
  #     start_date: 1.month.ago,
  #     end_date: Time.current
  #   )
  #   
  #   # Generate SOC2 compliance report
  #   soc2_report = reporting.generate_soc2_report(
  #     period: "2024-Q1"
  #   )
  #
  # @since 1.0.0
  module Compliance
    # Default configuration
    DEFAULT_CONFIG = {
      # Audit trail settings
      audit_trail: {
        enabled: true,
        storage_backend: :database,
        retention_days: 2555,  # 7 years
        encryption_enabled: true,
        real_time_monitoring: true
      },
      
      # Data retention settings
      data_retention: {
        enabled: true,
        default_retention_days: 2555,  # 7 years
        automatic_cleanup: true,
        secure_deletion: true,
        archive_before_deletion: true
      },
      
      # GDPR settings
      gdpr: {
        enabled: false,
        consent_required: true,
        data_minimization: true,
        purpose_limitation: true,
        storage_limitation: true,
        breach_notification_hours: 72
      },
      
      # HIPAA settings
      hipaa: {
        enabled: false,
        phi_encryption: true,
        access_controls: true,
        audit_controls: true,
        integrity_controls: true,
        transmission_security: true
      },
      
      # SOC2 settings
      soc2: {
        enabled: false,
        security_controls: true,
        availability_controls: true,
        processing_integrity: true,
        confidentiality_controls: true,
        privacy_controls: true
      },
      
      # Policy management
      policy_management: {
        enabled: true,
        policy_version_control: true,
        policy_approval_workflow: true,
        policy_training_tracking: true
      },
      
      # Reporting settings
      reporting: {
        enabled: true,
        automated_reports: true,
        report_formats: [:pdf, :csv, :json],
        report_retention_days: 2555
      },
      
      # Data classification
      data_classification: {
        enabled: true,
        automatic_classification: true,
        sensitivity_levels: [:public, :internal, :confidential, :restricted],
        classification_algorithms: [:keyword, :ml, :regex]
      },
      
      # Consent management
      consent_management: {
        enabled: true,
        consent_versioning: true,
        consent_withdrawal: true,
        consent_renewal: true,
        consent_audit_trail: true
      },
      
      # Breach detection
      breach_detection: {
        enabled: true,
        real_time_monitoring: true,
        anomaly_detection: true,
        automated_response: true,
        notification_enabled: true
      },
      
      # Export control
      export_control: {
        enabled: true,
        geographical_restrictions: true,
        data_localization: true,
        transfer_mechanisms: [:adequacy, :bcr, :scc],
        export_approval_workflow: true
      }
    }.freeze

    class << self
      # @return [Hash] Current configuration
      attr_accessor :config

      ##
      # Configure compliance settings
      #
      # @param options [Hash] Configuration options
      # @yield [config] Configuration block
      #
      # @example Configure compliance
      #   RAAF::Compliance.configure do |config|
      #     config.gdpr.enabled = true
      #     config.hipaa.enabled = true
      #     config.audit_trail.retention_days = 3650
      #   end
      #
      def configure
        @config ||= deep_dup(DEFAULT_CONFIG)
        yield @config if block_given?
        @config
      end

      ##
      # Get current configuration
      #
      # @return [Hash] Current configuration
      def config
        @config ||= deep_dup(DEFAULT_CONFIG)
      end

      ##
      # Create audit trail
      #
      # @param options [Hash] Audit trail options
      # @return [AuditTrail] Audit trail instance
      def create_audit_trail(**options)
        AuditTrail.new(**config[:audit_trail].merge(options))
      end

      ##
      # Create data retention manager
      #
      # @param options [Hash] Data retention options
      # @return [DataRetention] Data retention instance
      def create_data_retention(**options)
        DataRetention.new(**config[:data_retention].merge(options))
      end

      ##
      # Create GDPR compliance manager
      #
      # @param options [Hash] GDPR options
      # @return [GDPRCompliance] GDPR compliance instance
      def create_gdpr_compliance(**options)
        GDPRCompliance.new(**config[:gdpr].merge(options))
      end

      ##
      # Create HIPAA compliance manager
      #
      # @param options [Hash] HIPAA options
      # @return [HIPAACompliance] HIPAA compliance instance
      def create_hipaa_compliance(**options)
        HIPAACompliance.new(**config[:hipaa].merge(options))
      end

      ##
      # Create SOC2 compliance manager
      #
      # @param options [Hash] SOC2 options
      # @return [SOC2Compliance] SOC2 compliance instance
      def create_soc2_compliance(**options)
        SOC2Compliance.new(**config[:soc2].merge(options))
      end

      ##
      # Create compliance checker
      #
      # @param options [Hash] Compliance checker options
      # @return [ComplianceChecker] Compliance checker instance
      def create_compliance_checker(**options)
        ComplianceChecker.new(**options)
      end

      ##
      # Create policy manager
      #
      # @param options [Hash] Policy manager options
      # @return [PolicyManager] Policy manager instance
      def create_policy_manager(**options)
        PolicyManager.new(**config[:policy_management].merge(options))
      end

      ##
      # Create reporting manager
      #
      # @param options [Hash] Reporting options
      # @return [Reporting] Reporting instance
      def create_reporting(**options)
        Reporting.new(**config[:reporting].merge(options))
      end

      ##
      # Create data classification manager
      #
      # @param options [Hash] Data classification options
      # @return [DataClassification] Data classification instance
      def create_data_classification(**options)
        DataClassification.new(**config[:data_classification].merge(options))
      end

      ##
      # Create consent manager
      #
      # @param options [Hash] Consent manager options
      # @return [ConsentManager] Consent manager instance
      def create_consent_manager(**options)
        ConsentManager.new(**config[:consent_management].merge(options))
      end

      ##
      # Create breach detection manager
      #
      # @param options [Hash] Breach detection options
      # @return [BreachDetection] Breach detection instance
      def create_breach_detection(**options)
        BreachDetection.new(**config[:breach_detection].merge(options))
      end

      ##
      # Create export control manager
      #
      # @param options [Hash] Export control options
      # @return [ExportControl] Export control instance
      def create_export_control(**options)
        ExportControl.new(**config[:export_control].merge(options))
      end

      ##
      # Check overall compliance status
      #
      # @return [Hash] Compliance status
      def compliance_status
        {
          audit_trail: config[:audit_trail][:enabled],
          data_retention: config[:data_retention][:enabled],
          gdpr: config[:gdpr][:enabled],
          hipaa: config[:hipaa][:enabled],
          soc2: config[:soc2][:enabled],
          policy_management: config[:policy_management][:enabled],
          reporting: config[:reporting][:enabled],
          data_classification: config[:data_classification][:enabled],
          consent_management: config[:consent_management][:enabled],
          breach_detection: config[:breach_detection][:enabled],
          export_control: config[:export_control][:enabled]
        }
      end

      ##
      # Validate compliance configuration
      #
      # @return [Array<String>] Array of validation errors
      def validate_configuration
        errors = []
        
        # Check required settings for enabled features
        if config[:gdpr][:enabled] && !config[:consent_management][:enabled]
          errors << "GDPR requires consent management to be enabled"
        end
        
        if config[:hipaa][:enabled] && !config[:audit_trail][:enabled]
          errors << "HIPAA requires audit trail to be enabled"
        end
        
        if config[:soc2][:enabled] && !config[:breach_detection][:enabled]
          errors << "SOC2 requires breach detection to be enabled"
        end
        
        if config[:data_retention][:enabled] && config[:data_retention][:default_retention_days] < 1
          errors << "Data retention period must be at least 1 day"
        end
        
        errors
      end

      ##
      # Enable compliance for an agent
      #
      # @param agent [Agent] Agent to enable compliance for
      # @param options [Hash] Compliance options
      # @return [Agent] Agent with compliance enabled
      def enable_compliance(agent, **options)
        # Add compliance middleware to agent
        agent.add_middleware(ComplianceMiddleware.new(**options))
        agent
      end

      ##
      # Generate compliance summary
      #
      # @return [Hash] Compliance summary
      def compliance_summary
        {
          configuration: compliance_status,
          validation_errors: validate_configuration,
          enabled_features: compliance_status.select { |_, enabled| enabled }.keys,
          total_policies: PolicyManager.new.policy_count,
          audit_trail_size: AuditTrail.new.record_count,
          last_compliance_check: Time.current.iso8601
        }
      end

      private

      def deep_dup(hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key] = value.is_a?(Hash) ? deep_dup(value) : value.dup
        end
      rescue TypeError
        hash
      end
    end
  end
end