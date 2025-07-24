# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF Error Classes" do
  describe RAAF::Error do
    it "is a StandardError" do
      expect(described_class).to be < StandardError
    end

    it "can be rescued as a StandardError" do
      expect do
        raise described_class, "Test error"
      end.to raise_error(StandardError)
    end

    it "can be rescued specifically" do
      expect do
        raise described_class, "Test error"
      end.to raise_error(described_class, "Test error")
    end
  end

  describe RAAF::AgentError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    it "provides clear error messages for configuration issues" do
      error = described_class.new("Agent configuration is invalid: missing API key")
      expect(error.message).to eq("Agent configuration is invalid: missing API key")
    end

    it "can be rescued as RAAF::Error" do
      expect do
        raise described_class, "Agent failed"
      end.to raise_error(RAAF::Error)
    end
  end

  describe RAAF::ToolError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    context "tool not found" do
      it "provides clear error messages" do
        error = described_class.new("Tool 'calculator' not found")
        expect(error.message).to eq("Tool 'calculator' not found")
      end
    end

    context "tool execution failure" do
      it "includes execution error details" do
        original_error = RuntimeError.new("API timeout")
        error = described_class.new("Tool 'weather_api' execution failed: #{original_error}")
        expect(error.message).to include("weather_api")
        expect(error.message).to include("API timeout")
      end
    end
  end

  describe RAAF::HandoffError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    context "target not found" do
      it "provides clear error messages" do
        error = described_class.new("Cannot handoff to non-existent agent 'unknown'")
        expect(error.message).to include("non-existent agent 'unknown'")
      end
    end

    context "invalid configuration" do
      it "explains configuration requirements" do
        error = described_class.new("Handoff must be an Agent or Handoff object")
        expect(error.message).to eq("Handoff must be an Agent or Handoff object")
      end
    end
  end

  describe RAAF::TracingError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    it "provides clear error messages for tracing failures" do
      error = described_class.new("Failed to initialize tracer: connection refused")
      expect(error.message).to include("Failed to initialize tracer")
      expect(error.message).to include("connection refused")
    end
  end

  describe RAAF::MaxTurnsError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    it "includes turn limit in message" do
      error = described_class.new("Maximum turns (10) exceeded")
      expect(error.message).to eq("Maximum turns (10) exceeded")
    end
  end

  describe RAAF::BatchError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    context "submission failure" do
      it "provides clear error messages" do
        error = described_class.new("Failed to submit batch: invalid batch format")
        expect(error.message).to include("Failed to submit batch")
        expect(error.message).to include("invalid batch format")
      end
    end
  end

  describe RAAF::AuthenticationError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    it "provides security-appropriate error messages" do
      error = described_class.new("Invalid API key provided")
      expect(error.message).to eq("Invalid API key provided")
    end
  end

  describe RAAF::RateLimitError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    it "includes retry information" do
      error = described_class.new("Rate limit exceeded. Retry after 60 seconds")
      expect(error.message).to include("Rate limit exceeded")
      expect(error.message).to include("60 seconds")
    end
  end

  describe RAAF::ServerError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    it "includes status code information" do
      error = described_class.new("API server error (status 500): Internal server error")
      expect(error.message).to include("status 500")
      expect(error.message).to include("Internal server error")
    end
  end

  describe RAAF::APIError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    it "provides general API error messages" do
      error = described_class.new("API request failed: connection timeout")
      expect(error.message).to include("API request failed")
      expect(error.message).to include("connection timeout")
    end
  end

  describe RAAF::ExecutionStoppedError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    it "indicates user-requested stop" do
      error = described_class.new("Execution stopped by user request")
      expect(error.message).to eq("Execution stopped by user request")
    end
  end

  describe RAAF::ModelBehaviorError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    context "invalid tool input" do
      it "provides clear error messages" do
        error = described_class.new("Model provided invalid JSON for tool parameters")
        expect(error.message).to eq("Model provided invalid JSON for tool parameters")
      end
    end

    context "constraint violation" do
      it "indicates policy violations" do
        error = described_class.new("Model output violates content policy")
        expect(error.message).to eq("Model output violates content policy")
      end
    end
  end

  describe RAAF::ProviderError do
    it "inherits from RAAF::Error" do
      expect(described_class).to be < RAAF::Error
    end

    context "unsupported API" do
      it "provides clear error messages" do
        error = described_class.new("Provider doesn't support any known completion API")
        expect(error.message).to eq("Provider doesn't support any known completion API")
      end
    end

    context "initialization failure" do
      it "includes failure details" do
        error = described_class.new("Provider initialization failed: missing credentials")
        expect(error.message).to include("Provider initialization failed")
        expect(error.message).to include("missing credentials")
      end
    end
  end

  describe "Error hierarchy and rescue behavior" do
    it "allows rescuing all RAAF errors with base class" do
      errors_caught = []

      [
        RAAF::AgentError,
        RAAF::ToolError,
        RAAF::HandoffError,
        RAAF::TracingError,
        RAAF::MaxTurnsError,
        RAAF::BatchError,
        RAAF::AuthenticationError,
        RAAF::RateLimitError,
        RAAF::ServerError,
        RAAF::APIError,
        RAAF::ExecutionStoppedError,
        RAAF::ModelBehaviorError,
        RAAF::ProviderError
      ].each do |error_class|
        raise error_class, "Test error"
      rescue RAAF::Error => e
        errors_caught << e.class
      end

      expect(errors_caught.size).to eq(13)
      expect(errors_caught.uniq.size).to eq(13) # All different error classes
    end

    it "allows specific error handling while falling back to general" do
      handled = nil

      begin
        raise RAAF::AuthenticationError, "Invalid key"
      rescue RAAF::AuthenticationError
        handled = :auth_error
      rescue RAAF::Error
        handled = :general_error
      end

      expect(handled).to eq(:auth_error)
    end

    it "doesn't catch non-RAAF errors with RAAF::Error" do
      expect do
        raise StandardError, "Not a RAAF error"
      rescue RAAF::Error
        # This should not be reached
      end.to raise_error(StandardError, "Not a RAAF error")
    end
  end

  describe "Error use cases" do
    context "agent initialization" do
      it "uses AgentError for configuration issues" do
        expect do
          raise RAAF::AgentError, "Invalid model specified"
        end.to raise_error(RAAF::AgentError, "Invalid model specified")
      end
    end

    context "tool execution" do
      it "uses ToolError for missing tools" do
        expect do
          raise RAAF::ToolError, "Tool 'search' not found in agent"
        end.to raise_error(RAAF::ToolError, /Tool 'search' not found/)
      end

      it "uses ToolError for execution failures" do
        expect do
          raise RAAF::ToolError, "Tool execution failed: network error"
        end.to raise_error(RAAF::ToolError, /network error/)
      end
    end

    context "API interactions" do
      it "uses AuthenticationError for auth failures" do
        expect do
          raise RAAF::AuthenticationError, "API key expired"
        end.to raise_error(RAAF::AuthenticationError, "API key expired")
      end

      it "uses RateLimitError for rate limiting" do
        expect do
          raise RAAF::RateLimitError, "Rate limit: 3/min, retry after 20s"
        end.to raise_error(RAAF::RateLimitError, /retry after 20s/)
      end

      it "uses ServerError for server issues" do
        expect do
          raise RAAF::ServerError, "503 Service Unavailable"
        end.to raise_error(RAAF::ServerError, "503 Service Unavailable")
      end
    end

    context "model behavior" do
      it "uses ModelBehaviorError for unexpected outputs" do
        expect do
          raise RAAF::ModelBehaviorError, "Model returned empty response"
        end.to raise_error(RAAF::ModelBehaviorError, "Model returned empty response")
      end
    end
  end
end
