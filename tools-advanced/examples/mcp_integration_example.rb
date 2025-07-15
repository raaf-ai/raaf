#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates comprehensive Model Context Protocol (MCP) integration with OpenAI Agents Ruby.
# MCP is an open protocol that enables seamless integration between AI applications and external 
# data sources/tools. It provides a standardized way for AI agents to interact with databases, 
# APIs, file systems, and other services through a unified interface. This is crucial for 
# building production AI systems that need to access real-world data and perform actions 
# beyond text generation.

require_relative "../lib/openai_agents"

puts "=== Model Context Protocol (MCP) Integration Example ==="
puts

# Check for API key
unless ENV["OPENAI_API_KEY"]
  puts "❌ Error: OPENAI_API_KEY environment variable is required"
  puts "Please set your OpenAI API key:"
  puts "export OPENAI_API_KEY='your-api-key-here'"
  exit 1
end

# ============================================================================
# EXAMPLE 1: MCP CLIENT SETUP AND CONNECTION
# ============================================================================
# Demonstrates how to connect to an MCP server and explore its capabilities.
# MCP servers can run as separate processes, HTTP services, or embedded libraries.

puts "Example 1: MCP Client Setup and Connection"
puts "-" * 50

# Create MCP client with configuration
# The client handles protocol negotiation and capability discovery
mcp_client = OpenAIAgents::MCP::MCPClient.new(
  transport: :stdio,  # Communication method: :stdio, :sse, or :websocket
  timeout: 30         # Connection timeout in seconds
)

puts "MCP Client created with stdio transport"
puts "Transport: #{mcp_client.instance_variable_get(:@transport)}"
puts "Timeout: #{mcp_client.instance_variable_get(:@timeout)}s"
puts

# MCP server configuration examples
# Different server types provide different capabilities
mcp_servers = {
  filesystem: {
    description: "Local file system access with sandboxing",
    command: "mcp-server-filesystem",
    capabilities: ["read files", "list directories", "file search"]
  },
  
  github: {
    description: "GitHub repository interaction",
    command: "mcp-server-github",
    capabilities: ["search repositories", "read files", "create issues"]
  },
  
  postgres: {
    description: "PostgreSQL database operations",
    command: "mcp-server-postgres",
    capabilities: ["execute queries", "schema inspection", "data analysis"]
  },
  
  slack: {
    description: "Slack workspace integration",
    command: "mcp-server-slack",
    capabilities: ["read messages", "send messages", "channel management"]
  }
}

puts "Common MCP server types:"
mcp_servers.each do |type, config|
  puts "  #{type.to_s.capitalize}:"
  puts "    Description: #{config[:description]}"
  puts "    Command: #{config[:command]}"
  puts "    Capabilities: #{config[:capabilities].join(', ')}"
  puts
end

# Simulated connection for demonstration
# In production, you would connect to a real MCP server
puts "Simulating MCP server connection..."
puts "Note: This example simulates MCP functionality since no actual server is configured"
puts "In production, you would use: mcp_client.connect('stdio://path/to/mcp-server')"
puts

# ============================================================================
# EXAMPLE 2: MCP TOOL INTEGRATION WITH AGENTS
# ============================================================================
# Shows how MCP tools become agent capabilities through the MCPTool wrapper.
# Tools are automatically converted to OpenAI function calling format.

puts "Example 2: MCP Tool Integration with Agents"
puts "-" * 50

