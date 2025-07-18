**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Compliance Guide
=====================

This guide covers enterprise compliance frameworks available in RAAF, including GDPR, HIPAA, and SOC2 compliance. Learn how to implement automated audit trails, policy enforcement, and regulatory compliance for building enterprise-grade AI systems that meet industry standards.

After reading this guide, you will know:

* How to implement GDPR compliance for AI systems
* HIPAA compliance patterns for healthcare AI applications
* SOC2 compliance implementation and monitoring
* Automated audit trail generation
* Policy enforcement strategies
* Data governance and privacy controls
* Compliance reporting and documentation

--------------------------------------------------------------------------------

Introduction to RAAF Compliance
-------------------------------

RAAF Compliance provides enterprise-grade compliance frameworks that help organizations meet regulatory requirements when deploying AI systems. The compliance module offers:

* **Automated audit trails** for all AI interactions
* **Policy enforcement** at runtime
* **Data governance** controls
* **Privacy protection** mechanisms
* **Compliance reporting** and documentation
* **Multi-framework support** (GDPR, HIPAA, SOC2, and more)

### Installation

Add the compliance gem to your Gemfile:

```ruby
gem 'raaf-compliance'
```

Then bundle install:

```bash
bundle install
```

GDPR Compliance
--------------

### Overview

The General Data Protection Regulation (GDPR) requires organizations to protect personal data and privacy of EU citizens. RAAF's GDPR compliance module provides:

* **Data minimization** controls
* **Consent management** 
* **Right to erasure** (right to be forgotten)
* **Data portability** support
* **Privacy by design** patterns

### Basic GDPR Setup

```ruby
require 'raaf/compliance/gdpr'

# Configure GDPR compliance
gdpr_config = RAAF::Compliance::GDPR::Config.new(
  data_retention_period: 2.years,
  consent_required: true,
  anonymization_enabled: true,
  audit_trail_enabled: true
)

# Create GDPR-compliant agent
agent = RAAF::Agent.new(
  name: "CustomerService",
  instructions: "Help customers with inquiries while respecting privacy",
  model: "gpt-4o"
)

# Add GDPR compliance
compliance_manager = RAAF::Compliance::GDPR::Manager.new(gdpr_config)
agent.add_compliance(compliance_manager)
```

### Data Processing Consent

Implement consent management for data processing:

```ruby
class ConsentManager
  def initialize
    @consent_store = RAAF::Compliance::GDPR::ConsentStore.new
  end
  
  def request_consent(user_id, purpose, data_types)
    consent_request = RAAF::Compliance::GDPR::ConsentRequest.new(
      user_id: user_id,
      purpose: purpose,
      data_types: data_types,
      retention_period: 2.years,
      processing_lawful_basis: "consent"
    )
    
    @consent_store.create_request(consent_request)
  end
  
  def grant_consent(consent_id, user_consent)
    consent = @consent_store.find(consent_id)
    
    if user_consent
      consent.grant!
      Rails.logger.info("Consent granted for #{consent.user_id}")
    else
      consent.deny!
      Rails.logger.info("Consent denied for #{consent.user_id}")
    end
    
    consent
  end
  
  def check_consent(user_id, purpose)
    @consent_store.has_valid_consent?(user_id, purpose)
  end
end
```

### Data Minimization

Implement data minimization principles:

```ruby
class DataMinimizationGuardrail < RAAF::Guardrails::Base
  def initialize
    @gdpr_config = RAAF::Compliance::GDPR::Config.current
  end
  
  def process_input(input)
    # Extract only necessary data
    minimized_data = extract_necessary_data(input)
    
    # Log data processing
    audit_log = RAAF::Compliance::GDPR::AuditLog.new(
      action: "data_processing",
      data_types: identify_data_types(minimized_data),
      purpose: "customer_service",
      timestamp: Time.current
    )
    
    audit_log.save
    
    success(minimized_data)
  end
  
  private
  
  def extract_necessary_data(input)
    # Remove unnecessary personal data
    sanitized = input.dup
    
    # Remove credit card numbers (keep only last 4 digits)
    sanitized.gsub!(/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?(\d{4})\b/, "****-****-****-\\1")
    
    # Remove full addresses (keep only city)
    sanitized.gsub!(/\d+\s+[\w\s]+(?:street|st|avenue|ave|road|rd|drive|dr)\s*,?\s*([\w\s]+),?\s*\w{2}\s*\d{5}/, "\\1")
    
    sanitized
  end
  
  def identify_data_types(data)
    types = []
    
    types << "name" if data.match?(/\b[A-Z][a-z]+\s+[A-Z][a-z]+\b/)
    types << "email" if data.match?(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/)
    types << "phone" if data.match?(/\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/)
    types << "address" if data.match?(/\d+\s+[\w\s]+(?:street|st|avenue|ave|road|rd|drive|dr)/i)
    
    types
  end
end
```

