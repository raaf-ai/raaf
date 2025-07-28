#!/usr/bin/env ruby
# frozen_string_literal: true

##
# API Integration Example
#
# This example demonstrates how to use the RAAF Rails REST API
# for agent management and conversations.
#

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "rails", "~> 7.0"
  gem "raaf-rails", path: ".."
  gem "raaf-core", path: "../../core"
  gem "httparty"
  gem "colorize"
end

require "rails"
require "action_controller/railtie"
require "raaf-rails"
require "httparty"
require "colorize"

##
# API Client for RAAF Rails
#
class RAAFAPIClient
  include HTTParty

  base_uri "http://localhost:3000/api/v1"

  def initialize(api_key = nil)
    @options = {
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }
    }
    @options[:headers]["Authorization"] = "Bearer #{api_key}" if api_key
  end

  # Agent management

  def list_agents
    self.class.get("/agents", @options)
  end

  def create_agent(params)
    self.class.post("/agents", @options.merge(body: params.to_json))
  end

  def get_agent(id)
    self.class.get("/agents/#{id}", @options)
  end

  def update_agent(id, params)
    self.class.put("/agents/#{id}", @options.merge(body: params.to_json))
  end

  def delete_agent(id)
    self.class.delete("/agents/#{id}", @options)
  end

  def deploy_agent(id)
    self.class.post("/agents/#{id}/deploy", @options)
  end

  def undeploy_agent(id)
    self.class.delete("/agents/#{id}/undeploy", @options)
  end

  # Conversations

  def start_conversation(agent_id, message, context = {})
    params = { message: message, context: context }
    self.class.post("/agents/#{agent_id}/conversations", @options.merge(body: params.to_json))
  end

  def get_conversation(id)
    self.class.get("/conversations/#{id}", @options)
  end

  def continue_conversation(id, message)
    params = { message: message }
    self.class.post("/conversations/#{id}/messages", @options.merge(body: params.to_json))
  end

  # Analytics

  def agent_analytics(agent_id, period = "7d")
    self.class.get("/agents/#{agent_id}/analytics?period=#{period}", @options)
  end

  def global_analytics(period = "30d")
    self.class.get("/analytics?period=#{period}", @options)
  end
end

##
# Demo script
#
def demo_api_integration
  client = RAAFAPIClient.new(ENV.fetch("RAAF_API_KEY", nil))

  puts "RAAF Rails API Integration Demo".colorize(:blue)
  puts "=" * 50

  # Create an agent
  puts "\n1. Creating a new agent...".colorize(:green)
  agent_response = client.create_agent({
                                         name: "API Demo Agent",
                                         instructions: "You are a helpful assistant created via the API",
                                         model: "gpt-4o",
                                         tools: ["web_search"],
                                         metadata: {
                                           created_by: "api_demo",
                                           purpose: "demonstration"
                                         }
                                       })

  if agent_response.success?
    agent = agent_response.parsed_response
    puts "✓ Agent created: #{agent['name']} (ID: #{agent['id']})".colorize(:green)
  else
    puts "✗ Failed to create agent: #{agent_response.body}".colorize(:red)
    return
  end

  agent_id = agent["id"]

  # Deploy the agent
  puts "\n2. Deploying the agent...".colorize(:green)
  deploy_response = client.deploy_agent(agent_id)

  if deploy_response.success?
    puts "✓ Agent deployed successfully".colorize(:green)
  else
    puts "✗ Failed to deploy agent: #{deploy_response.body}".colorize(:red)
  end

  # Start a conversation
  puts "\n3. Starting a conversation...".colorize(:green)
  conversation_response = client.start_conversation(
    agent_id,
    "Hello! Can you help me understand the RAAF Rails API?",
    { user_id: "demo_user", session_id: "demo_session" }
  )

  if conversation_response.success?
    conversation = conversation_response.parsed_response
    puts "✓ Agent response: #{conversation['message']}".colorize(:cyan)
    puts "  Tokens used: #{conversation['usage']['total_tokens']}".colorize(:gray)
  else
    puts "✗ Failed to start conversation: #{conversation_response.body}".colorize(:red)
  end

  # Get analytics
  puts "\n4. Fetching agent analytics...".colorize(:green)
  analytics_response = client.agent_analytics(agent_id, "1d")

  if analytics_response.success?
    analytics = analytics_response.parsed_response
    puts "✓ Analytics:".colorize(:green)
    puts "  - Conversations: #{analytics['conversations_count']}".colorize(:gray)
    puts "  - Messages: #{analytics['messages_count']}".colorize(:gray)
    puts "  - Total tokens: #{analytics['total_tokens']}".colorize(:gray)
    puts "  - Avg response time: #{analytics['average_response_time']}s".colorize(:gray)
  else
    puts "✗ Failed to get analytics: #{analytics_response.body}".colorize(:red)
  end

  # List all agents
  puts "\n5. Listing all agents...".colorize(:green)
  list_response = client.list_agents

  if list_response.success?
    agents = list_response.parsed_response["agents"]
    puts "✓ Found #{agents.length} agents:".colorize(:green)
    agents.each do |agent|
      puts "  - #{agent['name']} (#{agent['status']})".colorize(:gray)
    end
  else
    puts "✗ Failed to list agents: #{list_response.body}".colorize(:red)
  end

  # Clean up
  puts "\n6. Cleaning up...".colorize(:green)
  client.undeploy_agent(agent_id)
  client.delete_agent(agent_id)
  puts "✓ Agent deleted".colorize(:green)
rescue StandardError => e
  puts "\n✗ Error: #{e.message}".colorize(:red)
  puts e.backtrace.first(5).join("\n").colorize(:gray)
end

# Example server setup
def start_api_server
  require "rack/handler/webrick"

  # Minimal Rails app with API
  api_app_class = Class.new(Rails::Application) do
    config.root = __dir__
    config.eager_load = false
    config.api_only = true
    config.secret_key_base = "secret"

    config.after_initialize do
      RAAF::Rails.configure do |config|
        config[:authentication_method] = :none
        config[:enable_api] = true
        config[:rate_limit] = { enabled: true, requests_per_minute: 100 }
      end
    end
  end

  stub_const("APIExampleApp", api_app_class)
  Rails.application.initialize!

  Rails.application.routes.draw do
    mount RAAF::Rails::Engine, at: "/"
  end

  puts "Starting API server on http://localhost:3000".colorize(:blue)
  puts "API endpoint: http://localhost:3000/api/v1".colorize(:blue)
  puts

  Thread.new do
    Rack::Handler::WEBrick.run Rails.application, Port: 3000, AccessLog: []
  end

  sleep 2 # Wait for server to start
end

# Run the demo
if __FILE__ == $PROGRAM_NAME
  puts "=" * 60
  puts "RAAF Rails API Integration Example".colorize(:blue)
  puts "=" * 60
  puts

  # Start server in background
  start_api_server

  # Run API demo
  demo_api_integration

  puts "\n" + ("=" * 60)
  puts "Demo completed!".colorize(:green)
  puts "=" * 60
end
