# frozen_string_literal: true

require "spec_helper"

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
  end

  describe "#with_error_handling" do
    context "with FAIL_FAST strategy (default)" do
      let(:handler) { described_class.new }

      it "executes block successfully" do
        result = handler.with_error_handling(context) { "success" }
        expect(result).to eq("success")
      end

      it "re-raises MaxTurnsError" do
        expect do
          handler.with_error_handling(context) { raise RAAF::MaxTurnsError, "Too many turns" }
        end.to raise_error(RAAF::MaxTurnsError, "Too many turns")
      end

      it "handles ExecutionStoppedError gracefully (always handled)" do
        result = handler.with_error_handling(context) { raise RAAF::ExecutionStoppedError, "Execution stopped" }
        expect(result).to eq({ error: :execution_stopped, message: "Execution stopped", handled: true })
      end

      it "re-raises JSON parsing errors" do
        expect do
          handler.with_error_handling(context) { raise JSON::ParserError, "Invalid JSON" }
        end.to raise_error(JSON::ParserError, "Invalid JSON")
      end

      it "re-raises general StandardError" do
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
        expect(result).to eq({ error: :execution_stopped, message: "Stopped", handled: true })
      end

      it "handles general errors gracefully" do
        result = handler.with_error_handling(context) { raise StandardError, "General error" }
        expect(result).to eq({ error: :general_error, message: "General error", handled: true })
      end
    end

    context "with GRACEFUL_DEGRADATION strategy" do
      let(:handler) { described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::GRACEFUL_DEGRADATION) }

      it "provides user-friendly error messages for MaxTurnsError" do
        result = handler.with_error_handling(context) { raise RAAF::MaxTurnsError, "Too many turns" }
        expect(result).to eq({ error: :max_turns_exceeded, message: "Conversation truncated due to length" })
      end

      it "provides user-friendly error messages for general errors" do
        result = handler.with_error_handling(context) { raise StandardError, "Some internal error" }
        expect(result).to eq({ error: :general_error, message: "An unexpected error occurred", handled: true })
      end

      it "handles ExecutionStoppedError gracefully" do
        result = handler.with_error_handling(context) { raise RAAF::ExecutionStoppedError, "Stopped" }
        expect(result).to eq({ error: :execution_stopped, message: "Stopped", handled: true })
      end
    end

    context "with RETRY_ONCE strategy" do
      let(:handler) { described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::RETRY_ONCE, max_retries: 2) }

      it "re-raises error on first attempt (for higher-level retry coordination)" do
        expect do
          handler.with_error_handling(context) { raise StandardError, "Temporary failure" }
        end.to raise_error(StandardError, "Temporary failure")
      end

      it "gives up after max retries reached" do
        # Simulate exhausted retries
        handler.instance_variable_set(:@retry_count, 2)
        
        result = handler.with_error_handling(context) { raise StandardError, "Persistent failure" }
        expect(result).to eq({ error: :general_error, message: "Failed after retries", handled: true })
      end

      it "tracks retry attempts" do
        initial_count = handler.instance_variable_get(:@retry_count)
        expect(initial_count).to eq(0)

        begin
          handler.with_error_handling(context) { raise StandardError, "Test" }
        rescue StandardError
          # Expected on first attempt
        end

        updated_count = handler.instance_variable_get(:@retry_count)
        expect(updated_count).to eq(1)
      end
    end
  end

  describe "#with_api_error_handling" do
    let(:handler) { described_class.new }

    it "handles Net::TimeoutError" do
      expect do
        handler.with_api_error_handling(context) { raise Net::TimeoutError, "Request timeout" }
      end.to raise_error(Net::TimeoutError, "Request timeout")
    end

    it "handles Net::HTTPError" do
      http_error = Net::HTTPBadResponse.new("Bad response")
      expect do
        handler.with_api_error_handling(context) { raise http_error }
      end.to raise_error(Net::HTTPBadResponse)
    end

    it "falls back to general error handling" do
      expect do
        handler.with_api_error_handling(context) { raise StandardError, "General API error" }
      end.to raise_error(StandardError, "General API error")
    end
  end

  describe "#handle_tool_error" do
    let(:agent) { create_test_agent(name: "TestAgent") }
    let(:handler) { described_class.new }

    it "handles ArgumentError for tool calls" do
      error = ArgumentError.new("Wrong number of arguments")
      
      expect do
        handler.handle_tool_error("test_tool", error, agent, context)
      end.to raise_error(ArgumentError, "Wrong number of arguments")
    end

    it "handles StandardError for tool calls" do
      error = StandardError.new("Tool execution failed")
      
      expect do
        handler.handle_tool_error("test_tool", error, agent, context)
      end.to raise_error(StandardError, "Tool execution failed")
    end

    it "includes tool context information" do
      error = StandardError.new("Test error")
      
      # The method should log with additional context - we'll verify it doesn't crash
      expect do
        handler.handle_tool_error("test_tool", error, agent, context)
      end.to raise_error(StandardError)
    end
  end

  describe "error type handling" do
    let(:handler) { described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::LOG_AND_CONTINUE) }

    context "ExecutionStoppedError handling" do
      it "always handles gracefully regardless of strategy" do
        # Test with different strategies - ExecutionStoppedError should always be handled
        [
          RAAF::Execution::ErrorHandler::RecoveryStrategy::FAIL_FAST,
          RAAF::Execution::ErrorHandler::RecoveryStrategy::LOG_AND_CONTINUE,
          RAAF::Execution::ErrorHandler::RecoveryStrategy::GRACEFUL_DEGRADATION,
          RAAF::Execution::ErrorHandler::RecoveryStrategy::RETRY_ONCE
        ].each do |strategy|
          test_handler = described_class.new(strategy: strategy)
          
          result = test_handler.with_error_handling(context) do
            raise RAAF::ExecutionStoppedError, "Stop requested"
          end
          
          expect(result).to eq({ error: :execution_stopped, message: "Stop requested", handled: true })
        end
      end
    end

    context "JSON::ParserError handling" do
      it "re-raises JSON parsing errors" do
        expect do
          handler.with_error_handling(context) { raise JSON::ParserError, "Malformed JSON" }
        end.to raise_error(JSON::ParserError, "Malformed JSON")
      end
    end
  end

  describe "retry count management" do
    let(:handler) { described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::RETRY_ONCE) }

    it "resets retry count after successful execution" do
      # First, increment retry count by causing an error
      begin
        handler.with_error_handling(context) { raise StandardError, "Test" }
      rescue StandardError
        # Expected
      end

      expect(handler.instance_variable_get(:@retry_count)).to eq(1)

      # Then execute successfully - should reset count
      result = handler.with_error_handling(context) { "success" }
      expect(result).to eq("success")
      expect(handler.instance_variable_get(:@retry_count)).to eq(0)
    end
  end

  describe "strategy-specific behaviors" do
    context "LOG_AND_CONTINUE vs other strategies" do
      it "LOG_AND_CONTINUE handles general errors gracefully" do
        log_handler = described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::LOG_AND_CONTINUE)
        result = log_handler.with_error_handling(context) { raise StandardError, "Test error" }
        expect(result).to eq({ error: :general_error, message: "Test error", handled: true })
      end

      it "FAIL_FAST re-raises general errors" do
        fail_handler = described_class.new(strategy: RAAF::Execution::ErrorHandler::RecoveryStrategy::FAIL_FAST)
        expect do
          fail_handler.with_error_handling(context) { raise StandardError, "Test error" }
        end.to raise_error(StandardError, "Test error")
      end
    end
  end
end