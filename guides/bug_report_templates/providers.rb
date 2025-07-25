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

RSpec.describe "RAAF Providers Bug Report" do
  it "tests OpenAI provider configuration" do
    # Test OpenAI provider configuration
    provider = RAAF::Models::ResponsesProvider.new(
      api_key: "test-key",
      timeout: 30
    )
    
    agent = RAAF::Agent.new(
      name: "TestAgent",
      instructions: "You are a test agent",
      model: "gpt-4o-mini"
    )
    
    runner = RAAF::Runner.new(agent: agent, provider: provider)
    
    # Add expectations for your specific provider bug
    expect(provider).to be_a(RAAF::Models::ResponsesProvider)
  end

  it "tests Anthropic provider configuration" do
    provider = RAAF::Models::AnthropicProvider.new(
      api_key: "test-key",
      timeout: 30
    )
    
    agent = RAAF::Agent.new(
      name: "TestAgent",
      instructions: "You are a test agent",
      model: "claude-3-5-sonnet-20241022"
    )
    
    runner = RAAF::Runner.new(agent: agent, provider: provider)
    
    # Add expectations for your specific provider bug
    expect(provider).to be_a(RAAF::Models::AnthropicProvider)
  end

  it "tests provider failover logic" do
    primary_provider = RAAF::Models::ResponsesProvider.new(api_key: "test-key")
    fallback_provider = RAAF::Models::AnthropicProvider.new(api_key: "test-key")
    
    # Test provider failover logic
    agent = RAAF::Agent.new(
      name: "TestAgent",
      instructions: "You are a test agent",
      model: "gpt-4o-mini"
    )
    
    # Add your specific test case for provider failover
    expect(primary_provider).to be_a(RAAF::Models::ResponsesProvider)
  end

  # Add your specific test case here that demonstrates the bug
  it "reproduces your specific provider bug case" do
    # Replace this with your specific test case that demonstrates the provider bug
    expect(true).to be true # Replace this with your actual test case
  end
end