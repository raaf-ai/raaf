# frozen_string_literal: true

require_relative "../logging"

module RAAF
  module Models
    ##
    # Handoff Fallback System for Non-Function-Calling LLMs
    #
    # This system provides handoff support for LLMs that don't support function calling
    # by using advanced content-based detection, structured prompting, and response parsing.
    #
    # It implements multiple fallback strategies to ensure handoff functionality
    # works across all LLM types, even those without native function calling.
    #
    # @example Basic usage
    #   fallback = HandoffFallbackSystem.new(["Support", "Billing", "Technical"])
    #   
    #   # Generate instructions for system prompt
    #   instructions = fallback.generate_handoff_instructions(["Support", "Billing"])
    #   
    #   # Detect handoff in response content
    #   target = fallback.detect_handoff_in_content('I need to transfer you. {"handoff_to": "Support"}')
    #   puts "Handoff to: #{target}" # "Support"
    #
    # @example With statistics tracking
    #   fallback = HandoffFallbackSystem.new(["Support", "Billing"])
    #   
    #   # Use detection multiple times
    #   fallback.detect_handoff_in_content('Transfer to Support')
    #   fallback.detect_handoff_in_content('No handoff here')
    #   fallback.detect_handoff_in_content('[HANDOFF:Billing]')
    #   
    #   # Get performance statistics
    #   stats = fallback.get_detection_stats
    #   puts "Success rate: #{stats[:success_rate]}" # "66.67%"
    #   puts "Most effective patterns: #{stats[:most_effective_patterns]}"
    #
    # @example Testing detection patterns
    #   fallback = HandoffFallbackSystem.new(["Support", "Billing"])
    #   
    #   test_cases = [
    #     { content: '{"handoff_to": "Support"}', expected_agent: "Support" },
    #     { content: 'Transfer to Billing', expected_agent: "Billing" },
    #     { content: 'No handoff here', expected_agent: nil }
    #   ]
    #   
    #   results = fallback.test_detection(test_cases)
    #   puts "Test success rate: #{results[:success_rate]}"
    #
    # @author RAAF Development Team
    # @since 0.2.0
    #
    class HandoffFallbackSystem
      include Logger

      # Handoff detection patterns for content-based parsing
      HANDOFF_PATTERNS = [
        # JSON-based patterns
        /"handoff_to":\s*"([^"]+)"/i,
        /"transfer_to":\s*"([^"]+)"/i,
        /"assistant":\s*"([^"]+)"/i,
        
        # Structured text patterns
        /\[HANDOFF:([^\]]+)\]/i,
        /\[TRANSFER:([^\]]+)\]/i,
        /\[AGENT:([^\]]+)\]/i,
        
        # Natural language patterns
        /transfer(?:ring)?\s+(?:to|you)\s+(?:to\s+)?([a-zA-Z_][a-zA-Z0-9_]*(?:\s*agent)?)/i,
        /handoff?\s+to\s+([a-zA-Z_][a-zA-Z0-9_]*(?:\s*agent)?)/i,
        /switching\s+to\s+([a-zA-Z_][a-zA-Z0-9_]*(?:\s*agent)?)/i,
        /forwarding\s+to\s+([a-zA-Z_][a-zA-Z0-9_]*(?:\s*agent)?)/i,
        
        # Code-style patterns
        /handoff\(["']([^"']+)["']\)/i,
        /transfer\(["']([^"']+)["']\)/i,
        /agent\(["']([^"']+)["']\)/i
      ].freeze

      # System instructions for non-function-calling LLMs
      HANDOFF_INSTRUCTIONS = <<~INSTRUCTIONS
        # Handoff Instructions for Multi-Agent System

        You are part of a multi-agent system. When you need to transfer control to another agent, use one of these formats:

        ## Preferred Format (JSON):
        ```json
        {"handoff_to": "AgentName"}
        ```

        ## Alternative Formats:
        - [HANDOFF:AgentName]
        - [TRANSFER:AgentName]
        - Transfer to AgentName

        ## Available Agents:
        %{available_agents}

        ## Important:
        - Only handoff when necessary
        - Use exact agent names
        - Include handoff instruction in your response
        - Continue with normal response after handoff instruction
      INSTRUCTIONS

      # Initialize fallback system
      #
      # @param available_agents [Array<String>] List of available agent names
      # @example Initialize with agents
      #   fallback = HandoffFallbackSystem.new(["Support", "Billing", "Technical"])
      #
      def initialize(available_agents = [])
        @available_agents = available_agents
        @detection_stats = {
          attempts: 0,
          successes: 0,
          patterns_matched: Hash.new(0)
        }
      end

      ##
      # Generate system instructions for non-function-calling LLMs
      #
      # Creates detailed instructions that teach the LLM how to trigger handoffs
      # using content-based patterns that this system can detect.
      #
      # @example Generate instructions
      #   fallback = HandoffFallbackSystem.new(["Support", "Billing"])
      #   instructions = fallback.generate_handoff_instructions(["Support", "Billing"])
      #   puts instructions
      #   # Output includes:
      #   # "# Handoff Instructions for Multi-Agent System"
      #   # "## Preferred Format (JSON):"
      #   # '{"handoff_to": "AgentName"}'
      #   # "## Available Agents:"
      #   # "- Support"
      #   # "- Billing"
      #
      # @param available_agents [Array<String>] Available agent names
      # @return [String] Enhanced system instructions with handoff patterns
      #
      def generate_handoff_instructions(available_agents)
        agents_list = available_agents.map { |name| "- #{name}" }.join("\n")
        
        HANDOFF_INSTRUCTIONS % { available_agents: agents_list }
      end

      ##
      # Detect handoff requests in text content
      #
      # This is the core detection method that analyzes response content
      # using multiple pattern matching strategies to find handoff requests.
      #
      # @example Detect JSON handoff
      #   fallback = HandoffFallbackSystem.new(["Support", "Billing"])
      #   content = 'I can help with that. {"handoff_to": "Support"}'
      #   target = fallback.detect_handoff_in_content(content)
      #   puts target # "Support"
      #
      # @example Detect structured handoff
      #   content = 'Let me transfer you. [HANDOFF:Billing]'
      #   target = fallback.detect_handoff_in_content(content)
      #   puts target # "Billing"
      #
      # @example Detect natural language handoff
      #   content = 'I will transfer you to Support for assistance.'
      #   target = fallback.detect_handoff_in_content(content)
      #   puts target # "Support"
      #
      # @example No handoff detected
      #   content = 'This is just a regular response.'
      #   target = fallback.detect_handoff_in_content(content)
      #   puts target # nil
      #
      # @param content [String] Response content to analyze
      # @return [String, nil] Target agent name if handoff detected, nil otherwise
      #
      def detect_handoff_in_content(content)
        return nil unless content.is_a?(String) && !content.empty?

        @detection_stats[:attempts] += 1
        
        log_debug("🔍 HANDOFF FALLBACK: Analyzing content for handoff patterns",
                  content_length: content.length,
                  available_agents: @available_agents.join(", "))

        # Try each pattern in order of reliability
        HANDOFF_PATTERNS.each_with_index do |pattern, index|
          match = content.match(pattern)
          next unless match

          candidate_agent = match[1].strip
          
          # Clean up agent name (remove "agent" suffix, normalize case)
          candidate_agent = normalize_agent_name(candidate_agent)
          
          # Validate against available agents
          if @available_agents.any? { |agent| agent.downcase == candidate_agent.downcase }
            actual_agent = @available_agents.find { |agent| agent.downcase == candidate_agent.downcase }
            
            @detection_stats[:successes] += 1
            @detection_stats[:patterns_matched][index] += 1
            
            log_debug("🔍 HANDOFF FALLBACK: Handoff detected",
                      pattern_index: index,
                      pattern: pattern.inspect,
                      raw_match: match[1],
                      normalized_agent: candidate_agent,
                      actual_agent: actual_agent)
            
            return actual_agent
          else
            log_debug("🔍 HANDOFF FALLBACK: Agent name not found in available agents",
                      candidate: candidate_agent,
                      available: @available_agents.join(", "))
          end
        end

        log_debug("🔍 HANDOFF FALLBACK: No handoff detected in content")
        nil
      end

      ##
      # Enhanced content-based handoff detection with context
      #
      # Provides detailed handoff detection results including confidence scores
      # and context information. Useful for debugging and monitoring.
      #
      # @example Basic context detection
      #   fallback = HandoffFallbackSystem.new(["Support"])
      #   content = '{"handoff_to": "Support"}'
      #   context = { conversation_id: "123", user_id: "456" }
      #   
      #   result = fallback.detect_handoff_with_context(content, context)
      #   puts result[:handoff_detected] # true
      #   puts result[:target_agent] # "Support"
      #   puts result[:confidence] # 0.8
      #   puts result[:detection_method] # "content_based"
      #   puts result[:context] # { conversation_id: "123", user_id: "456" }
      #
      # @example Failed detection
      #   result = fallback.detect_handoff_with_context("No handoff here")
      #   puts result[:handoff_detected] # false
      #   puts result[:target_agent] # nil
      #   puts result[:confidence] # 0.0
      #
      # @param content [String] Response content to analyze
      # @param context [Hash] Additional context for detection (optional)
      # @return [Hash] Detailed detection result with keys:
      #   - :handoff_detected - Boolean indicating if handoff was found
      #   - :target_agent - Target agent name or nil
      #   - :detection_method - "content_based" or nil
      #   - :confidence - Confidence score (0.0 to 1.0)
      #   - :context - Provided context hash
      #
      def detect_handoff_with_context(content, context = {})
        target_agent = detect_handoff_in_content(content)
        
        result = {
          handoff_detected: !target_agent.nil?,
          target_agent: target_agent,
          detection_method: target_agent ? "content_based" : nil,
          confidence: target_agent ? calculate_confidence(content, target_agent) : 0.0,
          context: context
        }

        log_debug("🔍 HANDOFF FALLBACK: Detection result",
                  result: result)

        result
      end

      ##
      # Generate handoff response in multiple formats
      #
      # This helps ensure the LLM can use the format it's most comfortable with.
      # Generates a response that includes multiple handoff formats to maximize
      # detection reliability.
      #
      # @example Generate basic handoff response
      #   fallback = HandoffFallbackSystem.new(["Support"])
      #   response = fallback.generate_handoff_response("Support")
      #   puts response
      #   # Output:
      #   # "Transferring to Support"
      #   # ""
      #   # '{"handoff_to":"Support"}'
      #
      # @example Generate handoff with custom message
      #   response = fallback.generate_handoff_response("Support", "I need specialist help")
      #   puts response
      #   # Output:
      #   # "I need specialist help"
      #   # ""
      #   # '{"handoff_to":"Support"}'
      #
      # @param target_agent [String] Target agent name
      # @param message [String] Optional message to include (default: "Transferring to {agent}")
      # @return [String] Formatted handoff response with multiple detection patterns
      #
      def generate_handoff_response(target_agent, message = nil)
        base_message = message || "Transferring to #{target_agent}"
        
        # Primary format (JSON)
        json_handoff = JSON.generate({ handoff_to: target_agent })
        
        # Alternative formats
        formats = [
          "#{base_message}\n\n#{json_handoff}",
          "#{base_message}\n\n[HANDOFF:#{target_agent}]",
          "#{base_message}\n\nTransfer to #{target_agent}"
        ]

        # Return the most explicit format
        formats.first
      end

      ##
      # Get detection statistics
      #
      # Returns comprehensive statistics about handoff detection performance,
      # including success rates and pattern effectiveness.
      #
      # @example Get statistics after multiple detections
      #   fallback = HandoffFallbackSystem.new(["Support", "Billing"])
      #   
      #   fallback.detect_handoff_in_content('{"handoff_to": "Support"}')
      #   fallback.detect_handoff_in_content('No handoff here')
      #   fallback.detect_handoff_in_content('[HANDOFF:Billing]')
      #   
      #   stats = fallback.get_detection_stats
      #   puts "Total attempts: #{stats[:total_attempts]}" # 3
      #   puts "Successful detections: #{stats[:successful_detections]}" # 2
      #   puts "Success rate: #{stats[:success_rate]}" # "66.67%"
      #   puts "Available agents: #{stats[:available_agents]}" # ["Support", "Billing"]
      #
      # @return [Hash] Statistics with keys:
      #   - :total_attempts - Total number of detection attempts
      #   - :successful_detections - Number of successful detections
      #   - :success_rate - Success rate as percentage string
      #   - :most_effective_patterns - Array of most effective patterns
      #   - :available_agents - List of available agent names
      #
      def get_detection_stats
        success_rate = @detection_stats[:attempts] > 0 ? 
                      (@detection_stats[:successes].to_f / @detection_stats[:attempts] * 100).round(2) : 0.0

        {
          total_attempts: @detection_stats[:attempts],
          successful_detections: @detection_stats[:successes],
          success_rate: "#{success_rate}%",
          most_effective_patterns: @detection_stats[:patterns_matched].sort_by { |_, count| -count }.first(3),
          available_agents: @available_agents
        }
      end

      ##
      # Reset detection statistics
      #
      # Clears all detection statistics while preserving available agents.
      # Useful for resetting performance tracking.
      #
      # @example Reset statistics
      #   fallback = HandoffFallbackSystem.new(["Support"])
      #   
      #   # Use detection multiple times
      #   fallback.detect_handoff_in_content('{"handoff_to": "Support"}')
      #   puts fallback.get_detection_stats[:total_attempts] # 1
      #   
      #   # Reset and verify
      #   fallback.reset_stats
      #   puts fallback.get_detection_stats[:total_attempts] # 0
      #   puts fallback.get_detection_stats[:available_agents] # ["Support"] (preserved)
      #
      # @return [void]
      #
      def reset_stats
        @detection_stats = {
          attempts: 0,
          successes: 0,
          patterns_matched: Hash.new(0)
        }
      end

      ##
      # Test handoff detection with sample content
      #
      # Runs a comprehensive test suite against provided test cases to validate
      # detection accuracy and performance.
      #
      # @example Test detection patterns
      #   fallback = HandoffFallbackSystem.new(["Support", "Billing"])
      #   
      #   test_cases = [
      #     { content: '{"handoff_to": "Support"}', expected_agent: "Support" },
      #     { content: '[HANDOFF:Billing]', expected_agent: "Billing" },
      #     { content: 'Transfer to Support', expected_agent: "Support" },
      #     { content: 'No handoff here', expected_agent: nil },
      #     { content: '{"handoff_to": "Unknown"}', expected_agent: nil }
      #   ]
      #   
      #   results = fallback.test_detection(test_cases)
      #   puts "Total tests: #{results[:total_tests]}" # 5
      #   puts "Passed: #{results[:passed]}" # 4
      #   puts "Failed: #{results[:failed]}" # 1
      #   puts "Success rate: #{results[:success_rate]}" # "80.0%"
      #   
      #   # Examine individual test results
      #   results[:details].each do |detail|
      #     puts "Content: #{detail[:content]}"
      #     puts "Expected: #{detail[:expected]}"
      #     puts "Detected: #{detail[:detected]}"
      #     puts "Passed: #{detail[:passed]}"
      #   end
      #
      # @param test_cases [Array<Hash>] Array of test cases with keys:
      #   - :content - Content to test
      #   - :expected_agent - Expected agent name (or nil)
      # @return [Hash] Test results with keys:
      #   - :total_tests - Total number of test cases
      #   - :passed - Number of tests that passed
      #   - :failed - Number of tests that failed
      #   - :success_rate - Success rate as percentage string
      #   - :details - Array of detailed results for each test
      #
      def test_detection(test_cases)
        results = {
          total_tests: test_cases.size,
          passed: 0,
          failed: 0,
          details: []
        }

        test_cases.each do |test_case|
          content = test_case[:content]
          expected = test_case[:expected_agent]
          
          detected = detect_handoff_in_content(content)
          passed = detected == expected
          
          results[:passed] += 1 if passed
          results[:failed] += 1 unless passed
          
          results[:details] << {
            content: content[0..100] + (content.length > 100 ? "..." : ""),
            expected: expected,
            detected: detected,
            passed: passed
          }
        end

        results[:success_rate] = "#{(results[:passed].to_f / results[:total_tests] * 100).round(2)}%"
        results
      end

      private

      ##
      # Normalize agent name for comparison
      #
      # Removes common suffixes and normalizes agent names for matching.
      # This allows flexible agent name matching (e.g., "Support Agent" -> "Support").
      #
      # @example Normalize agent names
      #   fallback = HandoffFallbackSystem.new(["Support"])
      #   
      #   normalized = fallback.send(:normalize_agent_name, "Support Agent")
      #   puts normalized # "Support"
      #   
      #   normalized = fallback.send(:normalize_agent_name, "billing agent")
      #   puts normalized # "billing"
      #
      # @param name [String] Agent name to normalize
      # @return [String] Normalized agent name
      #
      def normalize_agent_name(name)
        name.gsub(/\s*agent\s*$/i, '').strip
      end

      ##
      # Calculate confidence score for handoff detection
      #
      # Computes a confidence score (0.0 to 1.0) based on the type of pattern
      # matched and the clarity of the handoff request.
      #
      # @example Calculate confidence scores
      #   fallback = HandoffFallbackSystem.new(["Support"])
      #   
      #   # High confidence for JSON format
      #   conf1 = fallback.send(:calculate_confidence, '{"handoff_to": "Support"}', "Support")
      #   puts conf1 # ~0.8 (high confidence)
      #   
      #   # Medium confidence for structured format
      #   conf2 = fallback.send(:calculate_confidence, '[HANDOFF:Support]', "Support")
      #   puts conf2 # ~0.7 (medium confidence)
      #   
      #   # Lower confidence for natural language
      #   conf3 = fallback.send(:calculate_confidence, 'Transfer to Support', "Support")
      #   puts conf3 # ~0.5 (lower confidence)
      #
      # @param content [String] Content that triggered the detection
      # @param target_agent [String] Detected target agent name
      # @return [Float] Confidence score between 0.0 and 1.0
      #
      def calculate_confidence(content, target_agent)
        # Base confidence
        confidence = 0.5
        
        # Boost for JSON format
        confidence += 0.3 if content.include?('{"handoff_to"') || content.include?('{"transfer_to"')
        
        # Boost for structured format
        confidence += 0.2 if content.include?('[HANDOFF:') || content.include?('[TRANSFER:')
        
        # Boost for exact agent name match
        confidence += 0.2 if content.include?(target_agent)
        
        # Reduce for ambiguous content
        confidence -= 0.1 if content.scan(/transfer|handoff|agent/i).size > 3
        
        [confidence, 1.0].min
      end
    end
  end
end