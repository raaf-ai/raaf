#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"
require_relative "../lib/openai_agents/guardrails/pii_detector"

# Set API key from environment
OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY", nil)
end

puts "=== PII Detection Guardrail Example ==="
puts

# Create different PII detectors
standard_detector = OpenAIAgents::Guardrails::PIIDetector.new(
  name: "standard_pii",
  sensitivity_level: :medium,
  redaction_enabled: true
)

high_sensitivity_detector = OpenAIAgents::Guardrails::PIIDetector.new(
  name: "high_sensitivity_pii",
  sensitivity_level: :high,
  redaction_enabled: true
)

healthcare_detector = OpenAIAgents::Guardrails::HealthcarePIIDetector.new(
  name: "healthcare_pii",
  sensitivity_level: :high,
  redaction_enabled: true
)

financial_detector = OpenAIAgents::Guardrails::FinancialPIIDetector.new(
  name: "financial_pii",
  sensitivity_level: :medium,
  redaction_enabled: true
)

# Create guardrail manager
guardrails = OpenAIAgents::Guardrails::GuardrailManager.new
guardrails.add_guardrail(standard_detector)

# Create an agent with PII protection
agent = OpenAIAgents::Agent.new(
  name: "SecureAssistant",
  model: "gpt-4o",
  instructions: <<~INSTRUCTIONS
    You are a helpful assistant that handles sensitive information securely.
    Always be careful with personally identifiable information (PII).
    When you receive PII, acknowledge it but avoid repeating it unnecessarily.
  INSTRUCTIONS
)

# Create runner with guardrails
runner = OpenAIAgents::Runner.new(agent: agent, guardrails: guardrails)

# Example 1: Basic PII detection
puts "Example 1: Basic PII Detection"
puts "-" * 50

test_inputs = [
  "My email is john.doe@example.com and my phone is 555-123-4567",
  "My SSN is 123-45-6789 and I need help with my account",
  "My credit card number is 4532-1234-5678-9012",
  "I live at 123 Main St, and my zip code is 12345"
]

test_inputs.each do |input|
  puts "\nInput: #{input}"
  
  # Test detection
  context = { input: input }
  result = standard_detector.check(context)
  
  puts "Detection result: #{result.passed? ? 'PASSED' : 'FAILED'}"
  puts "Message: #{result.message}"
  
  if result.metadata[:detections]
    puts "Detected PII:"
    result.metadata[:detections].each do |detection|
      puts "  - #{detection[:name]}: #{detection[:value]} (confidence: #{detection[:confidence]})"
    end
  end
  
  # Show redacted version
  redacted = standard_detector.redact_text(input)
  puts "Redacted: #{redacted}"
end

# Example 2: Different sensitivity levels
puts "\n\nExample 2: Sensitivity Levels Comparison"
puts "-" * 50

test_text = "Contact John Smith at 555-987-6543 or email jsmith@company.com. DOB: 01/15/1985"

[standard_detector, high_sensitivity_detector].each do |detector|
  puts "\n#{detector.sensitivity_level.to_s.capitalize} sensitivity:"
  
  context = { input: test_text }
  result = detector.check(context)
  
  detections = detector.detect_pii(test_text)
  puts "Detections: #{detections.map { |d| d[:name] }.join(', ')}"
  puts "Redacted: #{detector.redact_text(test_text)}"
end

# Example 3: Healthcare context
puts "\n\nExample 3: Healthcare PII Detection"
puts "-" * 50

healthcare_text = <<~TEXT
  Patient: Jane Doe
  MRN: MR123456
  Medicare Number: 123-45-6789A
  Insurance ID: ABC123456789
  Provider NPI: 1234567890
  
  Please schedule a follow-up appointment.
TEXT

puts "Healthcare text:\n#{healthcare_text}"

detections = healthcare_detector.detect_pii(healthcare_text)
puts "\nDetected healthcare PII:"
detections.each do |detection|
  puts "  - #{detection[:name]}: #{detection[:value]} (confidence: #{detection[:confidence]})"
end

redacted = healthcare_detector.redact_text(healthcare_text)
puts "\nRedacted text:\n#{redacted}"

# Example 4: Financial context
puts "\n\nExample 4: Financial PII Detection"
puts "-" * 50

financial_text = <<~TEXT
  Wire transfer details:
  Account: 12345678
  Routing: 123456789
  SWIFT: CHASUS33XXX
  IBAN: GB82WEST12345698765432
  
  Bitcoin address: 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa
TEXT

puts "Financial text:\n#{financial_text}"

detections = financial_detector.detect_pii(financial_text)
puts "\nDetected financial PII:"
detections.each do |detection|
  puts "  - #{detection[:name]}: #{detection[:value]} (confidence: #{detection[:confidence]})"
end

redacted = financial_detector.redact_text(financial_text)
puts "\nRedacted text:\n#{redacted}"

# Example 5: Real agent interaction with PII protection
puts "\n\nExample 5: Agent Interaction with PII Protection"
puts "-" * 50

