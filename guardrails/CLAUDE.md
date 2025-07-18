# RAAF Guardrails - Claude Code Guide

This gem provides security and safety guardrails for RAAF agents, including PII detection, content filtering, and security scanning.

## Quick Start

```ruby
require 'raaf-guardrails'

# Create agent with guardrails
agent = RAAF::Agent.new(
  name: "SecureAgent",
  instructions: "You are a helpful but secure assistant",
  model: "gpt-4o"
)

# Add input guardrails
agent.add_input_guardrail(RAAF::Guardrails::PIIDetector.new)
agent.add_input_guardrail(RAAF::Guardrails::SecurityGuardrail.new)

# Add output guardrails
agent.add_output_guardrail(RAAF::Guardrails::ToxicityDetector.new)
agent.add_output_guardrail(RAAF::Guardrails::Tripwire.new)
```

## Core Components

- **PIIDetector** - Detects and masks personally identifiable information
- **SecurityGuardrail** - Prevents malicious input and injection attacks
- **ToxicityDetector** - Filters harmful or inappropriate content
- **Tripwire** - Custom rule-based content monitoring
- **Validator** - Schema and format validation

## Input Guardrails

### PII Detection
```ruby
pii_detector = RAAF::Guardrails::PIIDetector.new do |config|
  config.detect_email = true
  config.detect_phone = true
  config.detect_ssn = true
  config.detect_credit_card = true
  config.mask_detected = true
  config.replacement_text = "[REDACTED]"
end

agent.add_input_guardrail(pii_detector)

# Input: "My email is john@example.com"
# Processed: "My email is [REDACTED]"
```

### Security Scanning
```ruby
security_guardrail = RAAF::Guardrails::SecurityGuardrail.new do |config|
  config.block_sql_injection = true
  config.block_xss_attempts = true
  config.block_command_injection = true
  config.max_input_length = 10000
  config.scan_for_malware_urls = true
end

agent.add_input_guardrail(security_guardrail)
```

### Custom Input Validation
```ruby
custom_validator = RAAF::Guardrails::Validator.new do |config|
  config.max_length = 5000
  config.allowed_languages = ["en", "es", "fr"]
  config.blocked_domains = ["malicious-site.com"]
  config.required_fields = [:message, :user_id]
end

agent.add_input_guardrail(custom_validator)
```

## Output Guardrails

### Toxicity Detection
```ruby
toxicity_detector = RAAF::Guardrails::ToxicityDetector.new do |config|
  config.threshold = 0.7
  config.categories = [:hate_speech, :violence, :sexual_content]
  config.action_on_detection = :block  # :block, :warn, :log
end

agent.add_output_guardrail(toxicity_detector)
```

### Tripwire Monitoring
```ruby
tripwire = RAAF::Guardrails::Tripwire.new do |config|
  # Block specific keywords
  config.blocked_keywords = ["password", "secret", "confidential"]
  
  # Pattern matching
  config.blocked_patterns = [
    /\b\d{4}-\d{4}-\d{4}-\d{4}\b/,  # Credit card numbers
    /\b[A-Z]{2}\d{2}\s?\d{4}\s?\d{6}\b/  # Bank account format
  ]
  
  # Custom rules
  config.custom_rules = [
    {
      name: "no_personal_info",
      pattern: /(?:my|our)\s+(address|phone|email)/i,
      action: :redact
    }
  ]
end

agent.add_output_guardrail(tripwire)
```

## Parallel Processing

```ruby
# Process multiple guardrails in parallel for performance
parallel_guardrails = RAAF::Guardrails::ParallelGuardrails.new([
  RAAF::Guardrails::PIIDetector.new,
  RAAF::Guardrails::SecurityGuardrail.new,
  RAAF::Guardrails::ToxicityDetector.new
])

agent.add_input_guardrail(parallel_guardrails)
```

## Custom Guardrails

```ruby
class CustomDataGuardrail < RAAF::Guardrails::BaseGuardrail
  def process(content, context = {})
    # Custom logic
    if content.include?("proprietary")
      return {
        allowed: false,
        reason: "Contains proprietary information",
        modified_content: content.gsub("proprietary", "[CLASSIFIED]")
      }
    end
    
    { allowed: true, modified_content: content }
  end
end

agent.add_output_guardrail(CustomDataGuardrail.new)
```

## Configuration Patterns

### Environment-based Config
```ruby
# Development - permissive
if Rails.env.development?
  agent.add_input_guardrail(
    RAAF::Guardrails::PIIDetector.new(mask_detected: false)
  )
end

# Production - strict
if Rails.env.production?
  agent.add_input_guardrail(
    RAAF::Guardrails::PIIDetector.new(mask_detected: true)
  )
  agent.add_output_guardrail(
    RAAF::Guardrails::ToxicityDetector.new(threshold: 0.5)
  )
end
```

### Role-based Guardrails
```ruby
class AdminAgent < RAAF::Agent
  def initialize(*)
    super
    # Admins get relaxed guardrails
    add_input_guardrail(basic_security_only)
  end
end

class PublicAgent < RAAF::Agent
  def initialize(*)
    super
    # Public agents get strict guardrails
    add_input_guardrail(strict_pii_detection)
    add_output_guardrail(strict_content_filter)
  end
end
```

## Monitoring and Alerts

```ruby
# Set up guardrail monitoring
RAAF::Guardrails.configure do |config|
  config.log_violations = true
  config.alert_on_patterns = ["sql injection", "xss attempt"]
  config.webhook_url = "https://your-monitoring.com/alerts"
end

# Custom violation handler
RAAF::Guardrails.on_violation do |violation|
  SecurityLogger.warn(
    "Guardrail violation",
    type: violation.type,
    content: violation.sanitized_content,
    user_id: violation.context[:user_id]
  )
end
```

## Environment Variables

```bash
export RAAF_GUARDRAILS_ENABLED="true"
export RAAF_PII_DETECTION="strict"
export RAAF_TOXICITY_THRESHOLD="0.7"
export RAAF_SECURITY_ALERTS_WEBHOOK="https://alerts.example.com"
```