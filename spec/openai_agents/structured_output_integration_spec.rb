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
        output_schema: schema
      )
    end

    it "creates agent with output schema" do
      expect(agent.output_schema).to eq(schema)
    end

    it "includes schema in hash representation" do
      agent_hash = agent.to_h
      expect(agent_hash[:output_schema]).to eq(schema)
    end
  end

  describe "Runner with structured output" do
    let(:agent) do
      OpenAIAgents::Agent.new(
        name: "TestAgent",
        instructions: "Return structured data.",
        model: "gpt-4o",
        output_schema: schema
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
        expect(result.messages.last[:content]).to eq('{"name":"Alice","age":25,"email":"alice@example.com","active":true}')
      end

      it "applies strict schema processing" do
        # StrictSchema should make all properties required
        expect_any_instance_of(OpenAIAgents::Models::ResponsesProvider)
          .to receive(:chat_completion) do |_, **kwargs|
            schema_sent = kwargs[:response_format][:json_schema][:schema]
            expect(schema_sent["required"]).to contain_exactly("name", "age", "email", "active")
            expect(schema_sent["additionalProperties"]).to be false
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
        
        expect(result.messages.last[:content]).to eq('{"name":"Alice","age":25,"email":"alice@example.com","active":true}')
      end

      it "applies strict schema processing" do
        expect(openai_provider)
          .to receive(:chat_completion) do |_, **kwargs|
            schema_sent = kwargs[:response_format][:json_schema][:schema]
            expect(schema_sent["required"]).to contain_exactly("name", "age", "email", "active")
            expect(schema_sent["additionalProperties"]).to be false
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
        output_schema: complex_schema
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

    it "handles complex nested schemas with strict processing" do
      expect_any_instance_of(OpenAIAgents::Models::ResponsesProvider)
        .to receive(:chat_completion) do |_, **kwargs|
          schema_sent = kwargs[:response_format][:json_schema][:schema]
          
          # Root level should require all properties
          expect(schema_sent["required"]).to contain_exactly("user", "orders")
          
          # User object should require all properties
          user_schema = schema_sent["properties"]["user"]
          expect(user_schema["required"]).to contain_exactly("name", "email")
          expect(user_schema["additionalProperties"]).to be false
          
          # Order items should require all properties
          order_schema = schema_sent["properties"]["orders"]["items"]
          expect(order_schema["required"]).to contain_exactly("id", "total")
          expect(order_schema["additionalProperties"]).to be false
          
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
        output_schema: schema
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
        output_schema: built_schema.to_h
      )
    end

    let(:runner) { OpenAIAgents::Runner.new(agent: agent) }

    it "works with builder-created schemas" do
      expect(agent.output_schema).to include(
        type: "object",
        additionalProperties: false
      )
      
      properties = agent.output_schema[:properties]
      expect(properties[:product_name]).to include(type: "string", minLength: 1)
      expect(properties[:price]).to include(type: "number", minimum: 0)
      expect(properties[:category]).to include(type: "string", enum: %w[electronics clothing food])
      expect(properties[:features]).to include(type: "array", items: { type: "string" }, minItems: 1)
      expect(properties[:in_stock]).to include(type: "boolean")
    end
  end
end