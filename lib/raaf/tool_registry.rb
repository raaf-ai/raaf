# frozen_string_literal: true

require "concurrent"
begin
  require "raaf-core"
rescue LoadError
  # Allow standalone usage without full RAAF core
end

module RAAF
  # Registry for tool discovery and management
  #
  # This class provides a centralized registry for all RAAF tools,
  # supporting automatic registration, name-based lookup, and
  # namespace searching with user tool override capability.
  #
  # Tools in the Ai::Tools namespace automatically override
  # tools in the RAAF::Tools namespace when using auto-discovery.
  #
  # @example Registering a tool
  #   RAAF::ToolRegistry.register("my_tool", MyToolClass)
  #
  # @example Looking up a tool
  #   tool_class = RAAF::ToolRegistry.lookup(:web_search)
  #   # Searches in order:
  #   # 1. Registry by name
  #   # 2. Ai::Tools::WebSearchTool
  #   # 3. RAAF::Tools::WebSearchTool
  #
  class ToolRegistry
    extend RAAF::Logger

    # Thread-safe registry storage
    @registry = Concurrent::Hash.new
    @namespaces = ["Ai::Tools", "RAAF::Tools"]

    class << self
      # Register a tool with a name
      #
      # @param name [String, Symbol] Tool name for registration
      # @param tool_class [Class] The tool class to register
      def register(name, tool_class)
        tool_name = name.to_sym
        log_debug_tools("Registering tool", name: tool_name, class: tool_class.name) if respond_to?(:log_debug_tools)
        @registry[tool_name] = tool_class
      end

      # Get a tool by exact registered name
      #
      # @param name [String, Symbol] Tool name
      # @return [Class, nil] The tool class if found
      def get(name)
        @registry[name.to_sym]
      end

      # Lookup a tool using multiple strategies
      #
      # @param identifier [Class, String, Symbol] Tool identifier
      # @return [Class, nil] The resolved tool class
      def lookup(identifier)
        # Direct class reference
        return identifier if identifier.is_a?(Class)

        # Try registry first
        registered = get(identifier)
        return registered if registered

        # Auto-discovery in namespaces
        auto_discover(identifier)
      end

      # Resolve a tool (alias for lookup)
      #
      # @param identifier [Class, String, Symbol] Tool identifier
      # @return [Class, nil] The resolved tool class
      def resolve(identifier)
        lookup(identifier)
      end

      # List all registered tool names
      #
      # @return [Array<Symbol>] Registered tool names
      def list
        @registry.keys
      end

      # Check if a tool is registered
      #
      # @param name [String, Symbol] Tool name
      # @return [Boolean] Whether the tool is registered
      def registered?(name)
        @registry.key?(name.to_sym)
      end

      # Clear all registered tools (mainly for testing)
      def clear!
        @registry.clear
      end

      # Configure registry (currently just for namespace order)
      #
      # @yield [config] Configuration block
      def configure
        yield self if block_given?
      end

      # Set namespace search order
      #
      # @param namespaces [Array<String>] Namespace order
      attr_accessor :namespaces

      private

      # Auto-discover tool in configured namespaces
      def auto_discover(identifier)
        tool_name = identifier.to_s
        
        # Convert snake_case to CamelCase and add Tool suffix
        class_name = tool_name
          .split("_")
          .map(&:capitalize)
          .join
        class_name += "Tool" unless class_name.end_with?("Tool")

        # Search namespaces in order (user first, then RAAF)
        @namespaces.each do |namespace|
          full_class_name = "#{namespace}::#{class_name}"
          
          begin
            # Try to constantize the class name
            klass = Object.const_get(full_class_name)
            log_debug_tools("Auto-discovered tool", identifier: identifier, class: full_class_name) if respond_to?(:log_debug_tools)
            return klass
          rescue NameError
            # Continue to next namespace
            next
          end
        end

        # Not found in any namespace
        log_debug_tools("Tool not found", identifier: identifier) if respond_to?(:log_debug_tools)
        nil
      end
    end
  end
end