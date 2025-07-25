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

RSpec.describe "RAAF Generic Bug Report" do
  it "provides basic RAAF functionality" do
    agent = RAAF::Agent.new(
      name: "TestAgent",
      instructions: "You are a test agent",
      model: "gpt-4o-mini"
    )
    
    expect(agent.name).to eq("TestAgent")
    expect(agent.model).to eq("gpt-4o-mini")
  end

  it "creates a runner" do
    agent = RAAF::Agent.new(
      name: "TestAgent",
      instructions: "You are a test agent",
      model: "gpt-4o-mini"
    )
    
    runner = RAAF::Runner.new(agent: agent)
    
    expect(runner).to be_a(RAAF::Runner)
    expect(runner.agent).to be_a(RAAF::Agent)
  end

  # Add your specific test case here that demonstrates the bug
  it "reproduces your specific bug case" do
    # Replace this with your specific test case that demonstrates the bug
    # Include relevant setup, the action that causes the bug, and expectations
    expect(true).to be true # Replace this with your actual test case
  end
end