# Test without guardrails first
puts "WITHOUT guardrails:"
unsafe_runner = OpenAIAgents::Runner.new(agent: agent)
result = unsafe_runner.run("My SSN is 123-45-6789. Can you help me understand social security benefits?")
puts "Response: #{result.messages.last[:content]}"

# Now with guardrails
puts "\nWITH guardrails:"
begin
  result = runner.run("My SSN is 123-45-6789. Can you help me understand social security benefits?")
  puts "Response: #{result.messages.last[:content]}"
rescue OpenAIAgents::Guardrails::GuardrailError => e
  puts "Guardrail blocked: #{e.message}"
  puts "Attempting with redaction..."
  
  # Try again with a different approach
  runner.guardrails.clear
  runner.guardrails.add_guardrail(high_sensitivity_detector)
  
  result = runner.run("I have a question about social security benefits.")
  puts "Response: #{result.messages.last[:content]}"
end

# Example 6: Custom PII patterns
puts "\n\nExample 6: Custom PII Patterns"
puts "-" * 50

# Create detector with custom patterns
custom_detector = OpenAIAgents::Guardrails::PIIDetector.new(
  name: "custom_pii",
  sensitivity_level: :medium,
  custom_patterns: {
    employee_id: {
      pattern: /\bEMP\d{6}\b/,
      name: "Employee ID",
      confidence: 0.9,
      validator: ->(match) { match.start_with?("EMP") }
    },
    internal_code: {
      pattern: /\bINT-[A-Z]{2}-\d{4}\b/,
      name: "Internal Code",
      confidence: 0.85,
      validator: ->(match) { match.match?(/^INT-[A-Z]{2}-\d{4}$/) }
    }
  }
)

custom_text = "Employee EMP123456 reported issue INT-QA-5678 regarding system access."
puts "Text: #{custom_text}"

detections = custom_detector.detect_pii(custom_text)
puts "\nDetected custom PII:"
detections.each do |detection|
  puts "  - #{detection[:name]}: #{detection[:value]}"
end

# Example 7: Statistics and monitoring
puts "\n\nExample 7: Detection Statistics"
puts "-" * 50

# Reset stats
standard_detector.reset_stats

# Process multiple texts
texts = [
  "Email me at test@example.com",
  "Call 555-123-4567 for support",
  "SSN: 987-65-4321",
  "Card ending in 1234",
  "Contact admin@company.org or call 555-987-6543"
]

texts.each { |text| standard_detector.detect_pii(text) }

# Show statistics
stats = standard_detector.stats
puts "Detection Statistics:"
puts "  Total detections: #{stats[:total_detections]}"
puts "  By type:"
stats[:by_type].each do |type, count|
  puts "    #{type}: #{count}"
end

# Example 8: Batch processing with PII protection
puts "\n\nExample 8: Batch Processing"
puts "-" * 50

documents = [
  { id: 1, content: "John's email is john@example.com" },
  { id: 2, content: "SSN 123-45-6789 needs verification" },
  { id: 3, content: "No sensitive information here" },
  { id: 4, content: "Credit card 4111-1111-1111-1111" }
]

puts "Processing #{documents.length} documents..."

safe_documents = documents.map do |doc|
  detections = standard_detector.detect_pii(doc[:content])
  
  {
    id: doc[:id],
    original: doc[:content],
    redacted: standard_detector.redact_text(doc[:content]),
    has_pii: detections.any?,
    pii_types: detections.map { |d| d[:name] }.uniq
  }
end

safe_documents.each do |doc|
  puts "\nDocument #{doc[:id]}:"
  puts "  Has PII: #{doc[:has_pii] ? 'Yes' : 'No'}"
  puts "  PII Types: #{doc[:pii_types].join(', ')}" if doc[:has_pii]
  puts "  Redacted: #{doc[:redacted]}" if doc[:has_pii]
end

# Best practices
puts "\n\nPII Protection Best Practices:"
puts "-" * 50
puts <<~PRACTICES
  1. Sensitivity Levels:
     - Low: Only high-confidence patterns (SSN, credit cards)
     - Medium: Include emails, phones, addresses
     - High: Include potential names, dates, IDs
  
  2. Redaction Strategies:
     - Partial masking for verification (last 4 digits)
     - Full replacement with type indicators
     - Context-aware redaction
  
  3. Custom Patterns:
     - Add organization-specific identifiers
     - Include industry-specific formats
     - Validate with business logic
  
  4. Integration Points:
     - Input validation before processing
     - Output filtering before storage
     - Audit logging for compliance
     - Real-time monitoring
  
  5. Compliance Considerations:
     - GDPR: Right to erasure, data minimization
     - HIPAA: Protected Health Information (PHI)
     - PCI-DSS: Credit card data protection
     - CCPA: California privacy rights
  
  6. Performance Tips:
     - Cache compiled patterns
     - Process in batches
     - Use appropriate sensitivity levels
     - Monitor false positive rates
PRACTICES

puts "\nPII detection guardrail example completed!"