# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/raaf/models/handoff_fallback_system"

RSpec.describe RAAF::Models::HandoffFallbackSystem do
  let(:available_agents) { ["SupportAgent", "BillingAgent", "TechnicalAgent", "SpecialistAgent"] }
  subject { described_class.new(available_agents) }

  describe "#initialize" do
    it "initializes with available agents" do
      expect(subject.get_detection_stats[:available_agents]).to eq(available_agents)
    end

    it "initializes with empty statistics" do
      stats = subject.get_detection_stats
      expect(stats[:total_attempts]).to eq(0)
      expect(stats[:successful_detections]).to eq(0)
      expect(stats[:success_rate]).to eq("0.0%")
    end

    context "with empty agent list" do
      subject { described_class.new([]) }

      it "initializes successfully" do
        expect(subject.get_detection_stats[:available_agents]).to eq([])
      end
    end
  end

  describe "#generate_handoff_instructions" do
    it "generates instructions with agent list" do
      instructions = subject.generate_handoff_instructions(available_agents)
      
      expect(instructions).to include("Handoff Instructions")
      expect(instructions).to include("multi-agent system")
      expect(instructions).to include("SupportAgent")
      expect(instructions).to include("BillingAgent")
      expect(instructions).to include('{"handoff_to": "AgentName"}')
      expect(instructions).to include("[HANDOFF:AgentName]")
    end

    it "includes all available agents" do
      instructions = subject.generate_handoff_instructions(available_agents)
      
      available_agents.each do |agent|
        expect(instructions).to include(agent)
      end
    end

    context "with empty agent list" do
      it "generates basic instructions" do
        instructions = subject.generate_handoff_instructions([])
        expect(instructions).to include("Handoff Instructions")
        expect(instructions).not_to include("- ")
      end
    end
  end

  describe "#detect_handoff_in_content" do
    context "with JSON patterns" do
      it "detects handoff_to pattern" do
        content = 'I can help with that. {"handoff_to": "SupportAgent"}'
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("SupportAgent")
      end

      it "detects transfer_to pattern" do
        content = 'Let me help. {"transfer_to": "BillingAgent"}'
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("BillingAgent")
      end

      it "detects assistant pattern" do
        content = 'Switching to specialist. {"assistant": "TechnicalAgent"}'
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("TechnicalAgent")
      end

      it "handles JSON with whitespace" do
        content = '{"handoff_to"  :   "SpecialistAgent"  }'
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("SpecialistAgent")
      end
    end

    context "with structured patterns" do
      it "detects [HANDOFF:Agent] pattern" do
        content = "I need to transfer you. [HANDOFF:SupportAgent]"
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("SupportAgent")
      end

      it "detects [TRANSFER:Agent] pattern" do
        content = "Let me connect you. [TRANSFER:BillingAgent]"
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("BillingAgent")
      end

      it "detects [AGENT:Agent] pattern" do
        content = "Switching now. [AGENT:TechnicalAgent]"
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("TechnicalAgent")
      end

      it "handles case insensitive patterns" do
        content = "Transfer needed. [handoff:supportagent]"
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("SupportAgent")
      end
    end

    context "with natural language patterns" do
      it "detects 'transfer to' pattern" do
        content = "I will transfer you to SupportAgent for assistance."
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("SupportAgent")
      end

      it "detects 'handoff to' pattern" do
        content = "Let me handoff to BillingAgent."
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("BillingAgent")
      end

      it "detects 'switching to' pattern" do
        content = "Switching to TechnicalAgent now."
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("TechnicalAgent")
      end

      it "detects 'forwarding to' pattern" do
        content = "Forwarding to SpecialistAgent."
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("SpecialistAgent")
      end

      it "handles agent suffix" do
        content = "Transfer to Support Agent for help."
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("SupportAgent")
      end
    end

    context "with code-style patterns" do
      it "detects handoff() function pattern" do
        content = 'Please wait. handoff("SupportAgent")'
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("SupportAgent")
      end

      it "detects transfer() function pattern" do
        content = "One moment. transfer('BillingAgent')"
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("BillingAgent")
      end

      it "detects agent() function pattern" do
        content = 'Connecting... agent("TechnicalAgent")'
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("TechnicalAgent")
      end
    end

    context "with invalid or missing agents" do
      it "returns nil for unknown agent" do
        content = '{"handoff_to": "UnknownAgent"}'
        result = subject.detect_handoff_in_content(content)
        expect(result).to be_nil
      end

      it "returns nil for empty content" do
        result = subject.detect_handoff_in_content("")
        expect(result).to be_nil
      end

      it "returns nil for nil content" do
        result = subject.detect_handoff_in_content(nil)
        expect(result).to be_nil
      end

      it "returns nil for non-string content" do
        result = subject.detect_handoff_in_content(123)
        expect(result).to be_nil
      end

      it "returns nil for content with no handoff" do
        content = "This is just a regular response with no handoff."
        result = subject.detect_handoff_in_content(content)
        expect(result).to be_nil
      end
    end

    context "with case sensitivity" do
      it "handles mixed case agent names" do
        content = '{"handoff_to": "supportagent"}'
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("SupportAgent")
      end

      it "handles uppercase agent names" do
        content = '{"handoff_to": "BILLINGAGENT"}'
        result = subject.detect_handoff_in_content(content)
        expect(result).to eq("BillingAgent")
      end
    end

    context "statistics tracking" do
      it "increments attempt counter" do
        expect {
          subject.detect_handoff_in_content("test content")
        }.to change { subject.get_detection_stats[:total_attempts] }.by(1)
      end

      it "increments success counter on detection" do
        expect {
          subject.detect_handoff_in_content('{"handoff_to": "SupportAgent"}')
        }.to change { subject.get_detection_stats[:successful_detections] }.by(1)
      end

      it "does not increment success counter on failure" do
        expect {
          subject.detect_handoff_in_content("no handoff here")
        }.not_to change { subject.get_detection_stats[:successful_detections] }
      end
    end
  end

  describe "#detect_handoff_with_context" do
    let(:context) { { conversation_id: "123", user_id: "456" } }

    it "returns detailed detection result for successful detection" do
      content = '{"handoff_to": "SupportAgent"}'
      result = subject.detect_handoff_with_context(content, context)

      expect(result).to include(
        handoff_detected: true,
        target_agent: "SupportAgent",
        detection_method: "content_based",
        confidence: be > 0.0,
        context: context
      )
    end

    it "returns detailed result for failed detection" do
      content = "no handoff here"
      result = subject.detect_handoff_with_context(content, context)

      expect(result).to include(
        handoff_detected: false,
        target_agent: nil,
        detection_method: nil,
        confidence: 0.0,
        context: context
      )
    end

    it "works without context" do
      content = '{"handoff_to": "SupportAgent"}'
      result = subject.detect_handoff_with_context(content)

      expect(result[:handoff_detected]).to be true
      expect(result[:context]).to eq({})
    end
  end

  describe "#generate_handoff_response" do
    it "generates response with JSON format" do
      response = subject.generate_handoff_response("SupportAgent")
      expect(response).to include("SupportAgent")
      expect(response).to include('{"handoff_to":"SupportAgent"}')
    end

    it "includes custom message" do
      message = "Custom transfer message"
      response = subject.generate_handoff_response("SupportAgent", message)
      expect(response).to include(message)
      expect(response).to include("SupportAgent")
    end

    it "includes multiple format options" do
      response = subject.generate_handoff_response("SupportAgent")
      expect(response).to include('{"handoff_to":"SupportAgent"}')
    end
  end

  describe "#get_detection_stats" do
    before do
      # Generate some test statistics
      subject.detect_handoff_in_content('{"handoff_to": "SupportAgent"}')
      subject.detect_handoff_in_content("no handoff")
      subject.detect_handoff_in_content('{"handoff_to": "BillingAgent"}')
    end

    it "returns comprehensive statistics" do
      stats = subject.get_detection_stats

      expect(stats).to include(
        total_attempts: 3,
        successful_detections: 2,
        success_rate: "66.67%",
        most_effective_patterns: be_an(Array),
        available_agents: available_agents
      )
    end

    it "calculates success rate correctly" do
      stats = subject.get_detection_stats
      expect(stats[:success_rate]).to eq("66.67%")
    end

    it "tracks pattern effectiveness" do
      stats = subject.get_detection_stats
      expect(stats[:most_effective_patterns]).not_to be_empty
      expect(stats[:most_effective_patterns].first).to be_an(Array)
    end
  end

  describe "#reset_stats" do
    before do
      subject.detect_handoff_in_content('{"handoff_to": "SupportAgent"}')
    end

    it "resets all statistics" do
      expect {
        subject.reset_stats
      }.to change { subject.get_detection_stats[:total_attempts] }.to(0)
    end

    it "preserves available agents" do
      subject.reset_stats
      stats = subject.get_detection_stats
      expect(stats[:available_agents]).to eq(available_agents)
    end
  end

  describe "#test_detection" do
    let(:test_cases) do
      [
        {
          content: '{"handoff_to": "SupportAgent"}',
          expected_agent: "SupportAgent"
        },
        {
          content: "[HANDOFF:BillingAgent]",
          expected_agent: "BillingAgent"
        },
        {
          content: "Transfer to TechnicalAgent",
          expected_agent: "TechnicalAgent"
        },
        {
          content: "No handoff here",
          expected_agent: nil
        },
        {
          content: '{"handoff_to": "UnknownAgent"}',
          expected_agent: nil
        }
      ]
    end

    it "runs comprehensive test suite" do
      results = subject.test_detection(test_cases)

      expect(results).to include(
        total_tests: 5,
        passed: 4,
        failed: 1,
        success_rate: "80.0%",
        details: be_an(Array)
      )
    end

    it "provides detailed test results" do
      results = subject.test_detection(test_cases)
      
      expect(results[:details]).to have(5).items
      
      first_result = results[:details].first
      expect(first_result).to include(
        content: be_a(String),
        expected: "SupportAgent",
        detected: "SupportAgent",
        passed: true
      )
    end

    it "truncates long content in details" do
      long_content = "x" * 200
      long_test_cases = [{
        content: long_content + '{"handoff_to": "SupportAgent"}',
        expected_agent: "SupportAgent"
      }]

      results = subject.test_detection(long_test_cases)
      detail_content = results[:details].first[:content]
      
      expect(detail_content.length).to be <= 103 # 100 chars + "..."
      expect(detail_content).to end_with("...")
    end

    context "with empty test cases" do
      it "handles empty test suite" do
        results = subject.test_detection([])
        
        expect(results).to include(
          total_tests: 0,
          passed: 0,
          failed: 0,
          success_rate: "0.0%"
        )
      end
    end
  end

  describe "integration with multiple patterns" do
    it "prioritizes more reliable patterns" do
      # Content with both JSON and natural language patterns
      content = 'Transfer to BillingAgent. {"handoff_to": "SupportAgent"}'
      result = subject.detect_handoff_in_content(content)
      
      # Should detect the more reliable JSON pattern
      expect(result).to eq("SupportAgent")
    end

    it "handles multiple potential agents" do
      content = "Transfer from SupportAgent to BillingAgent"
      result = subject.detect_handoff_in_content(content)
      
      # Should detect the first valid pattern
      expect(["SupportAgent", "BillingAgent"]).to include(result)
    end
  end

  describe "error handling" do
    it "handles malformed JSON gracefully" do
      content = '{"handoff_to": SupportAgent}' # Missing quotes
      result = subject.detect_handoff_in_content(content)
      
      # Should still detect via other patterns if agent name appears
      expect(result).to eq("SupportAgent")
    end

    it "handles special characters in content" do
      content = 'Special chars: !@#$%^&*() {"handoff_to": "SupportAgent"}'
      result = subject.detect_handoff_in_content(content)
      expect(result).to eq("SupportAgent")
    end

    it "handles unicode characters" do
      content = 'Unicode: 你好 {"handoff_to": "SupportAgent"}'
      result = subject.detect_handoff_in_content(content)
      expect(result).to eq("SupportAgent")
    end
  end
end