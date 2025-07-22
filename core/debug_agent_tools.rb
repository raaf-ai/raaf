#!/usr/bin/env ruby

require_relative 'lib/raaf-core'
require_relative 'lib/raaf/models/capability_detector'
require_relative 'lib/raaf/models/interface'

# Test capability detector with original error provider from test
error_provider = Class.new(RAAF::Models::ModelInterface) do
  def chat_completion(messages:, model:, tools: nil, **_kwargs)
    raise StandardError, "Provider error"
  end

  def supported_models
    ["error-model-v1"]
  end

  def provider_name
    "ErrorProvider"
  end
end.new

detector = RAAF::Models::CapabilityDetector.new(error_provider)
report = detector.generate_report

puts "Provider: #{error_provider.provider_name}"
puts "Has chat_completion: #{error_provider.respond_to?(:chat_completion)}"

# Debug the method parameter introspection
if error_provider.respond_to?(:chat_completion)
  begin
    method = error_provider.method(:chat_completion)
    params = method.parameters
    puts "Method parameters: #{params.inspect}"
    tools_param = params.any? { |_param_type, param_name| param_name == :tools }
    puts "Has tools param: #{tools_param}"
    
    # Check if method is actually implemented or just inherited
    puts "Method owner: #{method.owner}"
    puts "Actual class: #{error_provider.class}"
    puts "Is implemented: #{method.owner == error_provider.class}"
  rescue => e
    puts "Parameter introspection failed: #{e.class} - #{e.message}"
  end
end

# Debug the generate_report format
capabilities = report[:capabilities]
puts "Capabilities count: #{capabilities.length}"
first_capability = capabilities.first
puts "First capability: #{first_capability.inspect}"
puts "First capability keys: #{first_capability.keys}"
puts "Name class: #{first_capability[:name].class}"
puts "Description class: #{first_capability[:description].class}"
puts "Supported class: #{first_capability[:supported].class}"
puts "Priority class: #{first_capability[:priority].class}"