# Create MCP tool that wraps server functionality
# The MCPTool class handles protocol communication and tool discovery
begin
  # This would connect to a real MCP server in production
  # For demo purposes, we'll show the configuration pattern
  puts "Creating MCP tool configuration..."
  
  # MCP tool configuration
  mcp_tool_config = {
    server_name: "filesystem",
    server_config: {
      type: "stdio",
      command: "mcp-server-filesystem",
      args: ["--root", "/tmp/mcp-demo"],
      timeout: 30
    }
  }
  
  puts "MCP Tool Configuration:"
  puts "  Server: #{mcp_tool_config[:server_name]}"
  puts "  Type: #{mcp_tool_config[:server_config][:type]}"
  puts "  Command: #{mcp_tool_config[:server_config][:command]}"
  puts "  Root Directory: #{mcp_tool_config[:server_config][:args]&.join(' ')}"
  puts

  # Create simulated MCP tool for demonstration
  # In production, this would use OpenAIAgents::Tools::MCPTool
  class SimulatedMCPTool
    def self.create_filesystem_tool
      OpenAIAgents::FunctionTool.new(
        proc do |operation:, path: "", content: nil|
          case operation
          when "read"
            "File content from MCP server: #{path}"
          when "list"
            "Directory listing from MCP server: #{path}"
          when "write"
            "File written to MCP server: #{path}"
          when "search"
            "Search results from MCP server: #{path}"
          else
            "Unknown operation: #{operation}"
          end
        end,
        name: "mcp_filesystem",
        description: "Access filesystem through MCP server",
        parameters: {
          type: "object",
          properties: {
            operation: {
              type: "string",
              enum: ["read", "list", "write", "search"],
              description: "File operation to perform"
            },
            path: {
              type: "string",
              description: "File or directory path"
            },
            content: {
              type: "string",
              description: "Content to write (for write operation)"
            }
          },
          required: ["operation", "path"]
        }
      )
    end
    
    def self.create_database_tool
      OpenAIAgents::FunctionTool.new(
        proc do |query:, database: "default"|
          # Simulate database query through MCP
          "Database query result from MCP server:\nQuery: #{query}\nDatabase: #{database}\nResults: [Sample data...]"
        end,
        name: "mcp_database",
        description: "Execute database queries through MCP server",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "SQL query to execute"
            },
            database: {
              type: "string",
              description: "Database name",
              default: "default"
            }
          },
          required: ["query"]
        }
      )
    end
  end

  # Create agent with MCP tools
  mcp_agent = OpenAIAgents::Agent.new(
    name: "MCPAgent",
    instructions: <<~INSTRUCTIONS,
      You are an AI agent with access to external systems through MCP (Model Context Protocol).
      You can:
      1. Access file systems to read, write, and search files
      2. Execute database queries to retrieve and analyze data
      3. Interact with APIs and external services
      
      Use these capabilities to help users with complex tasks that require external data access.
      Always explain what you're doing and provide clear, helpful responses.
    INSTRUCTIONS
    model: "gpt-4o"
  )

  # Add MCP tools to agent
  mcp_agent.add_tool(SimulatedMCPTool.create_filesystem_tool)
  mcp_agent.add_tool(SimulatedMCPTool.create_database_tool)

  puts "Agent created with MCP tools:"
  puts "  Agent name: #{mcp_agent.name}"
  puts "  Available tools: #{mcp_agent.tools.map(&:name).join(', ')}"
  puts

  # Test the agent with MCP tools
  runner = OpenAIAgents::Runner.new(agent: mcp_agent)
  
  test_messages = [
    { role: "user", content: "List the files in the current directory" }
  ]
  
  puts "Testing agent with MCP tools..."
  result = runner.run(test_messages)
  puts "Agent response: #{result.messages.last[:content]}"
  puts

rescue => e
  puts "Note: MCP tool creation failed (expected in demo): #{e.message}"
  puts "This demonstrates the configuration pattern for production use"
  puts
end

# ============================================================================
# EXAMPLE 3: MCP RESOURCE MANAGEMENT
# ============================================================================
# Demonstrates how to work with MCP resources (read-only data sources).
# Resources provide structured access to documents, configurations, and data.

puts "Example 3: MCP Resource Management"
puts "-" * 50