### Right to Erasure

Implement the right to be forgotten:

```ruby
class RightToErasureHandler
  def initialize
    @data_store = RAAF::Compliance::GDPR::DataStore.new
    @audit_logger = RAAF::Compliance::GDPR::AuditLogger.new
  end
  
  def process_erasure_request(user_id, request_reason)
    # Verify user identity
    unless verify_user_identity(user_id)
      return { success: false, error: "Identity verification failed" }
    end
    
    # Check if erasure is legally required
    unless erasure_required?(user_id, request_reason)
      return { success: false, error: "Erasure not legally required" }
    end
    
    # Perform erasure
    erasure_result = perform_erasure(user_id)
    
    # Log erasure action
    @audit_logger.log_erasure(
      user_id: user_id,
      reason: request_reason,
      result: erasure_result,
      timestamp: Time.current
    )
    
    erasure_result
  end
  
  private
  
  def perform_erasure(user_id)
    begin
      # Erase from conversation history
      @data_store.delete_user_conversations(user_id)
      
      # Erase from memory store
      @data_store.delete_user_memory(user_id)
      
      # Erase from audit logs (anonymize)
      @data_store.anonymize_audit_logs(user_id)
      
      # Erase from analytics
      @data_store.delete_user_analytics(user_id)
      
      { success: true, message: "User data successfully erased" }
    rescue => e
      Rails.logger.error("Erasure failed for user #{user_id}: #{e.message}")
      { success: false, error: "Erasure failed" }
    end
  end
  
  def erasure_required?(user_id, reason)
    valid_reasons = [
      "consent_withdrawn",
      "data_no_longer_necessary",
      "unlawful_processing",
      "user_request"
    ]
    
    valid_reasons.include?(reason)
  end
end
```

HIPAA Compliance
---------------

### Overview

The Health Insurance Portability and Accountability Act (HIPAA) requires healthcare organizations to protect sensitive patient health information. RAAF's HIPAA compliance module provides:

* **PHI protection** (Protected Health Information)
* **Access controls** and audit trails
* **Encryption** for data at rest and in transit
* **Business Associate Agreements** (BAA) compliance
* **Breach detection** and notification

### HIPAA Setup

```ruby
require 'raaf/compliance/hipaa'

# Configure HIPAA compliance
hipaa_config = RAAF::Compliance::HIPAA::Config.new(
  phi_detection_enabled: true,
  encryption_required: true,
  audit_trail_enabled: true,
  access_control_enabled: true,
  breach_detection_enabled: true
)

# Create HIPAA-compliant agent
agent = RAAF::Agent.new(
  name: "HealthcareAssistant",
  instructions: "Provide healthcare information while protecting patient privacy",
  model: "gpt-4o"
)

# Add HIPAA compliance
compliance_manager = RAAF::Compliance::HIPAA::Manager.new(hipaa_config)
agent.add_compliance(compliance_manager)
```

### PHI Detection and Protection

Implement PHI detection and redaction:

