# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/tool_use_tracker"

RSpec.describe RAAF::ToolUseTracker do
  let(:tracker) { described_class.new }
  let(:agent) { double("Agent", name: "TestAgent") }

  describe "#initialize" do
    it "initializes with empty agent tracking" do
      expect(tracker.total_tool_usage_count).to eq(0)
      expect(tracker.agents_with_tool_usage).to eq([])
      expect(tracker.usage_summary).to eq({})
    end
  end

  describe "#add_tool_use" do
    it "tracks tool usage for agents" do
      expect(tracker.used_tools?(agent)).to be(false)

      tracker.add_tool_use(agent, %w[get_weather send_email])

      expect(tracker.used_tools?(agent)).to be(true)
      expect(tracker.tools_used_by(agent)).to eq(%w[get_weather send_email])
      expect(tracker.total_tool_usage_count).to eq(2)
    end

    it "handles duplicate tool names" do
      tracker.add_tool_use(agent, ["get_weather"])
      tracker.add_tool_use(agent, %w[get_weather send_email])

      expect(tracker.tools_used_by(agent)).to eq(%w[get_weather send_email])
      expect(tracker.total_tool_usage_count).to eq(2)
    end

    it "preserves order of first occurrence when removing duplicates" do
      tracker.add_tool_use(agent, %w[tool_a tool_b tool_c])
      tracker.add_tool_use(agent, %w[tool_b tool_d tool_a])

      expect(tracker.tools_used_by(agent)).to eq(%w[tool_a tool_b tool_c tool_d])
    end

    it "handles empty tool lists" do
      tracker.add_tool_use(agent, [])
      
      expect(tracker.used_tools?(agent)).to be(false)
      expect(tracker.tools_used_by(agent)).to eq([])
    end

    it "handles string and symbol tool names" do
      tracker.add_tool_use(agent, ["string_tool", :symbol_tool])
      
      expect(tracker.tools_used_by(agent)).to eq(["string_tool", :symbol_tool])
      expect(tracker.total_tool_usage_count).to eq(2)
    end

    it "tracks multiple agents independently" do
      agent1 = double("Agent1", name: "Agent1")
      agent2 = double("Agent2", name: "Agent2")

      tracker.add_tool_use(agent1, ["tool_a"])
      tracker.add_tool_use(agent2, %w[tool_b tool_c])

      expect(tracker.tools_used_by(agent1)).to eq(["tool_a"])
      expect(tracker.tools_used_by(agent2)).to eq(%w[tool_b tool_c])
      expect(tracker.total_tool_usage_count).to eq(3)
    end
  end

  describe "#used_tools?" do
    it "returns false for agents with no tool usage" do
      expect(tracker.used_tools?(agent)).to be(false)
    end

    it "returns true after tools are added" do
      tracker.add_tool_use(agent, ["test_tool"])
      expect(tracker.used_tools?(agent)).to be(true)
    end

    it "returns false for unknown agents" do
      unknown_agent = double("Unknown", name: "Unknown")
      expect(tracker.used_tools?(unknown_agent)).to be(false)
    end
  end

  describe "#tools_used_by" do
    it "returns empty array for agents with no usage" do
      expect(tracker.tools_used_by(agent)).to eq([])
    end

    it "returns empty array for unknown agents" do
      unknown_agent = double("Unknown", name: "Unknown")
      expect(tracker.tools_used_by(unknown_agent)).to eq([])
    end

    it "returns tools in order of first use" do
      tracker.add_tool_use(agent, %w[first second])
      tracker.add_tool_use(agent, %w[third first])

      expect(tracker.tools_used_by(agent)).to eq(%w[first second third])
    end
  end

  describe "#agents_with_tool_usage" do
    it "returns empty array when no agents have used tools" do
      expect(tracker.agents_with_tool_usage).to eq([])
    end

    it "returns agents that have used tools" do
      agent1 = double("Agent1", name: "Agent1")
      agent2 = double("Agent2", name: "Agent2")
      agent3 = double("Agent3", name: "Agent3")

      tracker.add_tool_use(agent1, ["tool1"])
      tracker.add_tool_use(agent3, ["tool3"])

      agents = tracker.agents_with_tool_usage
      expect(agents).to include(agent1, agent3)
      expect(agents).not_to include(agent2)
    end
  end

  describe "#total_tool_usage_count" do
    it "returns 0 when no tools used" do
      expect(tracker.total_tool_usage_count).to eq(0)
    end

    it "counts unique tools per agent" do
      agent1 = double("Agent1", name: "Agent1")
      agent2 = double("Agent2", name: "Agent2")

      tracker.add_tool_use(agent1, %w[tool1 tool2])
      tracker.add_tool_use(agent2, %w[tool3 tool4 tool5])

      expect(tracker.total_tool_usage_count).to eq(5)
    end

    it "handles duplicate tools within same agent correctly" do
      tracker.add_tool_use(agent, %w[tool1 tool2 tool1])
      expect(tracker.total_tool_usage_count).to eq(2)
    end
  end

  describe "#tool_used?" do
    it "returns false when no agents have used the tool" do
      expect(tracker.tool_used?("nonexistent_tool")).to be(false)
    end

    it "returns true when any agent has used the tool" do
      agent1 = double("Agent1", name: "Agent1")
      agent2 = double("Agent2", name: "Agent2")

      tracker.add_tool_use(agent1, ["common_tool", "tool1"])
      tracker.add_tool_use(agent2, ["tool2", "tool3"])

      expect(tracker.tool_used?("common_tool")).to be(true)
      expect(tracker.tool_used?("tool2")).to be(true)
      expect(tracker.tool_used?("nonexistent")).to be(false)
    end

    it "handles string and symbol tool names" do
      tracker.add_tool_use(agent, ["string_tool", :symbol_tool])

      expect(tracker.tool_used?("string_tool")).to be(true)
      expect(tracker.tool_used?(:symbol_tool)).to be(true)
    end
  end

  describe "#clear" do
    it "removes all tracking data" do
      agent1 = double("Agent1", name: "Agent1")
      agent2 = double("Agent2", name: "Agent2")

      tracker.add_tool_use(agent1, ["tool1"])
      tracker.add_tool_use(agent2, ["tool2"])

      expect(tracker.total_tool_usage_count).to eq(2)

      tracker.clear

      expect(tracker.total_tool_usage_count).to eq(0)
      expect(tracker.agents_with_tool_usage).to eq([])
      expect(tracker.used_tools?(agent1)).to be(false)
      expect(tracker.used_tools?(agent2)).to be(false)
    end
  end

  describe "#usage_summary" do
    it "provides usage summary" do
      agent1 = double("Agent1", name: "Agent1")
      agent2 = double("Agent2", name: "Agent2")

      tracker.add_tool_use(agent1, ["tool1"])
      tracker.add_tool_use(agent2, %w[tool2 tool3])

      summary = tracker.usage_summary
      expect(summary).to eq("Agent1" => ["tool1"], "Agent2" => %w[tool2 tool3])
    end

    it "returns empty hash when no usage" do
      expect(tracker.usage_summary).to eq({})
    end

    it "uses agent names as keys" do
      agent = double("SpecialAgent", name: "007")
      tracker.add_tool_use(agent, ["secret_tool"])

      summary = tracker.usage_summary
      expect(summary).to have_key("007")
      expect(summary["007"]).to eq(["secret_tool"])
    end
  end

  describe "#to_s" do
    it "displays no usage message when empty" do
      expect(tracker.to_s).to eq("ToolUseTracker(no usage)")
    end

    it "displays agent tool usage summary" do
      agent = double("TestAgent", name: "TestAgent")
      tracker.add_tool_use(agent, %w[tool1 tool2])

      output = tracker.to_s
      expect(output).to include("ToolUseTracker")
      expect(output).to include("TestAgent")
      expect(output).to include("2") # Tool count
      expect(output).to eq("ToolUseTracker(TestAgent:2)")
    end

    it "handles multiple agents in string output" do
      agent1 = double("Agent1", name: "Agent1")
      agent2 = double("Agent2", name: "Agent2")

      tracker.add_tool_use(agent1, ["tool1"])
      tracker.add_tool_use(agent2, ["tool2"])

      output = tracker.to_s
      expect(output).to include("Agent1")
      expect(output).to include("Agent2")
      expect(output).to include("1") # Tool counts
      expect(output).to eq("ToolUseTracker(Agent1:1, Agent2:1)")
    end
  end

  describe "edge cases and error handling" do
    it "handles nil agent gracefully" do
      expect do
        tracker.add_tool_use(nil, ["tool"])
      end.not_to raise_error

      expect(tracker.used_tools?(nil)).to be(true)
      expect(tracker.tools_used_by(nil)).to eq(["tool"])
    end

    it "handles agents without name method" do
      agent_without_name = double("AgentWithoutName")
      allow(agent_without_name).to receive(:name).and_raise(NoMethodError)

      # This should still work for tracking, but may fail in usage_summary
      tracker.add_tool_use(agent_without_name, ["tool"])
      expect(tracker.used_tools?(agent_without_name)).to be(true)

      expect do
        tracker.usage_summary
      end.to raise_error(NoMethodError)
    end

    it "handles large numbers of tools efficiently" do
      large_tool_list = (1..1000).map { |i| "tool_#{i}" }
      
      expect do
        tracker.add_tool_use(agent, large_tool_list)
      end.not_to raise_error

      expect(tracker.tools_used_by(agent).size).to eq(1000)
      expect(tracker.total_tool_usage_count).to eq(1000)
    end
  end

  describe "integration scenarios" do
    it "handles complex multi-agent tool usage patterns" do
      # Create multiple agents
      research_agent = double("ResearchAgent", name: "ResearchAgent")
      writer_agent = double("WriterAgent", name: "WriterAgent")
      reviewer_agent = double("ReviewerAgent", name: "ReviewerAgent")

      # Research agent uses search tools
      tracker.add_tool_use(research_agent, %w[web_search document_search api_call])
      
      # Writer agent uses writing tools and some search tools (overlap)
      tracker.add_tool_use(writer_agent, %w[text_generator web_search spell_check])
      
      # Reviewer agent uses analysis tools
      tracker.add_tool_use(reviewer_agent, %w[grammar_check plagiarism_check])

      # Verify individual agent tracking
      expect(tracker.tools_used_by(research_agent)).to eq(%w[web_search document_search api_call])
      expect(tracker.tools_used_by(writer_agent)).to eq(%w[text_generator web_search spell_check])
      expect(tracker.tools_used_by(reviewer_agent)).to eq(%w[grammar_check plagiarism_check])

      # Verify cross-agent queries
      expect(tracker.tool_used?("web_search")).to be(true) # Used by 2 agents
      expect(tracker.tool_used?("api_call")).to be(true)   # Used by 1 agent
      expect(tracker.tool_used?("nonexistent")).to be(false)

      # Verify totals (8 unique tools across all agents)
      # research_agent: 3 tools, writer_agent: 3 tools, reviewer_agent: 2 tools = 8 total
      expect(tracker.total_tool_usage_count).to eq(8)
      expect(tracker.agents_with_tool_usage.size).to eq(3)
    end

    it "tracks tool usage evolution over time" do
      # Simulate agent learning new tools over time
      initial_tools = ["basic_tool"]
      additional_tools = %w[advanced_tool expert_tool]
      specialized_tools = ["specialized_tool"]

      # Phase 1: Basic tools
      tracker.add_tool_use(agent, initial_tools)
      expect(tracker.tools_used_by(agent)).to eq(["basic_tool"])

      # Phase 2: Add advanced tools
      tracker.add_tool_use(agent, additional_tools)
      expect(tracker.tools_used_by(agent)).to eq(%w[basic_tool advanced_tool expert_tool])

      # Phase 3: Add specialized tools
      tracker.add_tool_use(agent, specialized_tools)
      expect(tracker.tools_used_by(agent)).to eq(%w[basic_tool advanced_tool expert_tool specialized_tool])

      # Verify no duplicates even if tools are re-added
      tracker.add_tool_use(agent, ["basic_tool", "new_tool"])
      expect(tracker.tools_used_by(agent)).to eq(%w[basic_tool advanced_tool expert_tool specialized_tool new_tool])
    end
  end
end
