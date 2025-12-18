# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::GeminiProvider do
  let(:api_key) { "test-gemini-key" }
  let(:provider) { described_class.new(api_key: api_key) }

  describe "#initialize" do
    it "requires an API key" do
      expect { described_class.new }.to raise_error(RAAF::AuthenticationError, /Gemini API key is required/)
    end

    it "initializes with API key" do
      expect(provider.instance_variable_get(:@api_key)).to eq(api_key)
    end

    it "uses default API base if not provided" do
      expect(provider.instance_variable_get(:@api_base)).to eq("https://generativelanguage.googleapis.com")
    end

    it "accepts custom API base" do
      custom_provider = described_class.new(api_key: api_key, api_base: "https://custom.api.com")
      expect(custom_provider.instance_variable_get(:@api_base)).to eq("https://custom.api.com")
    end

    it "uses default HTTP timeout of 120 seconds" do
      expect(provider.instance_variable_get(:@http_timeout)).to eq(120)
    end

    it "accepts custom HTTP timeout" do
      custom_provider = described_class.new(api_key: api_key, timeout: 300)
      expect(custom_provider.instance_variable_get(:@http_timeout)).to eq(300)
    end

    it "allows http_timeout to be set via accessor" do
      provider.http_timeout = 60
      expect(provider.http_timeout).to eq(60)
    end

    it "uses GEMINI_HTTP_TIMEOUT environment variable if set" do
      with_env("GEMINI_HTTP_TIMEOUT" => "180") do
        env_provider = described_class.new(api_key: api_key)
        expect(env_provider.instance_variable_get(:@http_timeout)).to eq(180)
      end
    end
  end

  describe "#provider_name" do
    it "returns Gemini" do
      expect(provider.provider_name).to eq("Gemini")
    end
  end

  describe "#supported_models" do
    it "returns array of Gemini models" do
      models = provider.supported_models
      expect(models).to be_an(Array)
      # Gemini 2.5 series
      expect(models).to include("gemini-2.5-pro")
      expect(models).to include("gemini-2.5-flash")
      expect(models).to include("gemini-2.5-flash-lite")
      # Gemini 2.0 series
      expect(models).to include("gemini-2.0-flash")
      expect(models).to include("gemini-2.0-flash-exp")
      expect(models).to include("gemini-2.0-flash-lite")
      # Gemini 1.5 series
      expect(models).to include("gemini-1.5-pro-latest")
      expect(models).to include("gemini-1.5-flash-latest")
      # Legacy
      expect(models).to include("gemini-1.0-pro")
    end

    it "includes all expected model variants" do
      models = provider.supported_models
      expect(models.length).to be >= 11
    end
  end

  describe "#chat_completion" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "gemini-2.0-flash-exp" }

    it "validates supported models" do
      expect { provider.chat_completion(messages: messages, model: "invalid-model") }
        .to raise_error(ArgumentError, /not supported/)
    end

    it "accepts all supported models" do
      provider.supported_models.each do |supported_model|
        expect { provider.send(:validate_model, supported_model) }.not_to raise_error
      end
    end
  end

  describe "message format conversion" do
    describe "#extract_system_instruction" do
      it "separates system messages from user messages" do
        messages = [
          { role: "system", content: "You are helpful" },
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi there" }
        ]

        system_instruction, contents = provider.send(:extract_system_instruction, messages)

        expect(system_instruction).to eq("You are helpful")
        expect(contents.length).to eq(2)
        expect(contents[0][:role]).to eq("user")
        expect(contents[1][:role]).to eq("model")
      end

      it "converts assistant role to model role" do
        messages = [
          { role: "assistant", content: "I am Claude" }
        ]

        _system_instruction, contents = provider.send(:extract_system_instruction, messages)

        expect(contents[0][:role]).to eq("model")
        expect(contents[0][:parts]).to eq([{ text: "I am Claude" }])
      end

      it "handles messages without system instruction" do
        messages = [
          { role: "user", content: "Hello" }
        ]

        system_instruction, contents = provider.send(:extract_system_instruction, messages)

        expect(system_instruction).to be_nil
        expect(contents.length).to eq(1)
      end

      it "formats content as parts array" do
        messages = [
          { role: "user", content: "Test message" }
        ]

        _system_instruction, contents = provider.send(:extract_system_instruction, messages)

        expect(contents[0][:parts]).to eq([{ text: "Test message" }])
      end
    end
  end

  describe "tool conversion" do
    describe "#convert_tools_to_gemini" do
      it "converts OpenAI tool format to Gemini functionDeclarations" do
        tools = [{
          type: "function",
          function: {
            name: "get_weather",
            description: "Get weather for a location",
            parameters: {
              type: "object",
              properties: {
                location: { type: "string" }
              },
              required: ["location"]
            }
          }
        }]

        gemini_tools = provider.send(:convert_tools_to_gemini, tools)

        expect(gemini_tools).to be_an(Array)
        expect(gemini_tools.length).to eq(1)
        expect(gemini_tools[0]).to have_key(:functionDeclarations)

        func_decl = gemini_tools[0][:functionDeclarations][0]
        expect(func_decl[:name]).to eq("get_weather")
        expect(func_decl[:description]).to eq("Get weather for a location")
        expect(func_decl[:parameters]).to be_a(Hash)
      end

      it "returns empty array for nil tools" do
        gemini_tools = provider.send(:convert_tools_to_gemini, nil)
        expect(gemini_tools).to eq([])
      end

      it "handles multiple tools" do
        tools = [
          {
            type: "function",
            function: { name: "tool1", description: "Tool 1", parameters: {} }
          },
          {
            type: "function",
            function: { name: "tool2", description: "Tool 2", parameters: {} }
          }
        ]

        gemini_tools = provider.send(:convert_tools_to_gemini, tools)

        expect(gemini_tools[0][:functionDeclarations].length).to eq(2)
        expect(gemini_tools[0][:functionDeclarations][0][:name]).to eq("tool1")
        expect(gemini_tools[0][:functionDeclarations][1][:name]).to eq("tool2")
      end

      describe "Google Search grounding tools" do
        it "converts google_search tool for Gemini 2.0+" do
          tools = [{ google_search: {} }]

          gemini_tools = provider.send(:convert_tools_to_gemini, tools)

          expect(gemini_tools).to eq([{ googleSearch: {} }])
        end

        it "converts google_search tool with string key" do
          tools = [{ "google_search" => {} }]

          gemini_tools = provider.send(:convert_tools_to_gemini, tools)

          expect(gemini_tools).to eq([{ googleSearch: {} }])
        end

        it "converts google_search_retrieval tool for Gemini 1.5" do
          tools = [{ google_search_retrieval: { dynamic_retrieval_config: { mode: "MODE_DYNAMIC" } } }]

          gemini_tools = provider.send(:convert_tools_to_gemini, tools)

          expect(gemini_tools).to eq([{ googleSearchRetrieval: { dynamic_retrieval_config: { mode: "MODE_DYNAMIC" } } }])
        end

        it "handles mixed grounding and function tools" do
          tools = [
            { google_search: {} },
            {
              type: "function",
              function: { name: "get_weather", description: "Get weather", parameters: {} }
            }
          ]

          gemini_tools = provider.send(:convert_tools_to_gemini, tools)

          expect(gemini_tools.length).to eq(2)
          expect(gemini_tools[0]).to have_key(:functionDeclarations)
          expect(gemini_tools[1]).to eq({ googleSearch: {} })
        end
      end
    end
  end

  describe "generation config" do
    describe "#build_generation_config" do
      it "builds config from kwargs" do
        kwargs = {
          temperature: 0.7,
          top_p: 0.9,
          top_k: 40,
          max_tokens: 1024,
          stop: ["STOP"]
        }

        config = provider.send(:build_generation_config, kwargs)

        expect(config[:temperature]).to eq(0.7)
        expect(config[:topP]).to eq(0.9)
        expect(config[:topK]).to eq(40)
        expect(config[:maxOutputTokens]).to eq(1024)
        expect(config[:stopSequences]).to eq(["STOP"])
      end

      it "returns empty hash when no parameters provided" do
        config = provider.send(:build_generation_config, {})
        expect(config).to eq({})
      end

      it "only includes provided parameters" do
        kwargs = { temperature: 0.5 }
        config = provider.send(:build_generation_config, kwargs)

        expect(config.keys).to eq([:temperature])
      end
    end
  end

  describe "response conversion" do
    describe "#convert_gemini_to_openai_format" do
      it "converts Gemini response to OpenAI format" do
        gemini_response = {
          "candidates" => [{
            "content" => {
              "parts" => [{ "text" => "Hello! How can I help?" }],
              "role" => "model"
            },
            "finishReason" => "STOP"
          }],
          "usageMetadata" => {
            "promptTokenCount" => 5,
            "candidatesTokenCount" => 10,
            "totalTokenCount" => 15
          },
          "modelVersion" => "gemini-2.0-flash-exp"
        }

        openai_response = provider.send(:convert_gemini_to_openai_format, gemini_response)

        expect(openai_response["choices"]).to be_an(Array)
        expect(openai_response["choices"][0]["message"]["role"]).to eq("assistant")
        expect(openai_response["choices"][0]["message"]["content"]).to eq("Hello! How can I help?")
        expect(openai_response["choices"][0]["finish_reason"]).to eq("stop")
        expect(openai_response["usage"]["input_tokens"]).to eq(5)
        expect(openai_response["usage"]["output_tokens"]).to eq(10)
        expect(openai_response["usage"]["total_tokens"]).to eq(15)
        expect(openai_response["model"]).to eq("gemini-2.0-flash-exp")
      end

      it "handles empty response" do
        gemini_response = {
          "candidates" => [{}],
          "usageMetadata" => nil
        }

        openai_response = provider.send(:convert_gemini_to_openai_format, gemini_response)

        expect(openai_response["choices"][0]["message"]["content"]).to eq("")
        expect(openai_response["usage"]).to eq({})
      end
    end

    describe "#map_finish_reason" do
      it "maps STOP to stop" do
        expect(provider.send(:map_finish_reason, "STOP")).to eq("stop")
      end

      it "maps MAX_TOKENS to length" do
        expect(provider.send(:map_finish_reason, "MAX_TOKENS")).to eq("length")
      end

      it "maps SAFETY to content_filter" do
        expect(provider.send(:map_finish_reason, "SAFETY")).to eq("content_filter")
      end

      it "maps RECITATION to content_filter" do
        expect(provider.send(:map_finish_reason, "RECITATION")).to eq("content_filter")
      end

      it "defaults to stop for unknown reasons" do
        expect(provider.send(:map_finish_reason, "UNKNOWN")).to eq("stop")
        expect(provider.send(:map_finish_reason, nil)).to eq("stop")
      end
    end

    describe "#extract_usage_metadata" do
      it "extracts and converts usage metadata" do
        metadata = {
          "promptTokenCount" => 10,
          "candidatesTokenCount" => 20,
          "totalTokenCount" => 30
        }

        usage = provider.send(:extract_usage_metadata, metadata)

        expect(usage["input_tokens"]).to eq(10)
        expect(usage["output_tokens"]).to eq(20)
        expect(usage["total_tokens"]).to eq(30)
      end

      it "returns empty hash for nil metadata" do
        usage = provider.send(:extract_usage_metadata, nil)
        expect(usage).to eq({})
      end

      it "handles missing token counts" do
        metadata = {}
        usage = provider.send(:extract_usage_metadata, metadata)

        expect(usage["input_tokens"]).to eq(0)
        expect(usage["output_tokens"]).to eq(0)
        expect(usage["total_tokens"]).to eq(0)
      end
    end
  end

  describe "tool call extraction" do
    describe "#extract_tool_calls" do
      it "extracts function call from response part" do
        part = {
          "functionCall" => {
            "name" => "get_weather",
            "args" => { "location" => "Tokyo" }
          }
        }

        tool_calls = provider.send(:extract_tool_calls, part)

        expect(tool_calls).to be_an(Array)
        expect(tool_calls.length).to eq(1)
        expect(tool_calls[0][:type]).to eq("function")
        expect(tool_calls[0][:function][:name]).to eq("get_weather")

        args = JSON.parse(tool_calls[0][:function][:arguments])
        expect(args["location"]).to eq("Tokyo")
      end

      it "returns nil when no function call present" do
        part = { "text" => "Regular text response" }
        tool_calls = provider.send(:extract_tool_calls, part)
        expect(tool_calls).to be_nil
      end

      it "handles function call with empty args" do
        part = {
          "functionCall" => {
            "name" => "get_time"
          }
        }

        tool_calls = provider.send(:extract_tool_calls, part)
        expect(tool_calls[0][:function][:arguments]).to eq("{}")
      end

      it "generates unique call IDs" do
        part = {
          "functionCall" => {
            "name" => "test_function",
            "args" => {}
          }
        }

        tool_calls_1 = provider.send(:extract_tool_calls, part)
        tool_calls_2 = provider.send(:extract_tool_calls, part)

        expect(tool_calls_1[0][:id]).not_to eq(tool_calls_2[0][:id])
        expect(tool_calls_1[0][:id]).to start_with("call_")
      end
    end
  end

  describe "grounding metadata extraction" do
    describe "#extract_grounding_metadata" do
      it "extracts web search queries" do
        metadata = {
          "webSearchQueries" => ["euro 2024 winner", "european championship 2024"]
        }

        result = provider.send(:extract_grounding_metadata, metadata)

        expect(result["web_search_queries"]).to eq(["euro 2024 winner", "european championship 2024"])
      end

      it "extracts grounding chunks with URIs and titles" do
        metadata = {
          "groundingChunks" => [
            { "web" => { "uri" => "https://example.com/article1", "title" => "Euro 2024 Results" } },
            { "web" => { "uri" => "https://example.com/article2", "title" => "Championship Final" } }
          ]
        }

        result = provider.send(:extract_grounding_metadata, metadata)

        expect(result["grounding_chunks"]).to eq([
          { "uri" => "https://example.com/article1", "title" => "Euro 2024 Results" },
          { "uri" => "https://example.com/article2", "title" => "Championship Final" }
        ])
      end

      it "extracts grounding supports with segment mappings" do
        metadata = {
          "groundingSupports" => [
            {
              "segment" => { "startIndex" => 0, "endIndex" => 50 },
              "groundingChunkIndices" => [0],
              "confidenceScores" => [0.95]
            }
          ]
        }

        result = provider.send(:extract_grounding_metadata, metadata)

        expect(result["grounding_supports"]).to be_an(Array)
        expect(result["grounding_supports"][0]["segment"]).to eq({ "startIndex" => 0, "endIndex" => 50 })
        expect(result["grounding_supports"][0]["grounding_chunk_indices"]).to eq([0])
        expect(result["grounding_supports"][0]["confidence_scores"]).to eq([0.95])
      end

      it "extracts search entry point" do
        metadata = {
          "searchEntryPoint" => {
            "renderedContent" => "<div>Search suggestions...</div>"
          }
        }

        result = provider.send(:extract_grounding_metadata, metadata)

        expect(result["search_entry_point"]["rendered_content"]).to eq("<div>Search suggestions...</div>")
      end

      it "returns nil for nil metadata" do
        result = provider.send(:extract_grounding_metadata, nil)
        expect(result).to be_nil
      end

      it "returns nil for empty metadata" do
        result = provider.send(:extract_grounding_metadata, {})
        expect(result).to be_nil
      end

      it "handles complete grounding response" do
        metadata = {
          "webSearchQueries" => ["ruby 3.4 features"],
          "groundingChunks" => [
            { "web" => { "uri" => "https://ruby-lang.org", "title" => "Ruby 3.4" } }
          ],
          "groundingSupports" => [
            { "segment" => { "startIndex" => 0 }, "groundingChunkIndices" => [0] }
          ],
          "searchEntryPoint" => { "renderedContent" => "<div>...</div>" }
        }

        result = provider.send(:extract_grounding_metadata, metadata)

        expect(result["web_search_queries"]).to be_an(Array)
        expect(result["grounding_chunks"]).to be_an(Array)
        expect(result["grounding_supports"]).to be_an(Array)
        expect(result["search_entry_point"]).to be_a(Hash)
      end
    end

    describe "grounding metadata in response" do
      it "includes grounding_metadata in converted response when present" do
        gemini_response = {
          "candidates" => [{
            "content" => {
              "parts" => [{ "text" => "Spain won Euro 2024." }],
              "role" => "model"
            },
            "finishReason" => "STOP",
            "groundingMetadata" => {
              "webSearchQueries" => ["euro 2024 winner"],
              "groundingChunks" => [
                { "web" => { "uri" => "https://uefa.com", "title" => "Euro 2024" } }
              ]
            }
          }],
          "usageMetadata" => {
            "promptTokenCount" => 10,
            "candidatesTokenCount" => 5,
            "totalTokenCount" => 15
          }
        }

        openai_response = provider.send(:convert_gemini_to_openai_format, gemini_response)

        expect(openai_response).to have_key("grounding_metadata")
        expect(openai_response["grounding_metadata"]["web_search_queries"]).to eq(["euro 2024 winner"])
        expect(openai_response["grounding_metadata"]["grounding_chunks"][0]["uri"]).to eq("https://uefa.com")
      end

      it "does not include grounding_metadata when not present" do
        gemini_response = {
          "candidates" => [{
            "content" => { "parts" => [{ "text" => "Hello!" }] },
            "finishReason" => "STOP"
          }],
          "usageMetadata" => {}
        }

        openai_response = provider.send(:convert_gemini_to_openai_format, gemini_response)

        expect(openai_response).not_to have_key("grounding_metadata")
      end
    end
  end
end
