# frozen_string_literal: true

require_relative "../function_tool"
require_relative "client"

module RubyAIAgentsFactory
  module MCP
    # Adapter to use MCP tools as OpenAI Agent tools
    #
    # This adapter wraps MCP tools to make them compatible with
    # the OpenAI Agents tool interface.
    #
    # @example Basic usage
    #   client = MCPClient.new
    #   client.connect("stdio://mcp-server")
    #
    #   adapter = MCPToolAdapter.new(client)
    #   tools = adapter.get_all_tools
    #
    #   agent = Agent.new(name: "MCPAgent")
    #   tools.each { |tool| agent.add_tool(tool) }
    #
    # @example Selective tool loading
    #   adapter = MCPToolAdapter.new(client)
    #   tool = adapter.get_tool("search_web")
    #   agent.add_tool(tool)
    class MCPToolAdapter
      attr_reader :client

      def initialize(client)
        @client = client
        @tool_cache = {}
      end

      # Get all available tools from the MCP server as FunctionTools
      def get_all_tools
        mcp_tools = @client.list_tools
        mcp_tools.map { |tool| create_function_tool(tool) }
      end

      # Get a specific tool by name
      def get_tool(name)
        # Check cache first
        return @tool_cache[name] if @tool_cache[name]

        # Get from server
        mcp_tools = @client.list_tools
        mcp_tool = mcp_tools.find { |t| t.name == name }

        return nil unless mcp_tool

        create_function_tool(mcp_tool)
      end

      # Create a function tool that wraps an MCP tool
      def create_function_tool(mcp_tool)
        # Cache the tool
        @tool_cache[mcp_tool.name] = build_function_tool(mcp_tool)
      end

      private

      def build_function_tool(mcp_tool)
        # Create a proc that calls the MCP tool
        tool_proc = proc do |**kwargs|
          # Call the MCP tool with the provided arguments
          result = @client.call_tool(mcp_tool.name, kwargs)

          raise ToolExecutionError, "MCP tool error: #{result.content}" if result.error?

          result.content
        end

        # Create the FunctionTool with MCP tool metadata
        FunctionTool.new(
          tool_proc,
          name: mcp_tool.name,
          description: mcp_tool.description,
          parameters: mcp_tool.input_schema
        )
      end
    end

    # Resource adapter for using MCP resources in agents
    class MCPResourceAdapter
      attr_reader :client

      def initialize(client)
        @client = client
      end

      # List all available resources
      def list_resources
        @client.list_resources
      end

      # Read a resource and return its content
      def read_resource(uri)
        content = @client.read_resource(uri)

        if content.text?
          content.text
        else
          # For binary content, return base64 encoded
          content.blob
        end
      end

      # Create a tool that can read MCP resources
      def create_resource_reader_tool
        tool_proc = proc do |uri:|
          read_resource(uri)
        end

        FunctionTool.new(
          tool_proc,
          name: "read_mcp_resource",
          description: "Read a resource from the MCP server",
          parameters_schema: {
            type: "object",
            properties: {
              uri: {
                type: "string",
                description: "The URI of the resource to read"
              }
            },
            required: ["uri"]
          }
        )
      end
    end

    # Prompt adapter for using MCP prompts
    class MCPPromptAdapter
      attr_reader :client

      def initialize(client)
        @client = client
      end

      # List all available prompts
      def list_prompts
        @client.list_prompts
      end

      # Get a prompt and format it for use
      def get_prompt(name, **arguments)
        prompt_content = @client.get_prompt(name, arguments)

        # Convert MCP prompt messages to OpenAI format
        {
          messages: prompt_content.messages,
          description: prompt_content.description
        }
      end

      # Create an agent from an MCP prompt
      def create_agent_from_prompt(name, agent_name: nil, **prompt_args)
        prompt = get_prompt(name, **prompt_args)

        # Extract system message for instructions
        system_messages = prompt[:messages].select { |m| m["role"] == "system" }
        instructions = system_messages.map { |m| m["content"] }.join("\n\n")

        # Create agent with the prompt instructions
        Agent.new(
          name: agent_name || name,
          instructions: instructions || prompt[:description]
        )
      end
    end

    # Main MCP integration class
    class MCPIntegration
      attr_reader :client, :tool_adapter, :resource_adapter, :prompt_adapter

      def initialize(server_uri, transport: :stdio)
        @client = MCPClient.new(transport: transport)
        @client.connect(server_uri)

        @tool_adapter = MCPToolAdapter.new(@client)
        @resource_adapter = MCPResourceAdapter.new(@client)
        @prompt_adapter = MCPPromptAdapter.new(@client)
      end

      # Create an agent with all MCP tools
      def create_agent(name: "MCPAgent", instructions: nil, model: "gpt-4")
        agent = Agent.new(
          name: name,
          instructions: instructions || "You have access to MCP server tools and resources.",
          model: model
        )

        # Add all MCP tools
        tools = @tool_adapter.get_all_tools
        tools.each { |tool| agent.add_tool(tool) }

        # Add resource reader tool
        agent.add_tool(@resource_adapter.create_resource_reader_tool)

        agent
      end

      # Disconnect from MCP server
      def disconnect
        @client.disconnect
      end
    end

    # Custom error for tool execution failures
    class ToolExecutionError < StandardError; end
  end
end
