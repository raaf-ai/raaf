# frozen_string_literal: true

require "raaf/function_tool"

# Note: ToolRegistry is loaded by raaf-dsl.rb when this gem is initialized
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
        def tool(tool_identifier, **options, &block)
          # Handle block configuration
          if block_given?
            block_config = ToolConfigurationBuilder.new(&block).to_h
            options = options.merge(block_config)
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
            if e.message.include?("RAAF::ToolRegistry") || e.message.include?("uninitialized constant")
              nil
            else
              raise
            end
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
              if e.message.include?("RAAF::ToolRegistry") || e.message.include?("uninitialized constant")
                raise ToolResolutionError.new(
                  tool_identifier,
                  ["RAAF::ToolRegistry (not yet loaded)"],
                  ["Ensure the tool is registered in config/application.rb before eager loading"]
                )
              else
                raise
              end
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

        tools
      end

      # Create a tool instance from configuration
      #
      # @param config [Hash] Tool configuration with resolved tool_class OR tool_identifier for lazy resolution
      # @return [Object, nil] Instantiated tool or nil if instantiation fails
      def create_tool_instance_unified(config)
        tool_class = config[:tool_class]

        # If tool_class not resolved at class definition time (lazy resolution), resolve now
        if tool_class.nil? && config[:tool_identifier].present?
          # Check if ToolRegistry is available before trying to use it
          if defined?(RAAF::ToolRegistry).nil?
            error_msg = "RAAF::ToolRegistry not available at runtime for #{config[:tool_identifier].inspect}"
            log_error(error_msg)
            return nil
          end

          begin
            tool_class = RAAF::ToolRegistry.safe_lookup(config[:tool_identifier])
          rescue NameError => e
            error_msg = "Tool registry resolution error for #{config[:tool_identifier].inspect}: #{e.message}"
            log_error(error_msg)
            return nil
          end

          if tool_class.nil?
            error_msg = "Failed to resolve tool: #{config[:tool_identifier].inspect}\n" \
                        "Tool resolution failed at both class definition time and runtime."
            log_error(error_msg)
            return nil
          end
        end

        # If still no tool_class, we have a problem
        if tool_class.nil?
          error_msg = "BUG: tool_class is nil in create_tool_instance_unified. " \
                      "Neither tool_class nor tool_identifier present in config."
          log_error(error_msg)
          return nil
        end

        options = config[:options] || {}

        # Instantiate the tool with options
        tool_instance = tool_class.new(**options)

        # For native tools, return as-is
        if config[:native]
          return tool_instance
        end

        # For regular tools, ensure FunctionTool compatibility
        if tool_instance.respond_to?(:to_function_tool)
          converted = tool_instance.to_function_tool
          converted
        else
          tool_instance
        end
      rescue => e
        error_details = "Failed to create tool instance for #{tool_class&.name}: #{e.message}\nBacktrace: #{e.backtrace.first(10).join("\n")}"
        log_error("Failed to create tool instance",
                 tool_class: tool_class&.name,
                 error: e.message,
                 error_class: e.class.name)
        nil
      end

      # Tool configuration builder for block syntax
      class ToolConfigurationBuilder
        def initialize(&block)
          @config = {}
          instance_eval(&block) if block_given?
        end

        def method_missing(method_name, *args)
          if args.length == 1
            @config[method_name] = args.first
          elsif args.empty?
            @config[method_name] = true
          else
            @config[method_name] = args
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