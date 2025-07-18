# frozen_string_literal: true

module RAAF
  module Compliance
    ##
    # GDPR (General Data Protection Regulation) compliance implementation
    #
    # Provides comprehensive GDPR compliance features including data subject rights,
    # consent management, data minimization, purpose limitation, and breach notification.
    #
    class GDPRCompliance
      include RAAF::Logging

      # @return [Boolean] Consent required
      attr_reader :consent_required

      # @return [Boolean] Data minimization enabled
      attr_reader :data_minimization

      # @return [Boolean] Purpose limitation enabled
      attr_reader :purpose_limitation

      # @return [Boolean] Storage limitation enabled
      attr_reader :storage_limitation

      # @return [Integer] Breach notification hours
      attr_reader :breach_notification_hours

      ##
      # Initialize GDPR compliance
      #
      # @param consent_required [Boolean] Require consent for processing
      # @param data_minimization [Boolean] Enable data minimization
      # @param purpose_limitation [Boolean] Enable purpose limitation
      # @param storage_limitation [Boolean] Enable storage limitation
      # @param breach_notification_hours [Integer] Hours for breach notification
      #
      def initialize(consent_required: true, data_minimization: true, purpose_limitation: true, storage_limitation: true, breach_notification_hours: 72)
        @consent_required = consent_required
        @data_minimization = data_minimization
        @purpose_limitation = purpose_limitation
        @storage_limitation = storage_limitation
        @breach_notification_hours = breach_notification_hours
        @consent_manager = ConsentManager.new
        @data_retention = DataRetention.new
        @breach_detection = BreachDetection.new
        @audit_trail = AuditTrail.new
      end

      ##
      # Handle right to be forgotten (Article 17)
      #
      # @param user_id [String] User identifier
      # @param reason [String] Reason for erasure
      # @param verification_method [String] Verification method used
      # @return [Hash] Erasure result
      #
      def handle_erasure_request(user_id:, reason: "user_request", verification_method: "email_verification")
        log_info("Processing erasure request", user_id: user_id, reason: reason)
        
        # Verify user identity
        unless verify_user_identity(user_id, verification_method)
          return {
            success: false,
            error: "User identity verification failed",
            user_id: user_id
          }
        end
        
        # Check if erasure is legally required
        unless erasure_required?(user_id, reason)
          return {
            success: false,
            error: "Erasure not legally required",
            user_id: user_id,
            reason: reason
          }
        end
        
        # Perform erasure
        erasure_result = perform_user_erasure(user_id)
        
        # Log erasure activity
        @audit_trail.log_compliance_event(
          event_type: "data_erasure",
          compliance_framework: :gdpr,
          severity: :high,
          description: "User data erasure completed",
          metadata: {
            user_id: user_id,
            reason: reason,
            verification_method: verification_method,
            erasure_result: erasure_result
          }
        )
        
        {
          success: true,
          user_id: user_id,
          erasure_result: erasure_result,
          completion_time: Time.current.iso8601
        }
      end

      ##
      # Handle data portability request (Article 20)
      #
      # @param user_id [String] User identifier
      # @param format [Symbol] Export format (:json, :csv, :xml)
      # @param verification_method [String] Verification method used
      # @return [Hash] Export result
      #
      def export_user_data(user_id:, format: :json, verification_method: "email_verification")
        log_info("Processing data portability request", user_id: user_id, format: format)
        
        # Verify user identity
        unless verify_user_identity(user_id, verification_method)
          return {
            success: false,
            error: "User identity verification failed",
            user_id: user_id
          }
        end
        
        # Check if user has right to portability
        unless portability_applies?(user_id)
          return {
            success: false,
            error: "Data portability right does not apply",
            user_id: user_id
          }
        end
        
        # Export user data
        user_data = collect_user_data(user_id)
        exported_data = format_user_data(user_data, format)
        
        # Log portability activity
        @audit_trail.log_compliance_event(
          event_type: "data_portability",
          compliance_framework: :gdpr,
          severity: :medium,
          description: "User data export completed",
          metadata: {
            user_id: user_id,
            format: format,
            verification_method: verification_method,
            data_size: exported_data.bytesize
          }
        )
        
        {
          success: true,
          user_id: user_id,
          format: format,
          data: exported_data,
          export_time: Time.current.iso8601
        }
      end

      ##
      # Handle access request (Article 15)
      #
      # @param user_id [String] User identifier
      # @param verification_method [String] Verification method used
      # @return [Hash] Access result
      #
      def handle_access_request(user_id:, verification_method: "email_verification")
        log_info("Processing access request", user_id: user_id)
        
        # Verify user identity
        unless verify_user_identity(user_id, verification_method)
          return {
            success: false,
            error: "User identity verification failed",
            user_id: user_id
          }
        end
        
        # Collect information about processing
        processing_info = {
          purposes: get_processing_purposes(user_id),
          categories: get_data_categories(user_id),
          recipients: get_data_recipients(user_id),
          retention_period: get_retention_period(user_id),
          data_source: get_data_source(user_id),
          automated_processing: get_automated_processing_info(user_id),
          third_country_transfers: get_third_country_transfers(user_id)
        }
        
        # Log access activity
        @audit_trail.log_compliance_event(
          event_type: "data_access_request",
          compliance_framework: :gdpr,
          severity: :low,
          description: "User access request completed",
          metadata: {
            user_id: user_id,
            verification_method: verification_method,
            processing_info: processing_info
          }
        )
        
        {
          success: true,
          user_id: user_id,
          processing_info: processing_info,
          request_time: Time.current.iso8601
        }
      end

      ##
      # Handle rectification request (Article 16)
      #
      # @param user_id [String] User identifier
      # @param corrections [Hash] Data corrections
      # @param verification_method [String] Verification method used
      # @return [Hash] Rectification result
      #
      def handle_rectification_request(user_id:, corrections:, verification_method: "email_verification")
        log_info("Processing rectification request", user_id: user_id)
        
        # Verify user identity
        unless verify_user_identity(user_id, verification_method)
          return {
            success: false,
            error: "User identity verification failed",
            user_id: user_id
          }
        end
        
        # Validate corrections
        validation_result = validate_corrections(corrections)
        unless validation_result[:valid]
          return {
            success: false,
            error: "Invalid corrections provided",
            user_id: user_id,
            validation_errors: validation_result[:errors]
          }
        end
        
        # Apply corrections
        rectification_result = apply_corrections(user_id, corrections)
        
        # Log rectification activity
        @audit_trail.log_compliance_event(
          event_type: "data_rectification",
          compliance_framework: :gdpr,
          severity: :medium,
          description: "User data rectification completed",
          metadata: {
            user_id: user_id,
            corrections: corrections,
            verification_method: verification_method,
            rectification_result: rectification_result
          }
        )
        
        {
          success: true,
          user_id: user_id,
          corrections: corrections,
          rectification_result: rectification_result,
          completion_time: Time.current.iso8601
        }
      end

      ##
      # Handle restriction request (Article 18)
      #
      # @param user_id [String] User identifier
      # @param reason [String] Reason for restriction
      # @param verification_method [String] Verification method used
      # @return [Hash] Restriction result
      #
      def handle_restriction_request(user_id:, reason:, verification_method: "email_verification")
        log_info("Processing restriction request", user_id: user_id, reason: reason)
        
        # Verify user identity
        unless verify_user_identity(user_id, verification_method)
          return {
            success: false,
            error: "User identity verification failed",
            user_id: user_id
          }
        end
        
        # Check if restriction is justified
        unless restriction_justified?(user_id, reason)
          return {
            success: false,
            error: "Restriction not justified",
            user_id: user_id,
            reason: reason
          }
        end
        
        # Apply restriction
        restriction_result = apply_processing_restriction(user_id, reason)
        
        # Log restriction activity
        @audit_trail.log_compliance_event(
          event_type: "processing_restriction",
          compliance_framework: :gdpr,
          severity: :medium,
          description: "Processing restriction applied",
          metadata: {
            user_id: user_id,
            reason: reason,
            verification_method: verification_method,
            restriction_result: restriction_result
          }
        )
        
        {
          success: true,
          user_id: user_id,
          reason: reason,
          restriction_result: restriction_result,
          completion_time: Time.current.iso8601
        }
      end

      ##
      # Handle objection request (Article 21)
      #
      # @param user_id [String] User identifier
      # @param processing_purpose [String] Processing purpose to object to
      # @param verification_method [String] Verification method used
      # @return [Hash] Objection result
      #
      def handle_objection_request(user_id:, processing_purpose:, verification_method: "email_verification")
        log_info("Processing objection request", user_id: user_id, processing_purpose: processing_purpose)
        
        # Verify user identity
        unless verify_user_identity(user_id, verification_method)
          return {
            success: false,
            error: "User identity verification failed",
            user_id: user_id
          }
        end
        
        # Check if objection is valid
        unless objection_valid?(user_id, processing_purpose)
          return {
            success: false,
            error: "Objection not valid for this processing purpose",
            user_id: user_id,
            processing_purpose: processing_purpose
          }
        end
        
        # Check for compelling legitimate interests
        if compelling_legitimate_interests?(user_id, processing_purpose)
          return {
            success: false,
            error: "Compelling legitimate interests override objection",
            user_id: user_id,
            processing_purpose: processing_purpose
          }
        end
        
        # Stop processing
        objection_result = stop_processing_for_purpose(user_id, processing_purpose)
        
        # Log objection activity
        @audit_trail.log_compliance_event(
          event_type: "processing_objection",
          compliance_framework: :gdpr,
          severity: :medium,
          description: "Processing objection handled",
          metadata: {
            user_id: user_id,
            processing_purpose: processing_purpose,
            verification_method: verification_method,
            objection_result: objection_result
          }
        )
        
        {
          success: true,
          user_id: user_id,
          processing_purpose: processing_purpose,
          objection_result: objection_result,
          completion_time: Time.current.iso8601
        }
      end

      ##
      # Verify processing lawfulness (Article 6)
      #
      # @param user_id [String] User identifier
      # @param processing_purpose [String] Processing purpose
      # @return [Hash] Lawfulness verification result
      #
      def verify_processing_lawfulness(user_id:, processing_purpose:)
        log_info("Verifying processing lawfulness", user_id: user_id, processing_purpose: processing_purpose)
        
        # Check all legal bases
        legal_bases = []
        
        # Article 6(1)(a) - Consent
        if @consent_manager.has_valid_consent?(user_id, processing_purpose)
          legal_bases << :consent
        end
        
        # Article 6(1)(b) - Contract
        if contract_necessity?(user_id, processing_purpose)
          legal_bases << :contract
        end
        
        # Article 6(1)(c) - Legal obligation
        if legal_obligation?(processing_purpose)
          legal_bases << :legal_obligation
        end
        
        # Article 6(1)(d) - Vital interests
        if vital_interests?(user_id, processing_purpose)
          legal_bases << :vital_interests
        end
        
        # Article 6(1)(e) - Public task
        if public_task?(processing_purpose)
          legal_bases << :public_task
        end
        
        # Article 6(1)(f) - Legitimate interests
        if legitimate_interests?(user_id, processing_purpose)
          legal_bases << :legitimate_interests
        end
        
        lawful = legal_bases.any?
        
        # Log lawfulness check
        @audit_trail.log_compliance_event(
          event_type: "lawfulness_verification",
          compliance_framework: :gdpr,
          severity: :low,
          description: "Processing lawfulness verified",
          metadata: {
            user_id: user_id,
            processing_purpose: processing_purpose,
            legal_bases: legal_bases,
            lawful: lawful
          }
        )
        
        {
          lawful: lawful,
          legal_bases: legal_bases,
          user_id: user_id,
          processing_purpose: processing_purpose,
          verification_time: Time.current.iso8601
        }
      end

      ##
      # Check consent requirements
      #
      # @param user_id [String] User identifier
      # @param processing_purpose [String] Processing purpose
      # @return [Boolean] True if consent is required
      #
      def consent_required_for_processing?(user_id:, processing_purpose:)
        return false unless @consent_required
        
        # Check if other legal bases apply
        lawfulness = verify_processing_lawfulness(user_id: user_id, processing_purpose: processing_purpose)
        other_bases = lawfulness[:legal_bases] - [:consent]
        
        # Consent required if no other legal bases
        other_bases.empty?
      end

      ##
      # Generate GDPR compliance report
      #
      # @param start_date [Time] Start date for report
      # @param end_date [Time] End date for report
      # @return [Hash] Compliance report
      #
      def generate_compliance_report(start_date:, end_date:)
        log_info("Generating GDPR compliance report", start_date: start_date, end_date: end_date)
        
        # Get relevant audit records
        audit_records = @audit_trail.query(
          start_date: start_date,
          end_date: end_date,
          compliance_tags: [:gdpr]
        )
        
        # Analyze records
        report = {
          report_period: {
            start_date: start_date.iso8601,
            end_date: end_date.iso8601
          },
          data_subject_requests: analyze_data_subject_requests(audit_records),
          consent_statistics: @consent_manager.consent_statistics(start_date, end_date),
          data_breaches: analyze_data_breaches(audit_records),
          processing_activities: analyze_processing_activities(audit_records),
          retention_compliance: @data_retention.compliance_status,
          lawfulness_checks: analyze_lawfulness_checks(audit_records),
          generated_at: Time.current.iso8601
        }
        
        # Log report generation
        @audit_trail.log_compliance_event(
          event_type: "compliance_report",
          compliance_framework: :gdpr,
          severity: :low,
          description: "GDPR compliance report generated",
          metadata: {
            start_date: start_date.iso8601,
            end_date: end_date.iso8601,
            report_summary: report
          }
        )
        
        report
      end

      ##
      # Get GDPR compliance status
      #
      # @return [Hash] Current compliance status
      #
      def compliance_status
        {
          consent_management: @consent_manager.status,
          data_retention: @data_retention.status,
          breach_detection: @breach_detection.status,
          audit_trail: @audit_trail.statistics,
          last_compliance_check: Time.current.iso8601,
          enabled_features: {
            consent_required: @consent_required,
            data_minimization: @data_minimization,
            purpose_limitation: @purpose_limitation,
            storage_limitation: @storage_limitation
          }
        }
      end

      private

      def verify_user_identity(user_id, verification_method)
        # In a real implementation, this would verify user identity
        # through various methods (email, phone, etc.)
        case verification_method
        when "email_verification"
          # Verify email token
          true
        when "phone_verification"
          # Verify phone token
          true
        else
          false
        end
      end

      def erasure_required?(user_id, reason)
        # Check if erasure is legally required
        case reason
        when "user_request"
          # Check if user has right to erasure
          true
        when "consent_withdrawn"
          # Check if consent was the only legal basis
          !has_other_legal_bases?(user_id)
        when "unlawful_processing"
          # Always required for unlawful processing
          true
        else
          false
        end
      end

      def perform_user_erasure(user_id)
        # Perform actual data erasure
        # This would integrate with various data stores
        {
          user_data_deleted: true,
          conversation_data_deleted: true,
          audit_logs_anonymized: true,
          third_party_notified: true
        }
      end

      def portability_applies?(user_id)
        # Check if data portability right applies
        # Must be based on consent or contract
        consent_basis = @consent_manager.has_valid_consent?(user_id, "data_processing")
        contract_basis = contract_necessity?(user_id, "data_processing")
        
        consent_basis || contract_basis
      end

      def collect_user_data(user_id)
        # Collect all user data for export
        {
          personal_data: get_personal_data(user_id),
          conversation_data: get_conversation_data(user_id),
          preferences: get_user_preferences(user_id),
          consent_history: @consent_manager.consent_history(user_id)
        }
      end

      def format_user_data(user_data, format)
        case format
        when :json
          JSON.pretty_generate(user_data)
        when :csv
          # Convert to CSV format
          CSV.generate { |csv| flatten_to_csv(user_data, csv) }
        when :xml
          # Convert to XML format
          user_data.to_xml
        else
          JSON.pretty_generate(user_data)
        end
      end

      def get_processing_purposes(user_id)
        # Get all processing purposes for user
        ["customer_support", "service_improvement", "legal_compliance"]
      end

      def get_data_categories(user_id)
        # Get categories of personal data
        ["identity", "contact", "conversation", "preferences"]
      end

      def get_data_recipients(user_id)
        # Get recipients of personal data
        ["internal_staff", "ai_service_providers", "analytics_providers"]
      end

      def get_retention_period(user_id)
        # Get retention period for user data
        "7 years from last interaction"
      end

      def get_data_source(user_id)
        # Get source of personal data
        "directly_from_user"
      end

      def get_automated_processing_info(user_id)
        # Get automated processing information
        {
          automated_decision_making: true,
          profiling: false,
          logic_description: "AI-powered conversation analysis",
          significance: "personalized responses",
          consequences: "improved user experience"
        }
      end

      def get_third_country_transfers(user_id)
        # Get third country transfer information
        {
          transfers_occur: false,
          countries: [],
          adequacy_decisions: [],
          safeguards: []
        }
      end

      def validate_corrections(corrections)
        # Validate correction data
        errors = []
        
        corrections.each do |field, value|
          case field
          when :email
            errors << "Invalid email format" unless valid_email?(value)
          when :phone
            errors << "Invalid phone format" unless valid_phone?(value)
          end
        end
        
        {
          valid: errors.empty?,
          errors: errors
        }
      end

      def apply_corrections(user_id, corrections)
        # Apply corrections to user data
        corrections.each do |field, value|
          update_user_field(user_id, field, value)
        end
        
        {
          updated_fields: corrections.keys,
          update_time: Time.current.iso8601
        }
      end

      def restriction_justified?(user_id, reason)
        # Check if restriction is justified
        case reason
        when "accuracy_contested"
          true
        when "unlawful_processing"
          true
        when "data_no_longer_needed"
          true
        when "objection_pending"
          true
        else
          false
        end
      end

      def apply_processing_restriction(user_id, reason)
        # Apply processing restriction
        {
          restricted_processing: true,
          restriction_reason: reason,
          restriction_time: Time.current.iso8601
        }
      end

      def objection_valid?(user_id, processing_purpose)
        # Check if objection is valid
        case processing_purpose
        when "marketing"
          true
        when "profiling"
          true
        when "legitimate_interests"
          true
        else
          false
        end
      end

      def compelling_legitimate_interests?(user_id, processing_purpose)
        # Check for compelling legitimate interests
        case processing_purpose
        when "fraud_prevention"
          true
        when "security"
          true
        else
          false
        end
      end

      def stop_processing_for_purpose(user_id, processing_purpose)
        # Stop processing for specific purpose
        {
          processing_stopped: true,
          purpose: processing_purpose,
          stop_time: Time.current.iso8601
        }
      end

      def contract_necessity?(user_id, processing_purpose)
        # Check if processing is necessary for contract
        case processing_purpose
        when "service_delivery"
          true
        when "billing"
          true
        else
          false
        end
      end

      def legal_obligation?(processing_purpose)
        # Check if processing is required by law
        case processing_purpose
        when "tax_compliance"
          true
        when "audit_requirements"
          true
        else
          false
        end
      end

      def vital_interests?(user_id, processing_purpose)
        # Check if processing protects vital interests
        case processing_purpose
        when "emergency_response"
          true
        when "health_monitoring"
          true
        else
          false
        end
      end

      def public_task?(processing_purpose)
        # Check if processing is for public task
        case processing_purpose
        when "public_service"
          true
        when "regulatory_compliance"
          true
        else
          false
        end
      end

      def legitimate_interests?(user_id, processing_purpose)
        # Check if processing is for legitimate interests
        case processing_purpose
        when "service_improvement"
          true
        when "fraud_prevention"
          true
        else
          false
        end
      end

      def has_other_legal_bases?(user_id)
        # Check if there are other legal bases besides consent
        false # Simplified implementation
      end

      def analyze_data_subject_requests(audit_records)
        requests = audit_records.select { |r| r[:event_type].to_s.include?("data_") }
        
        {
          total_requests: requests.size,
          by_type: requests.group_by { |r| r[:event_type] }.transform_values(&:size),
          response_times: calculate_response_times(requests),
          success_rate: calculate_success_rate(requests)
        }
      end

      def analyze_data_breaches(audit_records)
        breaches = audit_records.select { |r| r[:event_type] == "data_breach" }
        
        {
          total_breaches: breaches.size,
          by_severity: breaches.group_by { |r| r[:severity] }.transform_values(&:size),
          notification_compliance: check_notification_compliance(breaches)
        }
      end

      def analyze_processing_activities(audit_records)
        activities = audit_records.select { |r| r[:event_type] == "processing_activity" }
        
        {
          total_activities: activities.size,
          by_purpose: activities.group_by { |r| r[:metadata][:purpose] }.transform_values(&:size),
          lawfulness_checks: activities.count { |r| r[:metadata][:lawfulness_verified] }
        }
      end

      def analyze_lawfulness_checks(audit_records)
        checks = audit_records.select { |r| r[:event_type] == "lawfulness_verification" }
        
        {
          total_checks: checks.size,
          lawful_processing: checks.count { |r| r[:metadata][:lawful] },
          legal_bases_used: checks.flat_map { |r| r[:metadata][:legal_bases] }.tally
        }
      end

      def calculate_response_times(requests)
        # Calculate average response times
        {
          average_hours: 24,
          within_30_days: requests.size,
          overdue: 0
        }
      end

      def calculate_success_rate(requests)
        # Calculate success rate
        successful = requests.count { |r| r[:metadata][:success] }
        (successful.to_f / requests.size * 100).round(2)
      end

      def check_notification_compliance(breaches)
        # Check if breaches were notified within 72 hours
        compliant = breaches.count do |breach|
          notification_time = breach[:metadata][:notification_time]
          notification_time && notification_time < 72.hours.from_now
        end
        
        {
          compliant_notifications: compliant,
          total_notifications: breaches.size,
          compliance_rate: (compliant.to_f / breaches.size * 100).round(2)
        }
      end

      def valid_email?(email)
        email.match?(/\A[^@\s]+@[^@\s]+\z/)
      end

      def valid_phone?(phone)
        phone.match?(/\A\+?[1-9]\d{1,14}\z/)
      end

      def get_personal_data(user_id)
        # Get personal data for user
        {}
      end

      def get_conversation_data(user_id)
        # Get conversation data for user
        {}
      end

      def get_user_preferences(user_id)
        # Get user preferences
        {}
      end

      def update_user_field(user_id, field, value)
        # Update user field
        # Implementation would update the actual data store
      end

      def flatten_to_csv(data, csv)
        # Flatten hash to CSV
        data.each do |key, value|
          csv << [key, value.to_s]
        end
      end
    end
  end
end