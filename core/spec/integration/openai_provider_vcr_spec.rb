# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenAI Provider Integration with VCR", :integration do
  let(:provider) { RAAF::Models::OpenAIProvider.new }
  
  describe "Chat Completions API" do
    context "basic completions" do
      it "records simple chat completion" do
        VCR.use_cassette("openai/chat_simple") do
          messages = [
            { role: "system", content: "You are a helpful assistant." },
            { role: "user", content: "What is the capital of France?" }
          ]
          
          response = provider.chat_completion(
            model: "gpt-3.5-turbo",
            messages: messages,
            temperature: 0.7
          )
          
          expect(response).to have_key("choices")
          expect(response["choices"]).to be_an(Array)
          expect(response["choices"].first).to have_key("message")
          expect(response).to have_key("usage")
        end
      end

      it "handles streaming responses" do
        VCR.use_cassette("openai/chat_streaming") do
          messages = [
            { role: "user", content: "Count from 1 to 3" }
          ]
          
          chunks = []
          provider.chat_completion(
            model: "gpt-3.5-turbo",
            messages: messages,
            stream: true
          ) do |chunk|
            chunks << chunk
          end
          
          expect(chunks).not_to be_empty
          expect(chunks.first).to have_key("choices")
          
          # Verify we got multiple chunks
          content_chunks = chunks
            .map { |c| c.dig("choices", 0, "delta", "content") }
            .compact
          
          expect(content_chunks.join).to match(/1.*2.*3/)
        end
      end
    end

    context "function calling" do
      let(:tools) do
        [{
          type: "function",
          function: {
            name: "get_current_time",
            description: "Get the current time",
            parameters: {
              type: "object",
              properties: {
                timezone: {
                  type: "string",
                  description: "The timezone (e.g., 'UTC', 'PST')"
                }
              },
              required: ["timezone"]
            }
          }
        }]
      end

      it "records function calling requests" do
        VCR.use_cassette("openai/function_calling") do
          messages = [
            { role: "user", content: "What time is it in Tokyo?" }
          ]
          
          response = provider.chat_completion(
            model: "gpt-3.5-turbo",
            messages: messages,
            tools: tools,
            tool_choice: "auto"
          )
          
          expect(response).to have_key("choices")
          
          message = response["choices"].first["message"]
          
          # Check if model decided to use a tool
          if message["tool_calls"]
            expect(message["tool_calls"]).to be_an(Array)
            expect(message["tool_calls"].first).to have_key("function")
            expect(message["tool_calls"].first["function"]["name"]).to eq("get_current_time")
          end
        end
      end

      it "handles forced function calls" do
        VCR.use_cassette("openai/forced_function_call") do
          messages = [
            { role: "user", content: "Hello" }
          ]
          
          response = provider.chat_completion(
            model: "gpt-3.5-turbo",
            messages: messages,
            tools: tools,
            tool_choice: {
              type: "function",
              function: { name: "get_current_time" }
            }
          )
          
          expect(response["choices"].first["message"]["tool_calls"]).to be_an(Array)
          expect(response["choices"].first["message"]["tool_calls"].first["function"]["name"])
            .to eq("get_current_time")
        end
      end
    end

    context "response formats" do
      it "handles JSON response format" do
        VCR.use_cassette("openai/json_response") do
          messages = [
            { 
              role: "user", 
              content: "Generate a JSON object with name and age fields for a fictional person" 
            }
          ]
          
          response = provider.chat_completion(
            model: "gpt-4o-mini",
            messages: messages,
            response_format: { type: "json_object" }
          )
          
          content = response["choices"].first["message"]["content"]
          expect { JSON.parse(content) }.not_to raise_error
          
          parsed = JSON.parse(content)
          expect(parsed).to be_a(Hash)
        end
      end
    end

    context "error handling" do
      it "records invalid API key error" do
        VCR.use_cassette("openai/invalid_api_key") do
          invalid_provider = RAAF::Models::OpenAIProvider.new(api_key: "invalid-key")
          
          expect {
            invalid_provider.chat_completion(
              model: "gpt-3.5-turbo",
              messages: [{ role: "user", content: "Hello" }]
            )
          }.to raise_error(RAAF::AuthenticationError)
        end
      end

      it "records model not found error" do
        VCR.use_cassette("openai/invalid_model") do
          expect {
            provider.chat_completion(
              model: "gpt-99-ultra",
              messages: [{ role: "user", content: "Hello" }]
            )
          }.to raise_error(RAAF::APIError)
        end
      end

      it "records context length exceeded error" do
        VCR.use_cassette("openai/context_length_exceeded") do
          # Create a very long message
          long_message = "Hello world. " * 10000
          
          expect {
            provider.chat_completion(
              model: "gpt-3.5-turbo",
              messages: [{ role: "user", content: long_message }],
              max_tokens: 4000
            )
          }.to raise_error(RAAF::APIError)
        end
      end
    end

    context "advanced features" do
      it "handles logprobs parameter" do
        VCR.use_cassette("openai/logprobs") do
          response = provider.chat_completion(
            model: "gpt-3.5-turbo",
            messages: [{ role: "user", content: "Say 'yes' or 'no'" }],
            logprobs: true,
            top_logprobs: 2
          )
          
          expect(response).to have_key("choices")
          
          # Check if logprobs are included
          if response["choices"].first["logprobs"]
            expect(response["choices"].first["logprobs"]).to have_key("content")
          end
        end
      end

      it "handles seed parameter for deterministic output" do
        VCR.use_cassette("openai/deterministic_seed") do
          messages = [{ role: "user", content: "Generate a random number" }]
          
          response1 = provider.chat_completion(
            model: "gpt-3.5-turbo",
            messages: messages,
            seed: 12345,
            temperature: 1.0
          )
          
          response2 = provider.chat_completion(
            model: "gpt-3.5-turbo",
            messages: messages,
            seed: 12345,
            temperature: 1.0
          )
          
          # With same seed, outputs should be similar (though not guaranteed identical)
          expect(response1["choices"].first["message"]["content"])
            .to eq(response2["choices"].first["message"]["content"])
        end
      end

      it "handles multiple choices" do
        VCR.use_cassette("openai/multiple_choices") do
          response = provider.chat_completion(
            model: "gpt-3.5-turbo",
            messages: [{ role: "user", content: "Say hello" }],
            n: 3,
            temperature: 0.8
          )
          
          expect(response["choices"].size).to eq(3)
          expect(response["choices"].map { |c| c["message"]["content"] }.uniq.size).to be >= 1
        end
      end
    end

    context "conversation context" do
      it "maintains conversation history" do
        VCR.use_cassette("openai/conversation_context") do
          conversation = [
            { role: "user", content: "My favorite color is blue" }
          ]
          
          # First response
          response1 = provider.chat_completion(
            model: "gpt-3.5-turbo",
            messages: conversation
          )
          
          assistant_message = response1["choices"].first["message"]
          conversation << assistant_message
          conversation << { role: "user", content: "What's my favorite color?" }
          
          # Second response should remember the color
          response2 = provider.chat_completion(
            model: "gpt-3.5-turbo",
            messages: conversation
          )
          
          final_content = response2["choices"].first["message"]["content"]
          expect(final_content.downcase).to include("blue")
        end
      end
    end

    context "token usage tracking" do
      it "accurately tracks token usage" do
        VCR.use_cassette("openai/token_tracking") do
          messages = [
            { role: "system", content: "You are a concise assistant." },
            { role: "user", content: "Explain quantum computing in exactly 50 words." }
          ]
          
          response = provider.chat_completion(
            model: "gpt-3.5-turbo",
            messages: messages,
            max_tokens: 100
          )
          
          expect(response["usage"]).to have_key("prompt_tokens")
          expect(response["usage"]).to have_key("completion_tokens")
          expect(response["usage"]).to have_key("total_tokens")
          
          expect(response["usage"]["total_tokens"]).to eq(
            response["usage"]["prompt_tokens"] + response["usage"]["completion_tokens"]
          )
        end
      end
    end
  end

  describe "Legacy Completions API" do
    it "records text completion requests" do
      VCR.use_cassette("openai/text_completion") do
        response = provider.send(:make_api_request,
          :post,
          "/completions",
          {
            model: "gpt-3.5-turbo-instruct",
            prompt: "Once upon a time",
            max_tokens: 50,
            temperature: 0.7
          }
        )
        
        expect(response).to have_key("choices")
        expect(response["choices"].first).to have_key("text")
        expect(response).to have_key("usage")
      end
    end
  end

  describe "Model information" do
    it "retrieves available models" do
      VCR.use_cassette("openai/list_models") do
        response = provider.send(:make_api_request, :get, "/models")
        
        expect(response).to have_key("data")
        expect(response["data"]).to be_an(Array)
        
        # Find GPT models
        gpt_models = response["data"].select { |m| m["id"].start_with?("gpt") }
        expect(gpt_models).not_to be_empty
      end
    end

    it "retrieves specific model details" do
      VCR.use_cassette("openai/model_details") do
        response = provider.send(:make_api_request, :get, "/models/gpt-3.5-turbo")
        
        expect(response).to have_key("id")
        expect(response["id"]).to eq("gpt-3.5-turbo")
        expect(response).to have_key("object")
        expect(response["object"]).to eq("model")
      end
    end
  end
end