# MCP resources are identified by URIs and can have different content types
# This enables universal access to various data sources
class MCPResourceManager
  def initialize(client)
    @client = client
    @cached_resources = {}
  end
  
  # List all available resources from MCP server
  def list_resources
    # In production, this would call @client.list_resources
    simulated_resources = [
      {
        uri: "file:///docs/api-reference.md",
        name: "API Reference",
        description: "Complete API documentation",
        mime_type: "text/markdown"
      },
      {
        uri: "config://app/settings.json",
        name: "App Settings",
        description: "Application configuration",
        mime_type: "application/json"
      },
      {
        uri: "db://analytics/user_stats",
        name: "User Statistics",
        description: "Current user analytics data",
        mime_type: "application/json"
      }
    ]
    
    puts "Available MCP resources:"
    simulated_resources.each_with_index do |resource, index|
      puts "  #{index + 1}. #{resource[:name]}"
      puts "     URI: #{resource[:uri]}"
      puts "     Type: #{resource[:mime_type]}"
      puts "     Description: #{resource[:description]}"
      puts
    end
    
    simulated_resources
  end
  
  # Read specific resource content
  def read_resource(uri)
    # In production, this would call @client.read_resource(uri)
    case uri
    when /\.md$/
      "# API Reference\n\nThis is markdown content from MCP resource: #{uri}"
    when /\.json$/
      '{"type": "mcp_resource", "uri": "' + uri + '", "data": {"sample": "value"}}'
    else
      "Resource content from MCP server: #{uri}"
    end
  end
  
  # Create resource-aware agent tool
  def create_resource_tool
    OpenAIAgents::FunctionTool.new(
      proc do |action:, uri: nil, query: nil|
        case action
        when "list"
          resources = list_resources
          "Found #{resources.size} resources:\n" + 
          resources.map { |r| "- #{r[:name]}: #{r[:uri]}" }.join("\n")
        when "read"
          return "Error: URI required for read operation" unless uri
          read_resource(uri)
        when "search"
          return "Error: Query required for search operation" unless query
          "Search results for '#{query}' in MCP resources:\n- Found 3 matches\n- See detailed results..."
        else
          "Unknown action: #{action}"
        end
      end,
      name: "mcp_resource_manager",
      description: "Manage and access MCP resources",
      parameters: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["list", "read", "search"],
            description: "Action to perform on resources"
          },
          uri: {
            type: "string",
            description: "Resource URI (required for read action)"
          },
          query: {
            type: "string",
            description: "Search query (required for search action)"
          }
        },
        required: ["action"]
      }
    )
  end
end

# Create resource manager and agent
resource_manager = MCPResourceManager.new(mcp_client)
resource_tool = resource_manager.create_resource_tool

resource_agent = OpenAIAgents::Agent.new(
  name: "ResourceAgent",
  instructions: "You can access and manage MCP resources. Use the resource manager to help users find and read information from connected data sources.",
  model: "gpt-4o"
)

resource_agent.add_tool(resource_tool)

# Test resource management
puts "Testing resource management..."
resource_runner = OpenAIAgents::Runner.new(agent: resource_agent)

resource_test_messages = [
  { role: "user", content: "Show me what resources are available" }
]

resource_result = resource_runner.run(resource_test_messages)
puts "Resource agent response: #{resource_result.messages.last[:content]}"
puts

# ============================================================================
# EXAMPLE 4: MCP PROMPT TEMPLATES
# ============================================================================
# Shows how to use MCP servers that provide reusable prompt templates.
# Templates enable consistent, high-quality agent behaviors across contexts.

puts "Example 4: MCP Prompt Templates"
puts "-" * 50

