# RAAF Compliance

[![Gem Version](https://badge.fury.io/rb/raaf-compliance.svg)](https://badge.fury.io/rb/raaf-compliance)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Compliance** gem provides comprehensive regulatory compliance features for the Ruby AI Agents Factory (RAAF) ecosystem. This gem ensures AI agents meet enterprise compliance requirements including GDPR, HIPAA, SOC2, and other regulatory standards with automated monitoring, audit trails, and policy enforcement.

## Overview

RAAF (Ruby AI Agents Factory) Compliance extends the core compliance capabilities from `raaf-core` to provide enterprise-grade regulatory compliance for AI agents. This gem offers comprehensive protection against compliance violations, automated policy enforcement, audit trail generation, and integration with enterprise compliance systems.

The compliance system operates across all agent interactions, providing real-time compliance validation, automated remediation capabilities, and detailed audit logging for regulatory requirements.

## Features

- **GDPR Compliance** - Data protection regulation compliance with consent management and data subject rights
- **HIPAA Compliance** - Healthcare data protection with PHI detection and security controls
- **SOC2 Compliance** - Security, availability, processing integrity, confidentiality, and privacy controls
- **ISO 27001 Integration** - Information security management system compliance
- **Automated Audit Trails** - Complete audit trail generation for all compliance activities
- **Policy Enforcement** - Automated enforcement of compliance policies and procedures
- **Data Retention Management** - Automated data lifecycle management and retention policies
- **Consent Management** - Comprehensive consent tracking and management system
- **Incident Response** - Automated incident detection and response workflows
- **Compliance Reporting** - Automated generation of compliance reports and dashboards
- **Risk Assessment** - Continuous risk assessment and mitigation recommendations
- **Enterprise Integration** - Support for enterprise compliance and GRC systems

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-compliance'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install raaf-compliance
```

## Quick Start

### Basic Compliance Setup

```ruby
require 'raaf-compliance'

# Configure global compliance settings
RubyAIAgentsFactory::Compliance.configure do |config|
  config.gdpr_enabled = true
  config.hipaa_enabled = true
  config.soc2_enabled = true
  config.audit_logging = true
  config.policy_enforcement = :strict
end

# Create a compliance manager
compliance_manager = RubyAIAgentsFactory::Compliance::Manager.new

# Create agent with compliance
agent = RubyAIAgentsFactory::Agent.new(
  name: "ComplianceAgent",
  instructions: "You are a compliant assistant that follows all regulatory requirements",
  compliance: compliance_manager
)

# All interactions are automatically compliance-checked
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("Can you help me with patient data?")
```

### GDPR Compliance

```ruby
require 'raaf-compliance'

# Create GDPR compliance manager
gdpr_manager = RubyAIAgentsFactory::Compliance::GDPRCompliance.new(
  data_controller: "YourCompany Ltd",
  privacy_policy_url: "https://yourcompany.com/privacy",
  consent_required: true,
  data_retention_days: 2555 # 7 years
)

# Configure data subject rights
gdpr_manager.configure_data_subject_rights(
  right_to_access: true,
  right_to_rectification: true,
  right_to_erasure: true,
  right_to_portability: true,
  right_to_object: true
)

# Check GDPR compliance
compliance_result = gdpr_manager.check_compliance({
  user_id: "user123",
  data_type: "personal_data",
  processing_purpose: "customer_support",
  consent_status: "granted"
})

if compliance_result.compliant?
  puts "GDPR compliant processing"
else
  puts "GDPR violation: #{compliance_result.violations.join(', ')}"
end
```

### HIPAA Compliance

```ruby
require 'raaf-compliance'

# Create HIPAA compliance manager
hipaa_manager = RubyAIAgentsFactory::Compliance::HIPAACompliance.new(
  covered_entity: "Healthcare Provider Inc",
  business_associate: false,
  minimum_necessary: true,
  access_controls: :strict
)

# Configure PHI protection
hipaa_manager.configure_phi_protection(
  encryption_required: true,
  access_logging: true,
  audit_controls: true,
  integrity_controls: true
)

# Check HIPAA compliance
compliance_result = hipaa_manager.check_compliance({
  user_role: "healthcare_provider",
  data_type: "phi",
  access_purpose: "treatment",
  patient_consent: "explicit"
})

if compliance_result.compliant?
  puts "HIPAA compliant access"
else
  puts "HIPAA violation: #{compliance_result.violations.join(', ')}"
end
```

### SOC2 Compliance

```ruby
require 'raaf-compliance'

# Create SOC2 compliance manager
soc2_manager = RubyAIAgentsFactory::Compliance::SOC2Compliance.new(
  trust_service_criteria: [:security, :availability, :confidentiality],
  control_environment: :enterprise,
  monitoring_enabled: true
)

# Configure security controls
soc2_manager.configure_security_controls(
  access_controls: true,
  logical_access: true,
  system_operations: true,
  change_management: true,
  risk_mitigation: true
)

# Check SOC2 compliance
compliance_result = soc2_manager.check_compliance({
  user_access: "authorized",
  data_classification: "confidential",
  system_availability: "high",
  change_approval: "required"
})

if compliance_result.compliant?
  puts "SOC2 compliant operation"
else
  puts "SOC2 violation: #{compliance_result.violations.join(', ')}"
end
```

## Configuration

### Global Configuration

```ruby
RubyAIAgentsFactory::Compliance.configure do |config|
  # Compliance frameworks
  config.gdpr_enabled = true
  config.hipaa_enabled = true
  config.soc2_enabled = true
  config.iso27001_enabled = true
  config.ccpa_enabled = true

  # Audit and logging
  config.audit_logging = true
  config.compliance_reporting = true
  config.incident_tracking = true
  config.risk_assessment = true

  # Policy enforcement
  config.policy_enforcement = :strict  # :strict, :moderate, :lenient
  config.auto_remediation = true
  config.violation_alerts = true
  
  # Data protection
  config.data_encryption = true
  config.data_retention_enabled = true
  config.consent_management = true
  config.data_subject_rights = true

  # Integration settings
  config.grc_integration = true
  config.compliance_dashboard = true
  config.automated_reporting = true
end
```

### Environment Variables

```bash
# Compliance configuration
export RAAF_COMPLIANCE_GDPR_ENABLED="true"
export RAAF_COMPLIANCE_HIPAA_ENABLED="true"
export RAAF_COMPLIANCE_SOC2_ENABLED="true"
export RAAF_COMPLIANCE_AUDIT_LOGGING="true"
export RAAF_COMPLIANCE_POLICY_ENFORCEMENT="strict"

# Data protection settings
export RAAF_COMPLIANCE_DATA_ENCRYPTION="true"
export RAAF_COMPLIANCE_DATA_RETENTION_DAYS="2555"
export RAAF_COMPLIANCE_CONSENT_REQUIRED="true"

# Integration settings
export RAAF_COMPLIANCE_GRC_ENDPOINT="https://your-grc-system.com/api"
export RAAF_COMPLIANCE_REPORTING_ENABLED="true"
```

## Compliance Frameworks

### GDPR (General Data Protection Regulation)

Comprehensive GDPR compliance with automated data protection:

```ruby
# GDPR compliance manager
gdpr = RubyAIAgentsFactory::Compliance::GDPRCompliance.new(
  data_controller: "Your Company",
  privacy_policy_url: "https://company.com/privacy",
  consent_required: true,
  lawful_basis: "consent"
)

# Configure data processing
gdpr.configure_data_processing(
  purpose_limitation: true,
  data_minimization: true,
  accuracy_requirement: true,
  storage_limitation: true,
  integrity_confidentiality: true
)

# Handle data subject requests
gdpr.handle_data_subject_request(
  type: :right_to_access,
  subject_id: "user123",
  request_details: "Request all personal data"
)

# Generate GDPR report
report = gdpr.generate_compliance_report(
  period: "2024-01-01".."2024-12-31",
  include_breaches: true,
  include_requests: true
)
```

**Supported GDPR Features:**
- **Data Subject Rights**: Access, rectification, erasure, portability, objection
- **Consent Management**: Granular consent tracking and withdrawal
- **Lawful Basis**: Support for all six lawful bases for processing
- **Data Protection Impact Assessment**: Automated DPIA workflows
- **Breach Notification**: Automated breach detection and reporting
- **Privacy by Design**: Built-in privacy controls and safeguards

### HIPAA (Health Insurance Portability and Accountability Act)

Healthcare-specific compliance with PHI protection:

```ruby
# HIPAA compliance manager
hipaa = RubyAIAgentsFactory::Compliance::HIPAACompliance.new(
  covered_entity: "Healthcare Provider",
  business_associate: false,
  minimum_necessary: true
)

# Configure safeguards
hipaa.configure_safeguards(
  administrative_safeguards: true,
  physical_safeguards: true,
  technical_safeguards: true
)

# Handle PHI access
hipaa.handle_phi_access(
  user_id: "provider123",
  patient_id: "patient456",
  access_purpose: "treatment",
  minimum_necessary: true
)

# Generate HIPAA audit report
report = hipaa.generate_audit_report(
  period: "2024-01-01".."2024-12-31",
  include_access_logs: true,
  include_violations: true
)
```

**Supported HIPAA Features:**
- **PHI Protection**: Automatic PHI detection and protection
- **Access Controls**: Role-based access control for PHI
- **Audit Controls**: Comprehensive audit logging
- **Integrity Controls**: Data integrity verification
- **Transmission Security**: Secure PHI transmission
- **Business Associate Agreements**: BAA compliance tracking

### SOC2 (Service Organization Control 2)

Security and availability controls for service organizations:

```ruby
# SOC2 compliance manager
soc2 = RubyAIAgentsFactory::Compliance::SOC2Compliance.new(
  trust_service_criteria: [:security, :availability, :confidentiality],
  control_environment: :enterprise
)

# Configure common criteria
soc2.configure_common_criteria(
  control_environment: true,
  communication_information: true,
  risk_assessment: true,
  monitoring_activities: true,
  control_activities: true
)

# Monitor system availability
soc2.monitor_availability(
  service_level_objectives: 99.9,
  uptime_tracking: true,
  incident_response: true
)

# Generate SOC2 report
report = soc2.generate_soc2_report(
  type: :type_ii,
  period: "2024-01-01".."2024-12-31",
  include_testing: true
)
```

**Supported SOC2 Features:**
- **Security**: Logical access controls, system operations
- **Availability**: System uptime, capacity planning
- **Processing Integrity**: Data processing accuracy
- **Confidentiality**: Data classification and protection
- **Privacy**: Personal information protection

## Advanced Features

### Automated Audit Trails

Comprehensive audit trail generation for all compliance activities:

```ruby
# Configure audit trail
audit_trail = RubyAIAgentsFactory::Compliance::AuditTrail.new(
  retention_period: 7.years,
  tamper_proof: true,
  encryption_enabled: true
)

# Track compliance events
audit_trail.track_event(
  event_type: "data_access",
  user_id: "user123",
  resource: "patient_data",
  action: "view",
  compliance_framework: "hipaa"
)

# Generate audit report
report = audit_trail.generate_report(
  period: "2024-01-01".."2024-12-31",
  frameworks: ["gdpr", "hipaa", "soc2"],
  format: :json
)
```

### Policy Enforcement

Automated enforcement of compliance policies:

```ruby
# Define compliance policies
policy_engine = RubyAIAgentsFactory::Compliance::PolicyEngine.new

# GDPR consent policy
policy_engine.define_policy(
  name: "gdpr_consent_required",
  framework: "gdpr",
  condition: -> (context) { context[:data_type] == "personal_data" },
  action: -> (context) { 
    unless context[:consent_status] == "granted"
      raise RubyAIAgentsFactory::Compliance::ConsentRequiredError
    end
  }
)

# HIPAA minimum necessary policy
policy_engine.define_policy(
  name: "hipaa_minimum_necessary",
  framework: "hipaa",
  condition: -> (context) { context[:data_type] == "phi" },
  action: -> (context) {
    unless context[:access_justification].present?
      raise RubyAIAgentsFactory::Compliance::MinimumNecessaryError
    end
  }
)

# Enforce policies
policy_engine.enforce_policies(context)
```

### Data Retention Management

Automated data lifecycle management:

```ruby
# Configure data retention
retention_manager = RubyAIAgentsFactory::Compliance::DataRetention.new(
  default_retention_period: 7.years,
  auto_deletion_enabled: true
)

# Define retention policies
retention_manager.define_policy(
  data_type: "personal_data",
  retention_period: 2555.days,  # 7 years
  deletion_method: :secure_wipe,
  compliance_framework: "gdpr"
)

retention_manager.define_policy(
  data_type: "phi",
  retention_period: 6.years,
  deletion_method: :cryptographic_erasure,
  compliance_framework: "hipaa"
)

# Process retention schedule
retention_manager.process_retention_schedule
```

### Consent Management

Comprehensive consent tracking and management:

```ruby
# Configure consent management
consent_manager = RubyAIAgentsFactory::Compliance::ConsentManager.new(
  granular_consent: true,
  consent_withdrawal: true,
  consent_history: true
)

# Record consent
consent_manager.record_consent(
  user_id: "user123",
  consent_type: "data_processing",
  consent_status: "granted",
  purpose: "customer_support",
  legal_basis: "consent",
  timestamp: Time.current
)

# Check consent status
consent_status = consent_manager.check_consent(
  user_id: "user123",
  purpose: "customer_support"
)

# Withdraw consent
consent_manager.withdraw_consent(
  user_id: "user123",
  consent_type: "data_processing",
  withdrawal_reason: "user_request"
)
```

## Agent Integration

### Basic Compliance Integration

```ruby
require 'raaf-core'
require 'raaf-compliance'

# Create compliance manager
compliance_manager = RubyAIAgentsFactory::Compliance::Manager.new(
  frameworks: [:gdpr, :hipaa, :soc2],
  policy_enforcement: :strict
)

# Create agent with compliance
agent = RubyAIAgentsFactory::Agent.new(
  name: "ComplianceAgent",
  instructions: "You are a compliant assistant",
  compliance: compliance_manager
)

# All interactions are automatically compliance-checked
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("Can you help me with personal data?")
```

### Multi-Framework Compliance

```ruby
# Configure multiple compliance frameworks
compliance_manager = RubyAIAgentsFactory::Compliance::Manager.new

# Add GDPR compliance
compliance_manager.add_framework(
  RubyAIAgentsFactory::Compliance::GDPRCompliance.new(
    data_controller: "Your Company",
    consent_required: true
  )
)

# Add HIPAA compliance
compliance_manager.add_framework(
  RubyAIAgentsFactory::Compliance::HIPAACompliance.new(
    covered_entity: "Healthcare Provider",
    minimum_necessary: true
  )
)

# Add SOC2 compliance
compliance_manager.add_framework(
  RubyAIAgentsFactory::Compliance::SOC2Compliance.new(
    trust_service_criteria: [:security, :availability]
  )
)

# Create compliant agent
agent = RubyAIAgentsFactory::Agent.new(
  name: "EnterpriseAgent",
  instructions: "You are an enterprise-compliant assistant",
  compliance: compliance_manager
)
```

## Monitoring and Reporting

### Compliance Dashboard

```ruby
# Configure compliance dashboard
dashboard = RubyAIAgentsFactory::Compliance::Dashboard.new(
  refresh_interval: 60.seconds,
  real_time_monitoring: true
)

# Get compliance metrics
metrics = dashboard.get_metrics(
  frameworks: [:gdpr, :hipaa, :soc2],
  period: "2024-01-01".."2024-12-31"
)

puts "Compliance Score: #{metrics[:overall_score]}%"
puts "Violations: #{metrics[:total_violations]}"
puts "Remediation Rate: #{metrics[:remediation_rate]}%"
```

### Automated Reporting

```ruby
# Configure automated reporting
reporter = RubyAIAgentsFactory::Compliance::Reporter.new(
  schedule: :monthly,
  recipients: ["compliance@company.com", "legal@company.com"]
)

# Generate compliance report
report = reporter.generate_report(
  frameworks: [:gdpr, :hipaa, :soc2],
  period: "2024-01-01".."2024-12-31",
  format: :pdf,
  include_remediation: true
)

# Schedule automated reports
reporter.schedule_report(
  type: :quarterly,
  frameworks: [:gdpr, :hipaa],
  delivery_method: :email
)
```

### Risk Assessment

```ruby
# Configure risk assessment
risk_assessor = RubyAIAgentsFactory::Compliance::RiskAssessment.new(
  assessment_frequency: :weekly,
  risk_tolerance: :low
)

# Perform risk assessment
assessment = risk_assessor.assess_risks(
  frameworks: [:gdpr, :hipaa, :soc2],
  include_recommendations: true
)

puts "Risk Level: #{assessment[:risk_level]}"
puts "Critical Issues: #{assessment[:critical_issues].count}"
puts "Recommendations: #{assessment[:recommendations].count}"
```

## Testing

### RSpec Integration

```ruby
require 'raaf-compliance/rspec'

RSpec.describe "Compliance Features" do
  let(:compliance_manager) { create_compliance_manager }
  let(:agent) { create_agent_with_compliance }
  
  it "enforces GDPR consent requirements" do
    result = agent.run("Process personal data", consent_status: "denied")
    expect(result).to be_blocked_by_compliance
    expect(result).to have_compliance_violation(:gdpr, :consent_required)
  end

  it "tracks HIPAA PHI access" do
    result = agent.run("Access patient data", user_role: "doctor")
    expect(result).to be_compliant
    expect(result).to have_audit_trail(:hipaa, :phi_access)
  end

  it "monitors SOC2 security controls" do
    result = agent.run("Access confidential data", security_level: "high")
    expect(result).to be_compliant
    expect(result).to have_security_controls(:soc2, :logical_access)
  end
end
```

### Test Helpers

```ruby
# Mock compliance responses for testing
RubyAIAgentsFactory::Compliance::TestHelpers.mock_compliance_check(
  framework: :gdpr,
  result: :compliant,
  audit_data: { consent_status: "granted" }
)

# Test with specific compliance frameworks
RubyAIAgentsFactory::Compliance::TestHelpers.with_compliance_frameworks(
  gdpr: true,
  hipaa: false,
  soc2: true
) do
  # Your test code here
end
```

## Relationship with Other RAAF Gems

### Core Dependencies

RAAF Compliance builds on and integrates with:

- **raaf-core** - Uses base agent classes and configuration system
- **raaf-logging** - Integrated audit logging and compliance reporting
- **raaf-guardrails** - Extends guardrails with compliance-specific validations

### Enterprise Integration

- **raaf-security** - Integrates with security controls and access management
- **raaf-tracing** - Traces compliance checks for audit and monitoring
- **raaf-rails** - Provides web interface for compliance management
- **raaf-analytics** - Analyzes compliance metrics and trends

### Tool Integration

- **raaf-tools-advanced** - Tools respect compliance requirements
- **raaf-memory** - Memory systems follow data retention policies
- **raaf-streaming** - Real-time compliance validation for streaming responses

## Architecture

### Core Components

```
RubyAIAgentsFactory::Compliance::
├── Manager                  # Main compliance orchestrator
├── GDPRCompliance          # GDPR-specific compliance
├── HIPAACompliance         # HIPAA-specific compliance
├── SOC2Compliance          # SOC2-specific compliance
├── AuditTrail              # Audit trail management
├── PolicyEngine            # Policy definition and enforcement
├── DataRetention           # Data lifecycle management
├── ConsentManager          # Consent tracking and management
├── Dashboard               # Compliance monitoring dashboard
├── Reporter                # Automated compliance reporting
└── RiskAssessment         # Continuous risk assessment
```

### Extension Points

The compliance system provides several extension points:

1. **Custom Compliance Frameworks** - Define new regulatory frameworks
2. **Policy Definitions** - Create custom compliance policies
3. **Audit Integrations** - Connect to external audit systems
4. **Reporting Extensions** - Custom compliance reports
5. **Risk Assessment Models** - Custom risk assessment algorithms

## Development

After checking out the repo, run:

```bash
bundle install
bundle exec rspec
```

### Adding New Compliance Frameworks

1. Create new framework class inheriting from `BaseCompliance`
2. Implement required methods: `check_compliance(context)`
3. Add comprehensive tests
4. Update documentation

```ruby
class MyCustomCompliance < RubyAIAgentsFactory::Compliance::BaseCompliance
  def check_compliance(context)
    # Your compliance validation logic here
    ComplianceResult.new(
      compliant: validation_passed?,
      violations: detected_violations,
      audit_data: compliance_audit_data
    )
  end
end
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for your changes
5. Ensure all tests pass (`bundle exec rspec`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).