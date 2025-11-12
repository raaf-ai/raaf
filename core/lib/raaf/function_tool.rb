# frozen_string_literal: true

require_relative "errors"
require_relative "logging"
require_relative "throttler"
require_relative "throttle_config"

module RAAF

  ##
  # FunctionTool wraps Ruby callables to make them available as tools for AI agents
  #
  # This class provides a standardized interface for agent tools, handling:
  # - Parameter extraction and validation
  # - Tool execution with proper error handling
  # - Dynamic enabling/disabling based on context
  # - Conversion to OpenAI-compatible tool definitions
  #
  # Tools extend agent capabilities by allowing them to execute code,
  # call APIs, or perform any custom logic defined in Ruby.
  #
  # Supports any callable object including Methods, Procs, and DSL tool instances.
  #
  # @example Creating a tool from a method
  #   def get_weather(city:, unit: "celsius")
  #     "Weather in #{city}: 22°#{unit[0].upcase}"
  #   end
  #
  #   tool = FunctionTool.new(method(:get_weather))
  #   result = tool.call(city: "Paris")  # => "Weather in Paris: 22°C"
  #
  # @example Creating a tool from a proc with custom metadata
  #   calculator = FunctionTool.new(
  #     proc { |expression:| eval(expression) },
  #     name: "calculator",
  #     description: "Evaluates mathematical expressions",
  #     parameters: {
  #       type: "object",
  #       properties: {
  #         expression: { type: "string", description: "Math expression to evaluate" }
  #       },
  #       required: ["expression"]
  #     }
  #   )
  #
  # @example Creating a tool from a DSL tool instance
  #   class CustomTool
  #     def call(**kwargs)
  #       "Processed: #{kwargs.inspect}"
  #     end
  #   end
  #
  #   tool = FunctionTool.new(CustomTool.new, name: "custom")
  #   result = tool.call(data: "test")  # => "Processed: {:data=>\"test\"}"
  #
  # @example Dynamic tool enabling based on context
  #   admin_tool = FunctionTool.new(
  #     proc { |action:| perform_admin_action(action) },
  #     name: "admin_action",
  #     is_enabled: proc { |context| context.user.admin? }
  #   )
  #
  class FunctionTool

    include Logger
    include Throttler
    include RAAF::Tracing::Traceable
    trace_as :tool

    # @!attribute [r] name
    #   @return [String] The tool's name used for identification
    # @!attribute [r] description
    #   @return [String] Human-readable description of what the tool does
    # @!attribute [r] parameters
    #   @return [Hash] JSON Schema describing the tool's parameters
    # @!attribute [r] callable
    #   @return [Method, Proc, Object] The underlying Ruby callable (any object with #call method)
    # @!attribute [rw] is_enabled
    #   @return [Boolean, Proc, nil] Controls whether the tool is available
    attr_reader :name, :description, :parameters, :callable
    attr_accessor :is_enabled

    ##
    # Initialize a new FunctionTool
    #
    # @param callable [Method, Proc, Object] The Ruby callable to wrap (any object with #call method)
    # @param name [String, nil] Optional tool name (extracted from callable if nil)
    # @param description [String, nil] Optional description
    # @param parameters [Hash, nil] Optional parameter schema (auto-extracted if nil)
    # @param is_enabled [Boolean, Proc, nil] Optional enablement control
    # @param throttle [Hash, nil] Optional throttle configuration (rpm:, burst:, timeout:, enabled:)
    #
    # @example Auto-extraction from method
    #   def search(query:)
    #     # search implementation
    #   end
    #   tool = FunctionTool.new(method(:search))
    #   # name: "search", parameters extracted automatically
    #
    # @example Custom parameters for complex types
    #   tool = FunctionTool.new(
    #     proc { |data:| process(data) },
    #     parameters: {
    #       type: "object",
    #       properties: {
    #         data: {
    #           type: "object",
    #           properties: {
    #             items: { type: "array", items: { type: "string" } }
    #           }
    #         }
    #       }
    #     }
    #   )
    #
    # @example With throttling enabled
    #   tool = FunctionTool.new(
    #     method(:expensive_api_call),
    #     throttle: { rpm: 60, enabled: true }
    #   )
    #
    def initialize(callable, name: nil, description: nil, parameters: nil, is_enabled: nil, throttle: nil)
      @callable = callable
      @name = name || extract_name(callable)
      @description = description || extract_description(callable)

      # Initialize throttle configuration
      initialize_throttle_config

      # Apply throttle configuration if provided
      configure_throttle(**throttle) if throttle.is_a?(Hash)

      # Debug logging for parameter handling
      log_debug_tools("FunctionTool.new called",
                      tool_name: @name,
                      parameters_provided: !parameters.nil?,
                      parameters_value: parameters&.inspect)

      # IMPORTANT: Only extract parameters if not explicitly provided
      # This ensures we use the DSL-defined parameters when available
      @parameters = if parameters.nil?
                      extracted = extract_parameters(callable)
                      log_debug_tools("Extracted parameters",
                                      tool_name: @name,
                                      extracted_parameters: extracted.inspect)
                      extracted
                    else
                      log_debug_tools("Using provided parameters",
                                      tool_name: @name,
                                      provided_parameters: parameters.inspect)
                      parameters
                    end
      @is_enabled = is_enabled # Can be a Proc, boolean, or nil
    end

    ##
    # Execute the tool with the given arguments
    #
    # This method handles both keyword and positional argument styles,
    # automatically adapting to the callable's parameter expectations.
    # If throttling is enabled, the execution will be rate-limited.
    #
    # @param kwargs [Hash] Keyword arguments to pass to the tool
    # @return [Object] The result from the tool execution
    # @raise [ToolError] If the callable is invalid or execution fails
    # @raise [ThrottleTimeoutError] If throttle timeout is exceeded
    #
    # @example Calling a tool
    #   tool = FunctionTool.new(method(:search))
    #   result = tool.call(query: "Ruby programming")
    #
    # @example Error handling
    #   begin
    #     result = tool.call(invalid_param: "value")
    #   rescue RAAF::ToolError => e
    #     puts "Tool failed: #{e.message}"
    #   end
    #
    def call(**kwargs)
      with_throttle(:call) do
        if @callable.is_a?(Method)
          @callable.call(**kwargs)
        elsif @callable.is_a?(Proc)
          # Handle both keyword and positional parameters for procs
          params = @callable.parameters
          if params.empty? || params.any? { |type, _| %i[keyreq key keyrest].include?(type) }
            # Proc expects keyword arguments or no arguments
            @callable.call(**kwargs)
          else
            # Proc expects positional arguments
            args = params.map { |_type, name| kwargs[name] }
            @callable.call(*args)
          end
        elsif @callable.respond_to?(:call)
          # Support duck typing for any object that responds to :call
          # This includes DSL tool instances and other callable objects
          @callable.call(**kwargs)
        else
          raise ToolError, "Callable must be a Method, Proc, or object that responds to :call"
        end
      end
    rescue StandardError => e
      raise ToolError, "Error executing tool '#{@name}': #{e.message}"
    end

    ##
    # Check if tool is enabled for the given context
    #
    # @param context [RunContextWrapper, nil] current run context
    # @return [Boolean] true if tool is enabled
    def enabled?(context = nil)
      case @is_enabled
      when true, nil
        true
      when false
        false
      when Proc
        begin
          if @is_enabled.arity.zero?
            @is_enabled.call
          else
            @is_enabled.call(context)
          end
        rescue StandardError => e
          log_warn("Error evaluating tool enabled state", tool: @name, error: e.message, error_class: e.class.name)
          false
        end
      else
        !!@is_enabled
      end
    end

    ##
    # Check if tool is callable (has valid callable)
    #
    # @return [Boolean] true if tool has a valid callable, false otherwise
    def callable?
      @callable.is_a?(Method) || @callable.is_a?(Proc) || @callable.respond_to?(:call)
    end

    ##
    # Check if tool has parameters defined
    #
    # @return [Boolean] true if tool has parameters, false otherwise
    def parameters?
      return false unless @parameters && @parameters[:properties]

      @parameters[:properties].any?
    end

    ##
    # Check if tool has required parameters
    #
    # @return [Boolean] true if tool has required parameters, false otherwise
    def required_parameters?
      return false unless @parameters && @parameters[:required]

      @parameters[:required].any?
    end

    ##
    # Get enabled tools from a collection
    #
    # @param tools [Array<FunctionTool>] collection of tools
    # @param context [RunContextWrapper, nil] current run context
    # @return [Array<FunctionTool>] enabled tools only
    def self.enabled_tools(tools, context = nil)
      tools.select do |tool|
        # Handle simple hash tools (like web_search) that don't have enabled? method
        if tool.respond_to?(:enabled?)
          tool.enabled?(context)
        else
          true # Simple hash tools and tools without enabled? method are always enabled
        end
      end
    end

    ##
    # Convert the tool to an OpenAI-compatible tool definition
    #
    # This method generates the JSON structure expected by OpenAI's API
    # for function calling, including the tool's metadata and parameter schema.
    #
    # @return [Hash] OpenAI-compatible tool definition
    #
    # @example Tool definition structure
    #   tool.to_h
    #   # => {
    #   #   type: "function",
    #   #   name: "search",
    #   #   function: {
    #   #     name: "search",
    #   #     description: "Search for information",
    #   #     parameters: {
    #   #       type: "object",
    #   #       properties: {
    #   #         query: { type: "string", description: "Search query" }
    #   #       },
    #   #       required: ["query"]
    #   #     }
    #   #   }
    #   # }
    #
    def to_h
      # Create a copy of parameters with string keys for API compliance
      api_parameters = @parameters.dup
      if api_parameters && api_parameters[:required]
        api_parameters = api_parameters.dup
        api_parameters[:required] = api_parameters[:required].map(&:to_s)
      end

      result = {
        type: "function",
        name: @name,
        function: {
          name: @name,
          description: @description,
          parameters: api_parameters
        }
      }

      # Debug logging for to_h output
      log_debug_tools("FunctionTool.to_h generated",
                      tool_name: @name,
                      result_size: result.to_s.length,
                      has_parameters: !result.dig(:function, :parameters).nil?,
                      properties_count: result.dig(:function, :parameters, :properties)&.keys&.length || 0,
                      required_count: result.dig(:function, :parameters, :required)&.length || 0)

      result
    end

    private

    ##
    # Extract a name from the callable
    #
    # @param callable [Method, Proc, Object] The callable to extract name from
    # @return [String] The extracted or generated name
    #
    def extract_name(callable)
      if callable.respond_to?(:name) && callable.name
        callable.name.to_s
      elsif callable.class.respond_to?(:name)
        # Use class name for instances without their own name
        callable.class.name.split("::").last.downcase
      else
        "anonymous_function"
      end
    end

    ##
    # Extract a description for the tool
    #
    # @param callable [Method, Proc] The callable (currently unused)
    # @return [String] A generic description
    # @todo Implement extraction from method documentation/comments
    #
    def extract_description(_callable)
      # Try to extract from method comments or documentation
      "A function tool"
    end

    ##
    # Extract parameter information from the callable's signature
    #
    # This method analyzes the callable's parameters to generate a JSON Schema
    # that describes the expected input format for the tool.
    #
    # @param callable [Method, Proc, Object] The callable to analyze
    # @return [Hash] JSON Schema describing the parameters
    #
    # @example Parameter extraction
    #   def example(required_param:, optional_param: "default")
    #     # ...
    #   end
    #
    #   # Extracts to:
    #   # {
    #   #   type: "object",
    #   #   properties: {
    #   #     required_param: { type: "string", description: "required_param parameter" },
    #   #     optional_param: { type: "string", description: "optional_param parameter" }
    #   #   },
    #   #   required: ["required_param"]
    #   # }
    #
    def extract_parameters(callable)
      # Extract parameter information from the callable
      properties = {}
      required = []

      if callable.respond_to?(:parameters)
        callable.parameters.each do |type, name|
          case type
          when :req, :keyreq
            properties[name] = { type: "string", description: "#{name} parameter" }
            required << name
          when :opt, :key
            properties[name] = { type: "string", description: "#{name} parameter" }
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

  end

end
