#!/usr/bin/env ruby
# frozen_string_literal: true

# Debug script to trace token usage from Gemini provider through RAAF chain

# Load gems from local path first
$LOAD_PATH.unshift File.expand_path("core/lib", __dir__)
$LOAD_PATH.unshift File.expand_path("providers/lib", __dir__)

require "bundler/setup"
require "raaf-core"
require "raaf/providers/gemini_provider"

puts "=" * 80
puts "TOKEN FLOW DEBUG SCRIPT"
puts "=" * 80

# Create a simple Gemini agent
agent = RAAF::Agent.new(
  name: "TokenDebugAgent",
  instructions: "You are a helpful assistant. Respond briefly to test token tracking.",
  model: "gemini-2.0-flash-exp"
)

puts "\n1. Agent created with model: #{agent.model}"

# Patch GeminiProvider to debug token extraction
module RAAF
  module Models
    class GeminiProvider
      alias_method :original_chat, :chat

      def chat(params)
        puts "\n2. GeminiProvider.chat called with params keys: #{params.keys}"
        result = original_chat(params)

        puts "\n3. GeminiProvider raw response:"
        puts "   Response class: #{result.class}"
        puts "   Response keys: #{result.keys}" if result.is_a?(Hash)

        if result[:usage]
          puts "\n4. PROVIDER LEVEL - Usage found in response:"
          puts "   usage keys: #{result[:usage].keys}"
          puts "   prompt_tokens: #{result[:usage][:prompt_tokens]}"
          puts "   completion_tokens: #{result[:usage][:completion_tokens]}"
          puts "   total_tokens: #{result[:usage][:total_tokens]}"
        else
          puts "\n4. PROVIDER LEVEL - NO usage field in response!"
        end

        result
      end
    end
  end
end

# Patch Runner to debug token flow
module RAAF
  class Runner
    alias_method :original_process_response, :process_response

    def process_response(response, context)
      puts "\n5. Runner.process_response called"
      puts "   Response keys: #{response.keys}" if response.is_a?(Hash)

      if response[:usage]
        puts "\n6. RUNNER LEVEL - Usage in response:"
        puts "   usage keys: #{response[:usage].keys}"
        puts "   prompt_tokens: #{response[:usage][:prompt_tokens]}"
        puts "   completion_tokens: #{response[:usage][:completion_tokens]}"
        puts "   total_tokens: #{response[:usage][:total_tokens]}"
      else
        puts "\n6. RUNNER LEVEL - NO usage field in response!"
      end

      result = original_process_response(response, context)

      puts "\n7. After process_response:"
      puts "   Result class: #{result.class}"
      puts "   Result keys: #{result.keys}" if result.is_a?(Hash)

      if result[:usage]
        puts "\n8. RESULT LEVEL (after processing) - Usage preserved:"
        puts "   usage keys: #{result[:usage].keys}"
        puts "   prompt_tokens: #{result[:usage][:prompt_tokens]}"
        puts "   completion_tokens: #{result[:usage][:completion_tokens]}"
        puts "   total_tokens: #{result[:usage][:total_tokens]}"
      else
        puts "\n8. RESULT LEVEL (after processing) - NO usage field!"
      end

      result
    end
  end
end

# Create runner and run the agent
puts "\n" + "=" * 80
puts "RUNNING AGENT"
puts "=" * 80

runner = RAAF::Runner.new(agent: agent)
result = runner.run("Say hello and tell me your model name.")

# Check final result
puts "\n" + "=" * 80
puts "FINAL RESULT ANALYSIS"
puts "=" * 80

puts "\n9. Final result object:"
puts "   Class: #{result.class}"
puts "   Keys: #{result.keys}" if result.respond_to?(:keys)

if result.respond_to?(:usage)
  puts "\n10. FINAL - Usage accessible via method:"
  usage = result.usage
  puts "   Usage: #{usage.inspect}"
else
  puts "\n10. FINAL - No usage method!"
end

if result.respond_to?(:[]) && result[:usage]
  puts "\n11. FINAL - Usage accessible via hash key:"
  puts "   usage keys: #{result[:usage].keys}"
  puts "   prompt_tokens: #{result[:usage][:prompt_tokens]}"
  puts "   completion_tokens: #{result[:usage][:completion_tokens]}"
  puts "   total_tokens: #{result[:usage][:total_tokens]}"
else
  puts "\n11. FINAL - NO usage accessible via hash key!"
end

# Try accessing through RunContext methods
if result.is_a?(RAAF::RunContext)
  puts "\n12. Result is RunContext - checking get/[] access:"
  puts "   result.get(:usage): #{result.get(:usage).inspect}"
  puts "   result[:usage]: #{result[:usage].inspect}"

  # Check internal data structure
  puts "\n13. Checking RunContext internals:"
  if result.instance_variable_defined?(:@data)
    data = result.instance_variable_get(:@data)
    puts "   @data keys: #{data.keys}"
    puts "   @data[:usage]: #{data[:usage].inspect}"
  end

  if result.instance_variable_defined?(:@context_data)
    context_data = result.instance_variable_get(:@context_data)
    puts "   @context_data keys: #{context_data.keys}"
    puts "   @context_data[:usage]: #{context_data[:usage].inspect}"
  end
end

puts "\n" + "=" * 80
puts "DEBUG COMPLETE"
puts "=" * 80