# MCP prompt templates are parameterized prompts for common tasks
class MCPPromptManager
  def initialize(client)
    @client = client
    @templates = {}
  end
  
  # List available prompt templates
  def list_prompts
    # In production, this would call @client.list_prompts
    simulated_prompts = [
      {
        name: "code_review",
        description: "Review code for quality, security, and best practices",
        arguments: [
          { name: "language", type: "string", description: "Programming language" },
          { name: "focus", type: "string", description: "Review focus area" }
        ]
      },
      {
        name: "data_analysis",
        description: "Analyze datasets and provide insights",
        arguments: [
          { name: "data_type", type: "string", description: "Type of data to analyze" },
          { name: "objective", type: "string", description: "Analysis objective" }
        ]
      },
      {
        name: "technical_writing",
        description: "Generate technical documentation",
        arguments: [
          { name: "topic", type: "string", description: "Documentation topic" },
          { name: "audience", type: "string", description: "Target audience" }
        ]
      }
    ]
    
    puts "Available MCP prompt templates:"
    simulated_prompts.each_with_index do |prompt, index|
      puts "  #{index + 1}. #{prompt[:name]}"
      puts "     Description: #{prompt[:description]}"
      puts "     Arguments: #{prompt[:arguments].map { |arg| arg[:name] }.join(', ')}"
      puts
    end
    
    simulated_prompts
  end
  
  # Get expanded prompt content
  def get_prompt(name, arguments = {})
    # In production, this would call @client.get_prompt(name, arguments)
    case name
    when "code_review"
      language = arguments[:language] || "any"
      focus = arguments[:focus] || "general"
      
      {
        messages: [
          {
            role: "system",
            content: "You are an expert code reviewer specializing in #{language} programming. " \
                     "Focus on #{focus} aspects of the code. Provide detailed, constructive feedback."
          }
        ],
        description: "Code review prompt for #{language} with #{focus} focus"
      }
    when "data_analysis"
      data_type = arguments[:data_type] || "general"
      objective = arguments[:objective] || "insights"
      
      {
        messages: [
          {
            role: "system",
            content: "You are a data analyst expert. Analyze #{data_type} data to achieve #{objective}. " \
                     "Provide clear insights, statistical analysis, and actionable recommendations."
          }
        ],
        description: "Data analysis prompt for #{data_type} data"
      }
    else
      {
        messages: [
          {
            role: "system",
            content: "You are a helpful assistant with access to MCP prompt template: #{name}"
          }
        ],
        description: "Generic prompt template"
      }
    end
  end
  
  # Create agent from prompt template
  def create_agent_from_prompt(prompt_name, agent_name, arguments = {})
    prompt_content = get_prompt(prompt_name, arguments)
    
    OpenAIAgents::Agent.new(
      name: agent_name,
      instructions: prompt_content[:messages][0][:content],
      model: "gpt-4o"
    )
  end
end

# Create prompt manager and demonstrate usage
prompt_manager = MCPPromptManager.new(mcp_client)

# List available prompts
available_prompts = prompt_manager.list_prompts

# Create specialized agents from prompts
code_review_agent = prompt_manager.create_agent_from_prompt(
  "code_review",
  "CodeReviewer",
  { language: "ruby", focus: "security" }
)

data_analysis_agent = prompt_manager.create_agent_from_prompt(
  "data_analysis",
  "DataAnalyst",
  { data_type: "sales", objective: "trend_analysis" }
)

puts "Created specialized agents from MCP prompts:"
puts "  #{code_review_agent.name}: #{code_review_agent.instructions[0..80]}..."
puts "  #{data_analysis_agent.name}: #{data_analysis_agent.instructions[0..80]}..."
puts

# ============================================================================
# EXAMPLE 5: MULTI-SERVER MCP INTEGRATION
# ============================================================================
# Demonstrates advanced patterns for using multiple MCP servers together.
# This enables complex workflows across different data sources and services.

puts "Example 5: Multi-Server MCP Integration"
puts "-" * 50

