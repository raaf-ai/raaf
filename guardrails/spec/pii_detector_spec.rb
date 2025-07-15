# frozen_string_literal: true

require "spec_helper"
require "openai_agents/guardrails/pii_detector"

RSpec.describe OpenAIAgents::Guardrails::PIIDetector do
  let(:detector) { described_class.new(sensitivity_level: :medium) }
  
  describe "#detect_pii" do
    context "with email addresses" do
      it "detects valid email addresses" do
        text = "Contact me at john.doe@example.com"
        detections = detector.detect_pii(text)
        
        expect(detections).not_to be_empty
        expect(detections.first[:type]).to eq(:email)
        expect(detections.first[:value]).to eq("john.doe@example.com")
        expect(detections.first[:confidence]).to be > 0.9
      end
    end
    
    context "with phone numbers" do
      it "detects US phone numbers" do
        texts = [
          "Call me at 555-123-4567",
          "Phone: (555) 123-4567",
          "Mobile: +1-555-123-4567"
        ]
        
        texts.each do |text|
          detections = detector.detect_pii(text)
          expect(detections).not_to be_empty
          expect(detections.first[:type]).to eq(:phone)
        end
      end
    end
    
    context "with social security numbers" do
      it "detects SSN patterns" do
        texts = [
          "SSN: 123-45-6789",
          "Social Security: 123456789"
        ]
        
        texts.each do |text|
          detections = detector.detect_pii(text)
          expect(detections).not_to be_empty
          expect(detections.first[:type]).to eq(:ssn)
        end
      end
    end
    
    context "with credit card numbers" do
      it "detects valid credit card numbers" do
        # Valid test credit card numbers
        text = "Card: 4111-1111-1111-1111"
        detections = detector.detect_pii(text)
        
        expect(detections).not_to be_empty
        expect(detections.first[:type]).to eq(:credit_card)
      end
      
      it "validates using Luhn algorithm" do
        valid_card = "4532015112830366" # Valid Luhn
        invalid_card = "4532015112830367"  # Invalid Luhn
        
        valid_detections = detector.detect_pii("Card: #{valid_card}")
        invalid_detections = detector.detect_pii("Card: #{invalid_card}")
        
        expect(valid_detections).not_to be_empty
        expect(invalid_detections).to be_empty
      end
    end
    
    context "with IP addresses" do
      it "detects valid IPv4 addresses" do
        text = "Server IP: 192.168.1.1"
        detections = detector.detect_pii(text)
        
        expect(detections).not_to be_empty
        expect(detections.first[:type]).to eq(:ip_address)
      end
      
      it "validates IP ranges" do
        valid_ip = "192.168.1.1"
        invalid_ip = "999.999.999.999"
        
        valid_detections = detector.detect_pii("IP: #{valid_ip}")
        invalid_detections = detector.detect_pii("IP: #{invalid_ip}")
        
        expect(valid_detections).not_to be_empty
        expect(invalid_detections).to be_empty
      end
    end
  end
  
  describe "#redact_text" do
    it "redacts email addresses" do
      text = "Email: john.doe@example.com"
      redacted = detector.redact_text(text)
      
      expect(redacted).to eq("Email: jo***@***.***")
      expect(redacted).not_to include("john.doe")
      expect(redacted).not_to include("example.com")
    end
    
    it "redacts phone numbers" do
      text = "Call 555-123-4567"
      redacted = detector.redact_text(text)
      
      expect(redacted).to eq("Call ***-***-4567")
      expect(redacted).to include("4567")  # Last 4 digits
    end
    
    it "redacts SSNs" do
      text = "SSN: 123-45-6789"
      redacted = detector.redact_text(text)
      
      expect(redacted).to eq("SSN: ***-**-6789")
      expect(redacted).to include("6789")  # Last 4 digits
    end
    
    it "redacts credit cards" do
      text = "Card: 4111-1111-1111-1111"
      redacted = detector.redact_text(text)
      
      expect(redacted).to eq("Card: ****-****-****-1111")
      expect(redacted).to include("1111")  # Last 4 digits
    end
    
    it "handles multiple PII in same text" do
      text = "Contact john@example.com or call 555-123-4567"
      redacted = detector.redact_text(text)
      
      expect(redacted).to eq("Contact jo***@***.*** or call ***-***-4567")
    end
  end
  
  describe "sensitivity levels" do
    it "detects more patterns with high sensitivity" do
      low_detector = described_class.new(sensitivity_level: :low)
      high_detector = described_class.new(sensitivity_level: :high)
      
      text = "John Smith called from ZIP 12345"
      
      low_detections = low_detector.detect_pii(text)
      high_detections = high_detector.detect_pii(text)
      
      expect(low_detections.size).to be < high_detections.size
    end
  end
  
  describe "#check" do
    it "passes when no PII detected" do
      context = { input: "This is safe text without any PII" }
      result = detector.check(context)
      
      expect(result.passed?).to be true
      expect(result.message).to eq("No PII detected")
    end
    
    it "fails when high-confidence PII detected" do
      context = { input: "My SSN is 123-45-6789" }
      result = detector.check(context)
      
      expect(result.passed?).to be false
      expect(result.message).to include("PII detected")
      expect(result.metadata[:severity]).to eq("high")
    end
    
    it "redacts output when enabled" do
      detector = described_class.new(redaction_enabled: true)
      context = { 
        input: "Process this",
        output: "Your SSN 123-45-6789 has been processed"
      }
      
      result = detector.check(context)
      
      expect(result.passed?).to be false
      expect(context[:output]).to eq("Your SSN ***-**-6789 has been processed")
    end
  end
  
  describe "custom patterns" do
    let(:custom_detector) do
      described_class.new(
        custom_patterns: {
          employee_id: {
            pattern: /\bEMP\d{6}\b/,
            name: "Employee ID",
            confidence: 0.9,
            validator: ->(match) { match.start_with?("EMP") }
          }
        }
      )
    end
    
    it "detects custom patterns" do
      text = "Employee ID: EMP123456"
      detections = custom_detector.detect_pii(text)
      
      expect(detections).not_to be_empty
      expect(detections.first[:type]).to eq(:employee_id)
      expect(detections.first[:value]).to eq("EMP123456")
    end
  end
  
  describe "statistics" do
    it "tracks detection counts" do
      detector.reset_stats
      
      detector.detect_pii("Email: test@example.com")
      detector.detect_pii("Phone: 555-123-4567")
      detector.detect_pii("Another email: admin@test.com")
      
      stats = detector.stats
      
      expect(stats[:total_detections]).to eq(3)
      expect(stats[:by_type][:email]).to eq(2)
      expect(stats[:by_type][:phone]).to eq(1)
    end
  end
