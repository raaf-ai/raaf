# frozen_string_literal: true

require_relative 'base'
require_relative 'pii_detector'

module RAAF
  module Guardrails
    # Ensures HIPAA (Health Insurance Portability and Accountability Act) compliance
    class HIPAACompliance < Base
      # PHI (Protected Health Information) identifiers under HIPAA
      PHI_IDENTIFIERS = {
        names: /\b(?:patient|Mr\.|Mrs\.|Ms\.|Dr\.)\s+[A-Z][a-z]+\s+[A-Z][a-z]+\b/,
        geographic: /\b\d{5}(?:-\d{4})?\b/,  # ZIP codes
        dates: /\b(?:0[1-9]|1[0-2])[-\/](?:0[1-9]|[12]\d|3[01])[-\/](?:19|20)\d{2}\b/,
        phone: /\b(?:\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}\b/,
        fax: /\bfax:?\s*(?:\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}\b/i,
        email: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
        ssn: /\b\d{3}[-.\s]?\d{2}[-.\s]?\d{4}\b/,
        medical_record: /\b(?:MRN|Medical Record Number):?\s*\d{6,}/i,
        health_plan: /\b(?:Member ID|Policy):?\s*[A-Z0-9]{8,}/i,
        account_number: /\b(?:Account|Acct):?\s*#?\d{6,}/i,
        certificate_license: /\b(?:License|Certificate):?\s*#?[A-Z0-9]{6,}/i,
        vehicle_id: /\b(?:VIN|Vehicle ID):?\s*[A-Z0-9]{17}\b/i,
        device_id: /\b(?:Device ID|Serial):?\s*[A-Z0-9]{8,}/i,
        web_url: /https?:\/\/(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b/,
        ip_address: /\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/,
        biometric: /\b(?:fingerprint|retina|iris|voice|facial)\s*(?:scan|print|recognition)\b/i,
        photo: /\b(?:photo|photograph|image|picture)\s*(?:of|showing)?\s*(?:patient|face)\b/i
      }.freeze

      # HIPAA-specific medical information patterns
      MEDICAL_PATTERNS = {
        diagnosis: {
          patterns: [
            /\b(?:diagnosed with|diagnosis of|suffering from)\s+[A-Za-z\s]+\b/i,
            /\bICD-?10:?\s*[A-Z]\d{2}(?:\.\d+)?\b/i,  # ICD-10 codes
            /\b(?:cancer|diabetes|hypertension|depression|anxiety)\b/i
          ],
          description: 'Medical diagnosis information'
        },
        treatment: {
          patterns: [
            /\b(?:prescribed|medication|treatment|therapy)\s+[A-Za-z\s]+\b/i,
            /\b(?:mg|mcg|ml|units)\s+(?:daily|twice|three times)\b/i,
            /\b(?:surgery|procedure|operation)\s+(?:on|scheduled|performed)\b/i
          ],
          description: 'Medical treatment information'
        },
        lab_results: {
          patterns: [
            /\b(?:test results?|lab results?|blood work)\b/i,
            /\b(?:positive|negative|normal|abnormal)\s+(?:for|test|result)\b/i,
            /\b(?:cholesterol|glucose|hemoglobin|blood pressure):?\s*\d+/i
          ],
          description: 'Laboratory or test results'
        },
        provider_info: {
          patterns: [
            /\bDr\.?\s+[A-Z][a-z]+\s+[A-Z][a-z]+\b/,
            /\b(?:physician|doctor|nurse|therapist)\s+(?:name|contact)\b/i,
            /\b(?:hospital|clinic|medical center)\s+[A-Z][a-z]+/i
          ],
          description: 'Healthcare provider information'
        }
      }.freeze

      # HIPAA safeguards
      SAFEGUARDS = {
        administrative: [
          :access_management,
          :workforce_training,
          :access_authorization,
          :incident_response
        ],
        physical: [
          :facility_controls,
          :workstation_security,
          :device_controls,
          :media_controls
        ],
        technical: [
          :access_control,
          :audit_controls,
          :integrity,
          :transmission_security
        ]
      }.freeze

      attr_reader :covered_entity, :business_associate, :minimum_necessary,
                  :safeguards, :phi_detector, :audit_required

      def initialize(action: :block, covered_entity: true, business_associate: false,
                     minimum_necessary: true, safeguards: nil, audit_required: true, **options)
        super(action: action, **options)
        @covered_entity = covered_entity
        @business_associate = business_associate
        @minimum_necessary = minimum_necessary
        @safeguards = configure_safeguards(safeguards)
        @audit_required = audit_required
        
        # Create internal PHI detector
        @phi_detector = PIIDetector.new(
          action: :redact,
          custom_patterns: PHI_IDENTIFIERS.transform_values { |pattern| { pattern: pattern, description: 'PHI' } }
        )
      end

      protected

      def perform_check(content, context)
        violations = []
        
        # Check for PHI exposure
        phi_result = @phi_detector.check_input(content, context)
        if phi_result.violated?
          violations.concat(convert_phi_violations(phi_result.violations))
        end
        
        # Check medical information patterns
        violations.concat(check_medical_patterns(content))
        
        # Check minimum necessary principle
        if @minimum_necessary && excessive_phi_disclosure?(content, context)
          violations << {
            type: :minimum_necessary_violation,
            severity: :high,
            description: "Potential violation of HIPAA minimum necessary standard"
          }
        end
        
        # Check authorization
        if context[:disclosure_type] && !authorized_disclosure?(context)
          violations << {
            type: :unauthorized_disclosure,
            severity: :critical,
            description: "PHI disclosure lacks proper authorization"
          }
        end
        
        # Check safeguards implementation
        safeguard_violations = check_safeguards(context)
        violations.concat(safeguard_violations)
        
        # Audit if required
        audit_check(content, context, violations) if @audit_required
        
        return safe_result if violations.empty?
        
        # Add HIPAA-specific metadata
        result = violation_result(violations)
        result.metadata[:hipaa_violations] = categorize_violations(violations)
        result.metadata[:required_actions] = determine_required_actions(violations)
        result.metadata[:breach_risk] = assess_breach_risk(violations)
        result
      end

      private

      def configure_safeguards(custom_safeguards)
        default_safeguards = {
          administrative: SAFEGUARDS[:administrative],
          physical: SAFEGUARDS[:physical],
          technical: SAFEGUARDS[:technical]
        }
        
        custom_safeguards ? default_safeguards.merge(custom_safeguards) : default_safeguards
      end

      def check_medical_patterns(content)
        violations = []
        
        MEDICAL_PATTERNS.each do |category, config|
          config[:patterns].each do |pattern|
            if content.match?(pattern)
              violations << {
                type: "hipaa_#{category}".to_sym,
                category: category,
                severity: :high,
                description: "#{config[:description]} detected",
                pattern: pattern.source
              }
            end
          end
        end
        
        violations
      end

      def convert_phi_violations(phi_violations)
        phi_violations.map do |violation|
          {
            type: :hipaa_phi_exposure,
            phi_type: violation[:type],
            severity: :critical,
            description: "HIPAA PHI identifier detected",
            safe_harbor_element: map_to_safe_harbor(violation[:type])
          }
        end
      end

      def map_to_safe_harbor(phi_type)
        # Map to HIPAA Safe Harbor 18 identifiers
        case phi_type
        when :names then "Names"
        when :geographic then "Geographic subdivisions"
        when :dates then "Dates related to individual"
        when :phone then "Telephone numbers"
        when :fax then "Fax numbers"
        when :email then "Email addresses"
        when :ssn then "Social Security numbers"
        when :medical_record then "Medical record numbers"
        when :health_plan then "Health plan beneficiary numbers"
        when :account_number then "Account numbers"
        when :certificate_license then "Certificate/license numbers"
        when :vehicle_id then "Vehicle identifiers"
        when :device_id then "Device identifiers"
        when :web_url then "Web URLs"
        when :ip_address then "IP addresses"
        when :biometric then "Biometric identifiers"
        when :photo then "Full face photos"
        else "Other unique identifier"
        end
      end

      def excessive_phi_disclosure?(content, context)
        # Check if more PHI is being disclosed than necessary
        phi_count = PHI_IDENTIFIERS.values.sum { |pattern| content.scan(pattern).size }
        
        # Context-dependent thresholds
        threshold = case context[:purpose]
                   when :treatment then 10
                   when :payment then 5
                   when :operations then 3
                   else 1
                   end
        
        phi_count > threshold
      end

      def authorized_disclosure?(context)
        # Check HIPAA-compliant authorization
        return true if context[:patient_authorization]
        return true if context[:purpose] && [:treatment, :payment, :operations].include?(context[:purpose])
        return true if context[:required_by_law]
        return true if context[:public_health_activity]
        
        false
      end

      def check_safeguards(context)
        violations = []
        
        # Check administrative safeguards
        if context[:access_type] && !proper_access_controls?(context)
          violations << {
            type: :administrative_safeguard_failure,
            safeguard: :access_control,
            severity: :high,
            description: "Inadequate administrative access controls"
          }
        end
        
        # Check technical safeguards
        if context[:transmission_type] && !secure_transmission?(context)
          violations << {
            type: :technical_safeguard_failure,
            safeguard: :transmission_security,
            severity: :critical,
            description: "PHI transmission lacks encryption"
          }
        end
        
        violations
      end

      def proper_access_controls?(context)
        return false unless context[:user_authenticated]
        return false unless context[:user_authorized]
        return false if context[:role] && !authorized_role?(context[:role])
        
        true
      end

      def authorized_role?(role)
        # Example authorized roles
        [:physician, :nurse, :medical_staff, :billing, :admin].include?(role)
      end

      def secure_transmission?(context)
        return true if context[:encrypted]
        return true if context[:transmission_type] == :internal
        
        false
      end

      def categorize_violations(violations)
        {
          phi_identifiers: violations.count { |v| v[:type] == :hipaa_phi_exposure },
          medical_information: violations.count { |v| v[:type].to_s.start_with?('hipaa_') && v[:type] != :hipaa_phi_exposure },
          safeguard_failures: violations.count { |v| v[:type].to_s.include?('safeguard') },
          authorization_issues: violations.count { |v| v[:type] == :unauthorized_disclosure }
        }
      end

      def determine_required_actions(violations)
        actions = []
        
        violations.each do |violation|
          case violation[:type]
          when :hipaa_phi_exposure
            actions << "Immediately contain and assess the PHI exposure"
            actions << "Document the incident for potential breach notification"
          when :unauthorized_disclosure
            actions << "Obtain proper authorization before disclosure"
            actions << "Review HIPAA authorization requirements"
          when :administrative_safeguard_failure
            actions << "Implement proper access controls and authentication"
            actions << "Conduct workforce training on HIPAA requirements"
          when :technical_safeguard_failure
            actions << "Implement encryption for PHI transmission"
            actions << "Review technical safeguard implementation"
          when :minimum_necessary_violation
            actions << "Limit PHI disclosure to minimum necessary"
            actions << "Review and update minimum necessary policies"
          end
        end
        
        actions.uniq
      end

      def assess_breach_risk(violations)
        # HIPAA breach risk assessment factors
        risk_score = 0
        
        # Nature and extent of PHI
        phi_count = violations.count { |v| v[:type] == :hipaa_phi_exposure }
        risk_score += phi_count * 2
        
        # Unauthorized person who received PHI
        if violations.any? { |v| v[:type] == :unauthorized_disclosure }
          risk_score += 5
        end
        
        # Whether PHI was actually viewed
        if violations.any? { |v| v[:severity] == :critical }
          risk_score += 3
        end
        
        # Mitigation possibilities
        if violations.any? { |v| v[:type].to_s.include?('safeguard') }
          risk_score += 2
        end
        
        case risk_score
        when 0..2 then :low
        when 3..5 then :medium
        when 6..8 then :high
        else :critical
        end
      end

      def audit_check(content, context, violations)
        return unless @logger
        
        audit_entry = {
          timestamp: Time.now.iso8601,
          check_type: 'HIPAA Compliance',
          content_hash: Digest::SHA256.hexdigest(content),
          violations_found: violations.size,
          violation_categories: categorize_violations(violations),
          covered_entity: @covered_entity,
          business_associate: @business_associate,
          breach_risk_level: assess_breach_risk(violations),
          context: sanitize_context_for_audit(context)
        }
        
        @logger.info "HIPAA Compliance Check: #{audit_entry.to_json}"
        
        # For high-risk violations, additional logging may be required
        if audit_entry[:breach_risk_level] == :critical
          @logger.error "CRITICAL HIPAA VIOLATION - Potential breach detected"
        end
      end

      def sanitize_context_for_audit(context)
        # Remove any actual PHI from audit logs
        context.reject { |k, _| [:patient_data, :phi, :medical_info].include?(k) }
      end
    end
  end
end