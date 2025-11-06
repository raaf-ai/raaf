# frozen_string_literal: true

module RAAF
  module Eval
    # Base error class for RAAF Eval
    class Error < StandardError; end

    # Error raised when span serialization fails
    class SerializationError < Error; end

    # Error raised when span deserialization fails
    class DeserializationError < Error; end

    # Error raised when evaluation execution fails
    class ExecutionError < Error; end

    # Error raised when metric calculation fails
    class MetricError < Error; end

    # Error raised when configuration is invalid
    class ConfigurationError < Error; end

    # Error raised when database operations fail
    class DatabaseError < Error; end
  end
end
