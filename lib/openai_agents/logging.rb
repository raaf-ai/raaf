# frozen_string_literal: true

require "logger"
require "fileutils"
require "json"
require "securerandom"

module OpenAIAgents
  ##
  # Logger mixin provides convenient logging methods to any class
  #
  # This module provides a comprehensive set of logging methods that can be
  # included in any class to enable structured logging with support for:
  # - Standard log levels (debug, info, warn, error, fatal)
  # - Category-based debug filtering
  # - Structured context data
  # - Agent-specific logging helpers
  # - Performance benchmarking
  #
  # The Logger module works in conjunction with the Logging module to provide
  # a unified logging system across the OpenAI Agents framework.
  #
  # @example Basic usage
  #   class MyClass
  #     include OpenAIAgents::Logger
  #
  #     def process_data
  #       log_info("Starting process", user_id: 123)
  #       log_debug("Processing data", rows: 1000)
  #       
  #       begin
  #         # do work
  #       rescue => e
  #         log_error("Process failed", error: e.message, user_id: 123)
  #       end
  #     end
  #   end
  #
  # @example Category-specific debug logging
  #   class APIClient
  #     include OpenAIAgents::Logger
  #
  #     def make_request(url)
  #       log_debug_api("Making API request", url: url, method: "GET")
  #       # Only shown when :api debug category is enabled
  #     end
  #   end
  #
  # @example Performance benchmarking
  #   log_benchmark("Database query", query: "SELECT * FROM users") do
  #     # Performs operation and logs timing
  #     database.execute(query)
  #   end
  #
  module Logger
    ##
    # Log a debug message with optional category filtering
    #
    # @param message [String] The message to log
    # @param category [Symbol] Debug category for filtering (default: :general)
    # @param context [Hash] Additional structured data to include
    #
    def log_debug(message, category: :general, **context)
      OpenAIAgents::Logging.debug(message, category: category, **context)
    end

    ##
    # Log an informational message
    #
    # @param message [String] The message to log
    # @param context [Hash] Additional structured data to include
    #
    def log_info(message, **context)
      OpenAIAgents::Logging.info(message, **context)
    end

    ##
    # Log a warning message
    #
    # @param message [String] The message to log
    # @param context [Hash] Additional structured data to include
    #
    def log_warn(message, **context)
      OpenAIAgents::Logging.warn(message, **context)
    end

    ##
    # Log an error message
    #
    # @param message [String] The message to log
    # @param context [Hash] Additional structured data to include
    #
    def log_error(message, **context)
      OpenAIAgents::Logging.error(message, **context)
    end

    ##
    # Log a fatal error message
    #
    # @param message [String] The message to log
    # @param context [Hash] Additional structured data to include
    #
    def log_fatal(message, **context)
      OpenAIAgents::Logging.fatal(message, **context)
    end

    ##
    # Log a debug message for tracing operations
    # Only shown when :tracing debug category is enabled
    #
    # @param message [String] The message to log
    # @param context [Hash] Additional structured data
    #
    def log_debug_tracing(message, **context)
      OpenAIAgents::Logging.debug(message, category: :tracing, **context)
    end

    ##
    # Log a debug message for API operations
    # Only shown when :api debug category is enabled
    #
    # @param message [String] The message to log
    # @param context [Hash] Additional structured data
    #
    def log_debug_api(message, **context)
      OpenAIAgents::Logging.debug(message, category: :api, **context)
    end

    ##
    # Log a debug message for tool operations
    # Only shown when :tools debug category is enabled
    #
    # @param message [String] The message to log
    # @param context [Hash] Additional structured data
    #
    def log_debug_tools(message, **context)
      OpenAIAgents::Logging.debug(message, category: :tools, **context)
    end

    ##
    # Log a debug message for agent handoffs
    # Only shown when :handoff debug category is enabled
    #
    # @param message [String] The message to log
    # @param context [Hash] Additional structured data
    #
    def log_debug_handoff(message, **context)
      OpenAIAgents::Logging.debug(message, category: :handoff, **context)
    end

    ##
    # Log a debug message for context operations
    # Only shown when :context debug category is enabled
    #
    # @param message [String] The message to log
    # @param context [Hash] Additional structured data
    #
    def log_debug_context(message, **context)
      OpenAIAgents::Logging.debug(message, category: :context, **context)
    end

    ##
    # Log a debug message for HTTP operations
    # Only shown when :http debug category is enabled
    #
    # @param message [String] The message to log
    # @param context [Hash] Additional structured data
    #
    def log_debug_http(message, **context)
      OpenAIAgents::Logging.debug(message, category: :http, **context)
    end

    ##
    # Check if HTTP debug logging is enabled
    #
    # @return [Boolean] true if :http debug category is enabled
    #
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

  ##
  # Unified logging system for OpenAI Agents framework
  #
  # The Logging module provides a centralized, structured logging interface that:
  # - Automatically integrates with Rails when available
  # - Supports multiple output formats (text, JSON)
  # - Enables category-based debug filtering
  # - Provides specialized methods for agent operations
  # - Maintains consistent log structure across the framework
  #
  # @example Basic logging
  #   OpenAIAgents::Logging.info("Agent started", agent: "GPT-4", run_id: "123")
  #   OpenAIAgents::Logging.debug("Tool called", tool: "search", category: :tools)
  #   OpenAIAgents::Logging.error("API error", error: e.message, status: 500)
  #
  # @example Configuration
  #   OpenAIAgents::Logging.configure do |config|
  #     config.log_level = :debug
  #     config.log_format = :json
  #     config.debug_categories = [:api, :tools]
  #   end
  #
  # @example Category-based debugging
  #   # Enable only specific debug categories
  #   ENV['OPENAI_AGENTS_DEBUG_CATEGORIES'] = 'api,tracing'
  #   
  #   # These will be shown:
  #   OpenAIAgents::Logging.debug("API call", category: :api)
  #   OpenAIAgents::Logging.debug("Span created", category: :tracing)
  #   
  #   # This will be hidden:
  #   OpenAIAgents::Logging.debug("Tool details", category: :tools)
  #
  # ## Environment Variables
  #
  # - `OPENAI_AGENTS_LOG_LEVEL` - Set log level (debug, info, warn, error, fatal)
  # - `OPENAI_AGENTS_LOG_FORMAT` - Output format (text, json)
  # - `OPENAI_AGENTS_LOG_OUTPUT` - Output destination (console, file, rails, auto)
  # - `OPENAI_AGENTS_DEBUG_CATEGORIES` - Enabled debug categories (all, none, or comma-separated)
  #
  # ## Debug Categories
  #
  # - `:tracing` - Span lifecycle, trace processing
  # - `:api` - API calls, responses, HTTP details
  # - `:tools` - Tool execution, function calls
  # - `:handoff` - Agent handoffs, delegation
  # - `:context` - Context management, memory
  # - `:http` - Detailed HTTP debug output
  # - `:general` - General debug messages
  #
  module Logging
    class << self
      ##
      # Configure the logging system
      #
      # @yield [config] Configuration block
      # @yieldparam config [Configuration] The configuration object
      # @return [Configuration] The current configuration
      #
      # @example
      #   OpenAIAgents::Logging.configure do |config|
      #     config.log_level = :debug
      #     config.log_format = :json
      #     config.debug_categories = [:api, :tracing]
      #   end
      #
      def configure
        @configuration ||= Configuration.new
        yield(@configuration) if block_given?
        @configuration
      end

      ##
      # Get current logging configuration
      #
      # @return [Configuration] The current configuration object
      #
      def configuration
        @configuration ||= Configuration.new
      end

      ##
      # Log a debug message with category filtering
      #
      # @param message [String] The message to log
      # @param category [Symbol] Debug category for filtering
      # @param context [Hash] Additional structured data
      # @return [void]
      #
      def debug(message, category: :general, **context)
        return unless configuration.debug_enabled?(category)

        log(:debug, message, category: category, **context)
      end

      ##
      # Log an informational message
      #
      # @param message [String] The message to log
      # @param context [Hash] Additional structured data
      # @return [void]
      #
      def info(message, **context)
        log(:info, message, **context)
      end

      ##
      # Log a warning message
      #
      # @param message [String] The message to log
      # @param context [Hash] Additional structured data
      # @return [void]
      #
      def warn(message, **context)
        log(:warn, message, **context)
      end

      ##
      # Log an error message
      #
      # @param message [String] The message to log
      # @param context [Hash] Additional structured data
      # @return [void]
      #
      def error(message, **context)
        log(:error, message, **context)
      end

      ##
      # Log a fatal error message
      #
      # @param message [String] The message to log
      # @param context [Hash] Additional structured data
      # @return [void]
      #
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
