# frozen_string_literal: true

module OpenAIAgents
  ##
  # Extensions - Plugin architecture for extensibility
  #
  # Provides a flexible plugin system for extending OpenAI Agents functionality.
  # Supports multiple extension types including agents, tools, processors, and
  # custom behaviors. Extensions can be loaded dynamically and configured
  # through the configuration system.
  #
  # == Features
  #
  # * Plugin discovery and loading
  # * Extension lifecycle management
  # * Dependency resolution
  # * Configuration integration
  # * Hot-reloading support
  # * Extension validation
  # * Multiple extension types
  #
  # == Extension Types
  #
  # * **Agent Extensions** - Custom agent behaviors and capabilities
  # * **Tool Extensions** - Additional tools for agents
  # * **Processor Extensions** - Custom tracing and logging processors
  # * **Provider Extensions** - Additional LLM providers
  # * **Guardrail Extensions** - Custom safety and validation rules
  # * **Visualization Extensions** - Custom visualization and reporting
  #
  # == Basic Usage
  #
  #   # Register an extension
  #   OpenAIAgents::Extensions.register(:my_tool) do |ext|
  #     ext.name = "My Custom Tool"
  #     ext.version = "1.0.0"
  #     ext.type = :tool
  #     ext.setup { |config| setup_my_tool(config) }
  #   end
  #
  #   # Load and activate extensions
  #   OpenAIAgents::Extensions.load_all
  #   OpenAIAgents::Extensions.activate(:my_tool)
  #
  # == Creating Extensions
  #
  #   class MyAgentExtension < OpenAIAgents::Extensions::BaseExtension
  #     def self.extension_info
  #       {
  #         name: "My Agent Extension",
  #         type: :agent,
  #         version: "1.0.0",
  #         dependencies: [:basic_tools]
  #       }
  #     end
  #
  #     def setup(config)
  #       # Extension setup logic
  #     end
  #
  #     def activate
  #       # Extension activation logic
  #     end
  #   end
  #
  # @author OpenAI Agents Ruby Team
  # @since 0.1.0
  module Extensions
    ##
    # Extension registry for managing loaded extensions
    @registry = {}
    @active_extensions = Set.new
    @extension_paths = []
    @hooks = Hash.new { |h, k| h[k] = [] }

    class << self
      attr_reader :registry, :active_extensions, :extension_paths

      ##
      # Registers a new extension
      #
      # @param name [Symbol] unique name for the extension
      # @yield [ExtensionBuilder] builder for configuring the extension
      # @return [Extension] the registered extension
      #
      # @example Register a simple extension
      #   Extensions.register(:weather_tool) do |ext|
      #     ext.name = "Weather Tool"
      #     ext.type = :tool
      #     ext.setup { |config| create_weather_tool }
      #   end
      #
      # @example Register an extension with dependencies
      #   Extensions.register(:advanced_agent) do |ext|
      #     ext.name = "Advanced Agent"
      #     ext.type = :agent
      #     ext.dependencies = [:web_search, :file_tools]
      #     ext.setup { |config| setup_advanced_features }
      #   end
      def register(name, &)
        builder = ExtensionBuilder.new(name)
        builder.instance_eval(&) if block_given?

        extension = builder.build
        validate_extension!(extension)

        @registry[name] = extension
        extension
      end

      ##
      # Loads an extension class
      #
      # @param extension_class [Class] extension class to load
      # @return [Extension] the loaded extension
      #
      # @example Load extension class
      #   Extensions.load_extension(MyCustomExtension)
      def load_extension(extension_class)
        raise ExtensionError, "Extension must inherit from BaseExtension" unless extension_class < BaseExtension

        info = extension_class.extension_info
        name = info[:name]&.to_sym || extension_class.name.to_sym

        extension = Extension.new(
          name: name,
          type: info[:type],
          version: info[:version],
          dependencies: info[:dependencies] || [],
          description: info[:description],
          author: info[:author],
          instance: extension_class.new
        )

        validate_extension!(extension)
        @registry[name] = extension
        extension
      end

      ##
      # Discovers and loads extensions from specified paths
      #
      # @param paths [Array<String>] paths to search for extensions
      # @return [Array<Extension>] loaded extensions
      #
      # @example Load extensions from directories
      #   Extensions.discover_extensions(["./extensions", "~/.openai_agents/extensions"])
      def discover_extensions(paths = extension_paths)
        loaded = []

        paths.each do |path|
          next unless Dir.exist?(path)

          Dir.glob(File.join(path, "**/*.rb")).each do |file|
            require file
            # Extensions should register themselves when loaded
          rescue LoadError => e
            warn "Failed to load extension from #{file}: #{e.message}"
          end
        end

        loaded
      end

      ##
      # Adds a path for extension discovery
      #
      # @param path [String] directory path to search for extensions
      # @return [void]
      #
      # @example Add extension path
      #   Extensions.add_path("./my_extensions")
      def add_path(path)
        expanded_path = File.expand_path(path)
        @extension_paths << expanded_path unless @extension_paths.include?(expanded_path)
      end

      ##
      # Loads all discovered extensions
      #
      # @return [Array<Extension>] all loaded extensions
      #
      # @example Load all extensions
      #   Extensions.load_all
      def load_all
        discover_extensions
        @registry.values
      end

      ##
      # Activates an extension and its dependencies
      #
      # @param name [Symbol] name of the extension to activate
      # @param config [Configuration] configuration object
      # @return [Boolean] true if activation succeeded
      # @raise [ExtensionError] if extension or dependencies not found
      #
      # @example Activate extension
      #   Extensions.activate(:web_search)
      #
      # @example Activate with custom config
      #   config = OpenAIAgents::Configuration.new
      #   Extensions.activate(:custom_tool, config)
      def activate(name, config = nil)
        extension = @registry[name]
        raise ExtensionError, "Extension '#{name}' not found" unless extension

        return true if @active_extensions.include?(name)

        # Activate dependencies first
        extension.dependencies.each do |dep|
          activate(dep, config) unless @active_extensions.include?(dep)
        end

        # Setup and activate extension
        begin
          extension.setup(config) if extension.respond_to?(:setup)
          extension.activate if extension.respond_to?(:activate)

          @active_extensions.add(name)
          trigger_hook(:extension_activated, extension)

          true
        rescue StandardError => e
          raise ExtensionError, "Failed to activate extension '#{name}': #{e.message}"
        end
      end

      ##
      # Deactivates an extension
      #
      # @param name [Symbol] name of the extension to deactivate
      # @return [Boolean] true if deactivation succeeded
      #
      # @example Deactivate extension
      #   Extensions.deactivate(:web_search)
      def deactivate(name)
        extension = @registry[name]
        return false unless extension && @active_extensions.include?(name)

        begin
          extension.deactivate if extension.respond_to?(:deactivate)
          @active_extensions.delete(name)
          trigger_hook(:extension_deactivated, extension)

          true
        rescue StandardError => e
          warn "Failed to deactivate extension '#{name}': #{e.message}"
          false
        end
      end

      ##
      # Checks if an extension is active
      #
      # @param name [Symbol] extension name
      # @return [Boolean] true if extension is active
      #
      # @example Check if extension is active
      #   Extensions.active?(:web_search) # => true
      def active?(name)
        @active_extensions.include?(name)
      end

      ##
      # Gets information about a registered extension
      #
      # @param name [Symbol] extension name
      # @return [Extension, nil] extension object or nil if not found
      #
      # @example Get extension info
      #   ext = Extensions.get(:web_search)
      #   puts "Version: #{ext.version}"
      def get(name)
        @registry[name]
      end

      ##
      # Lists all registered extensions
      #
      # @param type [Symbol, nil] filter by extension type
      # @return [Array<Extension>] list of extensions
      #
      # @example List all extensions
      #   Extensions.list.each { |ext| puts ext.name }
      #
      # @example List tool extensions
      #   Extensions.list(:tool).each { |ext| puts ext.name }
      def list(type = nil)
        extensions = @registry.values

        if type
          extensions.select { |ext| ext.type == type }
        else
          extensions
        end
      end

      ##
      # Registers a hook for extension events
      #
      # @param event [Symbol] event name (:extension_activated, :extension_deactivated)
      # @yield [Extension] called when event occurs
      # @return [void]
      #
      # @example Register activation hook
      #   Extensions.on(:extension_activated) do |extension|
      #     puts "Activated: #{extension.name}"
      #   end
      def on(event, &block)
        @hooks[event] << block
      end

      ##
      # Reloads an extension (deactivate and reactivate)
      #
      # @param name [Symbol] extension name
      # @param config [Configuration] configuration object
      # @return [Boolean] true if reload succeeded
      #
      # @example Reload extension
      #   Extensions.reload(:custom_tool)
      def reload(name, config = nil)
        was_active = active?(name)

        deactivate(name) if was_active

        # Clear from registry to force re-registration
        @registry.delete(name)

        # Extension should re-register itself when required again
        if was_active
          activate(name, config)
        else
          true
        end
      end

      ##
      # Validates extension dependencies
      #
      # @param name [Symbol] extension name
      # @return [Array<Symbol>] missing dependencies
      #
      # @example Check dependencies
      #   missing = Extensions.check_dependencies(:advanced_agent)
      #   puts "Missing: #{missing}" unless missing.empty?
      def check_dependencies(name)
        extension = @registry[name]
        return [] unless extension

        extension.dependencies.reject { |dep| @registry.key?(dep) }
      end

      ##
      # Creates a dependency graph for extensions
      #
      # @return [Hash] dependency graph
      #
      # @example Get dependency graph
      #   graph = Extensions.dependency_graph
      #   puts "Dependencies: #{graph}"
      def dependency_graph
        graph = {}

        @registry.each do |name, extension|
          graph[name] = extension.dependencies
        end

        graph
      end

      private

      def validate_extension!(extension)
        raise ExtensionError, "Extension name is required" unless extension.name
        raise ExtensionError, "Extension type is required" unless extension.type

        # Check for name conflicts
        if @registry.key?(extension.name) && @registry[extension.name] != extension
          raise ExtensionError, "Extension '#{extension.name}' already registered"
        end

        # Validate type
        valid_types = %i[agent tool processor provider guardrail visualization other]
        return if valid_types.include?(extension.type)

        raise ExtensionError, "Invalid extension type: #{extension.type}"
      end

      def trigger_hook(event, *args)
        @hooks[event].each { |hook| hook.call(*args) }
      end
    end

    ##
    # Extension - Represents a loaded extension
    #
    # Contains metadata and functionality for a single extension.
    class Extension
      attr_reader :name, :type, :version, :dependencies, :description, :author, :instance

      def initialize(name:, type:, version: "1.0.0", dependencies: [], description: nil,
                     author: nil, instance: nil, setup_proc: nil, activate_proc: nil)
        @name = name
        @type = type
        @version = version
        @dependencies = dependencies
        @description = description
        @author = author
        @instance = instance
        @setup_proc = setup_proc
        @activate_proc = activate_proc
      end

      def setup(config = nil)
        if @instance.respond_to?(:setup)
          @instance.setup(config)
        elsif @setup_proc
          @setup_proc.call(config)
        end
      end

      def activate
        if @instance.respond_to?(:activate)
          @instance.activate
        elsif @activate_proc
          @activate_proc.call
        end
      end

      def deactivate
        return unless @instance.respond_to?(:deactivate)

        @instance.deactivate
      end

      def to_h
        {
          name: @name,
          type: @type,
          version: @version,
          dependencies: @dependencies,
          description: @description,
          author: @author
        }
      end
    end

    ##
    # ExtensionBuilder - Builder for creating extensions via DSL
    #
    # Provides a fluent interface for configuring extensions.
    class ExtensionBuilder
      attr_reader :name

      def initialize(name)
        @name = name
        @type = :other
        @version = "1.0.0"
        @dependencies = []
        @description = nil
        @author = nil
        @setup_proc = nil
        @activate_proc = nil
      end

      def type(type)
        @type = type
      end

      def version(version)
        @version = version
      end

      def dependencies(*deps)
        @dependencies = deps.flatten
      end

      def description(desc)
        @description = desc
      end

      def author(author)
        @author = author
      end

      def setup(&block)
        @setup_proc = block
      end

      def activate(&block)
        @activate_proc = block
      end

      def build
        Extension.new(
          name: @name,
          type: @type,
          version: @version,
          dependencies: @dependencies,
          description: @description,
          author: @author,
          setup_proc: @setup_proc,
          activate_proc: @activate_proc
        )
      end
    end

    ##
    # BaseExtension - Base class for extension implementations
    #
    # Provides a standard interface for extension classes.
    class BaseExtension
      ##
      # Extension metadata (must be implemented by subclasses)
      #
      # @return [Hash] extension information
      #
      # @example Extension info
      #   def self.extension_info
      #     {
      #       name: :my_extension,
      #       type: :tool,
      #       version: "1.0.0",
      #       dependencies: [:basic_tools],
      #       description: "My custom extension",
      #       author: "Developer Name"
      #     }
      #   end
      def self.extension_info
        raise NotImplementedError, "Subclasses must implement extension_info"
      end

      ##
      # Called when extension is being set up
      #
      # @param config [Configuration] configuration object
      # @return [void]
      def setup(config = nil)
        # Override in subclasses
      end

      ##
      # Called when extension is activated
      #
      # @return [void]
      def activate
        # Override in subclasses
      end

      ##
      # Called when extension is deactivated
      #
      # @return [void]
      def deactivate
        # Override in subclasses
      end
    end

    # Set up default extension paths
    add_path("./extensions")
    add_path(File.expand_path("~/.openai_agents/extensions"))
    add_path("/usr/local/share/openai_agents/extensions")

    ##
    # ExtensionError - Exception for extension-related errors
    class ExtensionError < Error; end
  end
end
