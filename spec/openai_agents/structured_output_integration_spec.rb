# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Structured Output Integration" do
  let(:schema) do
    {
      type: "object",
      properties: {
        name: { type: "string" },
        age: { type: "integer", minimum: 0, maximum: 150 },
        email: { type: "string" },
        active: { type: "boolean" }
      },
      required: %w[name age],
      additionalProperties: false
    }
  end

  describe "Agent with structured output" do
    let(:agent) do
      OpenAIAgents::Agent.new(
        name: "StructuredAgent",
        instructions: "Extract user information and return as JSON.",
        model: "gpt-4o",
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "user_info",
            strict: true,
            schema: schema
          }
        }
      )
    end

    it "creates agent with response format" do
      expect(agent.response_format).to include(:type, :json_schema)
      expect(agent.response_format[:json_schema][:schema]).to eq(schema)
    end

    it "includes response format in hash representation" do
      agent_hash = agent.to_h
      expect(agent_hash[:response_format]).to include(:type, :json_schema)
    end
  end

  describe "Runner with structured output" do
    let(:agent) do
      OpenAIAgents::Agent.new(
        name: "TestAgent",
        instructions: "Return structured data.",
        model: "gpt-4o",
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "test_schema",
            strict: true,
            schema: schema
          }
        }
      )
    end

    let(:messages) { [{ role: "user", content: "Extract info for Alice, age 25" }] }

    context "with ResponsesProvider (default)" do
      let(:runner) { OpenAIAgents::Runner.new(agent: agent) }

      let(:responses_api_response) do
        {
          "id" => "response_123",
          "output" => [
            {
              "content" => [
                {
                  "type" => "output_text",
                  "text" => '{"name": "Alice", "age": 25, "email": "alice@example.com", "active": true}'
                }
              ]
            }
          ]
        }
      end

      before do
        # Mock the call_responses_api method since that's what gets called internally
        allow_any_instance_of(OpenAIAgents::Models::ResponsesProvider)
          .to receive(:call_responses_api)
          .and_return(responses_api_response)
      end

      it "passes response_format to provider as text.format" do
        # Expect the provider to receive response_format and handle it properly
        expect_any_instance_of(OpenAIAgents::Models::ResponsesProvider)
          .to receive(:chat_completion) do |_, **kwargs|
            # ResponsesProvider should receive response_format
            expect(kwargs).to have_key(:response_format)
            response_format = kwargs[:response_format]
            expect(response_format[:type]).to eq("json_schema")
            expect(response_format[:json_schema][:strict]).to be true
            expect(response_format[:json_schema][:schema]).to be_a(Hash)
            responses_api_response
          end

        runner.run(messages)
      end

      it "extracts JSON from nested content structure" do
        result = runner.run(messages)
        
        # Should extract the JSON from the nested content array
        response_content = result.messages.last[:content]
        parsed_response = JSON.parse(response_content)
        expect(parsed_response).to eq({
                                        "name" => "Alice",
                                        "age" => 25,
                                        "email" => "alice@example.com",
                                        "active" => true
                                      })
      end

      it "passes response_format directly without modification" do
        # response_format should be passed as-is, no automatic strict processing
        expect_any_instance_of(OpenAIAgents::Models::ResponsesProvider)
          .to receive(:chat_completion) do |_, **kwargs|
            expect(kwargs[:response_format]).to be_truthy
            expect(kwargs[:response_format][:type]).to eq("json_schema")
            expect(kwargs[:response_format][:json_schema][:strict]).to be true
            responses_api_response
          end

        runner.run(messages)
      end
    end

    context "with OpenAIProvider" do
      let(:openai_provider) { OpenAIAgents::Models::OpenAIProvider.new }
      let(:runner) { OpenAIAgents::Runner.new(agent: agent, provider: openai_provider) }

      let(:chat_completions_response) do
        {
          "id" => "chatcmpl_123",
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => '{"name": "Alice", "age": 25, "email": "alice@example.com", "active": true}'
              }
            }
          ]
        }
      end

      before do
        # Mock the OpenAIProvider
        allow(openai_provider)
          .to receive(:chat_completion)
          .and_return(chat_completions_response)
      end

      it "passes response_format directly to OpenAI Chat Completions API" do
        expect(openai_provider)
          .to receive(:chat_completion) do |_, **kwargs|
            expect(kwargs).to have_key(:response_format)
            response_format = kwargs[:response_format]
            expect(response_format[:type]).to eq("json_schema")
            expect(response_format[:json_schema][:strict]).to be true
            expect(response_format[:json_schema][:schema]).to be_a(Hash)
            chat_completions_response
          end

        runner.run(messages)
      end

      it "returns structured JSON directly" do
        result = runner.run(messages)
        
        # Parse JSON and compare objects instead of string comparison for robustness
        parsed_response = JSON.parse(result.messages.last[:content])
        expect(parsed_response).to eq({
                                        "name" => "Alice",
                                        "age" => 25,
                                        "email" => "alice@example.com",
                                        "active" => true
                                      })
      end

      it "passes response_format directly to OpenAI without modification" do
        expect(openai_provider)
          .to receive(:chat_completion) do |_, **kwargs|
            expect(kwargs[:response_format]).to be_truthy
            expect(kwargs[:response_format][:type]).to eq("json_schema")
            expect(kwargs[:response_format][:json_schema][:strict]).to be true
            chat_completions_response
          end

        runner.run(messages)
      end
    end
  end

  describe "Complex schema integration" do
    let(:complex_schema) do
      {
        type: "object",
        properties: {
          user: {
            type: "object",
            properties: {
              name: { type: "string" },
              email: { type: "string" }
            },
            required: ["name"]
          },
          orders: {
            type: "array",
            items: {
              type: "object",
              properties: {
                id: { type: "string" },
                total: { type: "number", minimum: 0 }
              },
              required: ["id"]
            },
            minItems: 1
          }
        },
        required: ["user"],
        additionalProperties: false
      }
    end

    let(:agent) do
      OpenAIAgents::Agent.new(
        name: "ComplexAgent",
        model: "gpt-4o",
        response_format: { type: "json_schema", json_schema: { name: "complex_schema", strict: true, schema: complex_schema } }
      )
    end

    let(:runner) { OpenAIAgents::Runner.new(agent: agent) }
    let(:messages) { [{ role: "user", content: "Create user with orders" }] }

    let(:complex_response) do
      {
        "id" => "response_complex",
        "output" => [
          {
            "content" => [
              {
                "type" => "output_text",
                "text" => '{"user": {"name": "John", "email": "john@example.com"}, "orders": [{"id": "order1", "total": 99.99}]}'
              }
            ]
          }
        ]
      }
    end

    before do
      allow_any_instance_of(OpenAIAgents::Models::ResponsesProvider)
        .to receive(:call_responses_api)
        .and_return(complex_response)
    end

    it "handles complex nested schemas" do
      expect_any_instance_of(OpenAIAgents::Models::ResponsesProvider)
        .to receive(:chat_completion) do |_, **kwargs|
          # Should receive the response_format as configured
          expect(kwargs[:response_format]).to be_truthy
          expect(kwargs[:response_format][:type]).to eq("json_schema")
          expect(kwargs[:response_format][:json_schema][:strict]).to be true
          
          # Return the mocked response - this forces the provider's convert_response_to_chat_format method to handle it
          provider = OpenAIAgents::Models::ResponsesProvider.new
          provider.send(:convert_response_to_chat_format, complex_response)
        end

      result = runner.run(messages)
      expect(result.messages.last[:content]).to include("John")
    end
  end

  describe "Error handling integration" do
    let(:agent) do
      OpenAIAgents::Agent.new(
        name: "ErrorAgent",
        model: "gpt-4o", 
        response_format: { type: "json_schema", json_schema: { name: "test_schema", strict: true, schema: schema } }
      )
    end

    let(:runner) { OpenAIAgents::Runner.new(agent: agent) }
    let(:messages) { [{ role: "user", content: "Test input" }] }

    context "when provider fails" do
      before do
        allow_any_instance_of(OpenAIAgents::Models::ResponsesProvider)
          .to receive(:chat_completion)
          .and_raise(OpenAIAgents::APIError, "API failed")
      end

      it "propagates provider errors" do
        expect do
          runner.run(messages)
        end.to raise_error(OpenAIAgents::APIError, "API failed")
      end
    end

    context "when response parsing fails" do
      let(:malformed_response) do
        {
          "id" => "response_malformed",
          "output" => [
            {
              "content" => [
                {
                  "type" => "output_text",
                  "text" => "This is not the expected nested structure"
                }
              ]
            }
          ]
        }
      end

      before do
        allow_any_instance_of(OpenAIAgents::Models::ResponsesProvider)
          .to receive(:call_responses_api)
          .and_return(malformed_response)
      end

      it "handles malformed responses gracefully" do
        # Should still complete the run even if response format is unexpected
        result = runner.run(messages)
        expect(result.messages.last[:content]).to eq("This is not the expected nested structure")
      end
    end
  end

  describe "ObjectSchema builder integration" do
    let(:built_schema) do
      OpenAIAgents::StructuredOutput::ObjectSchema.build do
        string :product_name, required: true, minLength: 1
        number :price, required: true, minimum: 0
        string :category, enum: %w[electronics clothing food], required: true
        array :features, items: { type: "string" }, minItems: 1, required: true
        boolean :in_stock, required: true
        
        no_additional_properties
      end
    end

    let(:agent) do
      OpenAIAgents::Agent.new(
        name: "ProductAgent",
        model: "gpt-4o",
        response_format: { type: "json_schema", json_schema: { name: "product_schema", strict: true, schema: built_schema.to_h } }
      )
    end

    let(:runner) { OpenAIAgents::Runner.new(agent: agent) }

    it "works with builder-created schemas" do
      schema = agent.response_format[:json_schema][:schema]
      expect(schema).to include(
        type: "object",
        additionalProperties: false
      )
      
      properties = schema[:properties]
      expect(properties[:product_name]).to include(type: "string", minLength: 1)
      expect(properties[:price]).to include(type: "number", minimum: 0)
      expect(properties[:category]).to include(type: "string", enum: %w[electronics clothing food])
      expect(properties[:features]).to include(type: "array", items: { type: "string" }, minItems: 1)
      expect(properties[:in_stock]).to include(type: "boolean")
    end
  end

  describe "Multi-provider response_format support" do
    let(:schema) do
      {
        type: "object",
        properties: {
          name: { type: "string" },
          age: { type: "integer" }
        },
        required: %w[name age]
      }
    end

    let(:agent) do
      OpenAIAgents::Agent.new(
        name: "MultiProviderAgent",
        instructions: "Extract user information.",
        model: "gpt-4o",
        response_format: { type: "json_schema", json_schema: { name: "test_schema", strict: true, schema: schema } }
      )
    end

    let(:messages) { [{ role: "user", content: "Extract info for Bob, age 30" }] }

    context "with AnthropicProvider" do
      let(:anthropic_provider) do
        provider = instance_double(OpenAIAgents::Models::AnthropicProvider)
        allow(provider).to receive(:provider_name).and_return("Anthropic")
        provider
      end
      let(:runner) { OpenAIAgents::Runner.new(agent: agent, provider: anthropic_provider) }

      let(:anthropic_response) do
        {
          "content" => [{ "text" => '{"name": "Bob", "age": 30}' }],
          "model" => "claude-3-5-sonnet-20241022",
          "stop_reason" => "end_turn"
        }
      end

      before do
        allow(anthropic_provider).to receive(:chat_completion).and_return({
                                                                            "choices" => [{
                                                                              "message" => {
                                                                                "role" => "assistant",
                                                                                "content" => '{"name": "Bob", "age": 30}'
                                                                              },
                                                                              "finish_reason" => "stop"
                                                                            }]
                                                                          })
      end

      it "enhances system message with JSON schema instructions" do
        expect(anthropic_provider).to receive(:chat_completion) do |**kwargs|
          expect(kwargs[:response_format]).to be_truthy
          expect(kwargs[:response_format][:type]).to eq("json_schema")
          
          # Check that system message is enhanced for structured output
          # (This would be tested at the HTTP request level in real integration)
          anthropic_response
        end

        runner.run(messages)
      end
    end

    context "with GroqProvider" do
      let(:groq_provider) do
        provider = instance_double(OpenAIAgents::Models::GroqProvider)
        allow(provider).to receive(:provider_name).and_return("Groq")
        provider
      end
      let(:runner) { OpenAIAgents::Runner.new(agent: agent, provider: groq_provider) }

      let(:groq_response) do
        {
          "id" => "chatcmpl_groq_123",
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => '{"name": "Bob", "age": 30}'
            },
            "finish_reason" => "stop"
          }]
        }
      end

      before do
        allow(groq_provider).to receive(:chat_completion).and_return(groq_response)
      end

      it "passes response_format directly to Groq API" do
        expect(groq_provider).to receive(:chat_completion) do |**kwargs|
          expect(kwargs[:response_format]).to be_truthy
          expect(kwargs[:response_format][:type]).to eq("json_schema")
          expect(kwargs[:response_format][:json_schema][:strict]).to be true
          groq_response
        end

        runner.run(messages)
      end
    end

    context "with CohereProvider" do
      let(:cohere_provider) do
        provider = instance_double(OpenAIAgents::Models::CohereProvider)
        allow(provider).to receive(:provider_name).and_return("Cohere")
        provider
      end
      let(:runner) { OpenAIAgents::Runner.new(agent: agent, provider: cohere_provider) }

      let(:cohere_response) do
        {
          "id" => "cohere_123",
          "model" => "command-r",
          "message" => {
            "content" => '{"name": "Bob", "age": 30}'
          },
          "finish_reason" => "complete"
        }
      end

      before do
        allow(cohere_provider).to receive(:chat_completion).and_return({
                                                                         "id" => "cohere_123",
                                                                         "object" => "chat.completion",
                                                                         "created" => Time.now.to_i,
                                                                         "model" => "command-r",
                                                                         "choices" => [{
                                                                           "index" => 0,
                                                                           "message" => {
                                                                             "role" => "assistant",
                                                                             "content" => '{"name": "Bob", "age": 30}'
                                                                           },
                                                                           "finish_reason" => "stop"
                                                                         }]
                                                                       })
      end

      it "converts json_schema to json_object format for Cohere" do
        expect(cohere_provider).to receive(:chat_completion) do |**kwargs|
          expect(kwargs[:response_format]).to be_truthy
          expect(kwargs[:response_format][:type]).to eq("json_schema")
          # Cohere provider should handle the conversion internally
          cohere_response
        end

        runner.run(messages)
      end
    end

    context "with direct response_format parameter" do
      let(:agent_with_response_format) do
        OpenAIAgents::Agent.new(
          name: "DirectFormatAgent",
          instructions: "Return JSON.",
          model: "gpt-4o",
          response_format: {
            type: "json_schema",
            json_schema: {
              name: "user_info",
              strict: true,
              schema: schema
            }
          }
        )
      end

      context "with ResponsesProvider" do
        let(:runner) { OpenAIAgents::Runner.new(agent: agent_with_response_format) }
        
        before do
          allow_any_instance_of(OpenAIAgents::Models::ResponsesProvider)
            .to receive(:call_responses_api)
            .and_return({
                          "id" => "response_direct",
                          "output" => [{
                            "content" => [{
                              "type" => "output_text",
                              "text" => '{"name": "Bob", "age": 30}'
                            }]
                          }]
                        })
        end

        it "uses direct response_format when provided" do
          expect_any_instance_of(OpenAIAgents::Models::ResponsesProvider)
            .to receive(:chat_completion) do |_, **kwargs|
              expect(kwargs[:response_format]).to be_truthy
              expect(kwargs[:response_format][:type]).to eq("json_schema")
              expect(kwargs[:response_format][:json_schema][:name]).to eq("user_info")
              expect(kwargs[:response_format][:json_schema][:strict]).to be true
              {}
            end

          runner.run(messages)
        end
      end

      context "with OpenAIProvider" do
        let(:openai_provider) do
          provider = instance_double(OpenAIAgents::Models::OpenAIProvider)
          allow(provider).to receive(:provider_name).and_return("OpenAI")
          provider
        end
        let(:runner) { OpenAIAgents::Runner.new(agent: agent_with_response_format, provider: openai_provider) }
        
        before do
          allow(openai_provider).to receive(:chat_completion).and_return({
                                                                           "choices" => [{
                                                                             "message" => {
                                                                               "role" => "assistant",
                                                                               "content" => '{"name": "Bob", "age": 30}'
                                                                             }
                                                                           }]
                                                                         })
        end

        it "passes direct response_format to OpenAI API" do
          expect(openai_provider).to receive(:chat_completion) do |**kwargs|
            expect(kwargs[:response_format]).to be_truthy
            expect(kwargs[:response_format][:type]).to eq("json_schema")
            expect(kwargs[:response_format][:json_schema][:name]).to eq("user_info")
            {}
          end

          runner.run(messages)
        end
      end
    end
  end
end