# Multi-server configuration
class MCPOrchestrator
  def initialize
    @servers = {}
    @agents = {}
  end
  
  # Register multiple MCP servers
  def register_server(name, config)
    @servers[name] = {
      config: config,
      client: nil,
      tools: [],
      resources: []
    }
    
    puts "Registered MCP server: #{name}"
    puts "  Type: #{config[:type]}"
    puts "  Description: #{config[:description]}"
    puts
  end
  
  # Create supervisor agent that coordinates multiple MCP agents
  def create_supervisor_agent
    supervisor = OpenAIAgents::Agent.new(
      name: "MCPSupervisor",
      instructions: <<~INSTRUCTIONS,
        You are a supervisor agent that coordinates multiple specialized MCP agents.
        Each agent has access to different external systems through MCP servers.
        
        Available agents:
        - FileSystemAgent: Access to file systems and documents
        - DatabaseAgent: Access to databases and analytics
        - APIAgent: Access to external APIs and services
        - CloudAgent: Access to cloud services and storage
        
        Route user requests to the appropriate agent based on their needs.
        Coordinate multi-step workflows that require multiple systems.
      INSTRUCTIONS
      model: "gpt-4o"
    )
    
    # Add handoffs to specialized agents
    @agents.each_value do |agent|
      supervisor.add_handoff(agent)
    end
    
    supervisor
  end
  
  # Create specialized agents for different server types
  def create_specialized_agents
    # Filesystem agent
    filesystem_agent = OpenAIAgents::Agent.new(
      name: "FileSystemAgent",
      instructions: "You specialize in file system operations through MCP. You can read, write, search, and manage files and directories.",
      model: "gpt-4o"
    )
    
    # Database agent
    database_agent = OpenAIAgents::Agent.new(
      name: "DatabaseAgent", 
      instructions: "You specialize in database operations through MCP. You can query databases, analyze data, and generate reports.",
      model: "gpt-4o"
    )
    
    # API agent
    api_agent = OpenAIAgents::Agent.new(
      name: "APIAgent",
      instructions: "You specialize in API integrations through MCP. You can interact with external services and APIs.",
      model: "gpt-4o"
    )
    
    @agents[:filesystem] = filesystem_agent
    @agents[:database] = database_agent
    @agents[:api] = api_agent
    
    puts "Created specialized MCP agents:"
    @agents.each do |type, agent|
      puts "  #{type.capitalize}: #{agent.name}"
    end
    puts
  end
  
  # Dynamic tool loading based on context
  def load_contextual_tools(context)
    case context
    when :development
      tools = ["code_review", "git_operations", "file_search", "test_runner"]
    when :research
      tools = ["web_search", "document_analysis", "data_query", "report_generator"]
    when :operations
      tools = ["system_monitor", "log_analysis", "deployment", "backup"]
    else
      tools = ["general_assistant"]
    end
    
    puts "Loading contextual tools for #{context}:"
    tools.each { |tool| puts "  - #{tool}" }
    puts
    
    tools
  end
end

# Create orchestrator and demonstrate multi-server setup
orchestrator = MCPOrchestrator.new

# Register different server types
server_configs = {
  filesystem: {
    type: "stdio",
    command: "mcp-server-filesystem",
    description: "Local file system access"
  },
  github: {
    type: "stdio", 
    command: "mcp-server-github",
    description: "GitHub repository integration"
  },
  postgres: {
    type: "stdio",
    command: "mcp-server-postgres", 
    description: "PostgreSQL database access"
  },
  slack: {
    type: "sse",
    endpoint: "https://mcp-slack-server.example.com",
    description: "Slack workspace integration"
  }
}

# Register servers
server_configs.each do |name, config|
  orchestrator.register_server(name, config)
end

# Create agent hierarchy
orchestrator.create_specialized_agents
supervisor = orchestrator.create_supervisor_agent

puts "MCP Orchestrator Setup Complete:"
puts "  Supervisor agent: #{supervisor.name}"
puts "  Specialized agents: #{orchestrator.instance_variable_get(:@agents).keys.join(', ')}"
puts "  Registered servers: #{orchestrator.instance_variable_get(:@servers).keys.join(', ')}"
puts

# Demonstrate contextual tool loading
contexts = [:development, :research, :operations]
contexts.each do |context|
  orchestrator.load_contextual_tools(context)
end

# ============================================================================
# EXAMPLE 6: PRODUCTION MCP DEPLOYMENT PATTERNS
# ============================================================================
# Shows production-ready patterns for deploying MCP-enabled agents.
# Includes error handling, monitoring, and scalability considerations.

puts "Example 6: Production MCP Deployment Patterns"
puts "-" * 50

