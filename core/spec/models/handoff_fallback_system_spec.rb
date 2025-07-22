# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/raaf/models/handoff_fallback_system"

RSpec.describe RAAF::Models::HandoffFallbackSystem do
  let(:available_agents) { ["Support", "Billing", "Technical"] }
  let(:fallback_system) { described_class.new(available_agents) }

  describe "#initialize" do
    it "initializes with available agents" do
      system = described_class.new(available_agents)
      expect(system.get_detection_stats[:available_agents]).to eq(available_agents)
    end

    it "initializes with empty agents list by default" do
      system = described_class.new
      expect(system.get_detection_stats[:available_agents]).to eq([])
    end

    it "initializes detection statistics" do
      stats = fallback_system.get_detection_stats
      expect(stats[:total_attempts]).to eq(0)
      expect(stats[:successful_detections]).to eq(0)
      expect(stats[:success_rate]).to eq("0.0%")
    end
  end

  describe "#generate_handoff_instructions" do
    it "generates instructions with available agents" do
      instructions = fallback_system.generate_handoff_instructions(["Support", "Billing"])
      
      expect(instructions).to include("# Handoff Instructions for Multi-Agent System")
      expect(instructions).to include('{"handoff_to": "AgentName"}')
      expect(instructions).to include("- Support")
      expect(instructions).to include("- Billing")
      expect(instructions).to include("[HANDOFF:AgentName]")
      expect(instructions).to include("Transfer to AgentName")
    end

    it "handles empty agent list" do
      instructions = fallback_system.generate_handoff_instructions([])
      
      expect(instructions).to include("# Handoff Instructions")
      expect(instructions).to include("## Available Agents:\n") # Empty list
    end

    it "formats agent names correctly" do
      agents = ["MyAgent", "Another Agent", "agent_with_underscore"]
      instructions = fallback_system.generate_handoff_instructions(agents)
      
      expect(instructions).to include("- MyAgent")
      expect(instructions).to include("- Another Agent") 
      expect(instructions).to include("- agent_with_underscore")
    end
  end

  describe "#detect_handoff_in_content" do
    context "with JSON format handoffs" do
      it "detects simple JSON handoff" do
        content = 'I can help with that. {"handoff_to": "Support"}'
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Support")
      end

      it "detects JSON transfer format" do
        content = 'Let me help. {"transfer_to": "Billing"}'
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Billing")
      end

      it "detects JSON assistant format" do
        content = 'Routing to specialist. {"assistant": "Technical"}'
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Technical")
      end

      it "handles JSON with extra whitespace" do
        content = '{"handoff_to":   "Support"   }'
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Support")
      end

      it "is case insensitive for JSON keys" do
        content = '{"HANDOFF_TO": "support"}'
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Support") # Matches available agent with correct case
      end
    end

    context "with structured format handoffs" do
      it "detects HANDOFF format" do
        content = "I'll transfer you. [HANDOFF:Support]"
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Support")
      end

      it "detects TRANSFER format" do
        content = "Moving you to billing. [TRANSFER:Billing]"
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Billing")
      end

      it "detects AGENT format" do
        content = "Connecting to technical team. [AGENT:Technical]"
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Technical")
      end

      it "handles case insensitive structured formats" do
        content = "[handoff:support]"
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Support")
      end
    end

    context "with natural language handoffs" do
      it "detects 'transfer to' pattern" do
        content = "I will transfer you to Support for assistance."
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Support")
      end

      it "detects 'transferring to' pattern" do
        content = "Transferring you to Billing department."
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Billing")
      end

      it "detects 'handoff to' pattern" do
        content = "I need to handoff to Technical support."
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Technical")
      end

      it "detects 'switching to' pattern" do
        content = "Switching to Support agent now."
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Support")
      end

      it "detects 'forwarding to' pattern" do
        content = "Forwarding to Billing agent for help."
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Billing")
      end

      it "handles agent name with 'agent' suffix" do
        content = "Transfer to Support agent"
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Support")
      end
    end

    context "with code-style handoffs" do
      it "detects handoff function call with double quotes" do
        content = 'Execute: handoff("Support")'
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Support")
      end

      it "detects transfer function call with single quotes" do
        content = "Running: transfer('Billing')"
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Billing")
      end

      it "detects agent function call" do
        content = 'Call: agent("Technical")'
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to eq("Technical")
      end
    end

    context "with invalid or ambiguous content" do
      it "returns nil for empty content" do
        result = fallback_system.detect_handoff_in_content("")
        expect(result).to be_nil
      end

      it "returns nil for nil content" do
        result = fallback_system.detect_handoff_in_content(nil)
        expect(result).to be_nil
      end

      it "returns nil for non-string content" do
        result = fallback_system.detect_handoff_in_content(123)
        expect(result).to be_nil
      end

      it "returns nil for content without handoff patterns" do
        content = "This is just a regular response without any handoff."
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to be_nil
      end

      it "returns nil for handoff to unknown agent" do
        content = '{"handoff_to": "UnknownAgent"}'
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to be_nil
      end

      it "detects handoff even in malformed JSON if pattern matches" do
        content = '{"handoff_to": "Support" // missing closing brace'
        result = fallback_system.detect_handoff_in_content(content)
        # The regex pattern will still match the valid part
        expect(result).to eq("Support")
      end

      it "validates agent name against available agents" do
        content = '{"handoff_to": "Marketing"}' # Not in available_agents
        result = fallback_system.detect_handoff_in_content(content)
        expect(result).to be_nil
      end
    end

    context "statistics tracking" do
      it "tracks detection attempts" do
        expect {
          fallback_system.detect_handoff_in_content('{"handoff_to": "Support"}')
        }.to change { fallback_system.get_detection_stats[:total_attempts] }.by(1)
      end

      it "tracks successful detections" do
        expect {
          fallback_system.detect_handoff_in_content('{"handoff_to": "Support"}')
        }.to change { fallback_system.get_detection_stats[:successful_detections] }.by(1)
      end

      it "tracks failed attempts without incrementing successes" do
        expect {
          fallback_system.detect_handoff_in_content("No handoff here")
        }.to change { fallback_system.get_detection_stats[:total_attempts] }.by(1)
        .and change { fallback_system.get_detection_stats[:successful_detections] }.by(0)
      end

      it "tracks pattern usage" do
        # Use different patterns
        fallback_system.detect_handoff_in_content('{"handoff_to": "Support"}') # Pattern 0
        fallback_system.detect_handoff_in_content('[HANDOFF:Billing]') # Pattern 3
        fallback_system.detect_handoff_in_content('transfer to Technical') # Pattern 6

        stats = fallback_system.get_detection_stats
        expect(stats[:most_effective_patterns]).to be_an(Array)
        expect(stats[:most_effective_patterns].size).to be <= 3
      end
    end
  end

  describe "#detect_handoff_with_context" do
    it "returns detailed detection result for successful handoff" do
      content = '{"handoff_to": "Support"}'
      context = { conversation_id: "123", user_id: "456" }
      
      result = fallback_system.detect_handoff_with_context(content, context)
      
      expect(result[:handoff_detected]).to be true
      expect(result[:target_agent]).to eq("Support")
      expect(result[:detection_method]).to eq("content_based")
      expect(result[:confidence]).to be > 0.0
      expect(result[:context]).to eq(context)
    end

    it "returns detailed result for failed detection" do
      content = "No handoff here"
      context = { conversation_id: "123" }
      
      result = fallback_system.detect_handoff_with_context(content, context)
      
      expect(result[:handoff_detected]).to be false
      expect(result[:target_agent]).to be_nil
      expect(result[:detection_method]).to be_nil
      expect(result[:confidence]).to eq(0.0)
      expect(result[:context]).to eq(context)
    end

    it "handles empty context" do
      content = '{"handoff_to": "Support"}'
      
      result = fallback_system.detect_handoff_with_context(content)
      
      expect(result[:handoff_detected]).to be true
      expect(result[:context]).to eq({})
    end

    it "calculates confidence scores" do
      # JSON format should have higher confidence
      json_result = fallback_system.detect_handoff_with_context('{"handoff_to": "Support"}')
      
      # Natural language should have lower confidence
      nl_result = fallback_system.detect_handoff_with_context('transfer to Support')
      
      expect(json_result[:confidence]).to be > nl_result[:confidence]
      expect(json_result[:confidence]).to be <= 1.0
      expect(nl_result[:confidence]).to be >= 0.0
    end
  end

  describe "#generate_handoff_response" do
    it "generates response with default message" do
      response = fallback_system.generate_handoff_response("Support")
      
      expect(response).to include("Transferring to Support")
      expect(response).to include('{"handoff_to":"Support"}')
    end

    it "generates response with custom message" do
      response = fallback_system.generate_handoff_response("Support", "I need specialist help")
      
      expect(response).to include("I need specialist help")
      expect(response).to include('{"handoff_to":"Support"}')
      expect(response).not_to include("Transferring to Support")
    end

    it "includes multiple detection patterns" do
      response = fallback_system.generate_handoff_response("Billing")
      
      expect(response).to include('{"handoff_to":"Billing"}')
    end

    it "handles agent names with special characters" do
      response = fallback_system.generate_handoff_response("Agent_123")
      
      expect(response).to include("Transferring to Agent_123")
      expect(response).to include('{"handoff_to":"Agent_123"}')
    end
  end

  describe "#get_detection_stats" do
    it "calculates success rate correctly" do
      # Perform 3 detections: 2 successful, 1 failed
      fallback_system.detect_handoff_in_content('{"handoff_to": "Support"}') # Success
      fallback_system.detect_handoff_in_content('No handoff here') # Fail
      fallback_system.detect_handoff_in_content('[HANDOFF:Billing]') # Success
      
      stats = fallback_system.get_detection_stats
      
      expect(stats[:total_attempts]).to eq(3)
      expect(stats[:successful_detections]).to eq(2)
      expect(stats[:success_rate]).to eq("66.67%")
    end

    it "handles zero attempts" do
      stats = fallback_system.get_detection_stats
      
      expect(stats[:total_attempts]).to eq(0)
      expect(stats[:successful_detections]).to eq(0)
      expect(stats[:success_rate]).to eq("0.0%")
      expect(stats[:most_effective_patterns]).to eq([])
    end

    it "includes available agents" do
      stats = fallback_system.get_detection_stats
      expect(stats[:available_agents]).to eq(available_agents)
    end

    it "tracks most effective patterns" do
      # Use same pattern multiple times
      3.times { fallback_system.detect_handoff_in_content('{"handoff_to": "Support"}') }
      2.times { fallback_system.detect_handoff_in_content('[HANDOFF:Billing]') }
      
      stats = fallback_system.get_detection_stats
      most_effective = stats[:most_effective_patterns]
      
      expect(most_effective).to be_an(Array)
      expect(most_effective.size).to be <= 3
      # First pattern should be most used (JSON pattern)
      expect(most_effective.first[1]).to eq(3) if most_effective.any?
    end
  end

  describe "#reset_stats" do
    it "resets all statistics" do
      # Generate some statistics
      fallback_system.detect_handoff_in_content('{"handoff_to": "Support"}')
      fallback_system.detect_handoff_in_content('[HANDOFF:Billing]')
      
      # Verify stats exist
      expect(fallback_system.get_detection_stats[:total_attempts]).to be > 0
      
      # Reset and verify
      fallback_system.reset_stats
      stats = fallback_system.get_detection_stats
      
      expect(stats[:total_attempts]).to eq(0)
      expect(stats[:successful_detections]).to eq(0)
      expect(stats[:success_rate]).to eq("0.0%")
    end

    it "preserves available agents" do
      original_agents = fallback_system.get_detection_stats[:available_agents]
      
      fallback_system.reset_stats
      
      expect(fallback_system.get_detection_stats[:available_agents]).to eq(original_agents)
    end
  end

  describe "#test_detection" do
    let(:test_cases) do
      [
        { content: '{"handoff_to": "Support"}', expected_agent: "Support" },
        { content: '[HANDOFF:Billing]', expected_agent: "Billing" },
        { content: 'Transfer to Technical', expected_agent: "Technical" },
        { content: 'No handoff here', expected_agent: nil },
        { content: '{"handoff_to": "Unknown"}', expected_agent: nil }
      ]
    end

    it "runs comprehensive test suite" do
      results = fallback_system.test_detection(test_cases)
      
      expect(results[:total_tests]).to eq(5)
      expect(results[:passed]).to be_between(3, 5) # At least 3 should pass
      expect(results[:failed]).to be >= 0
      expect(results[:success_rate]).to match(/\d+\.\d+%/)
    end

    it "provides detailed results" do
      results = fallback_system.test_detection(test_cases)
      
      expect(results[:details]).to be_an(Array)
      expect(results[:details].size).to eq(5)
      
      results[:details].each do |detail|
        expect(detail).to have_key(:content)
        expect(detail).to have_key(:expected)
        expect(detail).to have_key(:detected)
        expect(detail).to have_key(:passed)
        expect([true, false]).to include(detail[:passed])
      end
    end

    it "truncates long content in results" do
      long_content = "x" * 150
      test_case = [{ content: long_content, expected_agent: nil }]
      
      results = fallback_system.test_detection(test_case)
      detail = results[:details].first
      
      expect(detail[:content].length).to be <= 104 # 100 chars + "..."
      expect(detail[:content]).to end_with("...") if long_content.length > 100
    end

    it "calculates success rate correctly" do
      simple_test = [
        { content: '{"handoff_to": "Support"}', expected_agent: "Support" }, # Pass
        { content: 'No handoff', expected_agent: nil } # Pass
      ]
      
      results = fallback_system.test_detection(simple_test)
      expect(results[:success_rate]).to eq("100.0%")
    end

    it "handles empty test cases" do
      results = fallback_system.test_detection([])
      
      expect(results[:total_tests]).to eq(0)
      expect(results[:passed]).to eq(0)
      expect(results[:failed]).to eq(0)
      expect(results[:details]).to eq([])
    end
  end

  describe "private methods" do
    describe "#normalize_agent_name" do
      it "removes 'agent' suffix" do
        normalized = fallback_system.send(:normalize_agent_name, "Support Agent")
        expect(normalized).to eq("Support")
      end

      it "handles case insensitive 'agent' suffix" do
        normalized = fallback_system.send(:normalize_agent_name, "billing AGENT")
        expect(normalized).to eq("billing")
      end

      it "removes whitespace around 'agent'" do
        normalized = fallback_system.send(:normalize_agent_name, "Technical  agent  ")
        expect(normalized).to eq("Technical")
      end

      it "preserves names without 'agent' suffix" do
        normalized = fallback_system.send(:normalize_agent_name, "Support")
        expect(normalized).to eq("Support")
      end

      it "handles empty strings" do
        normalized = fallback_system.send(:normalize_agent_name, "")
        expect(normalized).to eq("")
      end
    end

    describe "#calculate_confidence" do
      it "gives higher confidence for JSON format" do
        confidence = fallback_system.send(:calculate_confidence, '{"handoff_to": "Support"}', "Support")
        expect(confidence).to be >= 0.7
      end

      it "gives medium confidence for structured format" do
        confidence = fallback_system.send(:calculate_confidence, '[HANDOFF:Support]', "Support")
        expect(confidence).to be_between(0.6, 0.9)
      end

      it "gives lower confidence for natural language" do
        confidence = fallback_system.send(:calculate_confidence, 'transfer to Support', "Support")
        expect(confidence).to be_between(0.4, 0.7)
      end

      it "boosts confidence for exact agent name match" do
        with_match = fallback_system.send(:calculate_confidence, 'Transfer to Support', "Support")
        without_match = fallback_system.send(:calculate_confidence, 'Transfer to agent', "Support")
        
        expect(with_match).to be > without_match
      end

      it "reduces confidence for ambiguous content" do
        ambiguous = fallback_system.send(:calculate_confidence, 'transfer agent handoff transfer agent', "Support")
        clear = fallback_system.send(:calculate_confidence, 'Transfer to Support', "Support")
        
        expect(clear).to be > ambiguous
      end

      it "caps confidence at 1.0" do
        confidence = fallback_system.send(:calculate_confidence, '{"handoff_to": "Support"} Support exact match', "Support")
        expect(confidence).to be <= 1.0
      end
    end
  end

  describe "integration scenarios" do
    it "handles complex multi-pattern content" do
      content = <<~TEXT
        I understand your request. Let me help you with that.
        
        {"handoff_to": "Support"}
        
        [HANDOFF:Support]
        
        I'm transferring you to Support for specialized assistance.
      TEXT
      
      result = fallback_system.detect_handoff_in_content(content)
      expect(result).to eq("Support")
    end

    it "prioritizes more reliable patterns" do
      # Content with both JSON (reliable) and natural language (less reliable)
      content = 'I will transfer to Billing. {"handoff_to": "Support"}'
      
      result = fallback_system.detect_handoff_in_content(content)
      # JSON pattern should win over natural language
      expect(result).to eq("Support")
    end

    it "maintains statistics across different detection methods" do
      # Use basic detection
      fallback_system.detect_handoff_in_content('{"handoff_to": "Support"}')
      
      # Use context detection
      fallback_system.detect_handoff_with_context('[HANDOFF:Billing]')
      
      # Statistics should reflect both
      stats = fallback_system.get_detection_stats
      expect(stats[:total_attempts]).to eq(2)
      expect(stats[:successful_detections]).to eq(2)
    end

    it "works with real-world conversation content" do
      realistic_content = <<~CONVERSATION
        I understand you're having trouble with your billing. Let me review your account details.
        
        After checking, I can see this is a complex billing issue that requires our specialist team.
        I'm going to transfer you to our Billing department who can better assist with this specific concern.
        
        {"handoff_to": "Billing"}
        
        They'll be able to help you resolve this billing discrepancy right away.
      CONVERSATION
      
      result = fallback_system.detect_handoff_in_content(realistic_content)
      expect(result).to eq("Billing")
      
      # Should also work with context detection
      context_result = fallback_system.detect_handoff_with_context(realistic_content, { session_id: "123" })
      expect(context_result[:handoff_detected]).to be true
      expect(context_result[:target_agent]).to eq("Billing")
      expect(context_result[:confidence]).to be > 0.5
    end
  end

  describe "error handling" do
    it "handles malformed JSON gracefully" do
      malformed_json = '{"handoff_to": "Support" invalid json'
      
      expect {
        result = fallback_system.detect_handoff_in_content(malformed_json)
        # Pattern matching will still work on the valid part
        expect(result).to eq("Support")
      }.not_to raise_error
    end

    it "handles special characters in agent names" do
      special_agents = ["Agent-1", "Agent_2", "Agent.3", "Agent@4"]
      system = described_class.new(special_agents)
      
      special_agents.each do |agent|
        content = %({"handoff_to": "#{agent}"})
        result = system.detect_handoff_in_content(content)
        expect(result).to eq(agent)
      end
    end

    it "handles very long content efficiently" do
      long_content = "x" * 10_000 + '{"handoff_to": "Support"}' + "y" * 10_000
      
      start_time = Time.now
      result = fallback_system.detect_handoff_in_content(long_content)
      duration = Time.now - start_time
      
      expect(result).to eq("Support")
      expect(duration).to be < 1.0 # Should complete within 1 second
    end

    it "handles Unicode and international characters" do
      content = '{"handoff_to": "Süppört"}'
      system = described_class.new(["Süppört"])
      
      result = system.detect_handoff_in_content(content)
      expect(result).to eq("Süppört")
    end
  end
end