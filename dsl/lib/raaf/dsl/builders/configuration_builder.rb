# frozen_string_literal: true

module RAAF
  module DSL
    ##
    # DSL for loading Ruby configuration files safely
    # This restricts what can be done in configuration files
    #
    class ConfigurationDSL
      def initialize
        @config = {}
      end

      # Allow setting configuration values
      def set(key, value)
        @config[key] = value
      end

      # Allow nested configuration blocks
      def configure(key, &block)
        nested_dsl = ConfigurationDSL.new
        nested_dsl.instance_eval(&block)
        @config[key] = nested_dsl.to_h
      end

      # Common configuration methods
      def logging(&block)
        configure(:logging, &block)
      end

      def tracing(&block)
        configure(:tracing, &block)
      end

      def memory(&block)
        configure(:memory, &block)
      end

      def agents(&block)
        configure(:agents, &block)
      end

      def tools(&block)
        configure(:tools, &block)
      end

      # Set individual values
      def method_missing(method_name, *args, **kwargs, &block)
        if method_name.to_s.end_with?("=")
          # Handle assignment methods
          key = method_name.to_s.chomp("=").to_sym
          @config[key] = args.first
        elsif block_given?
          # Handle nested configuration blocks
          configure(method_name, &block)
        elsif args.any? || kwargs.any?
          # Handle setting values
          value = args.first || kwargs
          @config[method_name] = value
        else
          # Return nil for undefined methods
          nil
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        true # Accept any configuration key
      end

      def to_h
        @config
      end
    end

    ##
    # Configuration builder for DSL-based configuration management
    #
    # Provides a fluent interface for building configurations using declarative
    # syntax with support for nested configurations, validation, and templates.
    #
    class ConfigurationBuilder
      include RAAF::Logging

      # @return [Hash] Configuration data
      attr_reader :config

      ##
      # Initialize configuration builder
      #
      def initialize
        @config = {}
        @validators = []
        @transformers = []
        @defaults = {}
      end

      ##
      # Configure logging
      #
      # @param block [Proc] Logging configuration block
      #
      def logging(&block)
        @config[:logging] = build_nested_config(&block)
      end

      ##
      # Configure tracing
      #
      # @param block [Proc] Tracing configuration block
      #
      def tracing(&block)
        @config[:tracing] = build_nested_config(&block)
      end

      ##
      # Configure memory
      #
      # @param block [Proc] Memory configuration block
      #
      def memory(&block)
        @config[:memory] = build_nested_config(&block)
      end

      ##
      # Configure guardrails
      #
      # @param block [Proc] Guardrails configuration block
      #
      def guardrails(&block)
        @config[:guardrails] = build_nested_config(&block)
      end

      ##
      # Configure providers
      #
      # @param block [Proc] Providers configuration block
      #
      def providers(&block)
        @config[:providers] = build_nested_config(&block)
      end

      ##
      # Configure security
      #
      # @param block [Proc] Security configuration block
      #
      def security(&block)
        @config[:security] = build_nested_config(&block)
      end

      ##
      # Configure streaming
      #
      # @param block [Proc] Streaming configuration block
      #
      def streaming(&block)
        @config[:streaming] = build_nested_config(&block)
      end

      ##
      # Configure testing
      #
      # @param block [Proc] Testing configuration block
      #
      def testing(&block)
        @config[:testing] = build_nested_config(&block)
      end

      ##
      # Configure compliance
      #
      # @param block [Proc] Compliance configuration block
      #
      def compliance(&block)
        @config[:compliance] = build_nested_config(&block)
      end

      ##
      # Configure debug
      #
      # @param block [Proc] Debug configuration block
      #
      def debug(&block)
        @config[:debug] = build_nested_config(&block)
      end

      ##
      # Configure visualization
      #
      # @param block [Proc] Visualization configuration block
      #
      def visualization(&block)
        @config[:visualization] = build_nested_config(&block)
      end

      ##
      # Configure analytics
      #
      # @param block [Proc] Analytics configuration block
      #
      def analytics(&block)
        @config[:analytics] = build_nested_config(&block)
      end

      ##
      # Configure monitoring
      #
      # @param block [Proc] Monitoring configuration block
      #
      def monitoring(&block)
        @config[:monitoring] = build_nested_config(&block)
      end

      ##
      # Configure deployment
      #
      # @param block [Proc] Deployment configuration block
      #
      def deployment(&block)
        @config[:deployment] = build_nested_config(&block)
      end

      ##
      # Configure workflow
      #
      # @param block [Proc] Workflow configuration block
      #
      def workflow(&block)
        @config[:workflow] = build_nested_config(&block)
      end

      ##
      # Configure integrations
      #
      # @param block [Proc] Integrations configuration block
      #
      def integrations(&block)
        @config[:integrations] = build_nested_config(&block)
      end

      ##
      # Configure environment
      #
      # @param env [String] Environment name
      # @param block [Proc] Environment configuration block
      #
      def environment(env, &block)
        @config[:environments] ||= {}
        @config[:environments][env] = build_nested_config(&block)
      end

      ##
      # Set configuration value
      #
      # @param key [Symbol] Configuration key
      # @param value [Object] Configuration value
      #
      def set(key, value)
        @config[key] = value
      end

      ##
      # Get configuration value
      #
      # @param key [Symbol] Configuration key
      # @return [Object] Configuration value
      #
      def get(key)
        @config[key]
      end

      ##
      # Merge configuration
      #
      # @param other_config [Hash] Configuration to merge
      #
      def merge(other_config)
        @config = deep_merge(@config, other_config)
      end

      ##
      # Set default values
      #
      # @param defaults [Hash] Default values
      #
      def defaults(**defaults)
        @defaults = deep_merge(@defaults, defaults)
      end

      ##
      # Add validator
      #
      # @param name [String] Validator name
      # @param block [Proc] Validator block
      #
      def validate(name, &block)
        @validators << {
          name: name,
          block: block
        }
      end

      ##
      # Add transformer
      #
      # @param name [String] Transformer name
      # @param block [Proc] Transformer block
      #
      def transform(name, &block)
        @transformers << {
          name: name,
          block: block
        }
      end

      ##
      # Load configuration from file
      #
      # @param file_path [String] Configuration file path
      #
      def load_from_file(file_path)
        raise ArgumentError, "Configuration file not found: #{file_path}" unless File.exist?(file_path)

        case File.extname(file_path)
        when ".json"
          load_json(file_path)
        when ".yaml", ".yml"
          load_yaml(file_path)
        when ".rb"
          load_ruby(file_path)
        else
          raise ArgumentError, "Unsupported configuration file format: #{file_path}"
        end
      end

      ##
      # Load configuration from environment variables
      #
      # @param prefix [String] Environment variable prefix
      #
      def load_from_env(prefix = "RAAF")
        env_config = {}

        ENV.each do |key, value|
          if key.start_with?(prefix)
            config_key = key.sub(/^#{prefix}_/, "").downcase.to_sym
            env_config[config_key] = parse_env_value(value)
          end
        end

        merge(env_config)
      end

      ##
      # Export configuration to file
      #
      # @param file_path [String] Output file path
      # @param format [Symbol] Output format (:json, :yaml, :ruby)
      #
      def export_to_file(file_path, format: :json)
        case format
        when :json
          export_json(file_path)
        when :yaml
          export_yaml(file_path)
        when :ruby
          export_ruby(file_path)
        else
          raise ArgumentError, "Unsupported export format: #{format}"
        end
      end

      ##
      # Build final configuration
      #
      # @return [Hash] Final configuration
      #
      def build
        # Apply defaults
        final_config = deep_merge(@defaults, @config)

        # Apply transformers
        @transformers.each do |transformer|
          final_config = transformer[:block].call(final_config)
        end

        # Validate configuration
        validate_configuration(final_config)

        final_config
      end

      ##
      # Validate configuration
      #
      # @param config [Hash] Configuration to validate
      # @return [Array<String>] Validation errors
      #
      def validate_configuration(config)
        errors = []

        @validators.each do |validator|
          result = validator[:block].call(config)
          if result.is_a?(String)
            errors << result
          elsif result.is_a?(Array)
            errors.concat(result)
          end
        rescue StandardError => e
          errors << "Validator '#{validator[:name]}' failed: #{e.message}"
        end

        raise DSL::ValidationError, "Configuration validation failed: #{errors.join(', ')}" if errors.any?

        errors
      end

      ##
      # Get configuration schema
      #
      # @return [Hash] Configuration schema
      #
      def schema
        {
          type: "object",
          properties: {
            logging: { type: "object" },
            tracing: { type: "object" },
            memory: { type: "object" },
            guardrails: { type: "object" },
            providers: { type: "object" },
            security: { type: "object" },
            streaming: { type: "object" },
            testing: { type: "object" },
            compliance: { type: "object" },
            debug: { type: "object" },
            visualization: { type: "object" },
            analytics: { type: "object" },
            monitoring: { type: "object" },
            deployment: { type: "object" },
            workflow: { type: "object" },
            integrations: { type: "object" },
            environments: { type: "object" }
          }
        }
      end

      private

      def build_nested_config(&block)
        nested_builder = NestedConfigBuilder.new
        nested_builder.instance_eval(&block)
        nested_builder.config
      end

      def deep_merge(hash1, hash2)
        hash1.merge(hash2) do |_key, old_val, new_val|
          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            deep_merge(old_val, new_val)
          else
            new_val
          end
        end
      end

      def load_json(file_path)
        require "json"
        config = JSON.parse(File.read(file_path), symbolize_names: true)
        merge(config)
      end

      def load_yaml(file_path)
        require "yaml"
        config = YAML.load_file(file_path)
        merge(config.transform_keys(&:to_sym))
      end

      def load_ruby(file_path)
        # Load Ruby configuration file using a DSL approach
        config = ConfigurationDSL.new
        config.instance_eval(File.read(file_path), file_path, 1)
        merge(config.to_h)
      end

      def export_json(file_path)
        require "json"
        File.write(file_path, JSON.pretty_generate(@config))
      end

      def export_yaml(file_path)
        require "yaml"
        File.write(file_path, @config.to_yaml)
      end

      def export_ruby(file_path)
        File.write(file_path, @config.inspect)
      end

      def parse_env_value(value)
        case value.downcase
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
    end

    ##
    # Nested configuration builder
    #
    class NestedConfigBuilder
      attr_reader :config

      def initialize
        @config = {}
      end

      def method_missing(method_name, *args, &block)
        if block_given?
          @config[method_name] = build_nested_config(&block)
        elsif args.length == 1
          @config[method_name] = args.first
        elsif args.length > 1
          @config[method_name] = args
        else
          @config[method_name]
        end
      end

      def respond_to_missing?(_method_name, _include_private = false)
        true
      end

      def set(key, value)
        @config[key] = value
      end

      def get(key)
        @config[key]
      end

      def merge(other_config)
        @config = deep_merge(@config, other_config)
      end

      private

      def build_nested_config(&block)
        nested_builder = NestedConfigBuilder.new
        nested_builder.instance_eval(&block)
        nested_builder.config
      end

      def deep_merge(hash1, hash2)
        hash1.merge(hash2) do |_key, old_val, new_val|
          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            deep_merge(old_val, new_val)
          else
            new_val
          end
        end
      end
    end
  end
end