# Production MCP manager with robust error handling
class ProductionMCPManager
  def initialize(config)
    @config = config
    @clients = {}
    @health_checks = {}
    @retry_policy = {
      max_retries: 3,
      initial_delay: 1.0,
      max_delay: 10.0,
      backoff_multiplier: 2.0
    }
  end
  
  # Initialize all MCP connections with error handling
  def initialize_connections
    @config[:servers].each do |server_name, server_config|
      begin
        connect_server(server_name, server_config)
      rescue => e
        puts "Warning: Failed to connect to MCP server #{server_name}: #{e.message}"
        # Continue with other servers
      end
    end
    
    puts "MCP connections initialized:"
    @clients.each do |name, client|
      status = client.connected? ? "✓ Connected" : "✗ Disconnected"
      puts "  #{name}: #{status}"
    end
    puts
  end
  
  # Connect to individual server with retry logic
  def connect_server(server_name, server_config)
    attempt = 0
    delay = @retry_policy[:initial_delay]
    
    loop do
      attempt += 1
      
      begin
        client = OpenAIAgents::MCP::MCPClient.new(
          transport: server_config[:transport].to_sym,
          timeout: server_config[:timeout] || 30
        )
        
        # client.connect(server_config[:uri])
        @clients[server_name] = client
        @health_checks[server_name] = { last_check: Time.now, status: :healthy }
        
        puts "Connected to MCP server: #{server_name}"
        return true
        
      rescue => e
        if attempt >= @retry_policy[:max_retries]
          puts "Failed to connect to #{server_name} after #{attempt} attempts: #{e.message}"
          raise
        end
        
        puts "Connection attempt #{attempt} failed for #{server_name}, retrying in #{delay}s..."
        sleep(delay)
        delay = [delay * @retry_policy[:backoff_multiplier], @retry_policy[:max_delay]].min
      end
    end
  end
  
  # Health check for all MCP servers
  def perform_health_checks
    results = {}
    
    @clients.each do |server_name, client|
      begin
        # In production, this would check actual server health
        # For now, we'll simulate the health check
        healthy = client.connected? # && client.ping
        
        @health_checks[server_name] = {
          last_check: Time.now,
          status: healthy ? :healthy : :unhealthy,
          response_time: rand(0.1..0.5) # Simulated response time
        }
        
        results[server_name] = @health_checks[server_name]
        
      rescue => e
        @health_checks[server_name] = {
          last_check: Time.now,
          status: :error,
          error: e.message
        }
        
        results[server_name] = @health_checks[server_name]
      end
    end
    
    results
  end
  
  # Get overall system health
  def system_health
    health_results = perform_health_checks
    
    healthy_count = health_results.values.count { |h| h[:status] == :healthy }
    total_count = health_results.size
    
    overall_status = if healthy_count == total_count
                      :healthy
                    elsif healthy_count > 0
                      :degraded
                    else
                      :unhealthy
                    end
    
    {
      overall_status: overall_status,
      healthy_servers: healthy_count,
      total_servers: total_count,
      server_details: health_results
    }
  end
  
  # Create production-ready agent with MCP integration
  def create_production_agent
    OpenAIAgents::Agent.new(
      name: "ProductionMCPAgent",
      instructions: <<~INSTRUCTIONS,
        You are a production AI agent with access to multiple external systems through MCP.
        You have robust error handling and can gracefully handle system failures.
        
        Available systems:
        - File system access for document management
        - Database access for data analysis
        - API integration for external services
        - Cloud services for scalable operations
        
        Always:
        1. Handle errors gracefully and inform users of any issues
        2. Validate inputs before performing operations
        3. Provide clear explanations of what you're doing
        4. Offer alternatives when systems are unavailable
      INSTRUCTIONS
      model: "gpt-4o"
    )
  end
end

