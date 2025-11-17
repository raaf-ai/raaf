#!/usr/bin/env ruby
# frozen_string_literal: true

# Token tracking trace for OpenAI provider
# Run with: cd core && bundle exec ruby ../openai_token_trace.rb

# Add to load path
raaf_root = File.expand_path(__dir__)
$LOAD_PATH.unshift File.join(raaf_root, "core/lib")
$LOAD_PATH.unshift File.join(raaf_root, "providers/lib")

require "raaf-core"
require "raaf-providers"

puts "=" * 80
puts "OpenAI Token Usage Trace"
puts "=" * 80
puts

# Read API key
env_file = "/Users/hajee/Enterprise Modules Dropbox/Bert Hajee/enterprisemodules/work/prospects_radar/.env"
api_key = ENV["OPENAI_API_KEY"]

if api_key.nil? || api_key.empty?
  if File.exist?(env_file)
    env_content = File.read(env_file)
    if env_content =~ /OPENAI_API_KEY=(.+)/
      api_key = $1.strip.split(/\s+#/).first.strip
      puts "📝 Using OPENAI_API_KEY from .env file"
      ENV["OPENAI_API_KEY"] = api_key
    end
  end
end

if api_key.nil? || api_key.empty?
  puts "ERROR: OPENAI_API_KEY not found"
  exit 1
end

# Patch ResponsesProvider to debug token usage
module RAAF
  module Models
    class ResponsesProvider
      alias_method :original_responses_completion, :responses_completion

      def responses_completion(messages:, model:, **kwargs)
        puts "\n1. 🤖 ResponsesProvider.responses_completion called"
        puts "   Model: #{model}"
        puts "   Messages: #{messages.count} messages"

        result = original_responses_completion(messages: messages, model: model, **kwargs)

        puts "\n2. 📥 ResponsesProvider response received"
        puts "   Response class: #{result.class.name}"
        puts "   Response keys: #{result.keys.inspect}" if result.respond_to?(:keys)

        if result[:usage]
          puts "\n3. ✅ PROVIDER LEVEL - Usage data found:"
          puts "   Usage keys: #{result[:usage].keys.inspect}"
          puts "   input_tokens: #{result[:usage][:input_tokens]}"  # NEW canonical name
          puts "   output_tokens: #{result[:usage][:output_tokens]}"  # NEW canonical name
          puts "   total_tokens: #{result[:usage][:total_tokens]}"
          puts "   Details: #{result[:usage].inspect}"
        else
          puts "\n3. ❌ PROVIDER LEVEL - NO usage data!"
          puts "   Available keys: #{result.keys.inspect}"
        end

        result
      end
    end
  end
end

# Patch Runner to trace usage flow
module RAAF
  class Runner
    alias_method :original_run, :run

    def run(message = nil, **kwargs)
      puts "\n4. 🏃 Runner.run called"
      puts "   Message: #{message}"

      result = original_run(message, **kwargs)

      puts "\n5. 📤 Runner result returned"
      puts "   Result class: #{result.class.name}"

      # Check different ways to access usage
      if result.respond_to?(:usage)
        puts "\n6. ✅ RUNNER LEVEL - Usage accessible via .usage method:"
        usage = result.usage
        puts "   Usage: #{usage.inspect}"
      else
        puts "\n6. ❌ RUNNER LEVEL - No .usage method"
      end

      if result.respond_to?(:[])
        puts "\n7. 🔍 Checking hash key access:"
        if result[:usage]
          puts "   ✅ result[:usage] exists: #{result[:usage].inspect}"
        else
          puts "   ❌ result[:usage] is nil or missing"
          puts "   Available keys: #{result.keys.inspect}" if result.respond_to?(:keys)
        end
      end

      # Check RunContext internals
      if result.is_a?(RAAF::RunContext)
        puts "\n8. 🔬 RunContext internals check:"
        puts "   Class: #{result.class.name}"

        # Check instance variables
        ivars = result.instance_variables
        puts "   Instance variables: #{ivars.inspect}"

        ivars.each do |ivar|
          value = result.instance_variable_get(ivar)
          puts "   #{ivar}: #{value.class.name}"
          if value.respond_to?(:keys)
            puts "     Keys: #{value.keys.inspect}"
            if value[:usage] || value["usage"]
              puts "     ✅ FOUND USAGE: #{(value[:usage] || value["usage"]).inspect}"
            end
          end
        end
      end

      result
    end
  end
end

puts "\n" + "=" * 80
puts "Creating Agent and Running Test"
puts "=" * 80

# Create agent
agent = RAAF::Agent.new(
  name: "TestAgent",
  instructions: "You are a helpful assistant. Respond briefly.",
  model: "gpt-4o-mini"
)

puts "\n✅ Agent created: #{agent.name}"

# Create provider and runner (use default ResponsesProvider)
runner = RAAF::Runner.new(agent: agent)

puts "✅ Runner created with ResponsesProvider (default)"
puts "\n" + "=" * 80
puts "Running Agent"
puts "=" * 80

# Run agent
result = runner.run("Say hello and tell me your model name.")

puts "\n" + "=" * 80
puts "FINAL ANALYSIS"
puts "=" * 80

puts "\nToken Usage Summary:"
puts "- Provider level: Check output above (step 3)"
puts "- Runner level: Check output above (steps 6-7)"
puts "- RunContext internals: Check output above (step 8)"
puts "\nLook for ✅ markers to see where usage data exists"
puts "Look for ❌ markers to see where usage data is missing"
puts "\n" + "=" * 80
