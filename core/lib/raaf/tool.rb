# frozen_string_literal: true

begin
  require "raaf-core"
rescue LoadError
  # Allow standalone usage without full RAAF core
end

# ToolRegistry is now in raaf-dsl gem
# Try to require from raaf-dsl first, then fall back to local location for backward compatibility
begin
  require "raaf/tool_registry"  # raaf-dsl location
rescue LoadError
  # Fall back to local location if raaf-dsl not available
  require_relative "tool_registry"
end

module RAAF
  # Unified base class for all RAAF tools
  #
  # This class provides the foundation for all tools in the RAAF framework,
  # following convention over configuration principles. Tools automatically
  # register themselves, generate names and descriptions, and extract
  # parameters from method signatures.
  #
  # @example Basic tool definition
  #   class CalculatorTool < RAAF::Tool
  #     def call(expression:)
  #       eval(expression)
  #     end
  #   end
  #
  # @example Tool with configuration
  #   class SearchTool < RAAF::Tool
  #     configure name: "web_search", description: "Search the web"
  #     
  #     def call(query:, max_results: 10)
  #       # Search implementation
  #     end
  #   end
  #
  class Tool
    include RAAF::Logger

    class << self
      # Configure tool-level settings
      #
      # @param name [String] Explicit tool name
      # @param description [String] Tool description
      # @param enabled [Boolean] Whether tool is enabled by default
      def configure(name: nil, description: nil, enabled: true)
        @configured_name = name
        @configured_description = description
        @configured_enabled = enabled
      end

      # Define parameters explicitly
      #
      # @yield Block for parameter definition
      def parameters(&block)
        @parameter_builder = ParameterBuilder.new(&block)
      end

      # Hook called when a class inherits from Tool
      def inherited(subclass)
        super
        # Auto-register the tool when class is defined
        # Use a delayed registration to allow the class to be fully defined
        TracePoint.new(:end) do |tp|
          if tp.self == subclass
            tool_name = subclass.tool_name
            ToolRegistry.register(tool_name, subclass)
            tp.disable
          end
        end.enable
      end

      # Get the tool name (configured or generated)
      def tool_name
        @configured_name || generate_tool_name
      end

      # Get the tool description (configured or generated)
      def tool_description
        @configured_description || generate_tool_description
      end

      # Check if tool is enabled by default
      def tool_enabled?
        @configured_enabled.nil? ? true : @configured_enabled
      end

      # Get parameter builder if defined
      def parameter_builder
        @parameter_builder
      end

      private

      # Generate tool name from class name
      def generate_tool_name
        # Get the class name without namespace
        class_name = name.split("::").last
        # Remove Tool suffix and convert to snake_case
        class_name
          .gsub(/Tool$/, "")
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
      end

      # Generate description from class name
      def generate_tool_description
        class_name = name.split("::").last.gsub(/Tool$/, "")
        # Convert to human-readable format
        words = class_name
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1 \2')
          .gsub(/([a-z\d])([A-Z])/, '\1 \2')
          .downcase
        "Tool for #{words} operations"
      end
    end

    # Initialize a new tool instance
    #
    # @param options [Hash] Runtime configuration options
    def initialize(**options)
      @options = options
      log_debug_tools("Tool initialized", tool_name: name, options: options) if options.any?
    end

    # Execute the tool with given parameters
    #
    # This is the main method that must be implemented by subclasses.
    # It defines the tool's functionality.
    #
    # @param params [Hash] Parameters for tool execution
    # @return [Object] Result of tool execution
    # @raise [NotImplementedError] If not implemented by subclass
    def call(**params)
      raise NotImplementedError, "#{self.class.name} must implement #call method"
    end

    # Get the tool name
    #
    # @return [String] Tool name
    def name
      @options[:name] || self.class.tool_name
    end

    # Get the tool description
    #
    # @return [String] Tool description
    def description
      @options[:description] || self.class.tool_description
    end

    # Check if tool is enabled
    #
    # @return [Boolean] Whether tool is enabled
    def enabled?
      return @options[:enabled] if @options.key?(:enabled)
      self.class.tool_enabled?
    end

    # Get tool parameters schema
    #
    # @return [Hash] Parameter schema in JSON Schema format
    def parameters
      @parameters ||= build_parameters
    end

    # Check if this is a native tool
    #
    # @return [Boolean] false for regular tools
    def native?
      false
    end

    # Convert to FunctionTool for backward compatibility
    #
    # @return [FunctionTool] Compatible FunctionTool instance
    def to_function_tool
      log_debug_tools("Converting to FunctionTool", tool_name: name)
      
      FunctionTool.new(
        method(:call),
        name: name,
        description: description,
        parameters: parameters,
        is_enabled: enabled?
      )
    end

    # Generate tool definition for OpenAI API
    #
    # @return [Hash] Tool definition in OpenAI format
    def to_tool_definition
      {
        type: "function",
        function: {
          name: name,
          description: description,
          parameters: parameters
        }
      }
    end

    private

    # Build parameter schema from method signature or explicit definition
    def build_parameters
      # Use explicit parameters if defined
      if self.class.parameter_builder
        return self.class.parameter_builder.build
      end

      # Extract from method signature
      extract_parameters_from_method
    end

    # Extract parameters from the call method signature
    def extract_parameters_from_method
      method_obj = method(:call)
      properties = {}
      required = []

      method_obj.parameters.each do |type, name|
        next if name == :params # Skip **params

        case type
        when :keyreq
          properties[name] = {
            type: infer_type(name),
            description: "#{name} parameter"
          }
          required << name.to_s
        when :key
          properties[name] = {
            type: infer_type(name),
            description: "#{name} parameter"
          }
          
          # Try to get default value
          begin
            # This is a simplified approach; getting actual defaults requires more work
            properties[name][:description] += " (optional)"
          rescue
            # Ignore errors in getting defaults
          end
        end
      end

      {
        type: "object",
        properties: properties,
        required: required,
        additionalProperties: false
      }
    end

    # Infer parameter type from name
    def infer_type(name)
      case name.to_s
      when /count|limit|max|min|size|length/
        "integer"
      when /enabled|active|is_|has_/
        "boolean"
      when /data|items|results|list/
        "array"
      else
        "string"
      end
    end

    # Parameter builder for explicit parameter definition
    class ParameterBuilder
      def initialize(&block)
        @properties = {}
        @required = []
        instance_eval(&block) if block_given?
      end

      def property(name, type: "string", description: nil, enum: nil, **options)
        prop = { type: type }
        prop[:description] = description if description
        prop[:enum] = enum if enum
        prop.merge!(options)
        @properties[name] = prop
      end

      def required(*names)
        @required.concat(names.map(&:to_s))
      end

      def build
        {
          type: "object",
          properties: @properties,
          required: @required.uniq,
          additionalProperties: false
        }
      end
    end
  end
end