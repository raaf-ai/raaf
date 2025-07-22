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
    end
  end
end
