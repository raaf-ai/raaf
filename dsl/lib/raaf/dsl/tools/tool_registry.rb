# frozen_string_literal: true

require 'concurrent'

# Optional levenshtein for fuzzy matching - gracefully degrade if not available
begin
  require 'levenshtein'
  LEVENSHTEIN_AVAILABLE = true
rescue LoadError
  LEVENSHTEIN_AVAILABLE = false
end

# Enhanced central registry for all available tools in RAAF DSL
#
# This registry provides:
# - Fast lookup by symbol name with O(1) complexity
# - Auto-registration when tools are loaded
# - Clear error messages with suggestions for typos
# - Support for multiple namespaces (RAAF::Tools, Ai::Tools, etc.)
# - Thread-safe operations with concurrent data structures
# - Fuzzy matching for tool name suggestions
#
# The registry automatically discovers and registers tools from multiple
# namespaces, providing a unified interface for tool resolution across
# the RAAF ecosystem.
#
# @example Basic usage
#   # Register a tool
#   ToolRegistry.register(:weather, WeatherTool)
#   
#   # Get a tool
#   tool_class = ToolRegistry.get(:weather)
#   
#   # Auto-discovery and suggestions
#   ToolRegistry.get(:wheather) # => raises error with suggestion: "Did you mean :weather?"
#
# @example Multiple namespaces
#   ToolRegistry.register_namespace("Ai::Tools")
#   ToolRegistry.auto_discover_tools
#
# @since 1.0.0
#
module RAAF
  module DSL
    module Tools
      class ToolRegistry
        # Error raised when a tool is not found
        class ToolNotFoundError < StandardError
          attr_reader :tool_name, :suggestions

          def initialize(tool_name, suggestions = [])
            @tool_name = tool_name
            @suggestions = suggestions
            
            message = "Tool '#{tool_name}' not found"
            if suggestions.any?
              message += ". Did you mean: #{suggestions.map { |s| ":#{s}" }.join(', ')}?"
            end
            message += "\n\nAvailable tools: #{ToolRegistry.available_tools.join(', ')}"
            
            super(message)
          end
        end

        # Thread-safe registry for storing tool mappings
        @registry = Concurrent::Hash.new
        # Thread-safe cache for discovery results
        @discovery_cache = Concurrent::Hash.new
        # Thread-safe set of registered namespaces
        @namespaces = Concurrent::Set.new
        # Thread-safe statistics tracking
        @stats = Concurrent::Hash.new { |h, k| h[k] = Concurrent::AtomicFixnum.new(0) }

        class << self
          attr_reader :registry, :discovery_cache, :namespaces, :stats

          # Register a tool class with a name
          #
          # @param name [Symbol, String] The name to register the tool under
          # @param tool_class [Class] The tool class to register
          # @param options [Hash] Additional options for tool registration
          # @option options [Array<Symbol>] :aliases Alternative names for the tool
          # @option options [Boolean] :enabled Whether the tool is enabled by default
          # @option options [String] :namespace Namespace the tool belongs to
          # @option options [Hash] :metadata Additional metadata about the tool
          #
          def register(name, tool_class, **options)
            name_sym = name.to_sym
            
            registry[name_sym] = {
              class: tool_class,
              options: options,
              registered_at: Time.current,
              namespace: options[:namespace] || infer_namespace(tool_class)
            }

            # Register aliases if provided
            if options[:aliases]
              options[:aliases].each do |alias_name|
                registry[alias_name.to_sym] = registry[name_sym]
              end
            end

            # Track registration statistics
            stats[:registrations].increment

            # Auto-register the tool's namespace
            register_namespace(registry[name_sym][:namespace])

            name_sym
          end

          # Get a tool class by name with enhanced error handling
          #
          # @param name [Symbol, String] The name of the tool to retrieve
          # @param strict [Boolean] Whether to raise error if not found
          # @return [Class, nil] The tool class if found
          # @raise [ToolNotFoundError] If tool not found and strict is true
          #
          def get(name, strict: true)
            name_sym = name.to_sym
            
            # Track lookup statistics
            stats[:lookups].increment

            # Check direct registry hit
            entry = registry[name_sym]
            if entry
              stats[:cache_hits].increment
              return entry[:class]
            end

            # Try auto-discovery if not found
            discovered_class = auto_discover_tool(name_sym)
            if discovered_class
              stats[:discoveries].increment
              return discovered_class
            end

            # Tool not found - handle based on strict mode
            if strict
              suggestions = suggest_similar_tools(name_sym)
              stats[:not_found].increment
              raise ToolNotFoundError.new(name, suggestions)
            end

            nil
          end

          # Check if a tool is registered
          #
          # @param name [Symbol, String] The name to check
          # @return [Boolean] True if the tool is registered
          #
          def registered?(name)
            name_sym = name.to_sym
            registry.key?(name_sym) || auto_discover_tool(name_sym).present?
          end

          # Register a namespace for auto-discovery
          #
          # @param namespace [String] Namespace to register (e.g., "RAAF::Tools")
          #
          def register_namespace(namespace)
            return unless namespace

            namespaces.add(namespace.to_s)
          end

          # Auto-discover and register tools from all registered namespaces
          #
          # @param force [Boolean] Whether to force re-discovery
          # @return [Integer] Number of tools discovered
          #
          def auto_discover_tools(force: false)
            discovered_count = 0

            namespaces.each do |namespace|
              discovered_count += discover_tools_in_namespace(namespace, force: force)
            end

            discovered_count
          end

          # Get all registered tool names
          #
          # @return [Array<Symbol>] Array of registered tool names
          #
          def names
            registry.keys.sort
          end

          # Get available tools with metadata
          #
          # @return [Array<String>] Array of available tool names
          #
          def available_tools
            names.map(&:to_s)
          end

          # Get detailed information about registered tools
          #
          # @param namespace [String, nil] Filter by namespace
          # @return [Hash] Detailed tool information
          #
          def tool_info(namespace: nil)
            tools = registry.select do |name, data|
              namespace.nil? || data[:namespace] == namespace
            end

            tools.transform_values do |data|
              {
                class_name: data[:class].name,
                namespace: data[:namespace],
                enabled: data[:options][:enabled] != false,
                aliases: find_aliases_for_tool(data[:class]),
                registered_at: data[:registered_at]
              }
            end
          end

          # Clear all registered tools (mainly for testing)
          #
          def clear!
            registry.clear
            discovery_cache.clear
            stats.clear
          end

          # Get registry statistics
          #
          # @return [Hash] Registry statistics
          #
          def statistics
            {
              registered_tools: registry.size,
              registered_namespaces: namespaces.size,
              lookups: stats[:lookups].value,
              cache_hits: stats[:cache_hits].value,
              discoveries: stats[:discoveries].value,
              not_found: stats[:not_found].value,
              cache_hit_ratio: calculate_cache_hit_ratio
            }
          end

          # Validate tool class before registration
          #
          # @param tool_class [Class] Tool class to validate
          # @return [Boolean] Whether the tool class is valid
          # @raise [ArgumentError] If tool class is invalid
          #
          def validate_tool_class!(tool_class)
            unless tool_class.is_a?(Class)
              raise ArgumentError, "Tool must be a class, got #{tool_class.class}"
            end

            unless tool_class.method_defined?(:call) || tool_class.method_defined?(:execute)
              raise ArgumentError, "Tool class #{tool_class.name} must implement #call or #execute method"
            end

            true
          end

          # Suggest similar tool names for typos
          #
          # @param name [Symbol] Misspelled tool name
          # @param max_suggestions [Integer] Maximum number of suggestions
          # @return [Array<Symbol>] Suggested tool names
          #
          def suggest_similar_tools(name, max_suggestions: 3)
            return [] if registry.empty?

            name_str = name.to_s
            
            if LEVENSHTEIN_AVAILABLE
              # Calculate Levenshtein distance for all registered tools
              candidates = registry.keys.map do |registered_name|
                distance = Levenshtein.distance(name_str, registered_name.to_s)
                { name: registered_name, distance: distance }
              end

              # Sort by distance and return top suggestions
              candidates.sort_by { |c| c[:distance] }
                       .first(max_suggestions)
                       .select { |c| c[:distance] <= 3 } # Only suggest if distance is reasonable
                       .map { |c| c[:name] }
            else
              # Fallback to simple string matching without levenshtein
              registry.keys.select do |registered_name|
                registered_name.to_s.include?(name_str) || name_str.include?(registered_name.to_s)
              end.first(max_suggestions)
            end
          end

          private

          # Auto-discover a specific tool by name
          #
          # @param name [Symbol] Tool name to discover
          # @return [Class, nil] Discovered tool class
          #
          def auto_discover_tool(name)
            cache_key = "tool_#{name}"
            
            discovery_cache.fetch(cache_key) do
              discovered_class = nil

              namespaces.each do |namespace|
                discovered_class = try_discover_tool_in_namespace(name, namespace)
                break if discovered_class
              end

              # Cache the result (even if nil) to avoid repeated discovery attempts
              discovered_class
            end
          end

          # Discover tools in a specific namespace
          #
          # @param namespace [String] Namespace to search
          # @param force [Boolean] Whether to force re-discovery
          # @return [Integer] Number of tools discovered
          #
          def discover_tools_in_namespace(namespace, force: false)
            cache_key = "namespace_#{namespace}"
            
            if !force && discovery_cache.key?(cache_key)
              return discovery_cache[cache_key]
            end

            discovered_count = 0
            
            begin
              namespace_module = namespace.constantize
              
              # Find all classes in the namespace that look like tools
              namespace_module.constants.each do |const_name|
                const = namespace_module.const_get(const_name)
                
                if const.is_a?(Class) && tool_class?(const)
                  tool_name = const.name.demodulize.underscore.gsub(/_tool$/, '').to_sym
                  
                  unless registry.key?(tool_name)
                    register(tool_name, const, namespace: namespace)
                    discovered_count += 1
                  end
                end
              end
            rescue NameError
              # Namespace doesn't exist - silently continue
            end

            discovery_cache[cache_key] = discovered_count
            discovered_count
          end

          # Try to discover a specific tool in a namespace
          #
          # @param name [Symbol] Tool name
          # @param namespace [String] Namespace to search
          # @return [Class, nil] Discovered tool class
          #
          def try_discover_tool_in_namespace(name, namespace)
            # Convert tool name to class name variations
            class_name_variants = generate_class_name_variants(name)
            
            class_name_variants.each do |class_name|
              begin
                full_class_name = "#{namespace}::#{class_name}"
                tool_class = full_class_name.constantize
                
                if tool_class?(tool_class)
                  # Auto-register the discovered tool
                  register(name, tool_class, namespace: namespace)
                  return tool_class
                end
              rescue NameError
                # Class doesn't exist - try next variant
                next
              end
            end

            nil
          end

          # Generate possible class name variants for a tool name
          #
          # @param name [Symbol] Tool name
          # @return [Array<String>] Possible class names
          #
          def generate_class_name_variants(name)
            base_name = name.to_s.camelize
            
            [
              "#{base_name}Tool",
              base_name,
              "#{base_name}Agent",
              "#{base_name}Service"
            ]
          end

          # Check if a class looks like a tool
          #
          # @param klass [Class] Class to check
          # @return [Boolean] Whether the class is a tool
          #
          def tool_class?(klass)
            return false unless klass.is_a?(Class)
            
            # Check if it has the required methods
            has_call_method = klass.method_defined?(:call) || klass.method_defined?(:execute)
            
            # Check if it inherits from known tool base classes
            inherits_from_tool = klass.ancestors.any? do |ancestor|
              ancestor.name&.include?('Tool') || ancestor.name&.include?('Agent')
            end

            has_call_method || inherits_from_tool
          end

          # Infer namespace from tool class
          #
          # @param tool_class [Class] Tool class
          # @return [String] Inferred namespace
          #
          def infer_namespace(tool_class)
            class_name = tool_class.name
            return 'Global' unless class_name
            
            parts = class_name.split('::')
            return 'Global' if parts.size == 1
            
            parts[0..-2].join('::')
          end

          # Find aliases for a specific tool class
          #
          # @param tool_class [Class] Tool class to find aliases for
          # @return [Array<Symbol>] Aliases for the tool
          #
          def find_aliases_for_tool(tool_class)
            registry.select { |name, data| data[:class] == tool_class }.keys
          end

          # Calculate cache hit ratio for performance monitoring
          #
          # @return [Float] Cache hit ratio (0.0 to 1.0)
          #
          def calculate_cache_hit_ratio
            lookups = stats[:lookups].value
            return 0.0 if lookups.zero?
            
            hits = stats[:cache_hits].value
            hits.to_f / lookups
          end
        end

        # Initialize with default namespaces
        register_namespace("RAAF::DSL::Tools")
        register_namespace("RAAF::Tools")
        register_namespace("Ai::Tools")
      end
    end
  end
end