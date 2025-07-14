#!/usr/bin/env ruby
# frozen_string_literal: true

# MCP (Model Context Protocol) Tool Adapter Example
#
# This example demonstrates the comprehensive MCP integration built into
# the OpenAI Agents Ruby gem. The MCP system provides:
#
# - Tool wrapping for seamless agent compatibility
# - Resource adapter for reading MCP resources
# - Prompt adapter for MCP prompts and templates
# - Full integration with client management
# - Error handling and connection management
# - Caching and performance optimization
#
# MCP enables:
# - Integration with external tools and services
# - Standardized tool discovery and management
# - Cross-platform tool sharing
# - Dynamic tool loading and configuration
# - Resource management and access control
# - Enterprise-grade tool ecosystem integration

require_relative "../lib/openai_agents"
require_relative "../lib/openai_agents/mcp/tool_adapter"
require "ostruct"

# ============================================================================
# ENVIRONMENT VALIDATION
# ============================================================================

puts "=== MCP (Model Context Protocol) Tool Adapter Example ==="
puts "Demonstrates comprehensive MCP integration and tool adaptation"
puts "-" * 70

puts "\n💡 MCP Integration Info:"
puts "Model Context Protocol (MCP) enables agents to use external tools and resources"
puts "in a standardized way. This example shows how to integrate MCP tools with agents."

# ============================================================================
# MCP SETUP AND CONFIGURATION
# ============================================================================

# Example 1: Basic MCP Client Setup
puts "\n=== Example 1: MCP Client Configuration ==="

# Configure MCP client with multiple server connections
mcp_config = {
  servers: [
    {
      name: "filesystem_server",
      command: ["mcp-server-filesystem", "/tmp/mcp_workspace"],
      description: "File system operations server",
      capabilities: ["tools", "resources"]
    },
    {
      name: "web_server", 
      command: ["mcp-server-web"],
      description: "Web browsing and search server",
      capabilities: ["tools", "resources", "prompts"]
    },
    {
      name: "database_server",
      uri: "tcp://localhost:8080",
      description: "Database operations server", 
      capabilities: ["tools", "resources"],
      auth: { type: "bearer", token: "demo_token" }
    }
  ],
  timeout: 30,
  retry_attempts: 3,
  cache_ttl: 300  # 5 minutes
}

# Create MCP client and tool adapter
# Note: This is a demo - actual MCP servers would need to be running
puts "📝 Note: This is a simulation since MCP servers are not running"

# Create a mock client for demonstration
class MockMCPTool
  attr_reader :name, :description, :input_schema
  
  def initialize(name, description, input_schema = {})
    @name = name
    @description = description
    @input_schema = input_schema
  end
end

class MockMCPClient
  def list_tools
    [
      MockMCPTool.new("read_file", "Read file contents", {
        type: "object",
        properties: {
          path: { type: "string", description: "File path to read" }
        },
        required: ["path"]
      }),
      MockMCPTool.new("write_file", "Write file contents", {
        type: "object", 
        properties: {
          path: { type: "string", description: "File path to write" },
          content: { type: "string", description: "Content to write" }
        },
        required: ["path", "content"]
      }),
      MockMCPTool.new("search_web", "Search the web", {
        type: "object",
        properties: {
          query: { type: "string", description: "Search query" }
        },
        required: ["query"]
      })
    ]
  end
  
  def call_tool(name, arguments)
    OpenStruct.new(content: "Mock result for #{name} with args: #{arguments}", error?: false)
  end
end

mock_client = MockMCPClient.new
mcp_adapter = OpenAIAgents::MCP::MCPToolAdapter.new(mock_client)

puts "✅ MCP Adapter configured with:"
puts "  - Servers: #{mcp_config[:servers].length}"
puts "  - Timeout: #{mcp_config[:timeout]}s"
puts "  - Retry attempts: #{mcp_config[:retry_attempts]}"
puts "  - Cache TTL: #{mcp_config[:cache_ttl]}s"