```ruby
class PHIDetectionGuardrail < RAAF::Guardrails::Base
  def initialize
    @phi_patterns = load_phi_patterns
    @encryption_service = RAAF::Compliance::HIPAA::EncryptionService.new
  end
  
  def process_input(input)
    # Detect PHI in input
    phi_detected = detect_phi(input)
    
    if phi_detected.any?
      # Log PHI access
      log_phi_access(phi_detected)
      
      # Redact or encrypt PHI
      processed_input = redact_phi(input, phi_detected)
      
      return success(processed_input)
    end
    
    success(input)
  end
  
  private
  
  def detect_phi(text)
    detected_phi = []
    
    @phi_patterns.each do |pattern_name, pattern|
      matches = text.scan(pattern)
      if matches.any?
        detected_phi << {
          type: pattern_name,
          matches: matches,
          positions: find_match_positions(text, pattern)
        }
      end
    end
    
    detected_phi
  end
  
  def load_phi_patterns
    {
      ssn: /\b\d{3}-\d{2}-\d{4}\b/,
      medical_record_number: /\bMRN[:\s]+\d{6,10}\b/i,
      date_of_birth: /\b(?:DOB|Date of Birth)[:\s]+\d{1,2}\/\d{1,2}\/\d{4}\b/i,
      health_plan_id: /\b(?:Health Plan|Insurance|Policy)[:\s#]+\d{8,15}\b/i,
      device_identifier: /\b(?:Device|Implant)\s+ID[:\s]+[\w\d-]{8,20}\b/i,
      biometric_identifier: /\b(?:Fingerprint|Biometric)[:\s]+[A-F0-9]{16,32}\b/i
    }
  end
  
  def redact_phi(text, phi_detected)
    redacted_text = text.dup
    
    phi_detected.each do |phi|
      phi[:matches].each do |match|
        redacted_text.gsub!(match, "[REDACTED_#{phi[:type].upcase}]")
      end
    end
    
    redacted_text
  end
  
  def log_phi_access(phi_detected)
    RAAF::Compliance::HIPAA::AuditLogger.log(
      event: "phi_access",
      phi_types: phi_detected.map { |p| p[:type] },
      timestamp: Time.current,
      user_id: current_user_id,
      session_id: current_session_id
    )
  end
end
```

### Access Control and Authorization

Implement role-based access control:

```ruby
class HIPAAAccessControl
  def initialize
    @role_permissions = load_role_permissions
    @audit_logger = RAAF::Compliance::HIPAA::AuditLogger.new
  end
  
  def authorize_access(user_id, requested_action, resource_type)
    user_role = get_user_role(user_id)
    
    unless authorized?(user_role, requested_action, resource_type)
      @audit_logger.log_access_denied(
        user_id: user_id,
        role: user_role,
        action: requested_action,
        resource: resource_type,
        timestamp: Time.current
      )
      
      return { authorized: false, error: "Access denied" }
    end
    
    @audit_logger.log_access_granted(
      user_id: user_id,
      role: user_role,
      action: requested_action,
      resource: resource_type,
      timestamp: Time.current
    )
    
    { authorized: true }
  end
  
  private
  
  def load_role_permissions
    {
      physician: {
        patient_data: [:read, :write, :update],
        treatment_plans: [:read, :write, :update, :delete],
        prescriptions: [:read, :write, :update]
      },
      nurse: {
        patient_data: [:read, :update],
        treatment_plans: [:read, :update],
        prescriptions: [:read]
      },
      admin: {
        patient_data: [:read],
        treatment_plans: [:read],
        prescriptions: [:read],
        audit_logs: [:read]
      }
    }
  end
  
  def authorized?(role, action, resource)
    permissions = @role_permissions[role.to_sym]
    return false unless permissions
    
    resource_permissions = permissions[resource.to_sym]
    return false unless resource_permissions
    
    resource_permissions.include?(action.to_sym)
  end
end
```

### Breach Detection

Implement automated breach detection:

```ruby
class HIPAABreachDetector
  def initialize
    @breach_patterns = load_breach_patterns
    @notification_service = RAAF::Compliance::HIPAA::NotificationService.new
  end
  
  def monitor_activity(activity_log)
    potential_breaches = detect_breaches(activity_log)
    
    potential_breaches.each do |breach|
      handle_potential_breach(breach)
    end
  end
  
  private
  
  def detect_breaches(activity_log)
    breaches = []
    
    # Detect unusual access patterns
    unusual_access = detect_unusual_access(activity_log)
    breaches.concat(unusual_access)
    
    # Detect unauthorized access attempts
    unauthorized_access = detect_unauthorized_access(activity_log)
    breaches.concat(unauthorized_access)
    
    # Detect data exfiltration
    data_exfiltration = detect_data_exfiltration(activity_log)
    breaches.concat(data_exfiltration)
    
    breaches
  end
  
  def detect_unusual_access(activity_log)
    breaches = []
    
    # Group activities by user
    user_activities = activity_log.group_by { |log| log[:user_id] }
    
    user_activities.each do |user_id, activities|
      # Check for access outside normal hours
      after_hours_access = activities.select do |activity|
        hour = activity[:timestamp].hour
        hour < 7 || hour > 18 # Outside 7 AM - 6 PM
      end
      
      if after_hours_access.size > 5
        breaches << {
          type: "unusual_access_pattern",
          user_id: user_id,
          description: "Excessive after-hours access",
          activities: after_hours_access,
          severity: "medium"
        }
      end
      
      # Check for rapid sequential access
      if activities.size > 50 && activities.last[:timestamp] - activities.first[:timestamp] < 1.hour
        breaches << {
          type: "rapid_access_pattern",
          user_id: user_id,
          description: "Rapid sequential access to patient data",
          activities: activities,
          severity: "high"
        }
      end
    end
    
    breaches
  end
  
  def handle_potential_breach(breach)
    # Log the breach
    RAAF::Compliance::HIPAA::BreachLog.create(
      type: breach[:type],
      user_id: breach[:user_id],
      description: breach[:description],
      severity: breach[:severity],
      detected_at: Time.current,
      status: "investigating"
    )
    
    # Notify security team
    @notification_service.notify_security_team(breach)
    
    # If high severity, immediate action
    if breach[:severity] == "high"
      @notification_service.notify_compliance_officer(breach)
      
      # Temporarily suspend user access
      suspend_user_access(breach[:user_id])
    end
  end
end
```

