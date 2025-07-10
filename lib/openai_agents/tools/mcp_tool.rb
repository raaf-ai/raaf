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
    class MCPTool < FunctionTool
      include Logger
      attr_reader :server_name, :server_config, :client

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
      # @return [Array<String>] names of available tools
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
      # @return [Hash] tool name => tool info mapping
      def available_tools_info
        @available_tools.dup
      end

      ##
      # Refresh tool list from MCP server
      #
      # @return [Boolean] true if refresh was successful
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
      # @return [Boolean] true if connected
      def connected?
        @client&.connected? || false
      end

      ##
      # Connect to MCP server
      #
      # @return [Boolean] true if connection successful
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
      def disconnect!
        @client&.disconnect
        @client = nil
        @available_tools.clear
      end

      private

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

      def format_mcp_result(result)
        case result["type"]
        when "text"
          result["text"]
        when "image"
          "[Image: #{result["data"][0..50]}...]"
        when "resource"
          "[Resource: #{result["resource"]["uri"]}]"
        else
          result.to_s
        end
      end

      def initialize_client
        @client = MCP::Client.new(@server_config)
        @client.connect
        refresh_tools!
      rescue StandardError => e
        log_error("Failed to initialize MCP client for #{@server_name}: #{e.message}", server: @server_name,
                                                                                       error_class: e.class.name)
      end

      def update_parameters_enum
        # Update the parameters to include current tool names
        @parameters[:properties][:tool_name][:enum] = available_tool_names
      end
    end

    ##
    # HostedMCPTool - Wrapper for OpenAI hosted MCP tools
    #
    # This provides compatibility with OpenAI's hosted MCP tool format
    class HostedMCPTool
      attr_reader :server_name, :server_config

      def initialize(server_name:, **server_config)
        @server_name = server_name
        @server_config = server_config
      end

      def name
        "mcp:#{@server_name}"
      end

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
    class MCPToolFactory
      ##
      # Create MCP tool from configuration
      #
      # @param config [Hash] MCP server configuration
      # @option config [String] :name server name
      # @option config [String] :type server type ('stdio', 'sse', 'websocket')
      # @option config [Hash] :config server-specific configuration
      # @return [MCPTool] configured MCP tool
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
      def self.create_from_configs(configs)
        configs.map { |config| create_from_config(config) }
      end

      ##
      # Create MCP tool from environment variables
      #
      # Looks for environment variables like:
      # - MCP_SERVER_NAME
      # - MCP_SERVER_TYPE
      # - MCP_SERVER_CONFIG_*
      #
      # @param prefix [String] environment variable prefix (default: 'MCP_SERVER')
      # @return [MCPTool, nil] configured MCP tool or nil if not found
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
