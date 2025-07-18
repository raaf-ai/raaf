# frozen_string_literal: true

module RAAF
  module MCP
    # MCP Protocol constants and helpers
    module Protocol
      PROTOCOL_VERSION = "0.1.0"

      # JSON-RPC 2.0 error codes
      module ErrorCodes
        PARSE_ERROR = -32_700
        INVALID_REQUEST = -32_600
        METHOD_NOT_FOUND = -32_601
        INVALID_PARAMS = -32_602
        INTERNAL_ERROR = -32_603

        # MCP-specific error codes
        RESOURCE_NOT_FOUND = -32_001
        TOOL_NOT_FOUND = -32_002
        PROMPT_NOT_FOUND = -32_003
        UNAUTHORIZED = -32_004
        RATE_LIMITED = -32_005
      end

      # Standard MCP methods
      module Methods
        # Lifecycle
        INITIALIZE = "initialize"
        INITIALIZED = "initialized"
        SHUTDOWN = "shutdown"

        # Resources
        LIST_RESOURCES = "resources/list"
        READ_RESOURCE = "resources/read"
        SUBSCRIBE_RESOURCE = "resources/subscribe"
        UNSUBSCRIBE_RESOURCE = "resources/unsubscribe"

        # Tools
        LIST_TOOLS = "tools/list"
        CALL_TOOL = "tools/call"

        # Prompts
        LIST_PROMPTS = "prompts/list"
        GET_PROMPT = "prompts/get"

        # Sampling
        CREATE_MESSAGE = "sampling/createMessage"

        # Notifications
        RESOURCES_LIST_CHANGED = "notifications/resources/list-changed"
        TOOLS_LIST_CHANGED = "notifications/tools/list-changed"
        PROMPTS_LIST_CHANGED = "notifications/prompts/list-changed"
        RESOURCE_UPDATED = "notifications/resources/updated"
      end

      # MIME types commonly used in MCP
      module MimeTypes
        TEXT_PLAIN = "text/plain"
        TEXT_MARKDOWN = "text/markdown"
        TEXT_HTML = "text/html"
        APPLICATION_JSON = "application/json"
        APPLICATION_XML = "application/xml"
        IMAGE_PNG = "image/png"
        IMAGE_JPEG = "image/jpeg"
        IMAGE_SVG = "image/svg+xml"
      end

      # Helper method to validate protocol version
      def self.compatible_version?(version)
        # For now, only exact match
        # In future, could implement semantic versioning comparison
        version == PROTOCOL_VERSION
      end

      # Helper to create error response
      def self.error_response(id, code, message, data = nil)
        response = {
          jsonrpc: "2.0",
          id: id,
          error: {
            code: code,
            message: message
          }
        }

        response[:error][:data] = data if data
        response
      end

      # Helper to create success response
      def self.success_response(id, result)
        {
          jsonrpc: "2.0",
          id: id,
          result: result
        }
      end

      # Helper to create notification
      def self.notification(method, params = nil)
        notification = {
          jsonrpc: "2.0",
          method: method
        }

        notification[:params] = params if params
        notification
      end
    end
  end
end
