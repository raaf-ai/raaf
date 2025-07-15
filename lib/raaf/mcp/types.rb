# frozen_string_literal: true

module RubyAIAgentsFactory
  module MCP
    # MCP type definitions

    # Resource represents a piece of content that can be read from the server
    class Resource
      attr_reader :uri, :name, :description, :mime_type

      def initialize(uri:, name:, description: nil, mime_type: nil)
        @uri = uri
        @name = name
        @description = description
        @mime_type = mime_type
      end

      def to_h
        {
          uri: uri,
          name: name,
          description: description,
          mimeType: mime_type
        }.compact
      end
    end

    # ResourceContent represents the actual content of a resource
    class ResourceContent
      attr_reader :uri, :mime_type, :text, :blob

      def initialize(uri:, mime_type:, text: nil, blob: nil)
        @uri = uri
        @mime_type = mime_type
        @text = text
        @blob = blob
      end

      def text?
        !@text.nil?
      end

      def binary?
        !@blob.nil?
      end

      def to_h
        {
          uri: uri,
          mimeType: mime_type,
          text: text,
          blob: blob
        }.compact
      end
    end

    # Tool represents a function that can be called on the server
    class Tool
      attr_reader :name, :description, :input_schema

      def initialize(name:, description:, input_schema:)
        @name = name
        @description = description
        @input_schema = input_schema
      end

      def to_h
        {
          name: name,
          description: description,
          inputSchema: input_schema
        }
      end

      # Convert to OpenAI function tool format
      def to_function_tool
        {
          type: "function",
          function: {
            name: name,
            description: description,
            parameters: input_schema
          }
        }
      end
    end

    # ToolResult represents the result of calling a tool
    class ToolResult
      attr_reader :tool_name, :content, :is_error

      def initialize(tool_name:, content:, is_error: false)
        @tool_name = tool_name
        @content = content
        @is_error = is_error
      end

      def success?
        !@is_error
      end

      def error?
        @is_error
      end

      def to_h
        {
          toolName: tool_name,
          content: content,
          isError: is_error
        }
      end
    end

    # Prompt represents a prompt template on the server
    class Prompt
      attr_reader :name, :description, :arguments

      def initialize(name:, description: nil, arguments: nil)
        @name = name
        @description = description
        @arguments = arguments || []
      end

      def to_h
        {
          name: name,
          description: description,
          arguments: arguments
        }.compact
      end
    end

    # PromptContent represents the expanded content of a prompt
    class PromptContent
      attr_reader :messages, :description

      def initialize(messages:, description: nil)
        @messages = messages
        @description = description
      end

      def to_h
        {
          messages: messages,
          description: description
        }.compact
      end
    end

    # SamplingResult represents the result of a sampling request
    class SamplingResult
      attr_reader :role, :content, :model, :stop_reason

      def initialize(role:, content:, model: nil, stop_reason: nil)
        @role = role
        @content = content
        @model = model
        @stop_reason = stop_reason
      end

      def to_h
        {
          role: role,
          content: content,
          model: model,
          stopReason: stop_reason
        }.compact
      end

      # Convert to OpenAI message format
      def to_message
        {
          role: role,
          content: content
        }
      end
    end

    # ServerInfo represents information about the MCP server
    class ServerInfo
      attr_reader :name, :version, :protocol_version, :capabilities

      def initialize(name:, version:, protocol_version:, capabilities: {})
        @name = name
        @version = version
        @protocol_version = protocol_version
        @capabilities = capabilities
      end

      def supports_resources?
        capabilities.dig("resources", "list") == true
      end

      def supports_tools?
        capabilities.dig("tools", "list") == true
      end

      def supports_prompts?
        capabilities.dig("prompts", "list") == true
      end

      def supports_sampling?
        capabilities.dig("sampling", "createMessage") == true
      end

      def to_h
        {
          name: name,
          version: version,
          protocolVersion: protocol_version,
          capabilities: capabilities
        }
      end
    end

    # Root represents a root directory for resources
    class Root
      attr_reader :uri, :name

      def initialize(uri:, name: nil)
        @uri = uri
        @name = name || uri
      end

      def to_h
        {
          uri: uri,
          name: name
        }
      end
    end
  end
end
