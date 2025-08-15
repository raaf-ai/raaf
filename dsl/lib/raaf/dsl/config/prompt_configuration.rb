# frozen_string_literal: true

require_relative "../prompts/prompt_resolver"
require_relative "../prompts/class_resolver"
require_relative "../prompts/file_resolver"

module RAAF
  module DSL
    ##
    # Configuration for prompt resolution system
    #
    class PromptConfiguration
      include RAAF::Logger

      attr_reader :paths, :resolvers, :default_format

      ##
      # Initialize prompt configuration
      #
      # @param paths [Array<String>] directories to search for prompts
      # @param resolvers [Array<Symbol>] resolver types to enable
      # @param default_format [Symbol] default format when not specified
      #
      def initialize(paths: ["prompts"], resolvers: %i[class file], default_format: :class)
        @paths = paths
        @resolvers = resolvers
        @default_format = default_format
        @custom_resolvers = {}

        setup_default_resolvers
      end

      ##
      # Configure prompt system with a block
      #
      # @example
      #   RAAF.configure_prompts do |config|
      #     config.add_path "app/prompts"
      #     config.add_path "lib/prompts"
      #
      #     config.enable_resolver :file, priority: 100
      #     config.disable_resolver :phlex
      #
      #     config.register_resolver :custom, MyCustomResolver
      #   end
      #
      def self.configure
        config = new
        yield config if block_given?
        config.apply!
        config
      end

      ##
      # Add a search path for prompts
      #
      def add_path(path)
        @paths << path unless @paths.include?(path)
        update_resolver_paths
      end

      ##
      # Remove a search path
      #
      def remove_path(path)
        @paths.delete(path)
        update_resolver_paths
      end

      ##
      # Enable a resolver type
      #
      # @param name [Symbol] resolver name
      # @param priority [Integer] resolver priority (higher = checked first)
      # @param options [Hash] additional options for the resolver
      #
      def enable_resolver(name, priority: nil, **options)
        @resolvers << name unless @resolvers.include?(name)

        if (resolver = DSL.prompt_resolvers.find(name))
          # Update existing resolver
          resolver.options[:priority] = priority if priority
          resolver.options.merge!(options)
        else
          # Create new resolver
          create_resolver(name, priority: priority, **options)
        end
      end

      ##
      # Disable a resolver type
      #
      def disable_resolver(name)
        @resolvers.delete(name)
        DSL.prompt_resolvers.unregister(name)
      end

      ##
      # Register a custom resolver
      #
      # @param name [Symbol] unique resolver name
      # @param resolver_class [Class] resolver class (must inherit from PromptResolver)
      # @param options [Hash] options for the resolver
      #
      def register_resolver(name, resolver_class, **options)
        unless resolver_class < PromptResolver
          raise ArgumentError, "Resolver class must inherit from RAAF::PromptResolver"
        end

        @custom_resolvers[name] = { class: resolver_class, options: options }
        enable_resolver(name, **options)
      end

      ##
      # Apply this configuration to the global registry
      #
      def apply!
        # Clear existing resolvers
        DSL.prompt_resolvers.clear

        # Register enabled resolvers
        @resolvers.each do |name|
          create_resolver(name) unless DSL.prompt_resolvers.find(name)
        end

        log_info("Applied prompt configuration",
                 paths: @paths,
                 resolvers: @resolvers,
                 default_format: @default_format)
      end

      ##
      # Create a preconfigured agent with prompt resolution
      #
      # @param name [String] agent name
      # @param prompt_spec [Object] prompt specification
      # @param options [Hash] additional agent options
      # @return [Agent] configured agent
      #
      def create_agent(name:, prompt:, **options)
        resolved_prompt = DSL.prompt_resolvers.resolve(prompt, options[:context] || {})

        raise ArgumentError, "Could not resolve prompt: #{prompt.inspect}" unless resolved_prompt

        ::RAAF::Agent.new(
          name: name,
          prompt: resolved_prompt,
          **options
        )
      end

      private

      def setup_default_resolvers
        # Default resolver classes
        @default_resolver_classes = {
          class: PromptResolvers::ClassResolver,
          file: PromptResolvers::FileResolver
        }
      end

      def create_resolver(name, **options)
        resolver_class = @custom_resolvers.dig(name, :class) ||
                         @default_resolver_classes[name]

        return unless resolver_class

        resolver_options = {
          paths: @paths,
          **(@custom_resolvers.dig(name, :options) || {}),
          **options
        }

        resolver = resolver_class.new(**resolver_options)
        DSL.prompt_resolvers.register(resolver)
      end

      def update_resolver_paths
        # Update paths for file resolver
        if (resolver = DSL.prompt_resolvers.find(:file))
          resolver.instance_variable_set(:@paths, @paths)
        end
      end
    end

    ##
    # Global prompt configuration
    #
    class << self
      def prompt_configuration
        @prompt_configuration ||= PromptConfiguration.new
      end

      def configure_prompts(&block)
        PromptConfiguration.configure(&block)
      end
    end
  end
end