end

RSpec.describe OpenAIAgents::Guardrails::HealthcarePIIDetector do
  let(:detector) { described_class.new }
  
  it "detects medical record numbers" do
    text = "Patient MRN: MR123456"
    detections = detector.detect_pii(text)
    
    expect(detections).not_to be_empty
    expect(detections.first[:name]).to eq("Medical Record Number")
  end
  
  it "detects Medicare numbers" do
    text = "Medicare: 123-45-6789A"
    detections = detector.detect_pii(text)
    
    expect(detections).not_to be_empty
    expect(detections.first[:name]).to eq("Medicare Number")
  end
end

RSpec.describe OpenAIAgents::Guardrails::FinancialPIIDetector do
  let(:detector) { described_class.new }
  
  it "detects SWIFT codes" do
    text = "SWIFT: CHASUS33XXX"
    detections = detector.detect_pii(text)
    
    expect(detections).not_to be_empty
    expect(detections.first[:name]).to eq("SWIFT Code")
  end
  
  it "detects Bitcoin addresses" do
    text = "Send to: 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
    detections = detector.detect_pii(text)
    
    expect(detections).not_to be_empty
    expect(detections.first[:name]).to eq("Bitcoin Address")
  end
  
  it "validates routing numbers" do
    valid_routing = "122000247" # Valid JPMorgan Chase routing
    invalid_routing = "123456789" # Invalid checksum
    
    valid_detections = detector.detect_pii("Routing: #{valid_routing}")
    invalid_detections = detector.detect_pii("Routing: #{invalid_routing}")
    
    expect(valid_detections.any? { |d| d[:name] == "Routing Number" }).to be true
    expect(invalid_detections.any? { |d| d[:name] == "Routing Number" }).to be false
  end
end