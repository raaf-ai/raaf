# Guardrails Examples

This directory contains examples demonstrating safety and compliance features for RAAF (Ruby AI Agents Factory).

## Example Status

✅ = Working example  
⚠️ = Partial functionality (some features may require external setup)  

## Guardrails Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `guardrails_example.rb` | ✅ | Input/output guardrails and safety | Fully working |
| `pii_guardrail_example.rb` | ⚠️ | PII detection guardrails | Requires PII detection setup |
| `compliance_example.rb` | ⚠️ | Compliance and audit features | Requires compliance module setup |
| `security_scanning_example.rb` | ⚠️ | Security scanning integration | Requires security tools |
| `tripwire_guardrail_example.rb` | ⚠️ | Tripwire rules | Requires guardrail configuration |

## Running Examples

### Prerequisites

1. Set your OpenAI API key:
   ```bash
   export OPENAI_API_KEY="your-api-key"
   ```

2. Install required gems:
   ```bash
   bundle install
   ```

3. Optional: Configure external security services:
   ```bash
   export SECURITY_API_KEY="your-security-service-key"
   export COMPLIANCE_API_KEY="your-compliance-service-key"
   ```

### Running Guardrails Examples

```bash
# Basic guardrails
ruby guardrails/examples/guardrails_example.rb

# PII detection (requires setup)
ruby guardrails/examples/pii_guardrail_example.rb

# Compliance features (requires setup)
ruby guardrails/examples/compliance_example.rb

# Security scanning (requires setup)
ruby guardrails/examples/security_scanning_example.rb
```

## Guardrails Features

### Input Validation
- **Content filtering**: Block inappropriate input
- **PII detection**: Identify and handle sensitive data
- **Format validation**: Ensure input meets requirements
- **Injection prevention**: Protect against prompt injection

### Output Filtering
- **Content moderation**: Filter inappropriate responses
- **Sensitive data removal**: Strip PII from outputs
- **Format enforcement**: Ensure consistent output format
- **Quality validation**: Check response quality

### Security Features
- **Prompt injection detection**: Identify malicious prompts
- **Data leakage prevention**: Prevent sensitive information exposure
- **Rate limiting**: Control usage to prevent abuse
- **Audit logging**: Track all interactions for compliance

### Compliance
- **GDPR compliance**: Handle personal data appropriately
- **HIPAA compliance**: Protect health information
- **SOC 2 compliance**: Meet security standards
- **Custom policies**: Define organization-specific rules

## Configuration

### Basic Guardrails
```ruby
guardrails = RAAF::Guardrails::Manager.new
guardrails.add_rule(:input_filter, pattern: /sensitive_pattern/)
guardrails.add_rule(:output_filter, max_length: 1000)

agent = RAAF::Agent.new(
  name: "Safe Agent",
  instructions: "Be helpful and safe",
  guardrails: guardrails
)
```

### PII Detection
```ruby
pii_detector = RAAF::Guardrails::PIIDetector.new
guardrails.add_rule(:pii_detection, detector: pii_detector)
```

### Custom Rules
```ruby
class CustomRule
  def validate(input)
    # Your validation logic
    return { valid: true } if safe?(input)
    return { valid: false, reason: "Content not allowed" }
  end
end

guardrails.add_rule(:custom, CustomRule.new)
```

## Enterprise Features

### Audit Trail
- **Complete logging**: Record all inputs and outputs
- **Compliance reports**: Generate audit reports
- **Data retention**: Manage data lifecycle
- **Access controls**: Control who can access logs

### Policy Management
- **Central policies**: Define organization-wide rules
- **Role-based rules**: Different rules for different users
- **Dynamic policies**: Update rules without code changes
- **Policy testing**: Test rules before deployment

### Integration
- **SIEM integration**: Send security events to SIEM systems
- **Compliance dashboards**: Monitor compliance metrics
- **Alert systems**: Real-time security notifications
- **Workflow integration**: Connect to approval workflows

## Notes

- Basic guardrails work out of the box
- Advanced features may require external service integration
- Performance impact is minimal for most rules
- Custom rules can be added for specific requirements
- Check individual example files for detailed configuration options