# frozen_string_literal: true

require "raaf/function_tool"

# NOTE: ToolRegistry is loaded by raaf-dsl.rb when this gem is initialized
# We don't require it here since the parent file handles the initialization
# This keeps tool management concerns centralized in raaf-dsl gem

module RAAF
  module DSL
    # Tool integration methods for DSL Agent
    #
    # This module provides the unified tool interface for agents with
    # HYBRID EAGER/LAZY RESOLUTION for maximum compatibility:
    #
    # **EAGER RESOLUTION** (at class definition time):
    # - When ToolRegistry is available, tools are resolved immediately
    # - Class references are resolved instantly (no registry needed)
    # - Errors are caught early at class definition time
    #
    # **LAZY RESOLUTION** (at runtime):
    # - Symbol identifiers fall back to runtime resolution if registry unavailable
    # - Enables compatibility with early agent loading (e.g., in jobs)
    # - Tools resolved only when needed (agents instantiated)
    #
    # **DEFENSIVE NAMING:**
    # - Wraps ToolRegistry constant access in NameError handling
    # - Returns nil if ToolRegistry not available at class definition time
    # - Enables symbol identifiers to defer to lazy resolution in all contexts
    # - Critical for job contexts where RAAF modules may load after agent definition
    #
    # **CONSOLIDATION BENEFIT:**
    # - All tool resolution delegated to RAAF::ToolRegistry.safe_lookup
    # - Single source of truth for tool resolution logic
    # - Eliminates 50+ lines of duplicate code
    # - Simplifies maintenance and reduces complexity
    #
    # This ensures:
    # - Compatible with eager loading in acceptance/production
    # - Compatible with lazy loading in development
    # - Compatible with job contexts (loads agents before RAAF modules)
    # - Clear error messages at class definition time (not silent runtime failures)
    # - No timing dependencies between ToolRegistry and agent loading
    #
    module AgentToolIntegration
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Unified tool method for adding tools to agents
        #
        # Implements HYBRID EAGER/LAZY RESOLUTION with defensive NameError handling:
        # 1. **Symbol identifiers** (e.g., :web_search)
        #    - Attempts eager resolution via ToolRegistry.safe_lookup
        #    - If ToolRegistry unavailable (NameError), defers to lazy resolution
        #    - Enables compatibility with job contexts and early agent loading
        #
        # 2. **Class identifiers** (e.g., MyTool)
        #    - Resolved immediately (no registry needed)
        #    - Stored directly in configuration
        #    - Always available at class definition time
        #
        # 3. **Configuration options** (optional)
        #    - Applied to the tool at instantiation time
        #    - Can be combined with block syntax for flexibility
        #
        # @param tool_identifier [Symbol, String, Class] Tool to add
        #   - Symbol: Will be looked up in ToolRegistry (eager) or deferred (lazy)
        #   - String: Converted to Symbol and treated as Symbol
        #   - Class: Resolved immediately, no registry lookup needed
        # @param options [Hash] Tool configuration options (optional)
        # @yield Configuration block for additional setup (optional)
        #
        # @return [void] Modifies agent's tool configuration
        #
        # @example Symbol identifier with auto-discovery (eager loading)
        #   tool :web_search
        #   # Resolves from registry when ToolRegistry is available
        #
        # @example Symbol identifier with deferred resolution (job context)
        #   tool :web_search
        #   # If ToolRegistry not available at class definition time,
        #   # stores identifier for runtime resolution (when agent is instantiated)
        #
        # @example Direct class reference (no registry needed)
        #   tool WebSearchTool
        #   # Resolved immediately at class definition time
        #
        # @example With configuration options
        #   tool :tavily_search, max_results: 20, timeout: 30
        #
        # @example With configuration block
        #   tool :api_tool do
        #     api_key ENV["API_KEY"]
        #     timeout 30
        #     max_retries 3
        #   end
        #
        # @example Combined options and block
        #   tool :calculator, timeout: 30 do
        #     precision :high
        #     enable_logging true
        #   end
        #
        # @note Job Context Compatibility
        #   This method is fully compatible with job contexts where agent classes
        #   are loaded before RAAF modules are available. If ToolRegistry constant
        #   doesn't exist at class definition time, symbol identifiers are deferred
        #   to runtime resolution, and resolution errors are raised only if the
        #   registry is still unavailable when the agent is instantiated.
        #
        def tool(tool_identifier = nil, **options, &block)
          # Handle block configuration
          if block_given?
            block_config = ToolConfigurationBuilder.new(&block).to_h
            options = options.merge(block_config)
          end

          # SPECIAL CASE: Google Search grounding configuration (provider-level, not a tool)
          # Gemini 2.0+: tool(google_search: {}) - recommended for current models
          # Gemini 1.5:  tool(google_search_retrieval: {}) - legacy support
          if options.key?(:google_search)
            # Passed as keyword argument: tool google_search: {} (Gemini 2.0+)
            _grounding_config[:google_search] = options[:google_search]
            return
          elsif tool_identifier.is_a?(Hash) && tool_identifier.key?(:google_search)
            # Passed as positional hash: tool({google_search: {}}) (Gemini 2.0+)
            _grounding_config[:google_search] = tool_identifier[:google_search]
            return
          elsif options.key?(:google_search_retrieval)
            # Passed as keyword argument: tool google_search_retrieval: {} (Gemini 1.5 legacy)
            _grounding_config[:google_search_retrieval] = options[:google_search_retrieval]
            return
          elsif tool_identifier.is_a?(Hash) && tool_identifier.key?(:google_search_retrieval)
            # Passed as positional hash: tool({google_search_retrieval: {}}) (Gemini 1.5 legacy)
            _grounding_config[:google_search_retrieval] = tool_identifier[:google_search_retrieval]
            return
          end

          # tool_identifier is required for regular tools. A blank string names no
          # tool any more than nil does, so it is rejected the same way rather
          # than going on to produce a "tool not found: " resolution error.
          if tool_identifier.nil? || (tool_identifier.respond_to?(:empty?) && tool_identifier.empty?)
            raise ArgumentError, "tool_identifier is required for tool registration"
          end

          # HYBRID RESOLUTION: Try eager resolution, fall back to lazy if registry not available
          # This ensures:
          # - Eager resolution when ToolRegistry is available (development, some eager_load scenarios)
          # - Lazy resolution when ToolRegistry isn't available yet (acceptance with early agent loading)
          # - Clear error only if resolution fails at runtime (when registry is definitely available)
          tool_class = begin
            result = RAAF::ToolRegistry.safe_lookup(tool_identifier)
            result
          rescue NameError => e
            # ToolRegistry constant not available yet - defer to lazy resolution
            raise unless e.message.include?("RAAF::ToolRegistry") || e.message.include?("uninitialized constant")

            nil
          end

          # Store either the resolved class OR the identifier for lazy resolution later
          config = {
            options: options
          }

          if tool_class.nil? && tool_identifier.is_a?(Symbol)
            # Could not resolve yet (registry might not be available), store identifier for lazy resolution
            config[:tool_identifier] = tool_identifier
          elsif tool_class.nil?
            # For non-symbol identifiers, must resolve immediately
            # Get detailed resolution info for error reporting
            begin
              details = RAAF::ToolRegistry.resolve_with_details(tool_identifier)
              raise ToolResolutionError.new(
                tool_identifier,
                details[:searched_namespaces],
                details[:suggestions]
              )
            rescue NameError => e
              # ToolRegistry not fully loaded yet - provide simpler error message
              raise unless e.message.include?("RAAF::ToolRegistry") || e.message.include?("uninitialized constant")

              raise ToolResolutionError.new(
                tool_identifier,
                ["RAAF::ToolRegistry (not yet loaded)"],
                ["Ensure the tool is registered in config/application.rb before eager loading"]
              )
            end
          else
            # Successfully resolved at class definition time
            config[:tool_class] = tool_class
          end

          _tools_config << config
        end

        # Add multiple tools at once
        def tools(*tool_identifiers, **shared_options)
          tool_identifiers.each do |identifier|
            tool(identifier, **shared_options)
          end
        end
      end

      # Instance methods for tool management

      # Build tool instances from configuration
      #
      # Tool resolution may have happened at class definition time (eager) or will happen
      # now at runtime (lazy). This method instantiates resolved tools.
      #
      # THIS IS THE MODULE VERSION (AgentToolIntegration)
      def build_tools_from_config
        tools = self.class._tools_config.map do |config|
          create_tool_instance_unified(config)
        end.compact

        # Append grounding configuration if present (provider-level, not a tool instance).
        # Grounding is an optional feature that the host class opts into by
        # defining _grounding_config, so this module does not require it.
        grounding_config = self.class.respond_to?(:_grounding_config) ? self.class._grounding_config : nil
        if grounding_config.present?
          # Convert to plain Hash for provider consumption
          # Support both Gemini 2.0+ (google_search) and Gemini 1.5 (google_search_retrieval)
          if grounding_config.key?(:google_search)
            tools << { google_search: grounding_config[:google_search] }
          elsif grounding_config.key?(:google_search_retrieval)
            tools << { google_search_retrieval: grounding_config[:google_search_retrieval] }
          end
        end

        tools
      end

      # Create a tool instance from configuration
      #
      # @param config [Hash] Tool configuration with resolved tool_class OR tool_identifier for lazy resolution
      # @return [Object, nil] Instantiated tool, or nil if the tool class itself
      #   raised while being built (which is logged and skipped)
      # @raise [ToolResolutionError] if a deferred identifier still cannot be resolved
      def create_tool_instance_unified(config)
        tool_class = config[:tool_class]

        # If tool_class not resolved at class definition time (lazy resolution), resolve now.
        # This is the last chance to resolve a deferred symbol identifier, so a
        # failure here is reported rather than swallowed - otherwise the agent
        # silently ends up with fewer tools than it declared.
        if tool_class.nil? && config[:tool_identifier].present?
          identifier = config[:tool_identifier]

          # Check if ToolRegistry is available before trying to use it
          if defined?(RAAF::ToolRegistry).nil?
            raise ToolResolutionError.new(
              identifier,
              ["RAAF::ToolRegistry (not available at runtime)"],
              ["Ensure raaf-core is loaded before the agent is instantiated"]
            )
          end

          begin
            tool_class = RAAF::ToolRegistry.safe_lookup(identifier)
          rescue NameError => e
            raise ToolResolutionError.new(
              identifier,
              ["RAAF::ToolRegistry (raised #{e.class})"],
              [e.message]
            )
          end

          if tool_class.nil?
            details = begin
              RAAF::ToolRegistry.resolve_with_details(identifier)
            rescue StandardError
              { searched_namespaces: [], suggestions: [] }
            end

            raise ToolResolutionError.new(
              identifier,
              details[:searched_namespaces],
              details[:suggestions]
            )
          end
        end

        # If still no tool_class, the config itself is malformed
        if tool_class.nil?
          raise ArgumentError,
                "Tool configuration has neither :tool_class nor :tool_identifier: #{config.inspect}"
        end

        options = config[:options] || {}

        begin
          # Instantiate the tool with options
          tool_instance = tool_class.new(**options)

          # For native tools, return as-is
          return tool_instance if config[:native]

          # For regular tools, ensure FunctionTool compatibility
          if tool_instance.respond_to?(:to_function_tool)
            tool_instance.to_function_tool
          else
            tool_instance
          end
        rescue StandardError => e
          # A tool that fails to build is skipped rather than taking the whole
          # agent down, but it is reported - silently dropping it is how an
          # agent ends up quietly running with fewer tools than it declared.
          RAAF.logger.warn(
            "[RAAF] Skipping tool #{tool_class}: #{e.class}: #{e.message}"
          )
          nil
        end
      end

      # Tool configuration builder for block syntax
      class ToolConfigurationBuilder
        def initialize(&block)
          @config = {}
          instance_eval(&block) if block_given?
        end

        def method_missing(method_name, *args)
          @config[method_name] = if args.length == 1
                                   args.first
                                 elsif args.empty?
                                   true
                                 else
                                   args
                                 end
        end

        def respond_to_missing?(method_name, include_private = false)
          true
        end

        def to_h
          @config
        end
      end
    end
  end
end
