# Security Policy

## Table of Contents

- [Supported Versions](#supported-versions)
- [Reporting a Vulnerability](#reporting-a-vulnerability)
- [Security Best Practices](#security-best-practices)
- [API Key Security](#api-key-security)
- [Data Privacy](#data-privacy)
- [Guardrails and Safety](#guardrails-and-safety)
- [Secure Configuration](#secure-configuration)
- [Production Security](#production-security)
- [Security Updates](#security-updates)

## Supported Versions

We provide security updates for the following versions of RAAF (Ruby AI Agents Factory):

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |
| < 0.1   | :x:                |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please report it responsibly.

### How to Report

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, please report security vulnerabilities by emailing: **security@enterprisemodules.com**

Include the following information:
- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact assessment
- Suggested fix (if you have one)

### What to Expect

- **Acknowledgment**: We'll acknowledge receipt within 48 hours
- **Assessment**: We'll assess the vulnerability within 5 business days
- **Updates**: We'll provide regular updates on our progress
- **Resolution**: We'll work to resolve critical issues within 30 days
- **Credit**: We'll credit you in our security advisory (if desired)

### Responsible Disclosure

We follow a responsible disclosure policy:
1. **Report**: Submit vulnerability privately
2. **Assessment**: We evaluate and develop a fix
3. **Release**: We release a security patch
4. **Disclosure**: We publicly disclose after users can update

## Security Best Practices

### General Security Guidelines

When using RAAF (Ruby AI Agents Factory), follow these security best practices:

#### 1. API Key Management
```ruby
# ✅ Good: Use environment variables
RAAF::Configuration.new(
  openai_api_key: ENV['OPENAI_API_KEY']
)

# ❌ Bad: Hard-code API keys
RAAF::Configuration.new(
  openai_api_key: "sk-abc123..."  # Never do this!
)
```

#### 2. Input Validation
```ruby
# ✅ Good: Validate and sanitize inputs
guardrails = RAAF::Guardrails::GuardrailManager.new
guardrails.add_guardrail(
  RAAF::Guardrails::LengthGuardrail.new(
    max_input_length: 10000
  )
)
guardrails.validate_input(user_input)

# ❌ Bad: Accept any input without validation
agent.run(messages: [{ role: "user", content: untrusted_input }])
```

#### 3. Content Safety
```ruby
# ✅ Good: Enable content safety guardrails
guardrails.add_guardrail(
  RAAF::Guardrails::ContentSafetyGuardrail.new
)

# ✅ Good: Implement rate limiting
guardrails.add_guardrail(
  RAAF::Guardrails::RateLimitGuardrail.new(
    max_requests_per_minute: 60
  )
)
```

#### 4. Error Handling
```ruby
# ✅ Good: Handle errors securely
begin
  result = runner.run(messages)
rescue RAAF::Error => e
  logger.error("Agent error: #{e.class}")  # Don't log sensitive details
  # Return generic error to user
end

# ❌ Bad: Expose internal details
rescue => e
  puts "Error: #{e.message}"  # May contain sensitive information
end
```

## API Key Security

### Storage and Management

#### Environment Variables
```bash
# ✅ Production: Use secure environment variables
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GEMINI_API_KEY="..."
```

#### Key Rotation
- Rotate API keys regularly (every 90 days recommended)
- Use different keys for different environments
- Monitor API key usage for anomalies
- Revoke compromised keys immediately

#### Key Permissions
- Use keys with minimal required permissions
- Implement usage limits and monitoring
- Set up alerts for unusual activity
- Use separate keys for different applications

### Configuration Security

#### Secure defaults
```ruby
# ✅ Good: Secure configuration
config = RAAF::Configuration.new(environment: "production")
config.set("guardrails.content_safety.enabled", true)
config.set("guardrails.rate_limiting.enabled", true)
config.set("logging.level", "info")  # Don't log debug info in production
config.set("tracing.enabled", true)
```

#### Environment-specific settings
```yaml
# config/openai_agents.production.yml
environment: production

openai:
  api_key: <%= ENV['OPENAI_API_KEY'] %>  # Use environment variables
  timeout: 30
  max_retries: 3

guardrails:
  content_safety:
    enabled: true
    strict_mode: true
  rate_limiting:
    enabled: true
    max_requests_per_minute: 120

logging:
  level: "info"  # Don't log sensitive debug info
  sanitize_logs: true  # Remove sensitive data from logs
```

## Data Privacy

### Personal Data Handling

#### Data Minimization
- Only collect and process necessary data
- Implement data retention policies
- Use data anonymization when possible
- Provide user data deletion capabilities

#### Compliance Considerations
- **GDPR**: Implement data subject rights
- **CCPA**: Provide data transparency and control
- **HIPAA**: Use appropriate safeguards for health data
- **SOX**: Maintain audit trails for financial data

#### Data Processing
```ruby
# ✅ Good: Sanitize sensitive data before processing
def sanitize_input(input)
  # Remove or mask sensitive patterns
  input.gsub(/\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/, '[CARD]')
       .gsub(/\b\d{3}-\d{2}-\d{4}\b/, '[SSN]')
       .gsub(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, '[EMAIL]')
end

sanitized_input = sanitize_input(user_input)
result = agent.run(messages: [{ role: "user", content: sanitized_input }])
```

### Logging and Monitoring

#### Secure Logging
```ruby
# ✅ Good: Sanitize logs
logger.info("User request processed", {
  user_id: user.id,                    # OK to log
  session_id: session.id,              # OK to log
  # request_content: request.content   # Don't log sensitive content
})

# ❌ Bad: Log sensitive information
logger.debug("Full request: #{request.to_json}")  # May contain secrets
```

#### Audit Trails
- Log all significant actions
- Include timestamps and user identification
- Monitor for suspicious activity
- Retain logs according to compliance requirements

## Guardrails and Safety

### Content Safety Implementation

#### Multi-layered Protection
```ruby
# Comprehensive safety setup
guardrails = RAAF::Guardrails::GuardrailManager.new

# Layer 1: Content safety
guardrails.add_guardrail(
  RAAF::Guardrails::ContentSafetyGuardrail.new(
    strict_mode: true,
    block_categories: [:hate, :violence, :self_harm, :sexual]
  )
)

# Layer 2: Input validation
guardrails.add_guardrail(
  RAAF::Guardrails::LengthGuardrail.new(
    max_input_length: 50000,
    max_output_length: 10000
  )
)

# Layer 3: Rate limiting
guardrails.add_guardrail(
  RAAF::Guardrails::RateLimitGuardrail.new(
    max_requests_per_minute: 60,
    max_requests_per_hour: 1000
  )
)

# Layer 4: Schema validation
user_schema = {
  type: "object",
  properties: {
    query: { type: "string", maxLength: 1000 },
    user_id: { type: "string", pattern: "^[a-zA-Z0-9_-]+$" }
  },
  required: ["query"],
  additionalProperties: false
}

guardrails.add_guardrail(
  RAAF::Guardrails::SchemaGuardrail.new(
    input_schema: user_schema
  )
)
```

### Custom Safety Rules

#### Business Logic Validation
```ruby
# Custom guardrail for business rules
class BusinessRuleGuardrail < RAAF::Guardrails::BaseGuardrail
  def validate_input(input)
    # Implement custom business validation
    if input[:amount] && input[:amount] > 10000
      raise RAAF::Guardrails::GuardrailError,
            "Amount exceeds maximum allowed"
    end
  end
  
  def validate_output(output)
    # Validate agent responses
    if output.include?("confidential") || output.include?("internal")
      raise RAAF::Guardrails::GuardrailError,
            "Output contains restricted information"
    end
  end
end

guardrails.add_guardrail(BusinessRuleGuardrail.new)
```

## Secure Configuration

### Production Configuration

#### Environment Isolation
```ruby
# ✅ Good: Environment-specific configuration
class SecureConfiguration
  def self.load(environment)
    config = RAAF::Configuration.new(environment: environment)
    
    case environment
    when "production"
      configure_production(config)
    when "staging"
      configure_staging(config)
    when "development"
      configure_development(config)
    end
    
    config
  end
  
  private
  
  def self.configure_production(config)
    config.set("guardrails.content_safety.enabled", true)
    config.set("guardrails.rate_limiting.enabled", true)
    config.set("logging.level", "info")
    config.set("tracing.enabled", true)
    config.set("openai.timeout", 30)
    config.set("openai.max_retries", 3)
  end
end
```

#### Secrets Management
```ruby
# ✅ Good: Use secure secrets management
def load_secrets
  if Rails.env.production?
    # Use Rails credentials or external secrets manager
    {
      openai_api_key: Rails.application.credentials.openai_api_key,
      anthropic_api_key: Rails.application.credentials.anthropic_api_key
    }
  else
    # Use environment variables for development
    {
      openai_api_key: ENV['OPENAI_API_KEY'],
      anthropic_api_key: ENV['ANTHROPIC_API_KEY']
    }
  end
end
```

### Network Security

#### HTTPS Only
```ruby
# ✅ Good: Enforce HTTPS in production
config.set("api.use_ssl", true)
config.set("api.verify_ssl", true)
```

#### Request Timeouts
```ruby
# ✅ Good: Set appropriate timeouts
config.set("openai.timeout", 30)        # 30 second timeout
config.set("openai.max_retries", 3)     # Maximum 3 retries
config.set("openai.retry_delay", 1)     # 1 second between retries
```

## Production Security

### Deployment Security

#### Container Security
```dockerfile
# ✅ Good: Secure Dockerfile
FROM ruby:3.2-alpine

# Create non-root user
RUN addgroup -g 1001 -S appuser && \
    adduser -u 1001 -S appuser -G appuser

# Install dependencies as root
COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

# Copy application files
COPY . .
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Set secure environment
ENV RAILS_ENV=production
ENV BUNDLE_WITHOUT=development:test

CMD ["ruby", "app.rb"]
```

#### Runtime Security
```ruby
# ✅ Good: Production runtime security
class ProductionApp
  def initialize
    @config = SecureConfiguration.load("production")
    @guardrails = setup_guardrails
    @monitor = setup_monitoring
  end
  
  private
  
  def setup_guardrails
    guardrails = RAAF::Guardrails::GuardrailManager.new
    guardrails.add_guardrail(
      RAAF::Guardrails::ContentSafetyGuardrail.new
    )
    guardrails.add_guardrail(
      RAAF::Guardrails::RateLimitGuardrail.new(
        max_requests_per_minute: 300  # Production rate limit
      )
    )
    guardrails
  end
  
  def setup_monitoring
    tracker = RAAF::UsageTracking::UsageTracker.new
    
    # Set up security alerts
    tracker.add_alert(:suspicious_activity) do |usage|
      usage[:error_rate] > 0.1 || usage[:requests_per_minute] > 500
    end
    
    tracker.add_alert(:cost_anomaly) do |usage|
      usage[:cost_increase] > 2.0  # 100% cost increase
    end
    
    tracker
  end
end
```

### Monitoring and Alerting

#### Security Monitoring
```ruby
# Set up comprehensive security monitoring
tracker = RAAF::UsageTracking::UsageTracker.new

# Monitor for security events
tracker.add_alert(:security_breach) do |usage|
  usage[:failed_authentications] > 10 ||
  usage[:guardrail_violations] > 50 ||
  usage[:unusual_patterns] == true
end

# Monitor for abuse
tracker.add_alert(:potential_abuse) do |usage|
  usage[:requests_per_user] > 1000 ||
  usage[:repeated_violations] > 5
end

# Monitor system health
tracker.add_alert(:system_health) do |usage|
  usage[:error_rate] > 0.05 ||
  usage[:response_time_p99] > 10000  # 10 seconds
end
```

## Security Updates

### Update Policy

- **Critical**: Immediate patches for critical vulnerabilities
- **High**: Patches within 7 days for high-severity issues
- **Medium**: Patches in next minor release
- **Low**: Patches in next major release

### Staying Updated

1. **Watch releases**: Enable notifications for new releases
2. **Security advisories**: Subscribe to security announcements
3. **Dependency updates**: Regularly update dependencies
4. **Vulnerability scanning**: Use automated vulnerability scanners

### Emergency Response

In case of a security incident:

1. **Immediate**: Isolate affected systems
2. **Assess**: Determine scope and impact
3. **Contain**: Prevent further damage
4. **Notify**: Inform stakeholders if required
5. **Recover**: Restore normal operations
6. **Learn**: Document lessons learned

## Security Resources

### Tools and Services

- **Vulnerability Scanners**: Brakeman, bundler-audit
- **Secrets Detection**: GitLeaks, TruffleHog
- **Code Analysis**: CodeQL, SonarQube
- **Dependency Monitoring**: Dependabot, Snyk

### Security Guides

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Ruby Security Guide](https://guides.rubyonrails.org/security.html)
- [OpenAI Safety Best Practices](https://platform.openai.com/docs/guides/safety-best-practices)
- [AI Security Framework](https://www.nist.gov/itl/ai-risk-management-framework)

---

**Security is a shared responsibility. Together, we can build a more secure AI ecosystem.**

For security questions or concerns, please contact: **security@enterprisemodules.com**