# Production configuration
production_config = {
  servers: {
    filesystem: {
      transport: :stdio,
      uri: "stdio://mcp-server-filesystem",
      timeout: 30,
      critical: true
    },
    database: {
      transport: :stdio,
      uri: "stdio://mcp-server-postgres",
      timeout: 45,
      critical: true
    },
    github: {
      transport: :stdio,
      uri: "stdio://mcp-server-github",
      timeout: 60,
      critical: false
    },
    slack: {
      transport: :sse,
      uri: "https://mcp-slack.example.com",
      timeout: 30,
      critical: false
    }
  },
  monitoring: {
    health_check_interval: 30,
    alert_thresholds: {
      response_time: 5.0,
      error_rate: 0.1
    }
  }
}

# Create production MCP manager
production_manager = ProductionMCPManager.new(production_config)

# Initialize connections (simulated for demo)
puts "Initializing production MCP connections..."
# production_manager.initialize_connections

# Simulate health checks
puts "Performing health checks..."
health_status = production_manager.system_health

puts "System Health Report:"
puts "  Overall Status: #{health_status[:overall_status]}"
puts "  Healthy Servers: #{health_status[:healthy_servers]}/#{health_status[:total_servers]}"
puts

health_status[:server_details].each do |server, details|
  status_icon = case details[:status]
                when :healthy then "✓"
                when :degraded then "⚠"
                when :unhealthy then "✗"
                else "?"
                end
  
  puts "  #{server}: #{status_icon} #{details[:status]}"
  puts "    Last check: #{details[:last_check]}"
  puts "    Response time: #{details[:response_time]&.round(3)}s" if details[:response_time]
  puts "    Error: #{details[:error]}" if details[:error]
  puts
end

# Create production agent
production_agent = production_manager.create_production_agent
puts "Production agent created: #{production_agent.name}"
puts

# ============================================================================
# BEST PRACTICES SUMMARY
# ============================================================================

puts "=== MCP Integration Best Practices ==="
puts "=" * 50
puts <<~PRACTICES
  1. Server Management:
     - Use appropriate transport types (stdio for local, SSE/WebSocket for remote)
     - Implement robust connection handling with retries
     - Monitor server health and implement fallback strategies
     - Use connection pooling for high-throughput scenarios

  2. Error Handling:
     - Implement comprehensive error handling for all MCP operations
     - Use circuit breakers for unreliable servers
     - Provide graceful degradation when servers are unavailable
     - Log errors appropriately for debugging and monitoring

  3. Security Considerations:
     - Validate all inputs before sending to MCP servers
     - Use secure communication channels (TLS for remote connections)
     - Implement proper authentication and authorization
     - Sanitize outputs from MCP servers before using

  4. Performance Optimization:
     - Cache frequently accessed resources
     - Use connection pooling for multiple concurrent requests
     - Implement request batching where possible
     - Monitor response times and optimize accordingly

  5. Tool Integration:
     - Design tools with clear, descriptive names and parameters
     - Use JSON Schema validation for all tool inputs
     - Implement proper type conversion between MCP and OpenAI formats
     - Provide comprehensive tool documentation

  6. Resource Management:
     - Implement resource discovery and caching
     - Use appropriate content type handling
     - Implement access control for sensitive resources
     - Monitor resource usage and implement quotas

  7. Monitoring and Observability:
     - Implement health checks for all MCP servers
     - Monitor request/response times and error rates
     - Set up alerts for server failures or performance issues
     - Track usage patterns and optimize accordingly

  8. Development Workflow:
     - Use local MCP servers for development and testing
     - Implement comprehensive unit tests for MCP integrations
     - Use staging environments that mirror production MCP setup
     - Version control MCP server configurations

  9. Deployment Patterns:
     - Use containerized MCP servers for consistent deployment
     - Implement proper service discovery for MCP servers
     - Use load balancing for high-availability MCP services
     - Implement rolling updates for MCP server changes

  10. Documentation:
      - Document all MCP server configurations and capabilities
      - Provide clear examples of tool usage
      - Maintain API documentation for custom MCP servers
      - Document troubleshooting procedures for common issues
PRACTICES

puts "\nMCP Integration example completed!"
puts "This demonstrates comprehensive Model Context Protocol integration for production AI systems."