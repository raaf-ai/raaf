#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/raaf-core"
require_relative "lib/raaf/models/capability_detector"
require_relative "lib/raaf/models/interface"

# Test capability detector with non-function calling provider from ProviderAdapter spec
non_function_calling_provider = Class.new(RAAF::Models::ModelInterface) do
  def chat_completion(messages:, model:, stream: false, **_kwargs)
    # NOTE: No tools parameter
    {
      "choices" => [{
        "message" => {
          "role" => "assistant",
          "content" => 'I can help you. {"handoff_to": "SupportAgent"}'
        }
      }],
      "usage" => { "prompt_tokens" => 8, "completion_tokens" => 12, "total_tokens" => 20 }
    }
  end

  def supported_models
    ["non-function-model-v1"]
  end

  def provider_name
    "NonFunctionCallingProvider"
  end
end.new

detector = RAAF::Models::CapabilityDetector.new(non_function_calling_provider)
report = detector.generate_report

puts "Provider: #{non_function_calling_provider.provider_name}"
puts "Has chat_completion: #{non_function_calling_provider.respond_to?(:chat_completion)}"

# Debug the method parameter introspection
if non_function_calling_provider.respond_to?(:chat_completion)
  begin
    method = non_function_calling_provider.method(:chat_completion)
    params = method.parameters
    puts "Method parameters: #{params.inspect}"
    tools_param = params.any? { |_param_type, param_name| param_name == :tools }
    puts "Has tools param: #{tools_param}"

    # Check if method is actually implemented or just inherited
    puts "Method owner: #{method.owner}"
    puts "Actual class: #{non_function_calling_provider.class}"
    puts "Is implemented: #{method.owner == non_function_calling_provider.class}"
  rescue StandardError => e
    puts "Parameter introspection failed: #{e.class} - #{e.message}"
  end
end

puts "Function calling capability: #{report[:capabilities].find { |c| c[:name] == "Function Calling" }[:supported]}"
puts "Handoff support: #{report[:handoff_support]}"
