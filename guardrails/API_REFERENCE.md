# Guardrails API Reference

Complete Ruby API documentation for RAAF Guardrails components.

## Table of Contents

1. [GuardrailManager](#guardrailmanager)
2. [Built-in Guardrails](#built-in-guardrails)
   - [ContentSafetyGuardrail](#contentsafetyguardrail)
   - [RateLimitGuardrail](#ratelimitguardrail)
   - [LengthGuardrail](#lengthguardrail)
   - [SchemaGuardrail](#schemaguardrail)
3. [Custom Guardrails](#custom-guardrails)
4. [Error Handling](#error-handling)
5. [Integration Examples](#integration-examples)

## GuardrailManager

Central guardrail management for agents.

### Constructor

```ruby
RAAF::Guardrails::GuardrailManager.new
```

### Guardrail Management

```ruby
# Add a guardrail
manager.add_guardrail(guardrail)

# Remove a guardrail by name
manager.remove_guardrail(name)

# Get all guardrails
manager.guardrails

# Check if a guardrail exists
manager.has_guardrail?(name)

# Clear all guardrails
manager.clear_guardrails
```

### Validation Methods

```ruby
# Validate input before processing
manager.validate_input(input)

# Validate output before returning
manager.validate_output(output)

# Validate tool call arguments
manager.validate_tool_call(tool_name, arguments)
```

### Example Usage

```ruby
# Create manager
manager = RAAF::Guardrails::GuardrailManager.new

# Add multiple guardrails
manager.add_guardrail(
  RAAF::Guardrails::ContentSafetyGuardrail.new
)
manager.add_guardrail(
  RAAF::Guardrails::RateLimitGuardrail.new(
    max_requests_per_minute: 60
  )
)

# Use with agent
agent = RAAF::Agent.new(
  name: "SafeAgent",
  guardrails: manager
)

# Or validate manually
begin
  manager.validate_input(user_input)
  # Process input...
rescue RAAF::Guardrails::GuardrailError => e
  puts "Input blocked: #{e.message}"
end
```

## Built-in Guardrails

### ContentSafetyGuardrail

Filters harmful, offensive, or inappropriate content.

```ruby
# Constructor
RAAF::Guardrails::ContentSafetyGuardrail.new(
  strict_mode: false,                  # Enable strict filtering
  block_categories: Array[Symbol],     # Categories to block
  custom_filters: Array[Proc],         # Custom filter functions
  allow_list: Array[String],           # Allowed terms/patterns
  block_list: Array[String]            # Additional blocked terms
)

# Categories
# :hate, :violence, :self_harm, :sexual, :profanity, 
# :illegal, :pii, :medical_advice
```

#### Example Usage

```ruby
# Basic content safety
safety = RAAF::Guardrails::ContentSafetyGuardrail.new

# Strict mode with specific categories
safety = RAAF::Guardrails::ContentSafetyGuardrail.new(
  strict_mode: true,
  block_categories: [:hate, :violence, :profanity],
  block_list: ["confidential", "secret", "password"]
)

# With custom filters
safety = RAAF::Guardrails::ContentSafetyGuardrail.new(
  custom_filters: [
    proc { |text| text.match?(/\b\d{3}-\d{2}-\d{4}\b/) }, # SSN
    proc { |text| text.match?(/\b\d{16}\b/) }             # Credit card
  ]
)

manager.add_guardrail(safety)
```

### RateLimitGuardrail

Enforces rate limits to prevent abuse.

```ruby
# Constructor
RAAF::Guardrails::RateLimitGuardrail.new(
  max_requests_per_minute: 60,         # Per-minute limit
  max_requests_per_hour: 1000,         # Per-hour limit
  max_requests_per_day: 10000,         # Per-day limit
  per_user: false,                     # Track per user
  storage: :memory                     # Storage backend (:memory, :redis)
)
```

#### Example Usage

```ruby
# Basic rate limiting
rate_limit = RAAF::Guardrails::RateLimitGuardrail.new(
  max_requests_per_minute: 60
)

# Tiered rate limiting
rate_limit = RAAF::Guardrails::RateLimitGuardrail.new(
  max_requests_per_minute: 60,
  max_requests_per_hour: 1000,
  max_requests_per_day: 10000
)

# Per-user rate limiting with Redis
rate_limit = RAAF::Guardrails::RateLimitGuardrail.new(
  max_requests_per_minute: 10,
  per_user: true,
  storage: :redis
)

# Check current usage
status = rate_limit.current_usage(user_id: "user123")
puts "Requests this minute: #{status[:minute]}"
puts "Requests remaining: #{status[:remaining]}"

manager.add_guardrail(rate_limit)
```

### LengthGuardrail

Enforces input/output length constraints.

```ruby
# Constructor
RAAF::Guardrails::LengthGuardrail.new(
  max_input_length: 10000,             # Max input characters
  max_output_length: 5000,             # Max output characters
  max_tool_input_length: 1000,         # Max tool input length
  max_conversation_length: 50000,      # Max total conversation
  encoding: "UTF-8"                    # Character encoding
)
```

#### Example Usage

```ruby
# Basic length limits
length = RAAF::Guardrails::LengthGuardrail.new(
  max_input_length: 10000,
  max_output_length: 5000
)

# Strict limits for cost control
length = RAAF::Guardrails::LengthGuardrail.new(
  max_input_length: 2000,
  max_output_length: 1000,
  max_tool_input_length: 500,
  max_conversation_length: 20000
)

# Check lengths
input_length = length.calculate_length(input_text)
if input_length > 10000
  puts "Input too long: #{input_length} characters"
end

manager.add_guardrail(length)
```

### SchemaGuardrail

Validates input/output against JSON schemas.

```ruby
# Constructor
RAAF::Guardrails::SchemaGuardrail.new(
  input_schema: Hash,                  # Input validation schema
  output_schema: Hash,                 # Output validation schema
  tool_schemas: Hash[String, Hash],    # Per-tool schemas
  strict: false                        # Strict validation mode
)
```

#### Example Usage

```ruby
# Define schemas
input_schema = {
  type: "object",
  properties: {
    query: { 
      type: "string", 
      minLength: 1,
      maxLength: 1000 
    },
    options: {
      type: "object",
      properties: {
        language: { 
          type: "string",
          enum: ["en", "es", "fr", "de"]
        },
        format: {
          type: "string",
          enum: ["text", "json", "markdown"]
        }
      }
    }
  },
  required: ["query"]
}

output_schema = {
  type: "object",
  properties: {
    result: { type: "string" },
    confidence: { 
      type: "number",
      minimum: 0,
      maximum: 1
    },
    metadata: { type: "object" }
  },
  required: ["result"]
}

# Create schema guardrail
schema = RAAF::Guardrails::SchemaGuardrail.new(
  input_schema: input_schema,
  output_schema: output_schema,
  strict: true
)

# Tool-specific schemas
schema = RAAF::Guardrails::SchemaGuardrail.new(
  tool_schemas: {
    "calculator" => {
      type: "object",
      properties: {
        expression: { 
          type: "string",
          pattern: "^[0-9+\\-*/().\\s]+$"
        }
      },
      required: ["expression"]
    },
    "database_query" => {
      type: "object",
      properties: {
        query: { type: "string" },
        params: { 
          type: "array",
          items: { type: "string" }
        }
      },
      required: ["query"]
    }
  }
)

manager.add_guardrail(schema)
```

## Custom Guardrails

### BaseGuardrail Interface

All guardrails must inherit from `BaseGuardrail`:

```ruby
class RAAF::Guardrails::BaseGuardrail
  # Required: Unique name for the guardrail
  def name
    raise NotImplementedError
  end
  
  # Optional: Validate input before processing
  def validate_input(input)
    # Raise GuardrailError if validation fails
  end
  
  # Optional: Validate output before returning
  def validate_output(output)
    # Raise GuardrailError if validation fails
  end
  
  # Optional: Validate tool calls
  def validate_tool_call(tool_name, arguments)
    # Raise GuardrailError if validation fails
  end
end
```

### Example Custom Guardrails

#### Business Logic Guardrail

```ruby
class BusinessRuleGuardrail < RAAF::Guardrails::BaseGuardrail
  def initialize(max_transaction_amount: 10000)
    @max_transaction_amount = max_transaction_amount
  end
  
  def name
    "business_rules"
  end
  
  def validate_input(input)
    # Check for transaction amounts
    if input.match?(/\$?\d+(?:\.\d{2})?/)
      amounts = input.scan(/\$?(\d+(?:\.\d{2})?)/).flatten.map(&:to_f)
      
      amounts.each do |amount|
        if amount > @max_transaction_amount
          raise RAAF::Guardrails::GuardrailError,
                "Transaction amount $#{amount} exceeds maximum allowed ($#{@max_transaction_amount})"
        end
      end
    end
  end
  
  def validate_output(output)
    # Ensure no internal information is leaked
    if output.match?(/internal|confidential|secret/i)
      raise RAAF::Guardrails::GuardrailError,
            "Output contains restricted information"
    end
  end
  
  def validate_tool_call(tool_name, arguments)
    # Restrict certain tools
    if tool_name == "database_write" && !authorized_user?
      raise RAAF::Guardrails::GuardrailError,
            "Unauthorized access to database write operations"
    end
  end
  
  private
  
  def authorized_user?
    # Your authorization logic
    false
  end
end
```

#### Compliance Guardrail

```ruby
class ComplianceGuardrail < RAAF::Guardrails::BaseGuardrail
  def initialize(compliance_rules:)
    @rules = compliance_rules
  end
  
  def name
    "compliance"
  end
  
  def validate_input(input)
    # GDPR: Check for personal data
    if @rules.include?(:gdpr)
      check_gdpr_compliance(input)
    end
    
    # HIPAA: Check for health information
    if @rules.include?(:hipaa)
      check_hipaa_compliance(input)
    end
    
    # PCI: Check for payment card data
    if @rules.include?(:pci)
      check_pci_compliance(input)
    end
  end
  
  private
  
  def check_gdpr_compliance(text)
    # Check for email addresses
    if text.match?(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/)
      raise RAAF::Guardrails::GuardrailError,
            "Input contains email addresses (GDPR compliance)"
    end
    
    # Check for names with context
    if text.match?(/\b(name|called|named)\s+is\s+[A-Z][a-z]+\b/i)
      raise RAAF::Guardrails::GuardrailError,
            "Input may contain personal names (GDPR compliance)"
    end
  end
  
  def check_hipaa_compliance(text)
    # Check for medical terms with personal context
    medical_terms = /diagnosis|prescription|medical|health|treatment/i
    personal_context = /my|patient|person|individual/i
    
    if text.match?(medical_terms) && text.match?(personal_context)
      raise RAAF::Guardrails::GuardrailError,
            "Input may contain protected health information (HIPAA compliance)"
    end
  end
  
  def check_pci_compliance(text)
    # Check for credit card numbers
    if text.match?(/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/)
      raise RAAF::Guardrails::GuardrailError,
            "Input contains credit card number (PCI compliance)"
    end
  end
end
```

#### Cost Control Guardrail

```ruby
class CostControlGuardrail < RAAF::Guardrails::BaseGuardrail
  def initialize(max_tokens_per_request: 1000, max_cost_per_day: 100.0)
    @max_tokens_per_request = max_tokens_per_request
    @max_cost_per_day = max_cost_per_day
    @daily_cost = 0.0
    @cost_reset_at = Time.current.beginning_of_day + 1.day
  end
  
  def name
    "cost_control"
  end
  
  def validate_input(input)
    # Estimate tokens (rough approximation)
    estimated_tokens = input.split.length * 1.3
    
    if estimated_tokens > @max_tokens_per_request
      raise RAAF::Guardrails::GuardrailError,
            "Input exceeds token limit (#{estimated_tokens} > #{@max_tokens_per_request})"
    end
    
    # Check daily cost limit
    reset_daily_cost_if_needed
    
    estimated_cost = estimate_cost(estimated_tokens)
    if @daily_cost + estimated_cost > @max_cost_per_day
      raise RAAF::Guardrails::GuardrailError,
            "Daily cost limit would be exceeded ($#{@daily_cost + estimated_cost} > $#{@max_cost_per_day})"
    end
  end
  
  def track_usage(tokens_used, cost)
    @daily_cost += cost
  end
  
  private
  
  def reset_daily_cost_if_needed
    if Time.current >= @cost_reset_at
      @daily_cost = 0.0
      @cost_reset_at = Time.current.beginning_of_day + 1.day
    end
  end
  
  def estimate_cost(tokens)
    # GPT-4 pricing example (adjust for your model)
    tokens * 0.00003
  end
end
```

## Error Handling

### GuardrailError

Base exception for guardrail violations:

```ruby
begin
  manager.validate_input(user_input)
rescue RAAF::Guardrails::GuardrailError => e
  # Handle guardrail violation
  puts "Guardrail violation: #{e.message}"
  puts "Guardrail: #{e.guardrail_name}" if e.respond_to?(:guardrail_name)
  
  # Log the violation
  logger.warn("Guardrail blocked input", {
    guardrail: e.guardrail_name,
    message: e.message,
    input_preview: user_input[0..100]
  })
  
  # Return safe response
  "I'm sorry, but I cannot process that request due to safety constraints."
end
```

### Multiple Guardrail Handling

```ruby
class SafeRunner
  def initialize(agent, guardrail_manager)
    @agent = agent
    @guardrails = guardrail_manager
    @runner = RAAF::Runner.new(agent: @agent)
  end
  
  def run_safely(messages)
    # Pre-validate input
    begin
      @guardrails.validate_input(messages.last[:content])
    rescue RAAF::Guardrails::GuardrailError => e
      return handle_input_violation(e)
    end
    
    # Run agent
    result = @runner.run(messages)
    
    # Post-validate output
    begin
      @guardrails.validate_output(result.messages.last[:content])
    rescue RAAF::Guardrails::GuardrailError => e
      return handle_output_violation(e, result)
    end
    
    result
  end
  
  private
  
  def handle_input_violation(error)
    {
      messages: [{
        role: "assistant",
        content: "I cannot process this request: #{error.message}"
      }],
      guardrail_triggered: true,
      error: error.message
    }
  end
  
  def handle_output_violation(error, original_result)
    # Log the violation
    logger.error("Output validation failed", {
      error: error.message,
      original_output: original_result.messages.last[:content]
    })
    
    # Return safe alternative
    {
      messages: [{
        role: "assistant",
        content: "I apologize, but I cannot provide that information."
      }],
      guardrail_triggered: true,
      error: error.message
    }
  end
end
```

## Integration Examples

### With Agent

```ruby
# Create comprehensive guardrails
guardrails = RAAF::Guardrails::GuardrailManager.new

guardrails.add_guardrail(
  RAAF::Guardrails::ContentSafetyGuardrail.new(strict_mode: true)
)
guardrails.add_guardrail(
  RAAF::Guardrails::RateLimitGuardrail.new(
    max_requests_per_minute: 20,
    per_user: true
  )
)
guardrails.add_guardrail(
  RAAF::Guardrails::LengthGuardrail.new(
    max_input_length: 5000,
    max_output_length: 2000
  )
)

# Create agent with guardrails
agent = RAAF::Agent.new(
  name: "SecureAssistant",
  instructions: "You are a helpful but security-conscious assistant.",
  model: "gpt-4",
  guardrails: guardrails
)

# Guardrails are automatically applied during execution
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Help me with my task")
```

### With Multiple Agents

```ruby
# Shared guardrails
shared_guardrails = RAAF::Guardrails::GuardrailManager.new
shared_guardrails.add_guardrail(
  RAAF::Guardrails::ContentSafetyGuardrail.new
)

# Agent-specific guardrails
support_guardrails = shared_guardrails.dup
support_guardrails.add_guardrail(
  BusinessRuleGuardrail.new(max_transaction_amount: 5000)
)

admin_guardrails = shared_guardrails.dup
admin_guardrails.add_guardrail(
  BusinessRuleGuardrail.new(max_transaction_amount: 50000)
)

# Create agents with different guardrail sets
support_agent = RAAF::Agent.new(
  name: "Support",
  guardrails: support_guardrails
)

admin_agent = RAAF::Agent.new(
  name: "Admin",
  guardrails: admin_guardrails
)
```

### Dynamic Guardrail Configuration

```ruby
class DynamicGuardrailManager
  def initialize
    @base_guardrails = RAAF::Guardrails::GuardrailManager.new
    setup_base_guardrails
  end
  
  def get_guardrails_for_user(user)
    guardrails = @base_guardrails.dup
    
    # Add user-specific guardrails
    if user.trial?
      guardrails.add_guardrail(
        RAAF::Guardrails::RateLimitGuardrail.new(
          max_requests_per_day: 100
        )
      )
    end
    
    if user.restricted?
      guardrails.add_guardrail(
        RAAF::Guardrails::ContentSafetyGuardrail.new(
          strict_mode: true
        )
      )
    end
    
    if user.compliance_requirements.any?
      guardrails.add_guardrail(
        ComplianceGuardrail.new(
          compliance_rules: user.compliance_requirements
        )
      )
    end
    
    guardrails
  end
  
  private
  
  def setup_base_guardrails
    @base_guardrails.add_guardrail(
      RAAF::Guardrails::ContentSafetyGuardrail.new
    )
    @base_guardrails.add_guardrail(
      RAAF::Guardrails::LengthGuardrail.new(
        max_input_length: 10000
      )
    )
  end
end

# Usage
manager = DynamicGuardrailManager.new
user_guardrails = manager.get_guardrails_for_user(current_user)

agent = RAAF::Agent.new(
  name: "UserAgent",
  guardrails: user_guardrails
)
```

For more information on using guardrails with agents, see the [Core API Reference](../core/API_REFERENCE.md).