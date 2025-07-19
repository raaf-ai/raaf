# frozen_string_literal: true

require_relative 'base'
require_relative 'pii_detector'

module RAAF
  module Guardrails
    # Ensures GDPR (General Data Protection Regulation) compliance
    class GDPRCompliance < Base
      # GDPR-specific PII types
      GDPR_PII_TYPES = [
        :email, :phone, :name, :address, :date_of_birth,
        :national_id, :passport, :iban, :vat_number,
        :ip_address, :cookie_id, :device_id
      ].freeze

      # GDPR principles patterns
      GDPR_PRINCIPLES = {
        data_minimization: {
          patterns: [
            /collect.*(?:all|every|any).*(?:data|information)/i,
            /store.*(?:everything|all\s+data)/i,
            /save.*(?:complete|full).*(?:profile|history)/i
          ],
          description: 'Potential violation of data minimization principle'
        },
        purpose_limitation: {
          patterns: [
            /use.*data.*(?:for|to).*(?:other|different|new).*purpose/i,
            /repurpose.*(?:personal|user).*(?:data|information)/i,
            /share.*with.*third.*party/i
          ],
          description: 'Potential violation of purpose limitation principle'
        },
        consent_required: {
          patterns: [
            /process.*(?:personal|user).*data.*without.*consent/i,
            /automatically.*collect/i,
            /track.*without.*(?:asking|permission|consent)/i
          ],
          description: 'Processing personal data without explicit consent'
        },
        right_to_erasure: {
          patterns: [
            /cannot.*delete.*(?:account|data|information)/i,
            /permanent.*storage/i,
            /never.*remove.*(?:data|information)/i
          ],
          description: 'Potential violation of right to erasure'
        },
        data_portability: {
          patterns: [
            /cannot.*export.*(?:data|information)/i,
            /no.*download.*option/i,
            /proprietary.*format.*only/i
          ],
          description: 'Potential violation of data portability rights'
        }
      }.freeze

      attr_reader :data_processing_purposes, :legal_basis, :data_subject_rights,
                  :pii_detector, :audit_trail, :data_retention_period

      def initialize(action: :flag, data_processing_purposes: [], legal_basis: nil,
                     data_retention_period: nil, data_subject_rights: nil, 
                     audit_trail: true, **options)
        super(action: action, **options)
        @data_processing_purposes = data_processing_purposes
        @legal_basis = legal_basis
        @data_retention_period = data_retention_period
        @data_subject_rights = configure_data_rights(data_subject_rights)
        @audit_trail = audit_trail
        
        # Create internal PII detector with GDPR-specific configuration
        @pii_detector = PIIDetector.new(
          action: :redact,
          detection_types: GDPR_PII_TYPES,
          custom_patterns: gdpr_specific_patterns
        )
      end

      protected

      def perform_check(content, context)
        violations = []
        
        # Check for PII exposure
        pii_result = @pii_detector.check_input(content, context)
        if pii_result.violated?
          violations.concat(convert_pii_violations(pii_result.violations))
        end
        
        # Check GDPR principles
        violations.concat(check_gdpr_principles(content, context))
        
        # Check data processing legitimacy
        if context[:processing_type] && !legitimate_processing?(context)
          violations << {
            type: :illegitimate_processing,
            severity: :high,
            description: "Data processing lacks legal basis under GDPR Article 6"
          }
        end
        
        # Check data retention
        if context[:retention_period] && exceeds_retention_limit?(context[:retention_period])
          violations << {
            type: :excessive_retention,
            severity: :medium,
            description: "Data retention period exceeds GDPR requirements"
          }
        end
        
        # Audit if enabled
        audit_check(content, context, violations) if @audit_trail
        
        return safe_result if violations.empty?
        
        # For GDPR, we often need to provide detailed information
        result = violation_result(violations)
        result.metadata[:gdpr_articles] = relevant_articles(violations)
        result.metadata[:required_actions] = required_actions(violations)
        result
      end

      private

      def configure_data_rights(rights)
        default_rights = {
          right_to_access: true,
          right_to_rectification: true,
          right_to_erasure: true,
          right_to_portability: true,
          right_to_object: true,
          right_to_restrict_processing: true,
          automated_decision_making: false
        }
        
        rights ? default_rights.merge(rights) : default_rights
      end

      def gdpr_specific_patterns
        {
          eu_national_id: {
            pattern: /[A-Z]{2}\d{6,12}/,
            description: 'EU National ID Number'
          },
          iban: {
            pattern: /[A-Z]{2}\d{2}[A-Z0-9]{4}\d{7}([A-Z0-9]?){0,16}/,
            description: 'International Bank Account Number'
          },
          vat_number: {
            pattern: /[A-Z]{2}\d{8,12}/,
            description: 'VAT Registration Number'
          },
          nhs_number: {
            pattern: /\d{3}[-\s]?\d{3}[-\s]?\d{4}/,
            description: 'NHS Number (UK)'
          }
        }
      end

      def check_gdpr_principles(content, context)
        violations = []
        
        GDPR_PRINCIPLES.each do |principle, config|
          config[:patterns].each do |pattern|
            if content.match?(pattern)
              violations << {
                type: "gdpr_#{principle}".to_sym,
                principle: principle,
                severity: :high,
                description: config[:description],
                pattern: pattern.source
              }
            end
          end
        end
        
        violations
      end

      def legitimate_processing?(context)
        return false unless @legal_basis
        
        case @legal_basis
        when :consent
          context[:user_consent] == true
        when :contract
          context[:contract_necessary] == true
        when :legal_obligation
          context[:legal_requirement] == true
        when :vital_interests
          context[:vital_interests] == true
        when :public_task
          context[:public_task] == true
        when :legitimate_interests
          legitimate_interests_assessment(context)
        else
          false
        end
      end

      def legitimate_interests_assessment(context)
        # Simplified LIA - in production this would be more comprehensive
        return false unless context[:legitimate_interest_purpose]
        return false if context[:high_privacy_impact]
        return false if context[:vulnerable_data_subjects]
        
        true
      end

      def exceeds_retention_limit?(proposed_period)
        return false unless @data_retention_period
        
        proposed_period > @data_retention_period
      end

      def convert_pii_violations(pii_violations)
        pii_violations.map do |violation|
          {
            type: :gdpr_pii_exposure,
            pii_type: violation[:type],
            severity: :critical,
            description: "GDPR-protected PII detected: #{violation[:description]}",
            gdpr_category: categorize_pii_gdpr(violation[:type])
          }
        end
      end

      def categorize_pii_gdpr(pii_type)
        case pii_type
        when :ssn, :national_id, :passport
          :special_category_data
        when :email, :phone, :address
          :personal_data
        when :ip_address, :cookie_id, :device_id
          :online_identifiers
        else
          :personal_data
        end
      end

      def relevant_articles(violations)
        articles = []
        
        violations.each do |violation|
          case violation[:type]
          when :gdpr_pii_exposure
            articles << "Article 5 (Principles)"
            articles << "Article 32 (Security)"
          when :gdpr_data_minimization
            articles << "Article 5(1)(c) (Data Minimisation)"
          when :gdpr_purpose_limitation
            articles << "Article 5(1)(b) (Purpose Limitation)"
          when :gdpr_consent_required
            articles << "Article 6 (Lawfulness)"
            articles << "Article 7 (Consent)"
          when :gdpr_right_to_erasure
            articles << "Article 17 (Right to Erasure)"
          when :gdpr_data_portability
            articles << "Article 20 (Data Portability)"
          when :illegitimate_processing
            articles << "Article 6 (Lawfulness of Processing)"
          when :excessive_retention
            articles << "Article 5(1)(e) (Storage Limitation)"
          end
        end
        
        articles.uniq
      end

      def required_actions(violations)
        actions = []
        
        violations.each do |violation|
          case violation[:type]
          when :gdpr_pii_exposure
            actions << "Implement appropriate technical measures to protect PII"
            actions << "Conduct Data Protection Impact Assessment (DPIA)"
          when :gdpr_consent_required
            actions << "Obtain explicit consent before processing"
            actions << "Provide clear privacy notice"
          when :gdpr_right_to_erasure
            actions << "Implement data deletion mechanisms"
            actions << "Document retention policies"
          when :illegitimate_processing
            actions << "Establish legal basis for processing"
            actions << "Document legitimate interests assessment if applicable"
          end
        end
        
        actions.uniq
      end

      def audit_check(content, context, violations)
        return unless @logger
        
        audit_entry = {
          timestamp: Time.now.iso8601,
          check_type: 'GDPR Compliance',
          content_hash: Digest::SHA256.hexdigest(content),
          violations_found: violations.size,
          violation_types: violations.map { |v| v[:type] }.uniq,
          context: sanitize_context_for_audit(context),
          legal_basis: @legal_basis,
          data_categories: violations.map { |v| v[:gdpr_category] }.compact.uniq
        }
        
        @logger.info "GDPR Compliance Check: #{audit_entry.to_json}"
      end

      def sanitize_context_for_audit(context)
        # Remove sensitive data from context before logging
        context.reject { |k, _| [:user_data, :content, :pii].include?(k) }
      end
    end
  end
end