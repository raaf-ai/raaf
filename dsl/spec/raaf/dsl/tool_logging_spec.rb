# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Tool Execution Logging", type: :feature do
  # Test tools
  class TestTool
    def tool_name
      "test_tool"
    end

    def description
      "A test tool for logging verification"
    end

    def call(message:)
      { success: true, message: "Processed: #{message}" }
    end
  end

  class ErrorTool
    def tool_name
      "error_tool"
    end

    def description
      "A tool that raises errors"
    end

    def call(input:)
      raise StandardError, "Intentional test error: #{input}"
    end
  end

  class LongArgsTool
    def tool_name
      "long_args_tool"
    end

    def description
      "A tool with long arguments for truncation testing"
    end

    def call(long_text:, short_text:)
      { success: true, processed: "#{long_text[0..10]}... and #{short_text}" }
    end
  end

  # Base test agent to avoid provider issues
  class BaseTestAgent < RAAF::DSL::Agent
    def build_instructions
      "Test agent for logging"
    end

    def build_schema
      { type: "object", properties: { message: { type: "string" } }, required: ["message"], additionalProperties: false }
    end
  end

  describe "log_tool_start" do
    it "logs tool execution start with tool name" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "LogTestAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
          log_arguments false
        end
      end

      tool_instance = TestTool.new
      agent = agent_class.new

      # Mock RAAF.logger to capture log output
      allow(RAAF.logger).to receive(:debug)

      # Call the logging method directly
      agent.send(:log_tool_start, tool_instance, { message: "test" })

      expect(RAAF.logger).to have_received(:debug)
        .with(include("[TOOL EXECUTION] Starting test_tool"))
    end

    it "logs tool arguments when log_arguments is enabled" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "LogArgsAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
          log_arguments true
        end
      end

      tool_instance = TestTool.new
      agent = agent_class.new

      allow(RAAF.logger).to receive(:debug)

      agent.send(:log_tool_start, tool_instance, { message: "test input" })

      expect(RAAF.logger).to have_received(:debug)
        .with(include("[TOOL EXECUTION] Starting test_tool"))
      expect(RAAF.logger).to have_received(:debug)
        .with(include("[TOOL EXECUTION] Arguments:"))
    end

    it "does not log arguments when log_arguments is disabled" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "NoArgsAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
          log_arguments false
        end
      end

      tool_instance = TestTool.new
      agent = agent_class.new

      allow(RAAF.logger).to receive(:debug)

      agent.send(:log_tool_start, tool_instance, { message: "test" })

      expect(RAAF.logger).to have_received(:debug)
        .with(include("[TOOL EXECUTION] Starting test_tool"))
        .once
    end

    it "truncates long arguments according to configuration" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "TruncateAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
          log_arguments true
          truncate_logs 20
        end
      end

      tool_instance = LongArgsTool.new
      agent = agent_class.new

      allow(RAAF.logger).to receive(:debug)

      long_text = "A" * 100
      agent.send(:log_tool_start, tool_instance, { long_text: long_text, short_text: "short" })

      expect(RAAF.logger).to have_received(:debug).with(
        include("[TOOL EXECUTION] Arguments:")
      )

      # Verify truncation happened (should not log full 100 character string)
      expect(RAAF.logger).not_to have_received(:debug).with(
        include("A" * 50)
      )
    end
  end

  describe "log_tool_end" do
    it "logs successful tool completion with duration" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "CompletionAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
        end
      end

      tool_instance = TestTool.new
      agent = agent_class.new
      result = { success: true, data: "result" }

      allow(RAAF.logger).to receive(:debug)

      agent.send(:log_tool_end, tool_instance, result, 42.5)

      expect(RAAF.logger).to have_received(:debug)
        .with(include("[TOOL EXECUTION] Completed test_tool (42.5ms)"))
    end

    it "logs failed tool execution with error message" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "FailureAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
        end
      end

      tool_instance = TestTool.new
      agent = agent_class.new
      result = { success: false, error: "Something went wrong" }

      allow(RAAF.logger).to receive(:debug)

      agent.send(:log_tool_end, tool_instance, result, 15.3)

      expect(RAAF.logger).to have_received(:debug)
        .with(include("[TOOL EXECUTION] Failed test_tool (15.3ms): Something went wrong"))
    end

    it "formats duration to 2 decimal places" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "DurationAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
        end
      end

      tool_instance = TestTool.new
      agent = agent_class.new
      result = { success: true }

      allow(RAAF.logger).to receive(:debug)

      agent.send(:log_tool_end, tool_instance, result, 123.456789)

      expect(RAAF.logger).to have_received(:debug)
        .with(include("123.46ms"))
    end
  end

  describe "log_tool_error" do
    it "logs error message with tool name" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "ErrorLogAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
        end
      end

      tool_instance = ErrorTool.new
      agent = agent_class.new
      error = StandardError.new("Test error occurred")

      allow(RAAF.logger).to receive(:error)

      agent.send(:log_tool_error, tool_instance, error)

      expect(RAAF.logger).to have_received(:error)
        .with(include("[TOOL EXECUTION] Error in error_tool: Test error occurred"))
    end

    it "logs stack trace (first 5 lines)" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "StackTraceAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
        end
      end

      tool_instance = ErrorTool.new
      agent = agent_class.new

      begin
        raise StandardError, "Test error with trace"
      rescue StandardError => e
        allow(RAAF.logger).to receive(:error)
        agent.send(:log_tool_error, tool_instance, e)

        expect(RAAF.logger).to have_received(:error)
          .with(include("[TOOL EXECUTION] Stack trace:"))
      end
    end
  end

  describe "format_arguments" do
    it "formats arguments as key-value pairs" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "FormatAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
          log_arguments true
          truncate_logs 100
        end
      end

      agent = agent_class.new

      formatted = agent.send(:format_arguments, { name: "John", age: 30 })

      expect(formatted).to include("name: John")
      expect(formatted).to include("age: 30")
    end

    it "truncates long values according to configuration" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "TruncAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
          log_arguments true
          truncate_logs 20
        end
      end

      agent = agent_class.new
      long_value = "A" * 100

      formatted = agent.send(:format_arguments, { data: long_value })

      expect(formatted.length).to be < 100
      expect(formatted).to include("...")
    end

    it "handles multiple arguments with truncation" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "MultiArgAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
          log_arguments true
          truncate_logs 15
        end
      end

      agent = agent_class.new

      formatted = agent.send(:format_arguments, {
        short: "abc",
        long: "X" * 50
      })

      expect(formatted).to include("short: abc")
      expect(formatted).to include("long:")
      expect(formatted).not_to include("X" * 30)
    end
  end

  describe "Integration with execute_tool" do
    it "logs complete execution cycle for successful tool" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "IntegrationAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
          log_arguments true
        end

        def self.tools_config
          []
        end
      end

      tool_instance = TestTool.new
      function_tool = RAAF::FunctionTool.new(
        tool_instance.method(:call),
        name: "test_tool",
        description: tool_instance.description
      )

      agent = agent_class.new
      allow(agent).to receive(:tools).and_return([function_tool])

      allow(RAAF.logger).to receive(:debug)
      allow(RAAF.logger).to receive(:error)

      result = agent.execute_tool("test_tool", message: "integration test")

      # Verify logging occurred
      expect(RAAF.logger).to have_received(:debug)
        .with(include("[TOOL EXECUTION] Starting test_tool"))
      expect(RAAF.logger).to have_received(:debug)
        .with(include("[TOOL EXECUTION] Completed test_tool"))
    end

    it "logs error execution cycle for failing tool" do
      agent_class = Class.new(BaseTestAgent) do
        agent_name "ErrorIntegrationAgent"
        model "gpt-4o"

        tool_execution do
          enable_logging true
        end

        def self.tools_config
          []
        end
      end

      tool_instance = ErrorTool.new
      function_tool = RAAF::FunctionTool.new(
        tool_instance.method(:call),
        name: "error_tool",
        description: tool_instance.description
      )

      agent = agent_class.new
      allow(agent).to receive(:tools).and_return([function_tool])

      allow(RAAF.logger).to receive(:debug)
      allow(RAAF.logger).to receive(:error)

      expect {
        agent.execute_tool("error_tool", input: "fail")
      }.to raise_error(RAAF::ToolError)

      expect(RAAF.logger).to have_received(:error)
        .with(include("[TOOL EXECUTION] Error in error_tool"))
    end
  end
end
