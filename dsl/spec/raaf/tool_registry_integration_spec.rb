# frozen_string_literal: true

require "spec_helper"
# ToolRegistry is now in raaf-core gem, loaded automatically by requiring raaf-core

RSpec.describe "RAAF::ToolRegistry Integration" do
  before do
    RAAF::ToolRegistry.clear!
  end

  describe "Basic tool registration and resolution" do
    it "registers and resolves tools correctly" do
      # Create a test tool
      test_tool = Class.new do
        def call
          { result: "test" }
        end
      end

      # Register it
      RAAF::ToolRegistry.register(:test_tool, test_tool)

      # Resolve it
      resolved = RAAF::ToolRegistry.resolve(:test_tool)
      expect(resolved).to eq(test_tool)
    end

    it "provides detailed error information when tool not found" do
      result = RAAF::ToolRegistry.resolve_with_details(:nonexistent_tool)

      expect(result[:success]).to be false
      expect(result[:identifier]).to eq(:nonexistent_tool)
      expect(result[:searched_namespaces]).to be_an(Array)
      expect(result[:suggestions]).to be_an(Array)
    end
  end

  describe "Namespace searching" do
    it "searches Ai::Tools namespace first" do
      user_tool = Class.new { def call; end }
      framework_tool = Class.new { def call; end }

      stub_const("Ai::Tools::TestSearchTool", user_tool)
      stub_const("RAAF::Tools::TestSearchTool", framework_tool)

      # Should resolve to user tool (Ai::Tools has priority)
      resolved = RAAF::ToolRegistry.resolve(:test_search)
      expect(resolved).to eq(user_tool)
    end

    it "falls back to RAAF::Tools namespace" do
      framework_tool = Class.new { def call; end }
      stub_const("RAAF::Tools::FallbackTestTool", framework_tool)

      resolved = RAAF::ToolRegistry.resolve(:fallback_test)
      expect(resolved).to eq(framework_tool)
    end
  end

  describe "Performance characteristics" do
    it "resolves tools quickly" do
      # Register some tools
      10.times do |i|
        tool = Class.new { def call; end }
        RAAF::ToolRegistry.register("perf_tool_#{i}", tool)
      end

      # Measure resolution time
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      100.times { RAAF::ToolRegistry.resolve(:perf_tool_5) }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      # Should be very fast (< 10ms for 100 resolutions)
      expect(elapsed * 1000).to be < 10
    end
  end

  describe "Thread safety" do
    it "handles concurrent registrations" do
      results = []
      threads = 10.times.map do |i|
        Thread.new do
          tool = Class.new { def call; end }
          RAAF::ToolRegistry.register("thread_tool_#{i}", tool)
          results << RAAF::ToolRegistry.resolve("thread_tool_#{i}")
        end
      end

      threads.each(&:join)
      expect(results.compact.length).to eq(10)
    end
  end
end