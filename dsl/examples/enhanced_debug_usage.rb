#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage example for enhanced debugging capabilities in RAAF::DSL::Agents::Base
#
# This example demonstrates how to use the new debugging features in a real scenario.

puts "=" * 80
puts "🔍 ENHANCED DEBUGGING USAGE EXAMPLES"
puts "=" * 80
puts

puts "1. Basic agent run with enhanced debugging:"
puts "   result = agent.run(debug_level: :verbose)"
puts

puts "2. Enhanced debugging with context variables:"
puts "   result = agent.run_with_debug("
puts "     input_context_variables: { session_id: 'abc-123' },"
puts "     debug_level: :verbose"
puts "   )"
puts

puts "3. Convenience methods for different debug levels:"
puts "   # Minimal debugging - basic execution flow"
puts "   result = agent.run_with_minimal_debug"
puts
puts "   # Standard debugging - includes LLM interception"
puts "   result = agent.run_with_standard_debug"
puts
puts "   # Verbose debugging - includes prompt and context inspection"
puts "   result = agent.run_with_verbose_debug"
puts

puts "4. Inspect agent state without running:"
puts "   # Get comprehensive context summary"
puts "   summary = agent.debug_context_summary"
puts
puts "   # Inspect current context variables"
puts "   agent.inspect_context"
puts
puts "   # Inspect prompt templates with substitutions"
puts "   agent.inspect_prompts"
puts

puts "5. Debug information in results:"
puts "   result = agent.run_with_debug(debug_level: :verbose)"
puts "   puts result[:debug_info][:context_summary]"
puts "   puts result[:debug_info][:execution_metadata]"
puts

puts "6. Integration with ProspectRadar patterns:"
puts <<~EXAMPLE
  # In ProspectRadar controllers or services:
  class ProspectDiscoveryService < BaseService
    def call_with_debug
      agent = create_discovery_agent
  #{"    "}
      # Enhanced debugging for development
      if Rails.env.development?
        result = agent.run_with_debug(
          input_context_variables: @context_variables,
          debug_level: :verbose
        )
  #{"      "}
        # Log debug summary
        Rails.logger.info "🔍 Agent Debug Summary:"
        Rails.logger.info result[:debug_info][:context_summary]
  #{"      "}
        return result
      end
  #{"    "}
      # Standard run for production
      agent.run(input_context_variables: @context_variables)
    end
  end
EXAMPLE

puts

puts "7. Available debug levels:"
puts "   :minimal  - Basic execution flow logging"
puts "   :standard - Includes LLM request/response interception"
puts "   :verbose  - Includes prompt and context inspection"
puts

puts "8. Debug output includes:"
puts "   - Complete OpenAI API requests and responses"
puts "   - Rendered prompts with variable substitutions"
puts "   - Context variable state at each step"
puts "   - Execution metadata (tokens, turns, tool calls)"
puts "   - Configuration source information"
puts

puts "=" * 80
puts "🏁 ENHANCED DEBUGGING USAGE EXAMPLES COMPLETE"
puts "=" * 80