SOC2 Compliance
--------------

### Overview

SOC2 (Service Organization Control 2) is a framework for managing customer data based on five trust service criteria. RAAF's SOC2 compliance module provides:

* **Security** controls and monitoring
* **Availability** monitoring and alerting
* **Processing integrity** validation
* **Confidentiality** protection
* **Privacy** controls

### SOC2 Setup

```ruby
require 'raaf/compliance/soc2'

# Configure SOC2 compliance
soc2_config = RAAF::Compliance::SOC2::Config.new(
  trust_service_criteria: [:security, :availability, :processing_integrity, :confidentiality, :privacy],
  continuous_monitoring: true,
  incident_response_enabled: true,
  change_management_enabled: true
)

# Create SOC2-compliant agent
agent = RAAF::Agent.new(
  name: "BusinessAgent",
  instructions: "Provide business services with SOC2 compliance",
  model: "gpt-4o"
)

# Add SOC2 compliance
compliance_manager = RAAF::Compliance::SOC2::Manager.new(soc2_config)
agent.add_compliance(compliance_manager)
```

### Security Controls

Implement SOC2 security controls:

```ruby
class SOC2SecurityControls
  def initialize
    @security_monitor = RAAF::Compliance::SOC2::SecurityMonitor.new
    @access_control = RAAF::Compliance::SOC2::AccessControl.new
    @encryption_service = RAAF::Compliance::SOC2::EncryptionService.new
  end
  
  def enforce_security_controls(request)
    # Authentication
    auth_result = authenticate_user(request)
    return auth_result unless auth_result[:success]
    
    # Authorization
    authz_result = authorize_access(request)
    return authz_result unless authz_result[:success]
    
    # Encrypt sensitive data
    encrypted_data = @encryption_service.encrypt(request[:data])
    
    # Monitor security events
    @security_monitor.log_access(
      user_id: request[:user_id],
      action: request[:action],
      resource: request[:resource],
      timestamp: Time.current
    )
    
    { success: true, data: encrypted_data }
  end
  
  private
  
  def authenticate_user(request)
    # Multi-factor authentication
    mfa_result = verify_mfa(request[:user_id], request[:mfa_token])
    return { success: false, error: "MFA verification failed" } unless mfa_result
    
    # Session validation
    session_valid = validate_session(request[:session_id])
    return { success: false, error: "Invalid session" } unless session_valid
    
    { success: true }
  end
  
  def authorize_access(request)
    @access_control.authorize(
      user_id: request[:user_id],
      action: request[:action],
      resource: request[:resource]
    )
  end
end
```

### Availability Monitoring

Implement availability monitoring:

