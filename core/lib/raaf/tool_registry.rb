# frozen_string_literal: true

require "concurrent"
begin
  require "raaf-core"
rescue LoadError
  # Allow standalone usage without full RAAF core
end

# Require DidYouMean if available (standard in Ruby 2.3+)
begin
  require "did_you_mean"
rescue LoadError
  # DidYouMean not available
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
    extend RAAF::Logger if defined?(RAAF::Logger)

    # Thread-safe registry storage
    @registry = Concurrent::Hash.new
    @namespaces = Concurrent::Array.new(["Ai::Tools", "RAAF::Tools", "RAAF::Tools::Basic", "Ai::Tools::Basic"])

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
        if registered
          return registered
        end

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

      # Safe lookup that gracefully handles uninitialized registry
      #
      # This method provides the same resolution logic as `lookup`, but with
      # graceful error handling for scenarios where ToolRegistry might not be
      # fully loaded yet (e.g., eager_load environments with lazy tool resolution).
      #
      # Used by RAAF::DSL::AgentToolIntegration to implement hybrid eager/lazy
      # tool resolution:
      # - Symbols return nil if registry unavailable (for lazy resolution)
      # - Class references return immediately (no registry needed)
      # - Other identifiers are looked up with full auto-discovery
      #
      # @param identifier [Class, String, Symbol] Tool identifier to resolve
      # @return [Class, nil] The resolved tool class, or nil if resolution fails
      #
      # @example Safe lookup for lazy resolution (symbol)
      #   tool_class = RAAF::ToolRegistry.safe_lookup(:web_search)
      #   # Returns tool class if registered, or nil if registry not available
      #
      # @example Direct class reference (immediate resolution)
      #   tool_class = RAAF::ToolRegistry.safe_lookup(MyCustomTool)
      #   # Always returns the class immediately, no registry lookup needed
      #
      # @example Error handling for NameErrors
      #   # NameError for uninitialized constants is caught and returns nil
      #   # Other errors are re-raised
      def safe_lookup(identifier)
        lookup(identifier)
      rescue NameError => e
        if e.message.include?("RAAF::ToolRegistry") || e.message.include?("uninitialized constant")
          # ToolRegistry not fully loaded yet - return nil for lazy resolution
          nil
        else
          # Re-raise if it's a different NameError
          raise
        end
      end

      # Resolve a tool with detailed error information
      #
      # @param identifier [Class, String, Symbol] Tool identifier
      # @return [Hash] Resolution result with success status and details
      #   - :success [Boolean] Whether the tool was resolved
      #   - :tool_class [Class, nil] The resolved tool class (if successful)
      #   - :identifier [Symbol, String, Class] The original identifier
      #   - :searched_namespaces [Array<String>] Namespaces that were searched
      #   - :suggestions [Array<String>] Helpful suggestions for resolution
      def resolve_with_details(identifier)
        # Track searched namespaces
        searched_namespaces = []

        # Direct class reference
        if identifier.is_a?(Class)
          return {
            success: true,
            tool_class: identifier,
            identifier: identifier,
            searched_namespaces: [],
            suggestions: []
          }
        end

        # Try registry first
        registered = get(identifier)
        if registered
          return {
            success: true,
            tool_class: registered,
            identifier: identifier,
            searched_namespaces: [],
            suggestions: []
          }
        end

        # Auto-discovery in namespaces with tracking
        tool_name = identifier.to_s
        class_name = tool_name.split("_").map(&:capitalize).join
        class_name += "Tool" unless class_name.end_with?("Tool")

        # Search namespaces
        @namespaces.each do |namespace|
          searched_namespaces << namespace
          full_class_name = "#{namespace}::#{class_name}"

          begin
            klass = Object.const_get(full_class_name)
            if valid_tool_class?(klass)
              return {
                success: true,
                tool_class: klass,
                identifier: identifier,
                searched_namespaces: searched_namespaces,
                suggestions: []
              }
            end
          rescue NameError
            # Continue to next namespace
          end
        end

        # Also try without namespace (global)
        searched_namespaces << "Global"
        begin
          klass = Object.const_get(class_name)
          if valid_tool_class?(klass)
            return {
              success: true,
              tool_class: klass,
              identifier: identifier,
              searched_namespaces: searched_namespaces,
              suggestions: []
            }
          end
        rescue NameError
          # Not found globally either
        end

        # Tool not found - generate helpful suggestions
        suggestions = generate_suggestions(identifier, class_name)

        {
          success: false,
          tool_class: nil,
          identifier: identifier,
          searched_namespaces: searched_namespaces,
          suggestions: suggestions
        }
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
            if valid_tool_class?(klass)
              log_debug_tools("Auto-discovered tool", identifier: identifier, class: full_class_name) if respond_to?(:log_debug_tools)
              return klass
            end
          rescue NameError
            # Continue to next namespace
            next
          end
        end

        # Not found in any namespace
        log_debug_tools("Tool not found", identifier: identifier) if respond_to?(:log_debug_tools)
        nil
      end

      # Check if a class is a valid tool class
      # (Could add additional validation here if needed)
      def valid_tool_class?(klass)
        klass.is_a?(Class)
      end

      # Generate helpful suggestions for failed tool resolution
      def generate_suggestions(identifier, class_name)
        suggestions = []

        # Use DidYouMean if available
        if defined?(DidYouMean)
          # Get registered tool names for similarity matching
          registered_names = @registry.keys.map(&:to_s)

          if registered_names.any?
            spell_checker = DidYouMean::SpellChecker.new(dictionary: registered_names)
            similar_names = spell_checker.correct(identifier.to_s)

            # Add up to 3 similarity suggestions
            similar_names.first(3).each do |name|
              suggestions << "Did you mean: :#{name}?"
            end
          end
        end

        # Add registration suggestion
        suggestions << "Register it: RAAF::ToolRegistry.register(:#{identifier}, #{class_name})"

        # Add direct class reference suggestion
        suggestions << "Use direct class: tool #{class_name}"

        suggestions
      end
    end
  end
end