require_relative "../function_tool"
require_relative "../mcp/client"
require_relative "../logging"

module OpenAIAgents
  module Tools
    ##
    # MCPTool - Model Context Protocol tool integration
    #
    # This tool provides integration with MCP servers, allowing agents to use
    # tools provided by external MCP-compatible services. This matches the
    # Python implementation's HostedMCPTool functionality.
    #
    # MCP (Model Context Protocol) is a standard for exposing tools and resources
    # to AI models. This tool acts as a bridge between OpenAI agents and MCP servers,
    # dynamically discovering and calling available tools.
    #
    # @example Basic usage
    #   tool = MCPTool.new(
    #     server_name: "my_server",
    #     server_config: { type: "stdio", command: "my-mcp-server" }
    #   )
    #   
    #   # Add to agent
    #   agent.add_tool(tool)
    #
    # @example Manual connection management
    #   tool = MCPTool.new(
    #     server_name: "api_server",
    #     server_config: { type: "websocket", url: "ws://localhost:8080" },
    #     auto_connect: false
    #   )
    #   
    #   tool.connect!
    #   tool.refresh_tools!
    #
    class MCPTool < FunctionTool
      include Logger
      
      # @!attribute [r] server_name
      #   @return [String] Name of the MCP server
      # @!attribute [r] server_config
      #   @return [Hash] Configuration for the MCP server connection
      # @!attribute [r] client
      #   @return [MCP::Client, nil] The MCP client instance
      attr_reader :server_name, :server_config, :client

      ##
      # Initialize a new MCP tool
      #
      # @param server_name [String] Unique name for the MCP server
      # @param server_config [Hash] MCP server configuration
      # @option server_config [String] :type Server type ("stdio", "sse", "websocket")
      # @option server_config [String] :command Command to launch stdio server
      # @option server_config [String] :url URL for SSE/WebSocket servers
      # @param auto_connect [Boolean] Whether to connect automatically on initialization
      #
      def initialize(server_name:, server_config: {}, auto_connect: true)
        @server_name = server_name
        @server_config = server_config
        @client = nil
        @available_tools = {}

        # Initialize client and connect if requested
        initialize_client if auto_connect

        # Create the MCP function
        mcp_function = create_mcp_function

        super(
          mcp_function,
          name: "mcp_#{server_name}",
          description: "Access tools from MCP server: #{server_name}",
          parameters: {
            type: "object",
            properties: {
              tool_name: {
                type: "string",
                description: "Name of the MCP tool to call",
                enum: available_tool_names
              },
              arguments: {
                type: "object",
                description: "Arguments to pass to the MCP tool"
              }
            },
            required: ["tool_name"]
          }
        )
      end

      ##
      # Get list of available tools from the MCP server
      #
      # Returns an empty array if not connected or if an error occurs.
      #
      # @return [Array<String>] names of available tools
      #
      # @example
      #   tool.available_tool_names
      #   # => ["search", "calculate", "file_read"]
      #
      def available_tool_names
        return [] unless @client&.connected?

        begin
          @available_tools.keys
        rescue StandardError => e
          log_warn("Error getting MCP tool names: #{e.message}", server: @server_name, error_class: e.class.name)
          []
        end
      end

      ##
      # Get detailed information about available tools
      #
      # Returns a hash mapping tool names to their full metadata including
      # descriptions and parameter schemas.
      #
      # @return [Hash] tool name => tool info mapping
      #
      # @example
      #   tool.available_tools_info
      #   # => {
      #   #   "search" => {
      #   #     name: "search",
      #   #     description: "Search the web",
      #   #     input_schema: { type: "object", properties: {...} }
      #   #   }
      #   # }
      #
      def available_tools_info
        @available_tools.dup
      end

      ##
      # Refresh tool list from MCP server
      #
      # Queries the MCP server for its current list of available tools
      # and updates the internal tool registry. Also updates the parameter
      # enum to reflect available tools.
      #
      # @return [Boolean] true if refresh was successful
      #
      # @example
      #   if tool.refresh_tools!
      #     puts "Tools updated: #{tool.available_tool_names}"
      #   end
      #
      def refresh_tools!
        return false unless @client&.connected?

        begin
          tools_response = @client.list_tools
          @available_tools = {}

          tools_response["tools"]&.each do |tool|
            @available_tools[tool["name"]] = {
              name: tool["name"],
              description: tool["description"],
              input_schema: tool["inputSchema"]
            }
          end

          # Update parameters enum
          update_parameters_enum
          true
        rescue StandardError => e
          log_warn("Error refreshing MCP tools: #{e.message}", server: @server_name, error_class: e.class.name)
          false
        end
      end

      ##
      # Check if MCP server is connected
      #
      # @return [Boolean] true if connected, false otherwise
      #
      def connected?
        @client&.connected? || false
      end

      ##
      # Connect to MCP server
      #
      # Establishes connection to the MCP server and refreshes the tool list.
      # If already connected, returns true without reconnecting.
      #
      # @return [Boolean] true if connection successful
      # @raise [StandardError] logs error if connection fails
      #
      # @example
      #   unless tool.connected?
      #     tool.connect!
      #   end
      #
      def connect!
        return true if connected?

        begin
          @client = MCP::Client.new(@server_config)
          @client.connect
          refresh_tools!
        rescue StandardError => e
          log_error("Failed to connect to MCP server #{@server_name}: #{e.message}", server: @server_name,
                                                                                     error_class: e.class.name)
          false
        end
      end

      ##
      # Disconnect from MCP server
      #
      # Closes the connection to the MCP server and clears the tool registry.
      #
      # @return [void]
      #
      def disconnect!
        @client&.disconnect
        @client = nil
        @available_tools.clear
      end

      private

      ##
      # Creates the function that handles MCP tool calls
      #
      # @return [Proc] Function that executes MCP tool calls
      # @private
      #
      def create_mcp_function
        proc do |tool_name:, arguments: {}|
          # Ensure connection
          return "Error: Not connected to MCP server #{@server_name}" unless connected?

          # Validate tool exists
          unless @available_tools.key?(tool_name)
            available = @available_tools.keys.join(", ")
            return "Error: Tool '#{tool_name}' not available. Available tools: #{available}"
          end

          # Call MCP tool
          begin
            response = @client.call_tool(tool_name, arguments)

            case response["result"]
            when Array
              # Multiple results - combine them
              response["result"].map do |result|
                format_mcp_result(result)
              end.join("\n\n")
            when Hash
              # Single result
              format_mcp_result(response["result"])
            else
              # Plain result
              response["result"].to_s
            end
          rescue StandardError => e
            "Error calling MCP tool '#{tool_name}': #{e.message}"
          end
        end
      end

      ##
      # Formats MCP result based on its type
      #
      # @param result [Hash] MCP result object
      # @return [String] Formatted result string
      # @private
      #
      def format_mcp_result(result)
        case result["type"]
        when "text"
          result["text"]
        when "image"
          # Show truncated data preview for images
          "[Image: #{result["data"][0..50]}...]"
        when "resource"
          "[Resource: #{result["resource"]["uri"]}]"
        else
          result.to_s
        end
      end

      ##
      # Initializes and connects the MCP client
      #
      # @return [void]
      # @private
      #
      def initialize_client
        @client = MCP::Client.new(@server_config)
        @client.connect
        refresh_tools!
      rescue StandardError => e
        log_error("Failed to initialize MCP client for #{@server_name}: #{e.message}", server: @server_name,
                                                                                       error_class: e.class.name)
      end

      ##
      # Updates the parameter enum with current tool names
      #
      # This ensures the OpenAI function calling knows which tools
      # are available from the MCP server.
      #
      # @return [void]
      # @private
      #
      def update_parameters_enum
        # Update the parameters to include current tool names
        @parameters[:properties][:tool_name][:enum] = available_tool_names
      end
    end

    ##
    # HostedMCPTool - Wrapper for OpenAI hosted MCP tools
    #
    # This provides compatibility with OpenAI's hosted MCP tool format.
    # Unlike MCPTool which connects to external MCP servers, HostedMCPTool
    # represents MCP tools that are hosted and managed by OpenAI.
    #
    # @example Creating a hosted MCP tool
    #   tool = HostedMCPTool.new(
    #     server_name: "brave_search",
    #     api_key: ENV["BRAVE_API_KEY"]
    #   )
    #   
    #   agent.add_tool(tool)
    #
    class HostedMCPTool
      # @!attribute [r] server_name
      #   @return [String] Name of the hosted MCP server
      # @!attribute [r] server_config
      #   @return [Hash] Configuration for the hosted MCP tool
      attr_reader :server_name, :server_config

      ##
      # Initialize a hosted MCP tool
      #
      # @param server_name [String] Name of the OpenAI-hosted MCP server
      # @param server_config [Hash] Additional configuration for the hosted tool
      #
      def initialize(server_name:, **server_config)
        @server_name = server_name
        @server_config = server_config
      end

      ##
      # Returns the tool name in MCP format
      #
      # @return [String] Tool name with "mcp:" prefix
      #
      def name
        "mcp:#{@server_name}"
      end

      ##
      # Converts to OpenAI tool definition format
      #
      # @return [Hash] Tool definition for OpenAI API
      #
      # @example
      #   tool.to_tool_definition
      #   # => {
      #   #   type: "mcp",
      #   #   name: "mcp:brave_search",
      #   #   mcp: { server_name: "brave_search", api_key: "..." }
      #   # }
      #
      def to_tool_definition
        {
          type: "mcp",
          name: name,
          mcp: {
            server_name: @server_name,
            **@server_config
          }
        }
      end
    end

    ##
    # MCPToolFactory - Factory for creating MCP tools from server configurations
    #
    # Provides convenient methods for creating MCP tools from various
    # configuration sources including hashes, arrays, and environment variables.
    #
    # @example From configuration hash
    #   tool = MCPToolFactory.create_from_config({
    #     name: "calculator",
    #     type: "stdio",
    #     config: { command: "calculator-mcp" }
    #   })
    #
    # @example From environment variables
    #   # With env vars: MCP_SERVER_NAME=calc, MCP_SERVER_TYPE=stdio
    #   tool = MCPToolFactory.create_from_env
    #
    class MCPToolFactory
      ##
      # Create MCP tool from configuration
      #
      # @param config [Hash] MCP server configuration
      # @option config [String] :name server name
      # @option config [String] :type server type ('stdio', 'sse', 'websocket')
      # @option config [Hash] :config server-specific configuration
      # @return [MCPTool] configured MCP tool
      #
      # @example
      #   tool = MCPToolFactory.create_from_config({
      #     name: "filesystem",
      #     type: "stdio",
      #     config: { command: "fs-mcp-server" }
      #   })
      #
      def self.create_from_config(config)
        server_name = config[:name] || config["name"]
        server_config = config[:config] || config["config"] || {}

        MCPTool.new(
          server_name: server_name,
          server_config: server_config
        )
      end

      ##
      # Create multiple MCP tools from configuration array
      #
      # @param configs [Array<Hash>] array of MCP server configurations
      # @return [Array<MCPTool>] array of configured MCP tools
      #
      # @example
      #   tools = MCPToolFactory.create_from_configs([
      #     { name: "search", type: "websocket", config: { url: "ws://search:8080" } },
      #     { name: "calc", type: "stdio", config: { command: "calc-server" } }
      #   ])
      #
      def self.create_from_configs(configs)
        configs.map { |config| create_from_config(config) }
      end

      ##
      # Create MCP tool from environment variables
      #
      # Looks for environment variables with the specified prefix to configure
      # an MCP tool. This is useful for containerized deployments.
      #
      # Environment variables:
      # - {prefix}_NAME: Server name (required)
      # - {prefix}_TYPE: Server type (default: "stdio")
      # - {prefix}_CONFIG_*: Additional configuration
      #
      # @param prefix [String] environment variable prefix (default: 'MCP_SERVER')
      # @return [MCPTool, nil] configured MCP tool or nil if not found
      #
      # @example With standard prefix
      #   # ENV: MCP_SERVER_NAME=browser, MCP_SERVER_TYPE=websocket
      #   #      MCP_SERVER_CONFIG_URL=ws://localhost:9000
      #   tool = MCPToolFactory.create_from_env
      #
      # @example With custom prefix
      #   # ENV: MY_MCP_NAME=custom, MY_MCP_TYPE=stdio
      #   tool = MCPToolFactory.create_from_env(prefix: "MY_MCP")
      #
      def self.create_from_env(prefix: "MCP_SERVER")
        server_name = ENV.fetch("#{prefix}_NAME", nil)
        return nil unless server_name

        server_type = ENV["#{prefix}_TYPE"] || "stdio"

        # Collect config variables
        config = {}
        ENV.each do |key, value|
          if key.start_with?("#{prefix}_CONFIG_")
            config_key = key.sub("#{prefix}_CONFIG_", "").downcase
            config[config_key] = value
          end
        end

        config["type"] = server_type

        MCPTool.new(
          server_name: server_name,
          server_config: config
        )
      end
    end
  end
end
