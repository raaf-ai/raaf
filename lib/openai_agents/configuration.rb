# frozen_string_literal: true

require "yaml"
require "json"
require_relative "logging"

module OpenAIAgents
  ##
  # Configuration - Environment-based configuration management system
  #
  # Provides centralized configuration management for OpenAI Agents with support for
  # environment variables, configuration files, and runtime overrides. Supports
  # multiple environments (development, test, production) and secure credential handling.
  #
  # == Features
  #
  # * Environment-based configuration (development, test, production)
  # * Multiple configuration sources (ENV, YAML, JSON)
  # * Secure credential management
  # * Configuration validation
  # * Runtime configuration updates
  # * Configuration inheritance and merging
  # * Type coercion and validation
  #
  # == Basic Usage
  #
  #   # Load configuration
  #   config = OpenAIAgents::Configuration.new
  #
  #   # Access configuration values
  #   config.openai.api_key        # => "sk-..."
  #   config.agent.max_turns       # => 10
  #   config.logging.level         # => "info"
  #
  # == Configuration Sources
  #
  #   # 1. Environment variables
  #   export OPENAI_API_KEY="sk-..."
  #   export OPENAI_AGENTS_MAX_TURNS="20"
  #
  #   # 2. Configuration files
  #   # config/openai_agents.yml
  #   # config/openai_agents.production.yml
  #
  #   # 3. Runtime configuration
  #   config.set("agent.max_turns", 15)
  #
  # == Environment-Specific Configuration
  #
  #   # Development environment
  #   config = OpenAIAgents::Configuration.new(environment: "development")
  #
  #   # Production environment
  #   config = OpenAIAgents::Configuration.new(environment: "production")
  #
  # @author OpenAI Agents Ruby Team
  # @since 0.1.0
  class Configuration
    include Logger
    ##
    # Default configuration values
    DEFAULT_CONFIG = {
      # Environment
      environment: "development",

      # OpenAI API Configuration
      openai: {
        api_key: nil,
        api_base: "https://api.openai.com/v1",
        organization: nil,
        timeout: 60,
        max_retries: 3
      },

      # Anthropic API Configuration
      anthropic: {
        api_key: nil,
        api_base: "https://api.anthropic.com",
        timeout: 60,
        max_retries: 3
      },

      # Gemini API Configuration
      gemini: {
        api_key: nil,
        api_base: "https://generativelanguage.googleapis.com",
        timeout: 60,
        max_retries: 3
      },

      # Agent Configuration
      agent: {
        default_model: "gpt-4",
        max_turns: 10,
        default_instructions: nil,
        enable_streaming: false
      },

      # Tools Configuration
      tools: {
        file_search: {
          max_results: 10,
          search_paths: ["."],
          file_extensions: nil
        },
        web_search: {
          engine: "duckduckgo",
          max_results: 5,
          timeout: 30
        },
        computer: {
          allowed_actions: [:screenshot],
          safety_mode: true
        }
      },

      # Guardrails Configuration
      guardrails: {
        content_safety: {
          enabled: true,
          strict_mode: false
        },
        rate_limiting: {
          enabled: true,
          max_requests_per_minute: 60
        },
        length_validation: {
          enabled: true,
          max_input_length: 10_000,
          max_output_length: 5000
        }
      },

      # Tracing Configuration
      tracing: {
        enabled: true,
        processors: ["console"],
        export_format: "json",
        max_spans_per_trace: 1000,
        trace_include_sensitive_data: false,
        detailed_tool_tracing: true,
        capture_openai_tool_results: true
      },

      # Logging Configuration
      logging: {
        level: "info",
        output: "stdout",
        format: "text",
        file: nil
      },

      # Voice Configuration
      voice: {
        transcription_model: "whisper-1",
        tts_model: "tts-1",
        voice: "alloy",
        language: nil
      },

      # REPL Configuration
      repl: {
        history_file: "~/.openai_agents_history",
        auto_save: true,
        debug_mode: false
      },

      # Cache Configuration
      cache: {
        enabled: false,
        ttl: 3600,
        max_size: 1000,
        storage: "memory"
      }
    }.freeze

    ##
    # Environment variable mappings
    ENV_MAPPINGS = {
      "OPENAI_API_KEY" => "openai.api_key",
      "OPENAI_API_BASE" => "openai.api_base",
      "OPENAI_ORGANIZATION" => "openai.organization",
      "ANTHROPIC_API_KEY" => "anthropic.api_key",
      "ANTHROPIC_API_BASE" => "anthropic.api_base",
      "GEMINI_API_KEY" => "gemini.api_key",
      "OPENAI_AGENTS_ENVIRONMENT" => "environment",
      "OPENAI_AGENTS_MAX_TURNS" => "agent.max_turns",
      "OPENAI_AGENTS_DEFAULT_MODEL" => "agent.default_model",
      "OPENAI_AGENTS_LOG_LEVEL" => "logging.level",
      "OPENAI_AGENTS_DEBUG" => "repl.debug_mode"
    }.freeze

    attr_reader :environment, :config_data, :config_paths

    ##
    # Creates a new Configuration instance
    #
    # @param environment [String] configuration environment (default: from ENV or "development")
    # @param config_paths [Array<String>] paths to search for configuration files
    # @param auto_load [Boolean] whether to automatically load configuration (default: true)
    #
    # @example Create default configuration
    #   config = OpenAIAgents::Configuration.new
    #
    # @example Create production configuration
    #   config = OpenAIAgents::Configuration.new(environment: "production")
    #
    # @example Custom configuration paths
    #   config = OpenAIAgents::Configuration.new(
    #     config_paths: ["./config", "/etc/openai_agents"]
    #   )
    def initialize(environment: nil, config_paths: nil, auto_load: true)
      @environment = environment || ENV["OPENAI_AGENTS_ENVIRONMENT"] || "development"
      @config_paths = config_paths || default_config_paths
      @config_data = {}
      @watchers = []

      load_configuration if auto_load
    end

    ##
    # Loads configuration from all sources
    #
    # Loads configuration in the following order:
    # 1. Default configuration
    # 2. Base configuration files
    # 3. Environment-specific configuration files
    # 4. Environment variables
    # 5. Runtime overrides
    #
    # @return [void]
    #
    # @example Reload configuration
    #   config.load_configuration
    def load_configuration
      # Start with default configuration
      @config_data = deep_dup(DEFAULT_CONFIG)

      # Load base configuration files
      load_config_files("openai_agents")

      # Load environment-specific configuration files
      load_config_files("openai_agents.#{@environment}")

      # Load environment variables
      load_environment_variables

      # Validate configuration
      validate_configuration

      # Notify watchers
      notify_watchers
    end

    ##
    # Gets a configuration value using dot notation
    #
    # @param key [String] configuration key in dot notation (e.g., "openai.api_key")
    # @param default [Object] default value if key is not found
    # @return [Object] configuration value or default
    #
    # @example Get simple value
    #   api_key = config.get("openai.api_key")
    #
    # @example Get with default
    #   timeout = config.get("openai.timeout", 30)
    #
    # @example Get nested value
    #   max_results = config.get("tools.file_search.max_results")
    def get(key, default = nil)
      return default if key.nil? || key.empty?

      keys = key.split(".")
      value = @config_data

      keys.each do |k|
        k = k.to_sym
        return default unless value.is_a?(Hash) && value.key?(k)

        value = value[k]
      end

      value
    end

    ##
    # Sets a configuration value using dot notation
    #
    # @param key [String] configuration key in dot notation
    # @param value [Object] value to set
    # @return [Object] the set value
    #
    # @example Set simple value
    #   config.set("openai.api_key", "sk-new-key")
    #
    # @example Set nested value
    #   config.set("agent.max_turns", 20)
    def set(key, value)
      keys = key.split(".")
      target = @config_data

      keys[0..-2].each do |k|
        k = k.to_sym
        target[k] ||= {}
        target = target[k]
      end

      last_key = keys.last.to_sym
      target[last_key] = coerce_value(value)

      notify_watchers
      value
    end

    ##
    # Provides method-based access to configuration sections
    #
    # @param method_name [Symbol] configuration section name
    # @return [ConfigurationSection] configuration section wrapper
    #
    # @example Access OpenAI configuration
    #   config.openai.api_key
    #   config.openai.timeout
    #
    # @example Access agent configuration
    #   config.agent.max_turns
    #   config.agent.default_model
    def method_missing(method_name, *args, &)
      if @config_data.key?(method_name)
        ConfigurationSection.new(@config_data[method_name], method_name.to_s, self)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      @config_data.key?(method_name) || super
    end

    ##
    # Merges additional configuration
    #
    # @param other_config [Hash] configuration hash to merge
    # @return [void]
    #
    # @example Merge runtime configuration
    #   config.merge!({
    #     agent: { max_turns: 15 },
    #     logging: { level: "debug" }
    #   })
    def merge!(other_config)
      @config_data = deep_merge(@config_data, other_config)
      validate_configuration
      notify_watchers
    end

    ##
    # Validates current configuration
    #
    # @return [Array<String>] array of validation errors
    # @raise [ConfigurationError] if validation fails and strict mode is enabled
    #
    # @example Validate configuration
    #   errors = config.validate
    #   puts "Configuration errors: #{errors}" unless errors.empty?
    def validate
      errors = []

      # Validate required API keys based on environment
      errors << "OpenAI API key is required in production" if production? && !get("openai.api_key")

      # Validate numeric values
      max_turns = get("agent.max_turns")
      errors << "agent.max_turns must be positive" if max_turns && max_turns <= 0

      # Validate URLs
      %w[openai.api_base anthropic.api_base gemini.api_base].each do |key|
        url = get(key)
        errors << "#{key} must be a valid URL" if url && !valid_url?(url)
      end

      # Validate file paths
      config_file = get("logging.file")
      errors << "logging.file directory does not exist" if config_file && !File.directory?(File.dirname(config_file))

      errors
    end

    ##
    # Checks if running in production environment
    #
    # @return [Boolean] true if environment is production
    def production?
      @environment == "production"
    end

    ##
    # Checks if running in development environment
    #
    # @return [Boolean] true if environment is development
    def development?
      @environment == "development"
    end

    ##
    # Checks if running in test environment
    #
    # @return [Boolean] true if environment is test
    def test?
      @environment == "test"
    end

    ##
    # Adds a configuration watcher
    #
    # @yield [Configuration] called when configuration changes
    # @return [void]
    #
    # @example Watch for configuration changes
    #   config.watch do |config|
    #     puts "Configuration updated!"
    #     update_loggers(config.logging.level)
    #   end
    def watch(&block)
      @watchers << block
    end

    ##
    # Exports configuration to hash
    #
    # @param include_sensitive [Boolean] whether to include sensitive values
    # @return [Hash] configuration as hash
    #
    # @example Export configuration
    #   config_hash = config.to_h
    #   puts JSON.pretty_generate(config_hash)
    def to_h(include_sensitive: false)
      if include_sensitive
        deep_dup(@config_data)
      else
        sanitize_sensitive_data(deep_dup(@config_data))
      end
    end

    ##
    # Exports configuration to YAML
    #
    # @param include_sensitive [Boolean] whether to include sensitive values
    # @return [String] configuration as YAML string
    def to_yaml(include_sensitive: false)
      YAML.dump(to_h(include_sensitive: include_sensitive))
    end

    ##
    # Exports configuration to JSON
    #
    # @param include_sensitive [Boolean] whether to include sensitive values
    # @return [String] configuration as JSON string
    def to_json(include_sensitive: false)
      JSON.pretty_generate(to_h(include_sensitive: include_sensitive))
    end

    ##
    # Saves current configuration to file
    #
    # @param file_path [String] path to save configuration
    # @param format [Symbol] format to save (:yaml or :json)
    # @param include_sensitive [Boolean] whether to include sensitive values
    # @return [void]
    #
    # @example Save configuration
    #   config.save_to_file("config/current.yml", :yaml)
    def save_to_file(file_path, format: :yaml, include_sensitive: false)
      content = case format
                when :yaml
                  to_yaml(include_sensitive: include_sensitive)
                when :json
                  to_json(include_sensitive: include_sensitive)
                else
                  raise ArgumentError, "Unsupported format: #{format}"
                end

      File.write(file_path, content)
    end

    private

    def default_config_paths
      paths = []

      # Current directory config
      paths << "./config" if Dir.exist?("./config")
      paths << "." if File.exist?("./openai_agents.yml")

      # User home directory
      home_config = File.expand_path("~/.config/openai_agents")
      paths << home_config if Dir.exist?(home_config)

      # System-wide config
      paths << "/etc/openai_agents" if Dir.exist?("/etc/openai_agents")

      paths
    end

    def load_config_files(base_name)
      @config_paths.each do |config_path|
        %w[.yml .yaml .json].each do |ext|
          file_path = File.join(config_path, "#{base_name}#{ext}")
          next unless File.exist?(file_path)

          begin
            file_config = load_config_file(file_path)
            @config_data = deep_merge(@config_data, file_config)
          rescue StandardError => e
            log_warn("Failed to load config file #{file_path}: #{e.message}", file_path: file_path,
                                                                              error_class: e.class.name)
          end
        end
      end
    end

    def load_config_file(file_path)
      content = File.read(file_path)

      case File.extname(file_path).downcase
      when ".yml", ".yaml"
        YAML.safe_load(content, symbolize_names: true) || {}
      when ".json"
        JSON.parse(content, symbolize_names: true)
      else
        {}
      end
    end

    def load_environment_variables
      ENV_MAPPINGS.each do |env_key, config_key|
        next unless ENV.key?(env_key)

        value = ENV.fetch(env_key, nil)
        set(config_key, value)
      end

      # Load any OPENAI_AGENTS_ prefixed variables
      ENV.each do |key, value|
        next unless key.start_with?("OPENAI_AGENTS_")

        config_key = key.sub("OPENAI_AGENTS_", "").downcase.gsub("_", ".")
        set(config_key, value)
      end
    end

    def coerce_value(value)
      case value
      when "true"
        true
      when "false"
        false
      when /^\d+$/
        value.to_i
      when /^\d+\.\d+$/
        value.to_f
      else
        value
      end
    end

    def validate_configuration
      errors = validate
      return if errors.empty?

      raise ConfigurationError, "Configuration validation failed: #{errors.join(", ")}" if production?

      log_warn("Configuration warnings: #{errors.join(", ")}", warning_count: errors.size)
    end

    def notify_watchers
      @watchers.each { |watcher| watcher.call(self) }
    end

    def valid_url?(url)
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      false
    end

    def deep_merge(hash1, hash2)
      result = hash1.dup

      hash2.each do |key, value|
        result[key] = if result[key].is_a?(Hash) && value.is_a?(Hash)
                        deep_merge(result[key], value)
                      else
                        value
                      end
      end

      result
    end

    def deep_dup(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_dup(v) }
      when Array
        obj.map { |v| deep_dup(v) }
      else
        begin
          obj.dup
        rescue StandardError
          obj
        end
      end
    end

    def sanitize_sensitive_data(data)
      case data
      when Hash
        data.each_with_object({}) do |(key, value), result|
          result[key] = if sensitive_key?(key)
                          "[REDACTED]"
                        else
                          sanitize_sensitive_data(value)
                        end
        end
      when Array
        data.map { |item| sanitize_sensitive_data(item) }
      else
        data
      end
    end

    def sensitive_key?(key)
      key.to_s.match?(/api_key|password|secret|token|credential/i)
    end
  end

  ##
  # ConfigurationSection - Wrapper for configuration sections
  #
  # Provides method-based access to configuration values within a section.
  class ConfigurationSection
    def initialize(data, path, config)
      @data = data
      @path = path
      @config = config
    end

    def method_missing(method_name, *args, &)
      if @data.is_a?(Hash) && @data.key?(method_name)
        value = @data[method_name]
        if value.is_a?(Hash)
          ConfigurationSection.new(value, "#{@path}.#{method_name}", @config)
        else
          value
        end
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      (@data.is_a?(Hash) && @data.key?(method_name)) || super
    end

    def to_h
      @data
    end
  end

  ##
  # ConfigurationError - Exception for configuration-related errors
  class ConfigurationError < Error; end
end
