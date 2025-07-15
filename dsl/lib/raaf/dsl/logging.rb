# frozen_string_literal: true

# Unified logging framework that integrates with the OpenAI Agents library
#
# This module provides a consistent logging interface across the AI Agent DSL framework,
# leveraging the OpenAI Agents tracing capabilities when available and falling back
# to standard Rails logging when not.
#
# Key features:
# - Structured logging with consistent format
# - Integration with OpenAI Agents tracer for distributed tracing
# - Automatic context enrichment with agent/tool/prompt metadata
# - Configurable log levels and output formats
# - Performance metrics and execution timing
# - Error tracking with stack traces
#
# @example Basic usage
#   class MyAgent < AiAgentDsl::Agents::Base
#     include AiAgentDsl::Logging
#
#     def run
#       log_info("Agent execution started", { agent: agent_name })
#       # ... agent logic ...
#       log_info("Agent execution completed", { success: true })
#     end
#   end
#
# @example With tracing
#   trace_span("agent_execution", { agent: agent_name }) do |span|
#     log_debug("Processing request", { params: params })
#     result = process_request(params)
#     span.set_attribute("result.success", result[:success])
#     result
#   end
#
# @since 0.1.0
module AiAgentDsl::Logging
  extend ActiveSupport::Concern

  # Log levels matching standard logging conventions
  LOG_LEVELS = {
    debug: 0,
    info:  1,
    warn:  2,
    error: 3,
    fatal: 4
  }.freeze

  included do
    # Include instance methods for logging
    include InstanceMethods
  end

  module ClassMethods
    # Configure logging for this class
    #
    # @param options [Hash] Logging configuration options
    # @option options [Symbol] :level Minimum log level (:debug, :info, :warn, :error, :fatal)
    # @option options [Boolean] :enable_tracing Enable OpenAI Agents tracing (default: auto-detect)
    # @option options [String] :component_name Override component name for logs
    # @option options [Hash] :default_metadata Default metadata to include in all logs
    #
    # @example
    #   class MyAgent < AiAgentDsl::Agents::Base
    #     include AiAgentDsl::Logging
    #     configure_logging level: :info, component_name: "MyAgent"
    #   end
    #
    def configure_logging(options = {})
      @logging_config = {
        level:            options[:level] || :info,
        enable_tracing:   options[:enable_tracing],
        component_name:   options[:component_name] || name.split("::").last,
        default_metadata: options[:default_metadata] || {}
      }
    end

    # Get the logging configuration for this class
    def logging_config
      @logging_config ||= {
        level:            :info,
        enable_tracing:   nil, # Auto-detect
        component_name:   name.split("::").last,
        default_metadata: {}
      }
    end

    # Class-level logging methods
    LOG_LEVELS.each_key do |level|
      define_method("log_#{level}") do |message, metadata = {}|
        AiAgentDsl::Logging.log(level, message, metadata.merge(
          component: logging_config[:component_name],
          **logging_config[:default_metadata]
        ))
      end
    end
  end

  module InstanceMethods
    # Instance-level logging methods with automatic context enrichment
    LOG_LEVELS.each_key do |level|
      define_method("log_#{level}") do |message, metadata = {}|
        enriched_metadata = enrich_log_metadata(metadata)
        AiAgentDsl::Logging.log(level, message, enriched_metadata)
      end
    end

    # Create a traced span with logging integration
    #
    # @param span_name [String] Name of the span for tracing
    # @param metadata [Hash] Additional metadata for the span and logs
    # @yield [span] Block to execute within the span
    # @yieldparam span [Object] The tracer span object
    # @return [Object] Result of the yielded block
    #
    # @example
    #   result = trace_span("agent_execution", { agent: agent_name }) do |span|
    #     log_info("Starting execution")
    #     result = perform_work()
    #     span.set_attribute("result.success", result[:success])
    #     log_info("Execution completed", { success: result[:success] })
    #     result
    #   end
    #
    def trace_span(span_name, metadata = {})
      if tracing_enabled? && openai_tracer_available?
        tracer = OpenAIAgents.tracer
        enriched_metadata = enrich_log_metadata(metadata)

        tracer.custom_span(span_name, enriched_metadata) do |span|
          # Add standard attributes
          span.set_attribute("component.name", component_name)
          span.set_attribute("component.class", self.class.name)

          # Add custom metadata as attributes
          enriched_metadata.each do |key, value|
            span.set_attribute(key.to_s, value.to_s) if value
          end

          log_debug("Trace span started", { span: span_name, **enriched_metadata })

          begin
            result = yield(span)
            span.set_attribute("execution.success", true)
            log_debug("Trace span completed", { span: span_name, success: true })
            result
          rescue StandardError => e
            span.set_attribute("execution.success", false)
            span.set_status(:error, description: e.message)
            span.record_exception(e) if span.respond_to?(:record_exception)
            log_error("Trace span failed", {
              span:        span_name,
              error:       e.message,
              error_class: e.class.name,
              **enriched_metadata
            })
            raise
          end
        end
      else
        # Fallback to regular execution with logging
        log_debug("Executing without tracing", { operation: span_name, **metadata })
        yield(nil)
      end
    end

    # Log execution timing for operations
    #
    # @param operation_name [String] Name of the operation being timed
    # @param metadata [Hash] Additional metadata to include
    # @yield Block to execute and time
    # @return [Object] Result of the yielded block
    #
    # @example
    #   result = log_execution_time("database_query") do
    #     User.where(active: true).limit(100).to_a
    #   end
    #
    def log_execution_time(operation_name, metadata = {})
      start_time = Time.current
      log_debug("Operation started", { operation: operation_name, **metadata })

      begin
        result = yield
        execution_time = Time.current - start_time

        log_info("Operation completed", {
          operation:   operation_name,
          duration_ms: (execution_time * 1000).round(2),
          success:     true,
          **metadata
        })

        result
      rescue StandardError => e
        execution_time = Time.current - start_time

        log_error("Operation failed", {
          operation:   operation_name,
          duration_ms: (execution_time * 1000).round(2),
          error:       e.message,
          error_class: e.class.name,
          **metadata
        })

        raise
      end
    end

    # Check if tracing is enabled for this instance
    def tracing_enabled?
      config = self.class.logging_config
      if config[:enable_tracing].nil?
        # Auto-detect based on OpenAI Agents availability and Rails environment
        openai_tracer_available? && (!defined?(Rails) || !Rails.env.test?)
      else
        config[:enable_tracing]
      end
    end

    # Check if OpenAI Agents tracer is available
    def openai_tracer_available?
      defined?(OpenAIAgents) && OpenAIAgents.respond_to?(:tracer)
    end

    # Get the component name for logging
    def component_name
      self.class.logging_config[:component_name]
    end

    private

    # Enrich log metadata with context information
    def enrich_log_metadata(metadata)
      base_metadata = {
        component:       component_name,
        component_class: self.class.name,
        timestamp:       Time.current.iso8601,
        thread_id:       Thread.current.object_id
      }

      # Add agent-specific context if available
      base_metadata[:agent_name] = agent_name if respond_to?(:agent_name, true)

      base_metadata[:tool_name] = tool_name if respond_to?(:tool_name, true)

      # Add debugging context if available
      base_metadata[:debug_enabled] = @debug_enabled if instance_variable_defined?(:@debug_enabled)

      # Add execution context if available
      if respond_to?(:context, true) && context.respond_to?(:to_h)
        base_metadata[:context_keys] = context.to_h.keys
        base_metadata[:context_size] = context.size if context.respond_to?(:size)
      end

      # Merge with class default metadata and provided metadata
      class_defaults = self.class.logging_config[:default_metadata]
      base_metadata.merge(class_defaults).merge(metadata)
    end
  end

  # Module-level logging methods for standalone usage
  class << self
    # Main logging method that handles output routing
    #
    # @param level [Symbol] Log level (:debug, :info, :warn, :error, :fatal)
    # @param message [String] Log message
    # @param metadata [Hash] Additional structured data
    #
    def log(level, message, metadata = {})
      return unless should_log?(level)

      formatted_entry = format_log_entry(level, message, metadata)

      if rails_logger_available?
        # Use Rails logger with structured format
        Rails.logger.send(level, formatted_entry)
      else
        # Fallback to standard output with timestamp
        timestamp = Time.current.strftime("%Y-%m-%d %H:%M:%S.%3N")
        puts "[#{timestamp}] [#{level.upcase}] #{formatted_entry}"
      end
    end

    # Convenience methods for different log levels
    LOG_LEVELS.each_key do |level|
      define_method(level) do |message, metadata = {}|
        log(level, message, metadata)
      end
    end

    # Configure global logging settings
    #
    # @param options [Hash] Global logging configuration
    # @option options [Symbol] :level Global minimum log level
    # @option options [Boolean] :structured Enable structured logging format
    # @option options [String] :format Log format string
    #
    def configure(options = {})
      @global_config = {
        level:      options[:level] || :info,
        structured: options[:structured] != false,
        format:     options[:format] || default_format
      }.merge(options)
    end

    # Get global logging configuration
    def global_config
      @global_config ||= {
        level:      :info,
        structured: true,
        format:     default_format
      }
    end

    private

    # Check if we should log at this level
    def should_log?(level)
      global_level = global_config[:level]
      LOG_LEVELS[level] >= LOG_LEVELS[global_level]
    end

    # Format a log entry for output
    def format_log_entry(_level, message, metadata)
      if global_config[:structured] && metadata.any?
        # Structured format with metadata
        metadata_str = metadata.map { |k, v| "#{k}=#{format_value(v)}" }.join(" ")
        "[#{metadata[:component] || 'AiAgentDsl'}] #{message} #{metadata_str}"
      else
        # Simple format
        component = metadata[:component] || "AiAgentDsl"
        "[#{component}] #{message}"
      end
    end

    # Format values for log output
    def format_value(value)
      case value
      when String
        value.include?(" ") ? "\"#{value}\"" : value
      when Hash
        value.to_json
      when Array
        "[#{value.join(',')}]"
      when Time
        value.iso8601
      else
        value.to_s
      end
    end

    # Check if Rails logger is available
    def rails_logger_available?
      defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
    end

    # Default log format
    def default_format
      "%<timestamp>s [%<level>s] [%<component>s] %<message>s %<metadata>s"
    end
  end
end
