# frozen_string_literal: true

require "raaf/function_tool"

module RAAF
  module DSL
    # Tool integration methods for DSL Agent
    #
    # This module provides the unified tool interface for agents,
    # supporting auto-discovery, direct class references, and
    # backward compatibility with existing tool patterns.
    #
    module AgentToolIntegration
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Unified tool method for adding tools to agents
        #
        # @param tool_identifier [Symbol, String, Class] Tool to add
        # @param options [Hash] Configuration options
        # @yield Configuration block for tool setup
        #
        # @example Symbol auto-discovery
        #   tool :web_search
        #
        # @example Direct class reference
        #   tool WebSearchTool
        #
        # @example With options
        #   tool :tavily_search, max_results: 20
        #
        # @example With configuration block
        #   tool :api_tool do
        #     api_key ENV["API_KEY"]
        #     timeout 30
        #   end
        #
        def tool(tool_identifier, **options, &block)
          # Handle block configuration
          if block_given?
            block_config = ToolConfigurationBuilder.new(&block).to_h
            options = options.merge(block_config)
          end

          # LAZY LOADING: Store identifier without resolving
          # Resolution will happen during agent initialization
          _tools_config << {
            identifier: tool_identifier,
            tool_class: nil,  # Not resolved yet
            options: options,
            resolution_deferred: true  # Flag for lazy loading
          }
        end

        # Add multiple tools at once
        def tools(*tool_identifiers, **shared_options)
          tool_identifiers.each do |identifier|
            tool(identifier, **shared_options)
          end
        end

        # Backward compatibility aliases
        alias_method :uses_tool, :tool
        alias_method :uses_tools, :tools
        alias_method :uses_native_tool, :tool
      end

      # Instance methods for tool management
      
      # Build tool instances from configuration
      def build_tools_from_config
        self.class._tools_config.map do |config|
          create_tool_instance_unified(config)
        end.compact
      end

      # Create a tool instance from configuration
      def create_tool_instance_unified(config)
        tool_class = config[:tool_class]
        options = config[:options] || {}
        
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
      rescue => e
        log_error("Failed to create tool instance", 
                 tool_class: tool_class.name,
                 error: e.message)
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