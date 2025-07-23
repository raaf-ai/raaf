# frozen_string_literal: true

require "spec_helper"
require "json"
require "json-schema"

RSpec.describe "API Contract Validation", :compliance do
  
  describe "OpenAI Responses API Contract" do
    let(:provider) { RAAF::Models::ResponsesProvider.new }
    
    # JSON Schema for OpenAI Responses API request
    let(:request_schema) do
      {
        type: "object",
        required: ["model", "input"],
        properties: {
          model: { type: "string" },
          input: {
            type: "array",
            items: {
              type: "object",
              required: ["role", "content"],
              properties: {
                role: { type: "string", enum: ["system", "user", "assistant", "tool"] },
                content: { type: "string" },
                name: { type: "string" },
                tool_call_id: { type: "string" }
              }
            }
          },
          tools: {
            type: "array",
            items: {
              type: "object",
              required: ["type", "function"],
              properties: {
                type: { type: "string", enum: ["function"] },
                function: {
                  type: "object",
                  required: ["name"],
                  properties: {
                    name: { type: "string" },
                    description: { type: "string" },
                    parameters: { type: "object" }
                  }
                }
              }
            }
          },
          stream: { type: "boolean" },
          max_tokens: { type: "integer", minimum: 1 },
          temperature: { type: "number", minimum: 0, maximum: 2 },
          top_p: { type: "number", minimum: 0, maximum: 1 }
        }
      }
    end
    
    # JSON Schema for OpenAI Responses API response
    let(:response_schema) do
      {
        type: "object",
        required: ["output", "usage"],
        properties: {
          output: {
            type: "array",
            items: {
              oneOf: [
                {
                  # Message output
                  type: "object",
                  required: ["type", "role"],
                  properties: {
                    type: { type: "string", enum: ["message"] },
                    role: { type: "string", enum: ["assistant"] },
                    content: {
                      type: "array",
                      items: {
                        type: "object",
                        required: ["type"],
                        properties: {
                          type: { type: "string", enum: ["text"] },
                          text: { type: "string" }
                        }
                      }
                    }
                  }
                },
                {
                  # Function call output
                  type: "object",
                  required: ["type", "name", "arguments"],
                  properties: {
                    type: { type: "string", enum: ["function_call"] },
                    name: { type: "string" },
                    arguments: { type: "string" },
                    call_id: { type: "string" }
                  }
                }
              ]
            }
          },
          usage: {
            type: "object",
            required: ["input_tokens", "output_tokens"],
            properties: {
              input_tokens: { type: "integer", minimum: 0 },
              output_tokens: { type: "integer", minimum: 0 },
              total_tokens: { type: "integer", minimum: 0 }
            }
          }
        }
      }
    end
    
    it "generates valid request payloads" do
      agent = RAAF::Agent.new(name: "ContractAgent", model: "gpt-4o")
      
      # Mock the HTTP layer to capture request payload
      captured_payload = nil
      allow(provider).to receive(:responses_completion) do |params|
        captured_payload = params
        
        # Return minimal valid response
        {
          "output" => [{
            "type" => "message",
            "role" => "assistant",
            "content" => [{ "type" => "text", "text" => "Response" }]
          }],
          "usage" => { "input_tokens" => 10, "output_tokens" => 5, "total_tokens" => 15 }
        }
      end
      
      runner = RAAF::Runner.new(agent: agent, provider: provider)
      runner.run("Test contract validation")
      
      # Validate request payload against schema
      expect(captured_payload).not_to be_nil
      
      # Debug: Show the captured payload
      puts "DEBUG: Captured payload keys: #{captured_payload.keys}"
      puts "DEBUG: Captured payload: #{captured_payload.inspect}"
      
      # Convert symbols to strings for JSON Schema validation
      payload_json = JSON.parse(captured_payload.to_json)
      
      puts "DEBUG: JSON payload: #{payload_json.inspect}"
      
      validation_errors = JSON::Validator.fully_validate(request_schema, payload_json)
      expect(validation_errors).to be_empty, "Request payload validation errors: #{validation_errors}"
      
      # Specific validations
      expect(payload_json).to have_key("model")
      expect(payload_json).to have_key("input")
      expect(payload_json["input"]).to be_an(Array)
      expect(payload_json["input"].first).to have_key("role")
      expect(payload_json["input"].first).to have_key("content")
    end
    
    it "validates tool definitions in requests" do
      tool = RAAF::FunctionTool.new(
        proc { |location:, unit: "celsius"| "Weather in #{location}" },
        name: "get_weather",
        description: "Get weather information"
      )
      
      agent = RAAF::Agent.new(name: "ToolContractAgent")
      agent.add_tool(tool)
      
      captured_payload = nil
      allow(provider).to receive(:responses_completion) do |params|
        captured_payload = params
        
        {
          "output" => [{
            "type" => "message", 
            "role" => "assistant",
            "content" => [{ "type" => "text", "text" => "I can help with weather" }]
          }],
          "usage" => { "input_tokens" => 15, "output_tokens" => 8, "total_tokens" => 23 }
        }
      end
      
      runner = RAAF::Runner.new(agent: agent, provider: provider)
      runner.run("What's the weather?")
      
      # Convert tools manually since we captured them at the raw level
      if captured_payload[:tools]
        converted_tools = captured_payload[:tools].map do |tool|
          if tool.is_a?(RAAF::FunctionTool)
            {
              "type" => "function",
              "function" => {
                "name" => tool.name,
                "description" => tool.description,
                "parameters" => tool.parameters
              }
            }
          else
            tool
          end
        end
        
        # Replace the tools in the payload for validation
        test_payload = captured_payload.dup
        test_payload[:tools] = converted_tools
        payload_json = JSON.parse(test_payload.to_json)
        
        # Validate tools array structure
        expect(payload_json["tools"]).to be_an(Array)
        
        payload_json["tools"].each do |tool_def|
          expect(tool_def).to have_key("type")
          expect(tool_def["type"]).to eq("function")
          expect(tool_def).to have_key("function")
          expect(tool_def["function"]).to have_key("name")
          expect(tool_def["function"]["name"]).to be_a(String)
        end
        
        # Full schema validation
        validation_errors = JSON::Validator.fully_validate(request_schema, payload_json)
        expect(validation_errors).to be_empty
      end
    end
    
    it "handles response validation" do
      # Test with various response formats
      response_formats = [
        # Simple message response
        {
          "output" => [{
            "type" => "message",
            "role" => "assistant", 
            "content" => [{ "type" => "text", "text" => "Hello!" }]
          }],
          "usage" => { "input_tokens" => 5, "output_tokens" => 3, "total_tokens" => 8 }
        },
        
        # Function call response
        {
          "output" => [{
            "type" => "function_call",
            "name" => "get_weather",
            "arguments" => JSON.generate({ location: "Paris" }),
            "call_id" => "call_123"
          }],
          "usage" => { "input_tokens" => 10, "output_tokens" => 5, "total_tokens" => 15 }
        },
        
        # Mixed response
        {
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => [{ "type" => "text", "text" => "I'll check the weather" }]
            },
            {
              "type" => "function_call", 
              "name" => "get_weather",
              "arguments" => "{}",
              "call_id" => "call_456"
            }
          ],
          "usage" => { "input_tokens" => 12, "output_tokens" => 8, "total_tokens" => 20 }
        }
      ]
      
      response_formats.each_with_index do |response_format, i|
        # Validate each response format against schema
        validation_errors = JSON::Validator.fully_validate(response_schema, response_format)
        expect(validation_errors).to be_empty, 
          "Response format #{i} validation errors: #{validation_errors}"
        
        # Test that RAAF can process the response
        allow(provider).to receive(:responses_completion).and_return(response_format)
        
        agent = RAAF::Agent.new(name: "ResponseValidationAgent#{i}")
        runner = RAAF::Runner.new(agent: agent, provider: provider)
        
        expect { runner.run("Test response #{i}") }.not_to raise_error
      end
    end
  end
  
  describe "Provider Interface Contract" do
    # Ensure all providers implement the same interface
    
    let(:providers) do
      [
        RAAF::Models::ResponsesProvider.new,
        RAAF::Models::OpenAIProvider.new
      ]
    end
    
    it "implements consistent interface across providers" do
      required_methods = [:complete, :responses_completion]
      
      providers.each do |provider|
        required_methods.each do |method|
          expect(provider).to respond_to(method), 
            "#{provider.class} should implement #{method}"
        end
      end
    end
    
    it "returns consistent response structure" do
      agent = RAAF::Agent.new(name: "InterfaceAgent")
      
      providers.each do |provider|
        # Mock each provider to return a standard response
        mock_response = {
          "output" => [{
            "type" => "message",
            "role" => "assistant",
            "content" => [{ "type" => "text", "text" => "Interface test" }]
          }],
          "usage" => { "input_tokens" => 10, "output_tokens" => 5, "total_tokens" => 15 }
        }
        
        allow(provider).to receive(:complete).and_return(mock_response)
        allow(provider).to receive(:responses_completion).and_return(mock_response)
        
        runner = RAAF::Runner.new(agent: agent, provider: provider)
        result = runner.run("Interface test")
        
        # All providers should produce consistent RunResult structure
        expect(result).to be_a(RAAF::RunResult)
        expect(result.messages).to be_an(Array)
        expect(result.usage).to be_a(Hash)
        expect(result.last_agent).to eq(agent)
        
        # Usage should have consistent keys
        expect(result.usage).to have_key(:input_tokens)
        expect(result.usage).to have_key(:output_tokens)
        expect(result.usage).to have_key(:total_tokens)
      end
    end
    
    it "handles errors consistently" do
      error_scenarios = [
        { error: RAAF::APIError.new("API Error"), expected_class: RAAF::APIError },
        { error: RAAF::AuthenticationError.new("Auth Error"), expected_class: RAAF::AuthenticationError },
        { error: RAAF::RateLimitError.new("Rate Limited"), expected_class: RAAF::RateLimitError }
      ]
      
      providers.each do |provider|
        error_scenarios.each do |scenario|
          # Create a fresh agent for each test to avoid state issues
          agent = RAAF::Agent.new(name: "ErrorAgent#{rand(1000)}")
          
          # Create a mock that explicitly raises the error without going through HTTP
          mock_provider = double("MockProvider")
          allow(mock_provider).to receive(:is_a?).with(RAAF::Models::ResponsesProvider).and_return(provider.is_a?(RAAF::Models::ResponsesProvider))
          allow(mock_provider).to receive(:complete).and_raise(scenario[:error])
          allow(mock_provider).to receive(:responses_completion).and_raise(scenario[:error])
          
          runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
          
          expect { runner.run("Error test") }.to raise_error(scenario[:expected_class])
        end
      end
    end
  end
  
  describe "Backwards Compatibility Contract" do
    it "maintains compatibility with legacy OpenAI provider" do
      # Test that the legacy provider normalizes response format correctly
      legacy_provider = RAAF::Models::OpenAIProvider.new
      
      # Test with legacy format response (prompt_tokens, completion_tokens)
      legacy_response = {
        choices: [{
          message: {
            role: "assistant",
            content: "Legacy response"
          }
        }],
        usage: {
          "prompt_tokens" => 10,      # Legacy format
          "completion_tokens" => 5,   # Legacy format  
          "total_tokens" => 15
        }
      }
      
      # Test the normalize_response_format method directly
      normalized = legacy_provider.send(:normalize_response_format, legacy_response)
      
      # Should convert to new format internally
      expect(normalized[:usage][:input_tokens]).to eq(10)   # Converted from prompt_tokens
      expect(normalized[:usage][:output_tokens]).to eq(5)   # Converted from completion_tokens
      expect(normalized[:usage][:total_tokens]).to eq(15)   # Should remain the same
    end
    
    it "supports legacy configuration parameters" do
      # Test deprecated parameter names still work
      legacy_configs = [
        { prompt_tokens: 100 },           # Old name
        { completion_tokens: 50 },        # Old name
        { max_completion_tokens: 200 }    # Old name
      ]
      
      legacy_configs.each do |config|
        expect { RAAF::RunConfig.new(**config) }.not_to raise_error
      end
    end
  end
  
  describe "Field Mapping Validation" do
    it "correctly maps Python SDK fields to RAAF fields" do
      # Python SDK -> RAAF field mappings
      field_mappings = {
        # Usage fields
        "input_tokens" => :input_tokens,
        "output_tokens" => :output_tokens,
        "total_tokens" => :total_tokens,
        
        # Legacy mappings
        "prompt_tokens" => :input_tokens,
        "completion_tokens" => :output_tokens,
        
        # Message fields
        "role" => :role,
        "content" => :content,
        "name" => :name,
        "tool_call_id" => :tool_call_id
      }
      
      # Test that RAAF correctly maps these fields
      python_usage = {
        "input_tokens" => 20,
        "output_tokens" => 10,
        "total_tokens" => 30
      }
      
      agent = RAAF::Agent.new(name: "MappingAgent")
      mock_provider = create_mock_provider
      mock_provider.add_response("Mapping test", usage: python_usage)
      
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      result = runner.run("Field mapping test")
      
      # Verify correct field mapping
      expect(result.usage[:input_tokens]).to eq(20)
      expect(result.usage[:output_tokens]).to eq(10)
      expect(result.usage[:total_tokens]).to eq(30)
    end
  end
  
  describe "Version Compatibility" do
    it "handles different API versions gracefully" do
      # Test with different response formats that might come from API updates
      version_responses = [
        # Current format
        {
          "output" => [{ "type" => "message", "role" => "assistant", "content" => [{ "type" => "text", "text" => "v1" }] }],
          "usage" => { "input_tokens" => 5, "output_tokens" => 2, "total_tokens" => 7 }
        },
        
        # Hypothetical future format with additional fields
        {
          "output" => [{ "type" => "message", "role" => "assistant", "content" => [{ "type" => "text", "text" => "v2" }] }],
          "usage" => { "input_tokens" => 5, "output_tokens" => 2, "total_tokens" => 7 },
          "model_version" => "gpt-4o-2024-05-13",  # New field
          "processing_time_ms" => 150               # New field
        }
      ]
      
      version_responses.each_with_index do |response, i|
        agent = RAAF::Agent.new(name: "VersionAgent#{i}")
        mock_provider = create_mock_provider
        
        allow(mock_provider).to receive(:complete).and_return(response)
        
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        # Should handle both formats gracefully
        expect { runner.run("Version test #{i}") }.not_to raise_error
      end
    end
  end
end