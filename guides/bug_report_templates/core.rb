# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  gem "raaf"
  gem "rspec"
  # If you want to test against edge RAAF replace the raaf line with this:
  # gem "raaf", github: "enterprisemodules/raaf", branch: "main"
end

require "raaf"
require "rspec/autorun"

RSpec.describe "RAAF Core Bug Report" do
  it "creates an agent with basic properties" do
    agent = RAAF::Agent.new(
      name: "TestAgent",
      instructions: "You are a helpful test agent",
      model: "gpt-4o-mini"
    )
    
    expect(agent.name).to eq("TestAgent")
    expect(agent.model).to eq("gpt-4o-mini")
    expect(agent.instructions).to include("helpful test agent")
  end

  it "executes runner with agent" do
    agent = RAAF::Agent.new(
      name: "TestAgent",
      instructions: "You are a helpful test agent. Always respond with 'Hello, World!'",
      model: "gpt-4o-mini"
    )
    
    runner = RAAF::Runner.new(agent: agent)
    
    # This test requires actual API access
    # Replace with your specific test case that demonstrates the bug
    result = runner.run("Say hello")
    
    expect(result.messages).not_to be_empty
    expect(result.messages).to be_a(Array)
  end

  it "integrates tools with agents" do
    # Define a simple tool for testing
    def get_current_time
      Time.now.strftime("%Y-%m-%d %H:%M:%S")
    end

    agent = RAAF::Agent.new(
      name: "TestAgent",
      instructions: "You can get the current time using the provided tool",
      model: "gpt-4o-mini"
    )
    
    agent.add_tool(method(:get_current_time))
    
    # Verify tool was added
    expect(agent.tools).to have_key(:get_current_time)
  end

  # Add your specific test case here that demonstrates the bug
  it "reproduces your specific bug case" do
    # Replace this with your specific test case that demonstrates the core bug
    # Include relevant setup, the action that causes the bug, and expectations
    expect(true).to be true # Replace this with your actual test case
  end
end