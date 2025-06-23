# frozen_string_literal: true

module OpenAIAgents
  class Error < StandardError; end

  class AgentError < Error; end

  class ToolError < Error; end

  class HandoffError < Error; end

  class TracingError < Error; end

  class MaxTurnsError < Error; end

  class BatchError < Error; end

  class AuthenticationError < Error; end

  class RateLimitError < Error; end

  class ServerError < Error; end

  class APIError < Error; end
end
