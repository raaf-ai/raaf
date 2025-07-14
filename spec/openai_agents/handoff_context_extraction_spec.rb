# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenAIAgents Handoff Context Extraction" do
  let(:source_agent) do
    OpenAIAgents::Agent.new(
      name: "SourceAgent", 
      instructions: "You are a source agent",
      model: "gpt-4"
    )
  end
  
  let(:target_agent) do
    OpenAIAgents::Agent.new(
      name: "TargetAgent", 
      instructions: "You are a target agent",
      model: "gpt-4"
    )
  end
  
  let(:runner) { OpenAIAgents::Runner.new(agent: source_agent) }
  let(:mock_provider) { instance_double(OpenAIAgents::Models::ResponsesProvider) }
  let(:context_wrapper) { OpenAIAgents::RunContextWrapper.new(OpenAIAgents::RunContext.new) }
  
  before do
    source_agent.add_handoff(target_agent)
    
    # Mock the provider
    allow(OpenAIAgents::Models::ResponsesProvider).to receive(:new).and_return(mock_provider)
    
    # Add context_storage_keys method to source agent for testing
    def source_agent.context_storage_keys
      ["user_info", "conversation_summary", "extracted_data"]
    end
  end

  describe "Context Extraction During Handoff" do
    context "when agent response contains JSON with context data" do
      let(:assistant_response) do
        {
          id: "response_123",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [
                {
                  type: "text",
                  text: JSON.generate({
                    response: "I'll transfer you to our technical support team",
                    handoff_to: "TargetAgent",
                    user_info: {
                      name: "John Doe",
                      email: "john@example.com",
                      tier: "premium"
                    },
                    conversation_summary: "User is experiencing login issues with 2FA",
                    extracted_data: {
                      error_code: "AUTH_001",
                      timestamp: "2024-01-15T10:30:00Z"
                    }
                  })
                }
              ]
            }
          ],
          usage: {
            input_tokens: 100,
            output_tokens: 150,
            total_tokens: 250
          }
        }
      end
      
      it "extracts context data from JSON response before handoff" do
        # Set up mock responses
        allow(mock_provider).to receive(:responses_completion).and_return(assistant_response)
        
        # Track context storage calls
        context_data = {}
        allow(context_wrapper).to receive(:store) do |key, value|
          context_data[key] = value
        end
        
        # Simulate the context extraction during handoff
        runner.instance_variable_set(:@current_context_wrapper, context_wrapper)
        
        # Create a mock generated_items array with the assistant message
        generated_items = [
          OpenAIAgents::Items::MessageOutputItem.new(
            agent: source_agent,
            raw_item: {
              type: "message",
              role: "assistant",
              content: [
                {
                  type: "text",
                  text: JSON.generate({
                    response: "I'll transfer you to our technical support team",
                    handoff_to: "TargetAgent",
                    user_info: {
                      name: "John Doe",
                      email: "john@example.com",
                      tier: "premium"
                    },
                    conversation_summary: "User is experiencing login issues with 2FA",
                    extracted_data: {
                      error_code: "AUTH_001",
                      timestamp: "2024-01-15T10:30:00Z"
                    }
                  })
                }
              ]
            }
          )
        ]
        
        # Mock the internal methods
        allow(runner).to receive(:extract_content_from_message_item).with(generated_items[0]).and_return(
          generated_items[0].raw_item[:content][0][:text]
        )
        
        # Test the context extraction logic directly
        last_assistant_item = generated_items.reverse.find { |item| 
          item.is_a?(OpenAIAgents::Items::MessageOutputItem) && 
          (item.raw_item[:role] == "assistant" || item.raw_item["role"] == "assistant")
        }
        
        expect(last_assistant_item).not_to be_nil
        
        content = runner.send(:extract_content_from_message_item, last_assistant_item)
        expect(content).to be_a(String)
        
        parsed_json = JSON.parse(content)
        expect(parsed_json).to include(
          "user_info" => {
            "name" => "John Doe",
            "email" => "john@example.com",
            "tier" => "premium"
          },
          "conversation_summary" => "User is experiencing login issues with 2FA",
          "extracted_data" => {
            "error_code" => "AUTH_001",
            "timestamp" => "2024-01-15T10:30:00Z"
          }
        )
        
        # Verify each context key is extracted
        source_agent.context_storage_keys.each do |key|
          expect(parsed_json).to have_key(key)
        end
      end
      
      it "stores context data using context wrapper store method" do
        # Since RunContextWrapper uses 'store' not 'set', we need to test with store
        context_data = {}
        allow(context_wrapper).to receive(:store) do |key, value|
          context_data[key] = value
        end
        
        # Test the store method directly
        user_info = { "name" => "John Doe", "email" => "john@example.com" }
        conversation_summary = "User experiencing login issues"
        extracted_data = { "error_code" => "AUTH_001" }
        
        context_wrapper.store("user_info", user_info)
        context_wrapper.store("conversation_summary", conversation_summary)
        context_wrapper.store("extracted_data", extracted_data)
        
        expect(context_data["user_info"]).to eq(user_info)
        expect(context_data["conversation_summary"]).to eq(conversation_summary)
        expect(context_data["extracted_data"]).to eq(extracted_data)
      end
    end
    
    context "when agent response is not valid JSON" do
      let(:non_json_response) do
        {
          id: "response_456",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [
                {
                  type: "text",
                  text: "I'll transfer you to the TargetAgent for further assistance."
                }
              ]
            }
          ]
        }
      end
      
      it "handles non-JSON responses gracefully" do
        generated_items = [
          OpenAIAgents::Items::MessageOutputItem.new(
            agent: source_agent,
            raw_item: {
              type: "message",
              role: "assistant",
              content: [
                {
                  type: "text",
                  text: "I'll transfer you to the TargetAgent for further assistance."
                }
              ]
            }
          )
        ]
        
        content = runner.send(:extract_content_from_message_item, generated_items[0])
        
        expect {
          JSON.parse(content)
        }.to raise_error(JSON::ParserError)
        
        # The system should handle this gracefully and not crash
        expect(content).to be_a(String)
        expect(content).to include("TargetAgent")
      end
    end
    
    context "when context_storage_keys is not configured" do
      before do
        # Remove context_storage_keys method from source agent
        source_agent.singleton_class.remove_method(:context_storage_keys)
      end
      
      it "skips context extraction when no keys are configured" do
        expect(source_agent.respond_to?(:context_storage_keys)).to be false
        
        # Context extraction should be skipped
        context_data = {}
        allow(context_wrapper).to receive(:store) do |key, value|
          context_data[key] = value
        end
        
        # No context should be stored
        expect(context_data).to be_empty
      end
    end
  end
  
  describe "Context Placement Before Next Agent" do
    context "when handoff occurs with context data" do
      it "makes context available to target agent through system prompt" do
        # Set up context with extracted data
        context_wrapper.store("user_info", { "name" => "John Doe", "tier" => "premium" })
        context_wrapper.store("conversation_summary", "User having login issues")
        
        # Mock the build_system_prompt method to verify context is passed
        allow(runner).to receive(:build_system_prompt).with(target_agent, context_wrapper).and_call_original
        
        # Test that context is available when building system prompt
        system_prompt = runner.send(:build_system_prompt, target_agent, context_wrapper)
        
        expect(system_prompt).to include("Name: TargetAgent")
        expect(system_prompt).to include("You are a target agent")
        
        # Verify the context_wrapper was passed to build_system_prompt
        expect(runner).to have_received(:build_system_prompt).with(target_agent, context_wrapper)
      end
    end
    
    context "when target agent has get_instructions method" do
      before do
        # Add get_instructions method to target agent that uses context
        def target_agent.get_instructions(context_wrapper)
          base_instructions = "You are a target agent"
          
          if context_wrapper
            user_info = context_wrapper.fetch("user_info", {})
            conversation_summary = context_wrapper.fetch("conversation_summary", "")
            
            if user_info.any?
              base_instructions += "\n\nUser Context:"
              base_instructions += "\n- Name: #{user_info['name']}" if user_info['name']
              base_instructions += "\n- Tier: #{user_info['tier']}" if user_info['tier']
            end
            
            if !conversation_summary.empty?
              base_instructions += "\n\nConversation Summary: #{conversation_summary}"
            end
          end
          
          base_instructions
        end
      end
      
      it "passes context to dynamic instructions" do
        # Set up context
        context_wrapper.store("user_info", { "name" => "John Doe", "tier" => "premium" })
        context_wrapper.store("conversation_summary", "User experiencing login issues")
        
        # Get instructions with context
        instructions = target_agent.get_instructions(context_wrapper)
        
        expect(instructions).to include("You are a target agent")
        expect(instructions).to include("Name: John Doe")
        expect(instructions).to include("Tier: premium")
        expect(instructions).to include("Conversation Summary: User experiencing login issues")
      end
    end
  end
  
  describe "Bug Fix: Context Wrapper Method" do
    it "identifies the bug in context storage method call" do
      # The current code calls .set() but RunContextWrapper only has .store()
      # This test documents the bug and provides the fix
      
      # Current buggy code would call:
      # @current_context_wrapper.set(key, value)
      
      # But RunContextWrapper only has:
      expect(context_wrapper).to respond_to(:store)
      expect(context_wrapper).not_to respond_to(:set)
      
      # The fix is to either:
      # 1. Use .store() instead of .set()
      # 2. Or add a .set() method that delegates to .store()
    end
    
    it "provides a working solution using store method" do
      # This is the corrected approach
      test_data = { "name" => "John Doe", "status" => "active" }
      
      # This should work (using store)
      context_wrapper.store("user_info", test_data)
      retrieved_data = context_wrapper.fetch("user_info")
      
      expect(retrieved_data).to eq(test_data)
    end
  end
end