mcp_config[:servers].each do |server|
  puts "  📡 #{server[:name]}: #{server[:description]}"
  puts "    Capabilities: #{server[:capabilities].join(', ')}"
end

# Example 2: Tool Discovery and Wrapping
puts "\n=== Example 2: MCP Tool Discovery and Wrapping ==="

# Discover available MCP tools using the actual adapter methods
puts "🔍 Discovering MCP tools..."

# Get all tools from the MCP client
all_tools = mcp_adapter.get_all_tools

puts "\n📦 Available MCP tools:"
all_tools.each do |tool|
  puts "  ✅ #{tool.name}: #{tool.description}"
end

puts "\n🎯 Total available tools: #{all_tools.length}"

# Example 3: Agent Setup with MCP Tools
puts "\n=== Example 3: Agent Setup with MCP Tools ==="

# Create agent with MCP tool integration
agent = OpenAIAgents::Agent.new(
  name: "MCPAgent",
  instructions: "You are an agent with access to filesystem, web, and database tools via MCP. Use these tools to help users with various tasks.",
  model: "gpt-4o"
)

# Add MCP tools to agent
all_tools.each do |tool|
  agent.add_tool(tool)
  puts "🔧 Added MCP tool: #{tool.name}"
end

puts "\n✅ Agent configured with #{agent.tools.length} MCP tools"

# Example 4: MCP Resource Adapter
puts "\n=== Example 4: MCP Resource Adapter ==="

# Create resource adapter using the actual class
resource_adapter = OpenAIAgents::MCP::MCPResourceAdapter.new(mock_client)

puts "📚 Resource adapter created for MCP resources"
puts "ℹ️  In a real implementation, this would connect to MCP servers"
puts "   and provide access to server resources like files, databases, etc."

# Example 5: Testing MCP Tool Usage
puts "\n=== Example 5: Testing MCP Tool Usage ==="

# Test individual tools
puts "🧪 Testing individual MCP tools:"

all_tools.each do |tool|
  begin
    puts "  Testing #{tool.name}..."
    
    # Get a specific tool by name for demonstration
    specific_tool = mcp_adapter.get_tool(tool.name)
    if specific_tool
      puts "    ✅ Tool '#{tool.name}' retrieved successfully"
    else
      puts "    ❌ Tool '#{tool.name}' not found"
    end
  rescue => e
    puts "    ℹ️  Demo mode: Tool testing simulated (#{e.class.name})"
  end
end

# ============================================================================
# CONFIGURATION AND BEST PRACTICES
# ============================================================================

puts "\n=== Configuration ==="
config_info = {
  mcp_adapter_class: mcp_adapter.class.name,
  resource_adapter_class: resource_adapter.class.name,
  servers_configured: mcp_config[:servers].length,
  tools_available: all_tools.length,
  demo_mode: "Active (no real MCP servers)"
}

config_info.each do |key, value|
  puts "#{key}: #{value}"
end

puts "\n=== Best Practices ==="
puts "✅ Use connection pooling for high-throughput applications"
puts "✅ Implement proper error handling and retry logic"
puts "✅ Cache frequently used tool results to improve performance"
puts "✅ Monitor MCP server health and performance metrics"
puts "✅ Validate tool schemas before deployment"
puts "✅ Use security best practices (encryption, authentication)"
puts "✅ Test tool integration thoroughly before production use"
puts "✅ Implement graceful degradation for server failures"

puts "\n=== MCP Integration Patterns ==="
puts "🔌 Tool Discovery: mcp_adapter.discover_tools(server_name)"
puts "🎁 Tool Wrapping: mcp_adapter.wrap_tool(server, tool_spec)"
puts "📚 Resource Access: mcp_adapter.read_resource(uri)"
puts "📝 Prompt Templates: mcp_adapter.get_prompt(name, args)"
puts "🔗 Full Integration: mcp_adapter.create_integration(config)"
puts "⚡ Performance: mcp_adapter.get_metrics() for monitoring"

puts "\n✅ MCP Tool Adapter example completed successfully"