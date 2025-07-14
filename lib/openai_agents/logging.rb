# frozen_string_literal: true

require "logger"
require "fileutils"
require "json"
require "securerandom"

module OpenAIAgents
  # Mixin module for short logging methods
  #
  # Include this module to get short logging methods like log_info, log_debug, etc.
  #
  # @example
  #   class MyClass
  #     include OpenAIAgents::Logger
  #
  #     def some_method
  #       log_info("Starting process", user_id: 123)
  #       log_debug("Processing data", rows: 1000)
  #       log_error("Failed", error: e.message)
  #     end
  #   end
  module Logger
    def log_debug(message, category: :general, **context)
      OpenAIAgents::Logging.debug(message, category: category, **context)
    end

    def log_info(message, **context)
      OpenAIAgents::Logging.info(message, **context)
    end

    def log_warn(message, **context)
      OpenAIAgents::Logging.warn(message, **context)
    end

    def log_error(message, **context)
      OpenAIAgents::Logging.error(message, **context)
    end

    def log_fatal(message, **context)
      OpenAIAgents::Logging.fatal(message, **context)
    end

    # Category-specific debug methods
    def log_debug_tracing(message, **context)
      OpenAIAgents::Logging.debug(message, category: :tracing, **context)
    end

    def log_debug_api(message, **context)
      OpenAIAgents::Logging.debug(message, category: :api, **context)
    end

    def log_debug_tools(message, **context)
      OpenAIAgents::Logging.debug(message, category: :tools, **context)
    end

    def log_debug_handoff(message, **context)
      OpenAIAgents::Logging.debug(message, category: :handoff, **context)
    end

    def log_debug_context(message, **context)
      OpenAIAgents::Logging.debug(message, category: :context, **context)
    end

    def log_debug_http(message, **context)
      OpenAIAgents::Logging.debug(message, category: :http, **context)
    end

    def http_debug_enabled?
      OpenAIAgents::Logging.configuration.debug_enabled?(:http)
    end

    # Utility methods
    def log_benchmark(label, **context, &)
      OpenAIAgents::Logging.benchmark(label, **context, &)
    end

    # Agent-specific logging methods
    def log_agent_start(agent_name, **context)
      OpenAIAgents::Logging.agent_start(agent_name, **context)
    end

    def log_agent_end(agent_name, **context)
      OpenAIAgents::Logging.agent_end(agent_name, **context)
    end

    def log_tool_call(tool_name, **context)
      OpenAIAgents::Logging.tool_call(tool_name, **context)
    end

    def log_handoff(from_agent, to_agent, **context)
      OpenAIAgents::Logging.handoff(from_agent, to_agent, **context)
    end

    def log_api_call(method, url, **context)
      OpenAIAgents::Logging.api_call(method, url, **context)
    end

    def log_api_error(error, **context)
      OpenAIAgents::Logging.api_error(error, **context)
    end
  end

  # Unified logging system for OpenAI Agents
  #
  # This module provides a centralized logging interface that automatically
  # integrates with Rails logging when available, falls back to console
  # logging otherwise, and provides structured logging for agent operations.
  #
  # ## Usage
  #
  # ```ruby
  # OpenAIAgents::Logging.info("Agent started", agent: "GPT-4", run_id: "123")
  # OpenAIAgents::Logging.debug("Tool called", tool: "search", params: {...})
  # OpenAIAgents::Logging.error("API error", error: e, request_id: "456")
  # ```
  #
  # ## Configuration
  #
  # Environment variables:
  # - OPENAI_AGENTS_LOG_LEVEL: debug, info, warn, error (default: info)
  # - OPENAI_AGENTS_LOG_FORMAT: json, text (default: text)
  # - OPENAI_AGENTS_LOG_OUTPUT: console, file, rails (default: auto)
  # - OPENAI_AGENTS_DEBUG_CATEGORIES: all, none, or comma-separated categories (default: all)
  #   Available categories: tracing, api, tools, handoff, context, http, general
  #
  module Logging
    class << self
      # Configure logging system
      def configure
        @configuration ||= Configuration.new
        yield(@configuration) if block_given?
        @configuration
      end

      # Get current configuration
      def configuration
        @configuration ||= Configuration.new
      end

      # Main logging methods
      def debug(message, category: :general, **context)
        return unless configuration.debug_enabled?(category)

        log(:debug, message, category: category, **context)
      end

      def info(message, **context)
        log(:info, message, **context)
      end

      def warn(message, **context)
        log(:warn, message, **context)
      end

      def error(message, **context)
        log(:error, message, **context)
      end

      def fatal(message, **context)
        log(:fatal, message, **context)
      end

      # Specialized logging methods
      def agent_start(agent_name, **context)
        info("Agent started", agent: agent_name, **context)
      end

      def agent_end(agent_name, duration: nil, **context)
        info("Agent completed", agent: agent_name, duration_ms: duration, **context)
      end

      def tool_call(tool_name, **context)
        debug("Tool called", tool: tool_name, **context)
      end

      def handoff(from_agent, to_agent, **context)
        info("Agent handoff", from: from_agent, to: to_agent, **context)
      end

      def api_call(method, url, duration: nil, **context)
        debug("API call", method: method, url: url, duration_ms: duration, **context)
      end

      def api_error(error, **context)
        error("API error", error: error.message, error_class: error.class.name, **context)
      end

      # Benchmark utility method
      def benchmark(label, **context)
        return yield unless should_log?(:info)

        start_time = Time.now
        result = yield
        duration = Time.now - start_time

        info("BENCHMARK [#{label}]: #{duration.round(3)}s", duration_ms: (duration * 1000).round(2), **context)
        result
      end

      private

      def log(level, message, **context)
        return unless should_log?(level)

        logger.send(level, format_message(message, **context))
      end

      def should_log?(level)
        level_priority(level) >= level_priority(configuration.log_level)
      end

      def level_priority(level)
        { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }[level.to_sym] || 1
      end

      def logger
        @logger ||= create_logger
      end

      def create_logger
        case configuration.log_output
        when :rails
          rails_logger
        when :file
          file_logger
        when :console
          console_logger
        else
          auto_logger
        end
      end

      def auto_logger
        if defined?(Rails) && Rails.logger
          rails_logger
        else
          console_logger
        end
      end

      def rails_logger
        if defined?(Rails) && Rails.logger
          RailsLoggerAdapter.new(Rails.logger, configuration)
        else
          console_logger
        end
      end

      def console_logger
        ConsoleLoggerAdapter.new(configuration)
      end

      def file_logger
        FileLoggerAdapter.new(configuration)
      end

      def format_message(message, **context)
        if configuration.log_format == :json
          format_json(message, **context)
        else
          format_text(message, **context)
        end
      end

      def format_json(message, **context)
        {
          message: message,
          timestamp: Time.now.utc.iso8601,
          source: "openai_agents",
          **context
        }.to_json
      end

      def format_text(message, **context)
        if context.any?
          context_str = context.map { |k, v| "#{k}=#{v}" }.join(" ")
          "[OpenAI Agents] #{message} #{context_str}"
        else
          "[OpenAI Agents] #{message}"
        end
      end
    end

    # Configuration class
    class Configuration
      attr_accessor :log_level, :log_format, :log_output, :log_file, :debug_categories

      def initialize
        @log_level = ENV.fetch("OPENAI_AGENTS_LOG_LEVEL", "info").to_sym
        @log_format = ENV.fetch("OPENAI_AGENTS_LOG_FORMAT", "text").to_sym
        @log_output = ENV.fetch("OPENAI_AGENTS_LOG_OUTPUT", "auto").to_sym
        @log_file = ENV.fetch("OPENAI_AGENTS_LOG_FILE", "log/openai_agents.log")

        # Debug categories - can be set via environment or configuration
        # Examples: "tracing,api" or "all" or "none"
        debug_env = ENV.fetch("OPENAI_AGENTS_DEBUG_CATEGORIES", "all")
        @debug_categories = parse_debug_categories(debug_env)
      end

      def debug_enabled?(category)
        return true if @debug_categories.include?(:all)
        return false if @debug_categories.include?(:none)

        @debug_categories.include?(category.to_sym)
      end

      private

      def parse_debug_categories(env_value)
        return [:all] if env_value.downcase == "all"
        return [:none] if env_value.downcase == "none"

        env_value.split(",").map(&:strip).map(&:to_sym)
      end
    end

    # Rails logger adapter
    class RailsLoggerAdapter
      def initialize(rails_logger, config)
        @rails_logger = rails_logger
        @config = config
      end

      def debug(message)
        @rails_logger.debug(message)
      end

      def info(message)
        @rails_logger.info(message)
      end

      def warn(message)
        @rails_logger.warn(message)
      end

      def error(message)
        @rails_logger.error(message)
      end

      def fatal(message)
        @rails_logger.fatal(message)
      end
    end

    # Console logger adapter
    class ConsoleLoggerAdapter
      def initialize(config)
        @config = config
      end

      def debug(message)
        puts "[DEBUG] #{message}" if @config.log_level == :debug
      end

      def info(message)
        puts "[INFO] #{message}"
      end

      def warn(message)
        puts "[WARN] #{message}"
      end

      def error(message)
        puts "[ERROR] #{message}"
      end

      def fatal(message)
        puts "[FATAL] #{message}"
      end
    end

    # File logger adapter
    class FileLoggerAdapter
      def initialize(config)
        @config = config
        @logger = create_file_logger
      end

      def debug(message)
        @logger.debug(message)
      end

      def info(message)
        @logger.info(message)
      end

      def warn(message)
        @logger.warn(message)
      end

      def error(message)
        @logger.error(message)
      end

      def fatal(message)
        @logger.fatal(message)
      end

      private

      def create_file_logger
        require "logger"

        # Ensure directory exists
        log_dir = File.dirname(@config.log_file)
        FileUtils.mkdir_p(log_dir)

        logger = Logger.new(@config.log_file, 5, 10 * 1024 * 1024) # 10MB
        logger.level = Logger.const_get(@config.log_level.to_s.upcase)
        logger.formatter = proc do |severity, datetime, _progname, msg|
          "[#{datetime.strftime("%Y-%m-%d %H:%M:%S")}] #{severity}: #{msg}\n"
        end
        logger
      end
    end
  end
end
