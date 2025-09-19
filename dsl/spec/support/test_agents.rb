# frozen_string_literal: true

# Shared test agent classes used across multiple specs
module TestAgents
  class BasicTestAgent < RAAF::DSL::Agent
    agent_name "BasicTestAgent"
    model "gpt-4o"

    def build_instructions
      "You are a basic test assistant."
    end

    def build_schema
      {
        type: "object",
        properties: {
          message: { type: "string" }
        },
        required: ["message"],
        additionalProperties: false
      }
    end
  end

  class SmartTestAgent < RAAF::DSL::Agent
    agent_name "SmartTestAgent"
    model "gpt-4o-mini"
    max_turns 5
    temperature 0.7

    # Smart features using correct API
    retry_on :rate_limit, max_attempts: 3, backoff: :exponential
    retry_on Timeout::Error, max_attempts: 2
    circuit_breaker threshold: 5, timeout: 60, reset_timeout: 300

    # Context validation
    context do
      required :api_key
      required :endpoint
    end

    schema do
      field :status, type: :string, required: true
      field :data, type: :array do
        field :id, type: :string
        field :value, type: :integer, range: 0..100
      end
    end

    # Modern agent with static instructions and user prompt
    static_instructions "You are a smart test assistant."

    def build_instructions
      "You are a smart test assistant."
    end

    def build_user_prompt
      "Process endpoint #{context[:endpoint]} with key sk-123..."
    end

    def build_schema
      {
        type: "object",
        properties: {
          status: { type: "string" },
          data: {
            type: "array",
            items: {
              properties: {
                id: { type: "string" },
                value: { type: "integer" }
              }
            }
          }
        },
        required: ["status"],
        additionalProperties: false
      }
    end
  end

  class MinimalAgent < RAAF::DSL::Agent
    def build_instructions
      "Minimal agent"
    end

    def build_schema
      nil # Test unstructured output
    end
  end
end