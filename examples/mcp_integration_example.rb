#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"
require_relative "../lib/openai_agents/mcp/tool_adapter"

# Example demonstrating Model Context Protocol (MCP) integration

unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY environment variable is required"
  puts "Please set it with: export OPENAI_API_KEY='your-api-key'"
  exit 1
end

puts "=== MCP Integration Example ==="
puts
puts "This example demonstrates how to use MCP servers with OpenAI Agents."
puts "Note: This requires an MCP server to be running."
puts

# Example 1: Basic MCP client usage
puts "1. Basic MCP client connection:"
begin
  # Create MCP client
  OpenAIAgents::MCP::MCPClient.new(transport: :stdio)

  # Connect to an MCP server (example: filesystem MCP server)
  # In real usage, you would have an actual MCP server executable
  server_path = ENV["MCP_SERVER_PATH"] || "mcp-server-filesystem"

  puts "Attempting to connect to MCP server at: #{server_path}"

  # This would connect to a real MCP server
  # client.connect("stdio://#{server_path}")

  # For demo purposes, we'll show what would happen:
  puts "Would connect to: stdio://#{server_path}"
  puts "Server capabilities would include: resources, tools, prompts"
  puts
rescue StandardError => e
  puts "Note: MCP server connection failed (expected in demo): #{e.message}"
  puts
end

# Example 2: Using MCP tools with an agent (simulated)
puts "2. MCP tool integration with agents:"

# Simulate MCP tool for demo
class SimulatedMCPTool
  def self.create_search_tool
    OpenAIAgents::FunctionTool.new(
      proc { |query:| "MCP Search Results for: #{query}" },
      name: "mcp_search",
      description: "Search using MCP server",
      parameters_schema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search query" }
        },
        required: ["query"]
      }
    )
  end

  def self.create_file_tool
    OpenAIAgents::FunctionTool.new(
      proc { |path:| "MCP File Content: #{path}" },
      name: "mcp_read_file",
      description: "Read file via MCP server",
      parameters_schema: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path" }
        },
        required: ["path"]
      }
    )
  end
end

# Create agent with simulated MCP tools
mcp_agent = OpenAIAgents::Agent.new(
  name: "MCPAgent",
  instructions: <<~INSTRUCTIONS,
    You are an agent with access to MCP server tools.
    You can search for information and read files through the MCP protocol.
    Use these tools to help answer user questions.
  INSTRUCTIONS
  model: "gpt-4o"
)

# Add simulated MCP tools
mcp_agent.add_tool(SimulatedMCPTool.create_search_tool)
mcp_agent.add_tool(SimulatedMCPTool.create_file_tool)

# Create runner
runner = OpenAIAgents::Runner.new(agent: mcp_agent)

# Test the agent
messages = [{
  role: "user",
  content: "Search for information about Ruby programming"
}]

result = runner.run(messages)
puts "Agent response: #{result[:messages].last[:content]}"
puts

# Example 3: MCP integration pattern
puts "3. Full MCP integration pattern:"
puts <<~PATTERN
  # Real-world MCP integration would look like:

  # 1. Initialize MCP integration
  mcp = OpenAIAgents::MCP::MCPIntegration.new(
    "stdio://path/to/mcp-server",
    transport: :stdio
  )

  # 2. Create agent with all MCP tools automatically
  agent = mcp.create_agent(
    name: "SmartAgent",
    instructions: "You have access to MCP tools and resources."
  )

  # 3. List available resources
  resources = mcp.resource_adapter.list_resources
  puts "Available resources: \#{resources.map(&:name)}"

  # 4. List available tools
  tools = mcp.tool_adapter.get_all_tools
  puts "Available tools: \#{tools.map(&:name)}"

  # 5. Use the agent normally
  runner = OpenAIAgents::Runner.new(agent: agent)
  result = runner.run(messages)

  # 6. Clean up
  mcp.disconnect
PATTERN
puts

# Example 4: MCP resource handling
puts "4. MCP resource handling example:"

# Simulate MCP resource adapter
class SimulatedResourceAdapter
  def self.create_resource_tool
    OpenAIAgents::FunctionTool.new(
      proc do |uri:|
        case uri
        when /\.md$/
          "# MCP Resource Content\n\nThis is markdown content from: #{uri}"
        when /\.json$/
          '{"type": "mcp_resource", "uri": "' + uri + '"}'
        else
          "Plain text content from MCP resource: #{uri}"
        end
      end,
      name: "read_mcp_resource",
      description: "Read any MCP resource by URI",
      parameters_schema: {
        type: "object",
        properties: {
          uri: { type: "string", description: "Resource URI" }
        },
        required: ["uri"]
      }
    )
  end
end

resource_agent = OpenAIAgents::Agent.new(
  name: "ResourceAgent",
  instructions: "You can read MCP resources. Use the resource reader when asked about documents.",
  model: "gpt-4o"
)

resource_agent.add_tool(SimulatedResourceAdapter.create_resource_tool)

runner2 = OpenAIAgents::Runner.new(agent: resource_agent)

messages2 = [{
  role: "user",
  content: "Read the content from resource: docs/guide.md"
}]

result2 = runner2.run(messages2)
puts "Resource content: #{result2[:messages].last[:content]}"
puts

# Example 5: MCP prompt templates
puts "5. MCP prompt template usage:"
puts <<~PROMPTS
  # MCP servers can provide prompt templates:

  # Get available prompts
  prompts = mcp.prompt_adapter.list_prompts
  # => [
  #   { name: "code_review", description: "Review code for issues" },
  #   { name: "explain_concept", description: "Explain technical concepts" }
  # ]

  # Use a prompt template
  prompt_content = mcp.prompt_adapter.get_prompt(
    "code_review",
    language: "ruby",
    focus: "security"
  )

  # Create agent from prompt
  review_agent = mcp.prompt_adapter.create_agent_from_prompt(
    "code_review",
    agent_name: "CodeReviewer",
    language: "ruby"
  )
PROMPTS

# Example 6: Advanced MCP patterns
puts "6. Advanced MCP usage patterns:"
puts <<~ADVANCED
  # Combining multiple MCP servers
  servers = [
    "stdio://mcp-filesystem",
    "stdio://mcp-github",
    "stdio://mcp-database"
  ]

  agents = servers.map do |server|
    mcp = OpenAIAgents::MCP::MCPIntegration.new(server)
    mcp.create_agent(name: "Agent_\#{server}")
  end

  # Create supervisor agent that can delegate
  supervisor = OpenAIAgents::Agent.new(
    name: "Supervisor",
    instructions: "Delegate tasks to specialized MCP agents"
  )

  agents.each { |agent| supervisor.add_handoff(agent) }

  # Dynamic tool loading based on context
  def load_contextual_tools(mcp, context)
    all_tools = mcp.tool_adapter.get_all_tools
  #{"  "}
    case context
    when :development
      all_tools.select { |t| t.name.match?(/code|git|test/) }
    when :research
      all_tools.select { |t| t.name.match?(/search|read|analyze/) }
    else
      all_tools
    end
  end
ADVANCED

puts "\n=== Example Complete ==="
puts
puts "Note: This example uses simulated MCP components for demonstration."
puts "In production, you would connect to actual MCP servers that provide"
puts "real tools, resources, and prompts through the MCP protocol."
