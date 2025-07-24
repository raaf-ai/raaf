# frozen_string_literal: true

require "spec_helper"
require "net/http"
require "timeout"

RSpec.describe RAAF::Execution::ErrorHandler do
  let(:context) { { agent: "TestAgent", operation: "test_operation" } }

  describe "#initialize" do
    it "uses FAIL_FAST strategy by default" do
      handler = described_class.new
      expect(handler.strategy).to eq(RAAF::Execution::ErrorHandler::RecoveryStrategy::FAIL_FAST)
    end

    it "accepts custom strategy" do
      handler = described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::LOG_AND_CONTINUE)
      expect(handler.strategy).to eq(RAAF::Execution::ErrorHandler::RecoveryStrategy::LOG_AND_CONTINUE)
    end

    it "accepts max_retries configuration" do
      handler = described_class.new(max_retries: 3)
      expect(handler.instance_variable_get(:@max_retries)).to eq(3)
    end

    it "initializes retry count to zero" do
      handler = described_class.new
      expect(handler.instance_variable_get(:@retry_count)).to eq(0)
    end
  end

  describe "RecoveryStrategy constants" do
    it "defines all recovery strategies" do
      expect(RAAF::Execution::ErrorHandler::RecoveryStrategy::FAIL_FAST).to eq(:fail_fast)
      expect(RAAF::Execution::ErrorHandler::RecoveryStrategy::LOG_AND_CONTINUE).to eq(:log_and_continue)
      expect(RAAF::Execution::ErrorHandler::RecoveryStrategy::RETRY_ONCE).to eq(:retry_once)
      expect(RAAF::Execution::ErrorHandler::RecoveryStrategy::GRACEFUL_DEGRADATION).to eq(:graceful_degradation)
    end
  end

  describe "#with_error_handling" do
    context "with FAIL_FAST strategy" do
      let(:handler) { described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::FAIL_FAST) }

      it "executes block successfully" do
        result = handler.with_error_handling(context) { "success" }
        expect(result).to eq("success")
      end

      it "re-raises MaxTurnsError" do
        expect do
          handler.with_error_handling(context) { raise RAAF::MaxTurnsError, "Too many turns" }
        end.to raise_error(RAAF::MaxTurnsError, "Too many turns")
      end

      it "re-raises ExecutionStoppedError" do
        expect do
          handler.with_error_handling(context) { raise RAAF::ExecutionStoppedError, "Execution stopped" }
        end.to raise_error(RAAF::ExecutionStoppedError, "Execution stopped")
      end

      it "re-raises JSON parsing errors" do
        expect do
          handler.with_error_handling(context) { raise JSON::ParserError, "Invalid JSON" }
        end.to raise_error(JSON::ParserError, "Invalid JSON")
      end

      it "re-raises general errors" do
        expect do
          handler.with_error_handling(context) { raise StandardError, "General error" }
        end.to raise_error(StandardError, "General error")
      end
    end

    context "with LOG_AND_CONTINUE strategy" do
      let(:handler) { described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::LOG_AND_CONTINUE) }

      it "handles MaxTurnsError gracefully" do
        result = handler.with_error_handling(context) { raise RAAF::MaxTurnsError, "Too many turns" }
        expect(result).to eq({ error: :max_turns_exceeded, handled: true })
      end

      it "handles ExecutionStoppedError gracefully" do
        result = handler.with_error_handling(context) { raise RAAF::ExecutionStoppedError, "Stopped" }
        expect(result).to include({ error: :execution_stopped, handled: true })
      end

      it "still re-raises other errors in LOG_AND_CONTINUE mode" do
        # LOG_AND_CONTINUE is specific to certain error types
        expect do
          handler.with_error_handling(context) { raise StandardError, "General error" }
        end.to raise_error(StandardError, "General error")
      end
    end

    context "with GRACEFUL_DEGRADATION strategy" do
      let(:handler) { described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::GRACEFUL_DEGRADATION) }

      it "provides user-friendly error messages for MaxTurnsError" do
        result = handler.with_error_handling(context) { raise RAAF::MaxTurnsError, "Too many turns" }
        expect(result).to eq({ error: :max_turns_exceeded, message: "Conversation truncated due to length" })
      end

      it "provides user-friendly error messages for ExecutionStoppedError" do
        result = handler.with_error_handling(context) { raise RAAF::ExecutionStoppedError, "Stopped" }
        expect(result).to include({ error: :execution_stopped, message: "Execution was halted" })
      end
    end

    context "with RETRY_ONCE strategy" do
      let(:handler) { described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::RETRY_ONCE, max_retries: 1) }

      it "retries operation once on general errors" do
        attempt_count = 0
        result = handler.with_error_handling(context) do
          attempt_count += 1
          raise StandardError, "First attempt fails" if attempt_count == 1

          "success on retry"
        end

        expect(result).to eq("success on retry")
        expect(attempt_count).to eq(2)
      end

      it "gives up after max retries" do
        attempt_count = 0
        expect do
          handler.with_error_handling(context) do
            attempt_count += 1
            raise StandardError, "Always fails"
          end
        end.to raise_error(StandardError, "Always fails")

        expect(attempt_count).to eq(2) # Original attempt + 1 retry
      end
    end

    it "resets retry count after successful execution" do
      handler = described_class.new

      # Execute successfully
      handler.with_error_handling(context) { "success" }

      # Verify retry count is reset
      expect(handler.instance_variable_get(:@retry_count)).to eq(0)
    end
  end

  describe "#with_api_error_handling" do
    let(:handler) { described_class.new }

    it "executes block successfully" do
      result = handler.with_api_error_handling(context) { "api success" }
      expect(result).to eq("api success")
    end

    it "handles Timeout::Error" do
      expect do
        handler.with_api_error_handling(context) { raise Timeout::Error, "Request timeout" }
      end.to raise_error(Timeout::Error, "Request timeout")
    end

    it "handles Net::HTTPError" do
      expect do
        handler.with_api_error_handling(context) { raise Net::HTTPError.new("HTTP error", nil) }
      end.to raise_error(Net::HTTPError, "HTTP error")
    end

    it "falls back to general error handling for other errors" do
      expect do
        handler.with_api_error_handling(context) { raise StandardError, "General API error" }
      end.to raise_error(StandardError, "General API error")
    end
  end

  describe "#handle_tool_error" do
    let(:handler) { described_class.new }

    it "handles JSON::ParserError" do
      error = JSON::ParserError.new("Invalid JSON syntax")
      result = handler.handle_tool_error("test_tool", error, context)
      expect(result).to eq("Error: Invalid tool arguments format")
    end

    it "handles ArgumentError" do
      error = ArgumentError.new("Wrong number of arguments")
      result = handler.handle_tool_error("test_tool", error, context)
      expect(result).to eq("Error: Invalid arguments provided to tool")
    end

    it "handles general StandardError" do
      error = StandardError.new("Something went wrong")
      result = handler.handle_tool_error("test_tool", error, context)
      expect(result).to eq("Error: Tool execution failed - Something went wrong")
    end

    it "includes tool name in error context" do
      error = StandardError.new("Tool failed")

      # Mock the logging to verify context is included
      allow(handler).to receive(:log_error)

      handler.handle_tool_error("my_special_tool", error, context)

      expect(handler).to have_received(:log_error).with(
        "Tool execution failed",
        hash_including(tool: "my_special_tool", error_class: "StandardError", message: "Tool failed")
      )
    end

    it "merges additional context information" do
      error = ArgumentError.new("Bad args")
      additional_context = { user_id: "user123", request_id: "req456" }

      allow(handler).to receive(:log_error)

      handler.handle_tool_error("test_tool", error, additional_context)

      expect(handler).to have_received(:log_error).with(
        "Tool argument error",
        hash_including(
          tool: "test_tool",
          error_class: "ArgumentError",
          user_id: "user123",
          request_id: "req456",
          message: "Bad args"
        )
      )
    end
  end

  describe "error handling strategies integration" do
    context "MaxTurnsError handling" do
      it "applies different strategies correctly" do
        error = RAAF::MaxTurnsError.new("Max turns exceeded")

        # FAIL_FAST
        fail_fast_handler = described_class.new(strategy: :fail_fast)
        expect do
          fail_fast_handler.with_error_handling(context) { raise error }
        end.to raise_error(RAAF::MaxTurnsError)

        # LOG_AND_CONTINUE
        log_continue_handler = described_class.new(strategy: :log_and_continue)
        result = log_continue_handler.with_error_handling(context) { raise error }
        expect(result[:error]).to eq(:max_turns_exceeded)
        expect(result[:handled]).to be true

        # GRACEFUL_DEGRADATION
        graceful_handler = described_class.new(strategy: :graceful_degradation)
        result = graceful_handler.with_error_handling(context) { raise error }
        expect(result[:error]).to eq(:max_turns_exceeded)
        expect(result[:message]).to include("truncated")
      end
    end

    context "ExecutionStoppedError handling" do
      it "applies different strategies correctly" do
        error = RAAF::ExecutionStoppedError.new("Execution halted")

        # FAIL_FAST
        fail_fast_handler = described_class.new(strategy: :fail_fast)
        expect do
          fail_fast_handler.with_error_handling(context) { raise error }
        end.to raise_error(RAAF::ExecutionStoppedError)

        # LOG_AND_CONTINUE
        log_continue_handler = described_class.new(strategy: :log_and_continue)
        result = log_continue_handler.with_error_handling(context) { raise error }
        expect(result[:error]).to eq(:execution_stopped)
        expect(result[:handled]).to be true

        # GRACEFUL_DEGRADATION
        graceful_handler = described_class.new(strategy: :graceful_degradation)
        result = graceful_handler.with_error_handling(context) { raise error }
        expect(result[:error]).to eq(:execution_stopped)
        expect(result[:message]).to eq("Execution was halted")
      end
    end
  end

  describe "retry logic" do
    context "with RETRY_ONCE strategy" do
      it "tracks retry attempts correctly" do
        handler = described_class.new(strategy: :retry_once, max_retries: 2)
        attempts = []

        expect do
          handler.with_error_handling(context) do
            attempts << Time.now
            raise StandardError, "Always fails"
          end
        end.to raise_error(StandardError)

        expect(attempts.length).to eq(3) # Original + 2 retries
      end

      it "succeeds on retry attempt" do
        handler = described_class.new(strategy: :retry_once, max_retries: 1)
        attempt_count = 0

        result = handler.with_error_handling(context) do
          attempt_count += 1
          raise StandardError, "Temporary failure" if attempt_count <= 1

          "Success after retry"
        end

        expect(result).to eq("Success after retry")
        expect(attempt_count).to eq(2)
      end

      it "resets retry count between executions" do
        handler = described_class.new(strategy: :retry_once, max_retries: 1)

        # First execution with failure
        attempt_count1 = 0
        expect do
          handler.with_error_handling(context) do
            attempt_count1 += 1
            raise StandardError, "Always fails"
          end
        end.to raise_error(StandardError)
        expect(attempt_count1).to eq(2)

        # Second execution should also get full retries
        attempt_count2 = 0
        expect do
          handler.with_error_handling(context) do
            attempt_count2 += 1
            raise StandardError, "Always fails"
          end
        end.to raise_error(StandardError)
        expect(attempt_count2).to eq(2)
      end

      it "handles ExecutionStoppedError with retries" do
        handler = described_class.new(strategy: :retry_once, max_retries: 2)
        attempt_count = 0

        result = handler.with_error_handling(context) do
          attempt_count += 1
          raise RAAF::ExecutionStoppedError, "Stopped" if attempt_count <= 2

          "success after retries"
        end

        expect(attempt_count).to eq(3)
        expect(result).to eq("success after retries")
      end
    end
  end

  describe "parsing error handling" do
    context "with JSON::ParserError" do
      let(:parse_error) { JSON::ParserError.new("Unexpected token") }

      it "handles with FAIL_FAST strategy" do
        handler = described_class.new(strategy: :fail_fast)
        expect do
          handler.with_error_handling(context) { raise parse_error }
        end.to raise_error(JSON::ParserError)
      end

      it "handles with LOG_AND_CONTINUE strategy" do
        handler = described_class.new(strategy: :log_and_continue)
        result = handler.with_error_handling(context) { raise parse_error }
        expect(result).to eq({ error: :parsing_failed, message: "Failed to parse response", handled: true })
      end

      it "handles with GRACEFUL_DEGRADATION strategy" do
        handler = described_class.new(strategy: :graceful_degradation)
        result = handler.with_error_handling(context) { raise parse_error }
        expect(result).to eq({ error: :parsing_failed, message: "Failed to parse response", handled: true })
      end

      it "handles with RETRY_ONCE strategy" do
        handler = described_class.new(strategy: :retry_once, max_retries: 1)
        attempt_count = 0

        result = handler.with_error_handling(context) do
          attempt_count += 1
          raise parse_error
        end

        expect(attempt_count).to eq(2) # Original + 1 retry
        expect(result).to eq({ error: :parsing_failed, message: "Failed to parse after retries", handled: true })
      end
    end
  end

  describe "API error handling" do
    context "with Timeout::Error" do
      let(:timeout_error) { Timeout::Error.new("Request timed out") }

      it "handles with FAIL_FAST strategy" do
        handler = described_class.new(strategy: :fail_fast)
        expect do
          handler.with_api_error_handling(context) { raise timeout_error }
        end.to raise_error(Timeout::Error)
      end

      it "handles with RETRY_ONCE strategy" do
        handler = described_class.new(strategy: :retry_once, max_retries: 1)
        attempt_count = 0

        result = handler.with_api_error_handling(context) do
          attempt_count += 1
          raise timeout_error
        end

        expect(attempt_count).to eq(2)
        expect(result).to eq({ error: :timeout, message: "Request timed out after retries", handled: true })
      end

      it "handles with GRACEFUL_DEGRADATION strategy" do
        handler = described_class.new(strategy: :graceful_degradation)
        result = handler.with_api_error_handling(context) { raise timeout_error }
        expect(result).to eq({ error: :timeout, message: "Request timed out, please try again", handled: true })
      end
    end

    context "with Net::HTTPError" do
      let(:http_error) { Net::HTTPError.new("503 Service Unavailable", nil) }

      it "handles with GRACEFUL_DEGRADATION strategy" do
        handler = described_class.new(strategy: :graceful_degradation)
        result = handler.with_api_error_handling(context) { raise http_error }
        expect(result).to eq({ error: :http_error, message: "Service temporarily unavailable", handled: true })
      end

      it "re-raises with other strategies" do
        %i[fail_fast log_and_continue retry_once].each do |strategy|
          handler = described_class.new(strategy: strategy)
          expect do
            handler.with_api_error_handling(context) { raise http_error }
          end.to raise_error(Net::HTTPError)
        end
      end
    end
  end

  describe "general error handling" do
    let(:general_error) { StandardError.new("Something went wrong") }

    it "handles with FAIL_FAST strategy" do
      handler = described_class.new(strategy: :fail_fast)
      expect do
        handler.with_error_handling(context) { raise general_error }
      end.to raise_error(StandardError)
    end

    it "still raises with LOG_AND_CONTINUE for general errors" do
      handler = described_class.new(strategy: :log_and_continue)
      expect do
        handler.with_error_handling(context) { raise general_error }
      end.to raise_error(StandardError)
    end

    it "handles with GRACEFUL_DEGRADATION strategy" do
      handler = described_class.new(strategy: :graceful_degradation)
      result = handler.with_error_handling(context) { raise general_error }
      expect(result).to eq({ error: :general_error, message: "An unexpected error occurred", handled: true })
    end

    it "retries with RETRY_ONCE then raises" do
      handler = described_class.new(strategy: :retry_once, max_retries: 1)
      attempt_count = 0

      expect do
        handler.with_error_handling(context) do
          attempt_count += 1
          raise general_error
        end
      end.to raise_error(StandardError)

      expect(attempt_count).to eq(2)
    end
  end

  describe "guardrail error handling" do
    # NOTE: These tests simulate guardrail behavior when the Guardrails gem is not loaded
    context "when Guardrails is not defined" do
      it "handles errors normally" do
        handler = described_class.new
        expect do
          handler.with_error_handling(context) { raise StandardError, "Test" }
        end.to raise_error(StandardError)
      end
    end

    # If Guardrails were defined, we'd test:
    # - InputGuardrailTripwireTriggered handling
    # - OutputGuardrailTripwireTriggered handling
    # - Different recovery strategies for guardrail errors
  end

  describe "logging integration" do
    let(:handler) { described_class.new }

    it "includes Logger module" do
      expect(described_class.included_modules).to include(RAAF::Logger)
    end

    it "logs errors with context" do
      allow(handler).to receive(:log_error)

      expect do
        handler.with_error_handling(context) { raise StandardError, "Test error" }
      end.to raise_error(StandardError)

      expect(handler).to have_received(:log_error).with(
        "Unexpected error occurred",
        hash_including(
          agent: "TestAgent",
          operation: "test_operation",
          error_class: "StandardError",
          message: "Test error"
        )
      )
    end

    it "logs retries" do
      handler = described_class.new(strategy: :retry_once)
      allow(handler).to receive(:log_info)

      expect do
        handler.with_error_handling(context) do
          raise StandardError, "Retry me"
        end
      end.to raise_error(StandardError)

      expect(handler).to have_received(:log_info).with(
        "Retrying operation",
        hash_including(attempt: 1)
      )
    end

    it "logs warnings for guardrail-like errors" do
      handler = described_class.new(strategy: :log_and_continue)
      allow(handler).to receive(:log_warn)

      handler.with_error_handling(context) { raise RAAF::MaxTurnsError, "Too many" }

      expect(handler).to have_received(:log_warn).with("Continuing despite max turns exceeded")
    end
  end

  describe "strategy-specific behaviors" do
    context "LOG_AND_CONTINUE vs other strategies" do
      it "LOG_AND_CONTINUE still re-raises general errors" do
        log_handler = described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::LOG_AND_CONTINUE)
        expect do
          log_handler.with_error_handling(context) { raise StandardError, "Test error" }
        end.to raise_error(StandardError, "Test error")
      end

      it "FAIL_FAST re-raises general errors" do
        fail_handler = described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::FAIL_FAST)
        expect do
          fail_handler.with_error_handling(context) { raise StandardError, "Test error" }
        end.to raise_error(StandardError, "Test error")
      end

      it "GRACEFUL_DEGRADATION handles general errors gracefully" do
        graceful_handler = described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::GRACEFUL_DEGRADATION)
        result = graceful_handler.with_error_handling(context) { raise StandardError, "Test error" }
        expect(result).to eq({ error: :general_error, message: "An unexpected error occurred", handled: true })
      end
    end
  end

  describe "edge cases" do
    it "handles nil context gracefully" do
      handler = described_class.new
      result = handler.with_error_handling(nil) { "success" }
      expect(result).to eq("success")
    end

    it "handles empty context gracefully" do
      handler = described_class.new
      result = handler.with_error_handling({}) { "success" }
      expect(result).to eq("success")
    end

    it "preserves non-error exceptions" do
      handler = described_class.new

      expect do
        handler.with_error_handling(context) { throw :test_signal }
      end.to throw_symbol(:test_signal)
    end

    it "ensures retry count is reset in ensure block" do
      handler = described_class.new(strategy: :retry_once)

      begin
        handler.with_error_handling(context) { raise StandardError }
      rescue StandardError
        # Ignore
      end

      expect(handler.instance_variable_get(:@retry_count)).to eq(0)
    end
  end
end
