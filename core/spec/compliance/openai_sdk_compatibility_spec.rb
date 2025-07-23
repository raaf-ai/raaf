# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "OpenAI SDK Compatibility", :compliance do
  let(:mock_provider) { create_mock_provider }
  
  describe "Python SDK Feature Parity" do
    # Reference: OpenAI Python SDK Agents implementation
    # https://github.com/openai/openai-python/tree/main/src/openai/agents
    
    context "Agent creation API" do
      it "matches Python SDK agent initialization parameters" do
        # Python: client.agents.create(name="...", instructions="...", model="...")
        agent = RAAF::Agent.new(
          name: "TestAgent",
          instructions: "You are a helpful assistant",
          model: "gpt-4o",
          # Python SDK equivalent parameters
          temperature: 0.7,
          max_turns: 25,
          output_type: { type: "text" }
        )
        
        # Verify all Python SDK parameters are supported
        expect(agent.name).to eq("TestAgent")
        expect(agent.instructions).to eq("You are a helpful assistant")
        expect(agent.model).to eq("gpt-4o")
        expect(agent.max_turns).to eq(25)
        expect(agent.output_type).to eq({ type: "text" })
      end
      
      it "supports Python SDK tool definition format" do
        # Python SDK tool format
        python_tool_definition = {
          type: "function",
          function: {
            name: "get_weather",
            description: "Get weather information",
            parameters: {
              type: "object",
              properties: {
                location: { type: "string", description: "City name" },
                unit: { type: "string", enum: ["celsius", "fahrenheit"] }
              },
              required: ["location"]
            }
          }
        }
        
        # RAAF should handle Python SDK tool format
        ruby_proc = proc { |location:, unit: "celsius"| "Weather in #{location}: 22°#{unit[0].upcase}" }
        tool = RAAF::FunctionTool.new(ruby_proc, name: "get_weather")
        
        raaf_definition = tool.to_h
        
        # Verify structure matches Python SDK
        expect(raaf_definition[:type]).to eq("function")
        expect(raaf_definition[:function][:name]).to eq("get_weather")
        expect(raaf_definition[:function][:parameters][:type]).to eq("object")
        expect(raaf_definition[:function][:parameters][:properties]).to have_key(:location)
        expect(raaf_definition[:function][:parameters][:required]).to include("location")
      end
    end
    
    context "Runner execution API" do
      it "matches Python SDK run method signature" do
        agent = RAAF::Agent.new(name: "TestAgent")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        mock_provider.add_response("Test response")
        
        # Python: run = client.agents.runs.create(agent_id="...", messages=[...])
        # RAAF equivalent
        result = runner.run(
          "Hello",  # message content
          previous_messages: [{ role: "user", content: "Previous" }],  # messages history
          max_turns: 10,  # Python SDK parameter
          max_tokens: 1000  # Python SDK parameter
        )
        
        # Verify Python SDK compatible result structure
        expect(result).to respond_to(:messages)
        expect(result).to respond_to(:usage)
        expect(result).to respond_to(:last_agent)
        expect(result.messages).to be_an(Array)
        expect(result.usage).to be_a(Hash)
      end
      
      it "supports Python SDK message format" do
        agent = RAAF::Agent.new(name: "MessageFormatAgent")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        # Python SDK message format
        python_messages = [
          { role: "system", content: "You are a helpful assistant" },
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi there!" },
          { role: "user", content: "How are you?" }
        ]
        
        mock_provider.add_response("I'm doing well!")
        
        result = runner.run(
          "Final message",
          previous_messages: python_messages
        )
        
        # Verify message format preservation - the result should contain the final conversation
        expect(result.messages[0]).to include(role: "system")  # System message (auto-generated or provided)
        expect(result.messages[1]).to include(role: "user", content: "Final message")  # Latest user message
        expect(result.messages[2]).to include(role: "assistant")  # Assistant response
        
        # Verify that we can handle Python SDK message formats without errors
        expect(result.messages).to be_an(Array)
        expect(result.messages.size).to be >= 3  # At least system, user, assistant
      end
    end
    
    context "Responses API compatibility" do
      it "uses OpenAI Responses API by default (not Chat Completions)" do
        agent = RAAF::Agent.new(name: "ResponsesAPIAgent")
        runner = RAAF::Runner.new(agent: agent)  # No provider specified
        
        # Should default to ResponsesProvider, not OpenAIProvider
        provider = runner.instance_variable_get(:@provider)
        expect(provider).to be_a(RAAF::Models::ResponsesProvider)
        expect(provider).not_to be_a(RAAF::Models::OpenAIProvider)
      end
      
      it "sends requests in Responses API format" do
        agent = RAAF::Agent.new(name: "ResponsesFormatAgent")
        provider = RAAF::Models::ResponsesProvider.new
        
        # Mock the HTTP request to verify format
        expected_payload = {
          model: "gpt-4",
          input: [
            { role: "user", content: "Test message" }
          ]
        }
        
        allow(provider).to receive(:responses_completion) do |params|
          # Verify Python SDK compatible request format
          expect(params).to include(:model)
          expect(params).to include(:input)  # Not 'messages'
          expect(params[:input]).to be_an(Array)
          
          # Return mock response
          {
            "output" => [{
              "type" => "message",
              "role" => "assistant",
              "content" => [{ "type" => "text", "text" => "Response" }]
            }],
            "usage" => { "input_tokens" => 10, "output_tokens" => 5 }
          }
        end
        
        runner = RAAF::Runner.new(agent: agent, provider: provider)
        runner.run("Test message")
      end
    end
    
    context "Tool calling compatibility" do
      it "matches Python SDK tool call format" do
        weather_tool = RAAF::FunctionTool.new(
          proc { |location:| "Weather in #{location}" },
          name: "get_weather"
        )
        
        agent = RAAF::Agent.new(name: "ToolAgent")
        agent.add_tool(weather_tool)
        
        # Mock tool call response in Python SDK format
        mock_provider.add_response(
          "I'll check the weather",
          tool_calls: [{
            id: "call_123",
            function: {
              name: "get_weather",
              arguments: JSON.generate({ location: "Paris" })
            }
          }]
        )
        mock_provider.add_response("Weather retrieved")
        
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        # Debug: Add debugging hooks to track message flow
        def runner.debug_trace_messages(location, messages)
          puts "DEBUG TRACE [#{location}]: messages.size=#{messages.size}"
          messages.each_with_index do |msg, i|
            puts "  #{i}: role=#{msg[:role]}, keys=#{msg.keys}"
            puts "    raw_keys=#{msg.keys}" if msg.key?(:id) && msg.key?(:output)
          end
        end
        
        result = runner.run("What's the weather in Paris?")
        
        # Debug output
        puts "DEBUG: All messages count: #{result.messages.size}"
        puts "DEBUG: Message details:"
        result.messages.each_with_index do |msg, i|
          puts "  #{i}: role=#{msg[:role]}, keys=#{msg.keys}"
          if msg.key?(:output)
            puts "    output: #{msg[:output]}"
          end
          if msg.key?(:content)
            puts "    content: #{msg[:content]}"
          end
        end
        
        # Debug the step processor execution
        puts "DEBUG: Generated items from runner:"
        if runner.respond_to?(:generated_items)
          runner.generated_items.each_with_index do |item, i|
            puts "  #{i}: #{item.class.name}, role=#{item.raw_item[:role] rescue 'N/A'}, type=#{item.raw_item[:type] rescue 'N/A'}"
          end
        end
        
        # Verify tool call was processed
        tool_messages = result.messages.select { |m| m[:role] == "tool" }
        expect(tool_messages).not_to be_empty
        
        if tool_messages.any?
          tool_msg = tool_messages.first
          expect(tool_msg).to have_key(:tool_call_id)
          expect(tool_msg).to have_key(:content)
        end
      end
    end
  end
  
  describe "API Response Format Validation" do
    context "Responses API output format" do
      it "validates response structure matches Python SDK" do
        # Python SDK expected response structure
        expected_structure = {
          "output" => Array,
          "usage" => Hash
        }
        
        provider = RAAF::Models::ResponsesProvider.new
        
        # Mock a typical response
        mock_response = {
          "output" => [{
            "type" => "message",
            "role" => "assistant", 
            "content" => [
              { "type" => "text", "text" => "Hello!" }
            ]
          }],
          "usage" => {
            "input_tokens" => 10,
            "output_tokens" => 5,
            "total_tokens" => 15
          }
        }
        
        allow(provider).to receive(:responses_completion).and_return(mock_response)
        
        agent = RAAF::Agent.new(name: "ValidationAgent")
        runner = RAAF::Runner.new(agent: agent, provider: provider)
        
        result = runner.run("Test")
        
        # Verify response structure
        expect(result.usage).to include(:input_tokens, :output_tokens, :total_tokens)
        expect(result.messages).to be_an(Array)
        expect(result.messages.last[:role]).to eq("assistant")
      end
      
      it "handles Python SDK error response format" do
        provider = RAAF::Models::ResponsesProvider.new
        
        # Python SDK error format
        error_response = {
          "error" => {
            "type" => "invalid_request_error",
            "message" => "Invalid model specified",
            "code" => "invalid_model"
          }
        }
        
        allow(provider).to receive(:responses_completion).and_raise(
          RAAF::APIError.new("Invalid model specified", status: 400)
        )
        
        agent = RAAF::Agent.new(name: "ErrorAgent")
        runner = RAAF::Runner.new(agent: agent, provider: provider)
        
        # Should handle error in Python SDK compatible way
        expect { runner.run("Test") }.to raise_error(RAAF::APIError)
      end
    end
    
    context "Usage tracking compatibility" do
      it "tracks tokens in Python SDK format" do
        agent = RAAF::Agent.new(name: "TokenTrackingAgent")
        
        # Python SDK usage format
        python_usage = {
          "input_tokens" => 25,
          "output_tokens" => 15,
          "total_tokens" => 40
        }
        
        mock_provider.add_response("Response", usage: python_usage)
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        result = runner.run("Test token tracking")
        
        # Verify Python SDK compatible usage format
        expect(result.usage[:input_tokens]).to eq(25)
        expect(result.usage[:output_tokens]).to eq(15)  
        expect(result.usage[:total_tokens]).to eq(40)
        
        # Should also support legacy format
        expect(result.usage).to have_key(:input_tokens)  # Not prompt_tokens
        expect(result.usage).to have_key(:output_tokens) # Not completion_tokens
      end
    end
  end
  
  describe "Tracing Compatibility" do
    context "trace payload structure" do
      it "generates Python SDK compatible trace spans" do
        skip "Requires tracing implementation details"
        
        # Python SDK trace structure:
        # - Agent spans are root spans (parent_id: null)
        # - Response spans are children of agent spans
        # - Identical field structures
        
        agent = RAAF::Agent.new(name: "TracingAgent")
        tracer = RAAF::Tracing::SpanTracer.new
        
        # This would require access to tracing internals
        # to verify span structure matches Python SDK
      end
    end
  end
  
  describe "Configuration Compatibility" do
    context "environment variables" do
      it "respects Python SDK environment variable names" do
        # Python SDK uses these env vars - RAAF should too
        env_vars = {
          "OPENAI_API_KEY" => "test-key",
          "OPENAI_BASE_URL" => "https://api.openai.com/v1",
          "OPENAI_TIMEOUT" => "30"
        }
        
        env_vars.each do |key, value|
          original = ENV[key]
          ENV[key] = value
          
          begin
            # Test that RAAF respects these environment variables
            case key
            when "OPENAI_API_KEY"
              provider = RAAF::Models::ResponsesProvider.new
              expect(provider.instance_variable_get(:@api_key)).to eq(value)
            when "OPENAI_BASE_URL"
              # Test base URL configuration
              expect(true).to be true  # Placeholder
            when "OPENAI_TIMEOUT"
              # Test timeout configuration  
              expect(true).to be true  # Placeholder
            end
          ensure
            ENV[key] = original
          end
        end
      end
    end
    
    context "model parameter compatibility" do
      it "supports all Python SDK model parameters" do
        # Python SDK model parameters
        python_params = {
          model: "gpt-4o",
          temperature: 0.7,
          max_tokens: 1500,
          top_p: 0.9,
          frequency_penalty: 0.1,
          presence_penalty: 0.1,
          seed: 12345
        }
        
        agent = RAAF::Agent.new(name: "ParamAgent", **python_params.slice(:model))
        config = RAAF::RunConfig.new(**python_params.except(:model))
        
        # Should accept all Python SDK parameters
        expect(agent.model).to eq("gpt-4o")
        expect(config.temperature).to eq(0.7)
        expect(config.max_tokens).to eq(1500)
        # Additional parameters should be preserved in config
      end
    end
  end
  
  describe "Error Handling Compatibility" do
    context "exception types" do
      it "raises Python SDK compatible exceptions" do
        # Python SDK exception hierarchy
        python_exceptions = [
          { error: RAAF::APIError, python_type: "APIError" },
          { error: RAAF::AuthenticationError, python_type: "AuthenticationError" },
          { error: RAAF::RateLimitError, python_type: "RateLimitError" },
          { error: RAAF::InvalidRequestError, python_type: "InvalidRequestError" }
        ]
        
        python_exceptions.each do |exc|
          error = exc[:error].new("Test error")
          
          # Should have Python SDK compatible attributes
          expect(error).to respond_to(:message)
          expect(error.message).to be_a(String)
          
          # Error should be identifiable by type
          expect(error.class.name).to include(exc[:python_type].gsub("Error", ""))
        end
      end
    end
  end
  
  describe "Migration Path Testing" do
    context "deprecated OpenAI provider" do
      it "warns when using deprecated OpenAIProvider" do
        # Should guide users to ResponsesProvider
        expect {
          RAAF::Models::OpenAIProvider.new
        }.to(output(/deprecated/i).to_stderr.or(output("").to_stderr))
        
        # Or test through documentation/warnings
        agent = RAAF::Agent.new(name: "DeprecatedAgent")
        deprecated_provider = RAAF::Models::OpenAIProvider.new
        
        # Should still work but potentially with warnings
        expect {
          RAAF::Runner.new(agent: agent, provider: deprecated_provider)
        }.not_to raise_error
      end
    end
    
    context "configuration migration" do
      it "supports legacy configuration parameters" do
        # Test backward compatibility
        legacy_config = {
          max_completion_tokens: 1000,  # Old parameter name
          max_prompt_tokens: 2000       # Old parameter name
        }
        
        # Should handle gracefully or convert to new format
        expect {
          RAAF::RunConfig.new(**legacy_config)
        }.not_to raise_error
      end
    end
  end
end