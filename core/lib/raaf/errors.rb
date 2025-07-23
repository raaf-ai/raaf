# frozen_string_literal: true

module RAAF

  ##
  # Base error class for all RAAF exceptions
  #
  # All custom exceptions in the RAAF library inherit from this class,
  # allowing for easy rescue of any library-specific errors.
  #
  # @example Rescue any RAAF error
  #   begin
  #     agent.run("Hello")
  #   rescue RAAF::Error => e
  #     puts "RAAF error: #{e.message}"
  #   end
  class Error < StandardError; end

  ##
  # Raised when agent operations fail
  #
  # This exception is raised when agent configuration is invalid,
  # initialization fails, or other agent-related operations encounter errors.
  #
  # @example
  #   raise AgentError, "Agent configuration is invalid: missing API key"
  class AgentError < Error; end

  ##
  # Raised when tool execution fails or tool is not found
  #
  # This exception covers tool-related failures including missing tools,
  # invalid tool parameters, and runtime execution errors.
  #
  # @example Tool not found
  #   raise ToolError, "Tool 'calculator' not found"
  #
  # @example Tool execution failure
  #   raise ToolError, "Tool 'weather_api' execution failed: #{error}"
  class ToolError < Error; end

  ##
  # Raised when agent handoff operations fail
  #
  # This exception is raised when handoff configuration is invalid,
  # target agents are not found, or handoff execution fails.
  #
  # @example Handoff target not found
  #   raise HandoffError, "Cannot handoff to non-existent agent 'unknown'"
  #
  # @example Invalid handoff configuration
  #   raise HandoffError, "Handoff must be an Agent or Handoff object"
  class HandoffError < Error; end

  ##
  # Raised when tracing operations encounter errors
  #
  # This exception covers tracing initialization failures, span creation errors,
  # and other tracing-related issues.
  #
  # @example Tracing initialization failure
  #   raise TracingError, "Failed to initialize tracer: #{error}"
  class TracingError < Error; end

  ##
  # Raised when agent exceeds maximum allowed turns
  #
  # This exception prevents infinite loops by limiting the number of
  # conversation turns an agent can take.
  #
  # @example
  #   raise MaxTurnsError, "Maximum turns (10) exceeded"
  class MaxTurnsError < Error; end

  ##
  # Raised when batch processing operations fail
  #
  # This exception covers batch submission failures, processing errors,
  # and batch result retrieval issues.
  #
  # @example Batch submission failure
  #   raise BatchError, "Failed to submit batch: #{error}"
  class BatchError < Error; end

  ##
  # Raised when API authentication fails
  #
  # This exception is raised when API keys are invalid, missing, or expired.
  #
  # @example
  #   raise AuthenticationError, "Invalid API key provided"
  class AuthenticationError < Error
    attr_reader :status
    
    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  ##
  # Raised when API rate limits are exceeded
  #
  # This exception indicates that the API request rate has exceeded
  # the allowed limits and requests should be retried later.
  #
  # @example
  #   raise RateLimitError, "Rate limit exceeded. Retry after 60 seconds"
  class RateLimitError < Error
    attr_reader :status
    
    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  ##
  # Raised when the API server encounters an error
  #
  # This exception covers server-side errors including 5xx HTTP status codes
  # and other server-related failures.
  #
  # @example
  #   raise ServerError, "API server error (status 500): #{response}"
  class ServerError < Error
    attr_reader :status
    
    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  ##
  # Raised when API requests fail due to client or server errors
  #
  # This is a general exception for API-related failures that don't
  # fall into more specific categories.
  #
  # @example
  #   raise APIError, "API request failed: #{response}"
  class APIError < Error
    attr_reader :status
    
    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  ##
  # Raised when agent execution is stopped by user request
  #
  # This exception is raised when a stop condition is triggered during
  # agent execution, allowing for graceful termination.
  #
  # @example
  #   raise ExecutionStoppedError, "Execution stopped by user request"
  class ExecutionStoppedError < Error; end

  ##
  # Raised when AI model behavior is unexpected or invalid
  #
  # This exception is raised when the AI model produces output that doesn't
  # conform to expected formats, violates constraints, or exhibits unexpected behavior.
  #
  # @example Invalid tool input format
  #   raise ModelBehaviorError, "Model provided invalid JSON for tool parameters"
  #
  # @example Constraint violation
  #   raise ModelBehaviorError, "Model output violates content policy"
  class ModelBehaviorError < Error; end

  ##
  # Raised when provider operations fail
  #
  # This exception is raised when provider initialization fails, unsupported
  # operations are requested, or provider-specific errors occur.
  #
  # @example Provider doesn't support required API
  #   raise ProviderError, "Provider doesn't support any known completion API"
  #
  # @example Provider configuration error
  #   raise ProviderError, "Provider initialization failed: #{error}"
  class ProviderError < Error; end

  ##
  # Raised when API requests are invalid or malformed
  #
  # This exception is raised when request parameters are invalid,
  # missing required fields, or violate API constraints.
  #
  # @example
  #   raise InvalidRequestError, "Invalid model specified"
  class InvalidRequestError < Error
    attr_reader :status
    
    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

end
