# frozen_string_literal: true

require "json"
require "open3"
require "timeout"
require_relative "protocol"
require_relative "types"

module RubyAIAgentsFactory
  module MCP
    # MCP Client for connecting to Model Context Protocol servers
    #
    # This client implements the Model Context Protocol specification,
    # allowing agents to interact with MCP servers for enhanced context
    # and tool capabilities.
    #
    # @example Basic usage
    #   client = MCPClient.new
    #   client.connect("stdio://path/to/mcp-server")
    #   resources = client.list_resources
    #
    # @example With custom transport
    #   client = MCPClient.new(transport: :sse)
    #   client.connect("http://localhost:3000/mcp")
    class MCPClient
      include Protocol

      attr_reader :server_info, :capabilities, :connected

      def initialize(transport: :stdio, timeout: 30)
        @transport = transport
        @timeout = timeout
        @connected = false
        @server_info = nil
        @capabilities = nil
        @message_id = 0
        @pending_requests = {}
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @process = nil
      end

      # Connect to an MCP server
      def connect(uri)
        case @transport
        when :stdio
          connect_stdio(uri)
        when :sse
          connect_sse(uri)
        else
          raise ArgumentError, "Unsupported transport: #{@transport}"
        end

        # Perform initialization handshake
        initialize_connection
        @connected = true
      end

      # Disconnect from the MCP server
      def disconnect
        return unless @connected

        case @transport
        when :stdio
          disconnect_stdio
        when :sse
          disconnect_sse
        end

        @connected = false
      end

      # List available resources from the server
      def list_resources
        ensure_connected!

        request = create_request("resources/list")
        response = send_request(request)

        response["resources"].map do |resource|
          Resource.new(
            uri: resource["uri"],
            name: resource["name"],
            description: resource["description"],
            mime_type: resource["mimeType"]
          )
        end
      end

      # Read a specific resource
      def read_resource(uri)
        ensure_connected!

        request = create_request("resources/read", { uri: uri })
        response = send_request(request)

        ResourceContent.new(
          uri: response["uri"],
          mime_type: response["mimeType"],
          text: response["text"],
          blob: response["blob"]
        )
      end

      # List available tools from the server
      def list_tools
        ensure_connected!

        request = create_request("tools/list")
        response = send_request(request)

        response["tools"].map do |tool|
          Tool.new(
            name: tool["name"],
            description: tool["description"],
            input_schema: tool["inputSchema"]
          )
        end
      end

      # Call a tool on the server
      def call_tool(name, arguments = {})
        ensure_connected!

        request = create_request("tools/call", {
                                   name: name,
                                   arguments: arguments
                                 })

        response = send_request(request)

        ToolResult.new(
          tool_name: name,
          content: response["content"],
          is_error: response["isError"] || false
        )
      end

      # List available prompts from the server
      def list_prompts
        ensure_connected!

        request = create_request("prompts/list")
        response = send_request(request)

        response["prompts"].map do |prompt|
          Prompt.new(
            name: prompt["name"],
            description: prompt["description"],
            arguments: prompt["arguments"]
          )
        end
      end

      # Get a specific prompt
      def get_prompt(name, arguments = {})
        ensure_connected!

        request = create_request("prompts/get", {
                                   name: name,
                                   arguments: arguments
                                 })

        response = send_request(request)

        PromptContent.new(
          messages: response["messages"],
          description: response["description"]
        )
      end

      # Create a sampling request (for LLM completions)
      def create_message(messages, options = {})
        ensure_connected!

        request = create_request("sampling/createMessage", {
          messages: messages,
          modelPreferences: options[:model_preferences],
          systemPrompt: options[:system_prompt],
          includeContext: options[:include_context],
          temperature: options[:temperature],
          maxTokens: options[:max_tokens],
          stopSequences: options[:stop_sequences],
          metadata: options[:metadata]
        }.compact)

        response = send_request(request)

        SamplingResult.new(
          role: response["role"],
          content: response["content"],
          model: response["model"],
          stop_reason: response["stopReason"]
        )
      end

      private

      def ensure_connected!
        raise NotConnectedError, "Not connected to MCP server" unless @connected
      end

      def connect_stdio(uri)
        # Parse stdio URI: stdio://path/to/executable?arg1=val1&arg2=val2
        uri_parts = URI.parse(uri)
        executable = uri_parts.host + uri_parts.path

        # Parse query parameters as arguments
        args = []
        if uri_parts.query
          CGI.parse(uri_parts.query).each do |key, values|
            args << "--#{key}=#{values.first}"
          end
        end

        # Start the process
        @stdin, @stdout, @stderr, @process = Open3.popen3(executable, *args)

        # Start reader thread
        @reader_thread = Thread.new { read_messages }
      end

      def disconnect_stdio
        @stdin&.close
        @stdout&.close
        @stderr&.close
        @process&.kill if @process&.alive?
        @reader_thread&.kill
      end

      def connect_sse(uri)
        # SSE implementation would go here
        raise NotImplementedError, "SSE transport not yet implemented"
      end

      def disconnect_sse
        # SSE disconnect implementation
      end

      def initialize_connection
        # Send initialization request
        init_request = create_request("initialize", {
                                        protocolVersion: PROTOCOL_VERSION,
                                        capabilities: {
                                          roots: { listChanged: true },
                                          sampling: {}
                                        },
                                        clientInfo: {
                                          name: "openai-agents-ruby",
                                          version: "1.0.0"
                                        }
                                      })

        response = send_request(init_request)

        @server_info = response["serverInfo"]
        @capabilities = response["capabilities"]

        # Send initialized notification
        send_notification("initialized", {})
      end

      def create_request(method, params = nil)
        @message_id += 1

        request = {
          jsonrpc: "2.0",
          method: method,
          id: @message_id
        }

        request[:params] = params if params
        request
      end

      def send_request(request)
        message_id = request[:id]

        # Send the request
        send_message(request)

        # Wait for response with timeout
        response = nil
        Timeout.timeout(@timeout) do
          loop do
            response = @pending_requests.delete(message_id)
            break if response

            sleep 0.01
          end
        end

        raise MCPError.new(response["error"]["message"], response["error"]["code"]) if response["error"]

        response["result"]
      end

      def send_notification(method, params = nil)
        notification = {
          jsonrpc: "2.0",
          method: method
        }

        notification[:params] = params if params
        send_message(notification)
      end

      def send_message(message)
        json = JSON.generate(message)
        @stdin.puts(json)
        @stdin.flush
      end

      def read_messages
        while (line = @stdout.gets)
          begin
            message = JSON.parse(line)
            handle_message(message)
          rescue JSON::ParserError => e
            # Log parse error but continue
            log_warn("Failed to parse message: #{e.message}", client: "MCPClient", error_class: e.class.name)
          end
        end
      rescue IOError
        # Stream closed, exit gracefully
      end

      def handle_message(message)
        if message["id"]
          # This is a response to a request
          @pending_requests[message["id"]] = message
        elsif message["method"]
          # This is a notification or request from server
          handle_server_message(message)
        end
      end

      def handle_server_message(message)
        case message["method"]
        when "notifications/resources/list-changed"
          # Handle resource list change notification
          # Could emit an event or callback here
        when "notifications/tools/list-changed"
          # Handle tool list change notification
        when "notifications/prompts/list-changed"
          # Handle prompt list change notification
        else
          # Unknown notification, log it
          log_debug("Received unknown notification: #{message["method"]}", client: "MCPClient",
                                                                           method: message["method"])
        end
      end
    end

    # Errors
    class MCPError < StandardError
      attr_reader :code

      def initialize(message, code = nil)
        super(message)
        @code = code
      end
    end

    class NotConnectedError < MCPError; end
  end
end