```ruby
class SOC2AvailabilityMonitor
  def initialize
    @alert_service = RAAF::Compliance::SOC2::AlertService.new
    @metrics_collector = RAAF::Compliance::SOC2::MetricsCollector.new
  end
  
  def monitor_availability
    Thread.new do
      loop do
        check_system_health
        sleep(30) # Check every 30 seconds
      end
    end
  end
  
  private
  
  def check_system_health
    health_checks = {
      database: check_database_health,
      redis: check_redis_health,
      ai_providers: check_ai_providers_health,
      application: check_application_health
    }
    
    overall_health = health_checks.values.all? { |status| status[:healthy] }
    
    # Record metrics
    @metrics_collector.record_availability(
      overall_health: overall_health,
      component_health: health_checks,
      timestamp: Time.current
    )
    
    # Alert if unhealthy
    unless overall_health
      @alert_service.send_availability_alert(health_checks)
    end
    
    # Calculate uptime
    calculate_uptime(overall_health)
  end
  
  def check_database_health
    start_time = Time.current
    
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      response_time = Time.current - start_time
      
      {
        healthy: response_time < 1.0,
        response_time: response_time,
        status: "operational"
      }
    rescue => e
      {
        healthy: false,
        error: e.message,
        status: "error"
      }
    end
  end
  
  def calculate_uptime(current_health)
    uptime_calculator = RAAF::Compliance::SOC2::UptimeCalculator.new
    
    uptime_calculator.record_status(
      healthy: current_health,
      timestamp: Time.current
    )
    
    current_uptime = uptime_calculator.calculate_uptime(period: 30.days)
    
    # SOC2 requires 99.9% uptime
    if current_uptime < 0.999
      @alert_service.send_uptime_alert(current_uptime)
    end
  end
end
```

### Change Management

Implement change management controls:

```ruby
class SOC2ChangeManagement
  def initialize
    @change_log = RAAF::Compliance::SOC2::ChangeLog.new
    @approval_service = RAAF::Compliance::SOC2::ApprovalService.new
  end
  
  def process_change_request(change_request)
    # Validate change request
    validation_result = validate_change_request(change_request)
    return validation_result unless validation_result[:valid]
    
    # Require approval for high-risk changes
    if high_risk_change?(change_request)
      approval_result = @approval_service.request_approval(change_request)
      return approval_result unless approval_result[:approved]
    end
    
    # Log change
    @change_log.log_change(
      id: SecureRandom.uuid,
      type: change_request[:type],
      description: change_request[:description],
      requested_by: change_request[:user_id],
      approved_by: change_request[:approved_by],
      scheduled_at: change_request[:scheduled_at],
      status: "approved"
    )
    
    { success: true, change_id: change_request[:id] }
  end
  
  def implement_change(change_id)
    change = @change_log.find(change_id)
    
    begin
      # Create rollback point
      rollback_point = create_rollback_point(change)
      
      # Implement change
      implementation_result = execute_change(change)
      
      # Verify change
      verification_result = verify_change(change)
      
      if verification_result[:success]
        @change_log.update_status(change_id, "completed")
        { success: true, message: "Change implemented successfully" }
      else
        # Rollback on failure
        rollback_result = rollback_change(rollback_point)
        @change_log.update_status(change_id, "failed")
        { success: false, error: "Change failed, rolled back" }
      end
    rescue => e
      @change_log.update_status(change_id, "failed")
      { success: false, error: e.message }
    end
  end
  
  private
  
  def high_risk_change?(change_request)
    high_risk_types = [
      "security_configuration",
      "access_control_modification",
      "data_processing_change",
      "encryption_key_rotation"
    ]
    
    high_risk_types.include?(change_request[:type])
  end
end
```

Compliance Reporting
-------------------

### Automated Compliance Reports

Generate compliance reports automatically:

```ruby
class ComplianceReporter
  def initialize
    @gdpr_reporter = RAAF::Compliance::GDPR::Reporter.new
    @hipaa_reporter = RAAF::Compliance::HIPAA::Reporter.new
    @soc2_reporter = RAAF::Compliance::SOC2::Reporter.new
  end
  
  def generate_compliance_report(framework, period)
    case framework
    when :gdpr
      @gdpr_reporter.generate_report(period)
    when :hipaa
      @hipaa_reporter.generate_report(period)
    when :soc2
      @soc2_reporter.generate_report(period)
    when :all
      {
        gdpr: @gdpr_reporter.generate_report(period),
        hipaa: @hipaa_reporter.generate_report(period),
        soc2: @soc2_reporter.generate_report(period)
      }
    end
  end
  
  def schedule_automated_reports
    # Daily operational reports
    Cron.new("0 6 * * *") do
      daily_report = generate_compliance_report(:all, 1.day)
      send_to_compliance_team(daily_report)
    end
    
    # Weekly summary reports
    Cron.new("0 8 * * 1") do
      weekly_report = generate_compliance_report(:all, 1.week)
      send_to_management(weekly_report)
    end
    
    # Monthly audit reports
    Cron.new("0 9 1 * *") do
      monthly_report = generate_compliance_report(:all, 1.month)
      send_to_auditors(monthly_report)
    end
  end
end
```

### Audit Trail Management

Implement comprehensive audit trails:

```ruby
class AuditTrailManager
  def initialize
    @audit_store = RAAF::Compliance::AuditStore.new
    @encryption_service = RAAF::Compliance::EncryptionService.new
  end
  
  def log_event(event_type, details)
    audit_entry = {
      id: SecureRandom.uuid,
      event_type: event_type,
      timestamp: Time.current,
      user_id: details[:user_id],
      session_id: details[:session_id],
      action: details[:action],
      resource: details[:resource],
      result: details[:result],
      ip_address: details[:ip_address],
      user_agent: details[:user_agent],
      encrypted_details: @encryption_service.encrypt(details.to_json)
    }
    
    @audit_store.store(audit_entry)
    
    # Real-time compliance monitoring
    check_compliance_violations(audit_entry)
  end
  
  def query_audit_trail(filters = {})
    results = @audit_store.query(filters)
    
    # Decrypt details if authorized
    if authorized_for_audit_access?
      results.each do |entry|
        entry[:details] = JSON.parse(
          @encryption_service.decrypt(entry[:encrypted_details])
        )
      end
    end
    
    results
  end
  
  private
  
  def check_compliance_violations(audit_entry)
    # Check for unusual patterns
    if unusual_activity?(audit_entry)
      alert_compliance_team(audit_entry)
    end
    
    # Check for policy violations
    if policy_violation?(audit_entry)
      alert_security_team(audit_entry)
    end
  end
end
```

Integration with RAAF Agents
---------------------------

### Complete Compliance Integration

Here's how to integrate all compliance frameworks with your RAAF agents:

```ruby
class EnterpriseComplianceAgent
  def initialize
    # Create base agent
    @agent = RAAF::Agent.new(
      name: "ComplianceAgent",
      instructions: "Provide services while maintaining full compliance",
      model: "gpt-4o"
    )
    
    # Add compliance managers
    setup_compliance_frameworks
    
    # Add compliance-aware guardrails
    setup_compliance_guardrails
    
    # Configure audit trail
    setup_audit_trail
  end
  
  def process_request(input, user_context)
    # Check compliance requirements
    compliance_check = check_compliance_requirements(user_context)
    return compliance_check unless compliance_check[:compliant]
    
    # Process with full compliance
    result = @agent.run(input)
    
    # Log for audit trail
    log_compliance_event(input, result, user_context)
    
    result
  end
  
  private
  
  def setup_compliance_frameworks
    # GDPR compliance
    @gdpr_manager = RAAF::Compliance::GDPR::Manager.new(
      data_retention_period: 2.years,
      consent_required: true,
      anonymization_enabled: true
    )
    
    # HIPAA compliance
    @hipaa_manager = RAAF::Compliance::HIPAA::Manager.new(
      phi_detection_enabled: true,
      encryption_required: true,
      access_control_enabled: true
    )
    
    # SOC2 compliance
    @soc2_manager = RAAF::Compliance::SOC2::Manager.new(
      trust_service_criteria: [:security, :availability, :processing_integrity],
      continuous_monitoring: true
    )
    
    # Add all to agent
    @agent.add_compliance(@gdpr_manager)
    @agent.add_compliance(@hipaa_manager)
    @agent.add_compliance(@soc2_manager)
  end
  
  def setup_compliance_guardrails
    guardrails = [
      RAAF::Compliance::GDPR::DataMinimizationGuardrail.new,
      RAAF::Compliance::HIPAA::PHIDetectionGuardrail.new,
      RAAF::Compliance::SOC2::SecurityGuardrail.new
    ]
    
    @agent.guardrails = RAAF::ParallelGuardrails.new(guardrails)
  end
  
  def setup_audit_trail
    @audit_trail = RAAF::Compliance::AuditTrailManager.new
    
    # Log all agent interactions
    @agent.on_interaction do |interaction|
      @audit_trail.log_event("agent_interaction", interaction)
    end
  end
end
```

This comprehensive compliance guide provides the foundation for building enterprise-grade AI systems that meet regulatory requirements while maintaining functionality and performance.