# frozen_string_literal: true

require_relative "errors"

module OpenAIAgents
  class FunctionTool
    attr_reader :name, :description, :parameters, :callable
    attr_accessor :is_enabled

    def initialize(callable, name: nil, description: nil, parameters: nil, is_enabled: nil)
      @callable = callable
      @name = name || extract_name(callable)
      @description = description || extract_description(callable)

      # Debug logging for parameter handling
      if defined?(Rails) && Rails.logger && Rails.env.development?
        Rails.logger.debug "🔧 FunctionTool.new called for #{@name}:"
        Rails.logger.debug "   Parameters provided: #{parameters.nil? ? "nil" : "yes"}"
        Rails.logger.debug "   Parameters value: #{parameters.inspect}" unless parameters.nil?
      end

      # IMPORTANT: Only extract parameters if not explicitly provided
      # This ensures we use the DSL-defined parameters when available
      @parameters = if parameters.nil?
                      extracted = extract_parameters(callable)
                      if defined?(Rails) && Rails.logger && Rails.env.development?
                        Rails.logger.debug "   Extracted parameters: #{extracted.inspect}"
                      end
                      extracted
                    else
                      if defined?(Rails) && Rails.logger && Rails.env.development?
                        Rails.logger.debug "   Using provided parameters: #{parameters.inspect}"
                      end
                      parameters
                    end
      @is_enabled = is_enabled # Can be a Proc, boolean, or nil
    end

    def call(**kwargs)
      if @callable.is_a?(Method)
        @callable.call(**kwargs)
      elsif @callable.is_a?(Proc)
        # Handle both keyword and positional parameters for procs
        params = @callable.parameters
        if params.empty? || params.any? { |type, _| %i[keyreq key].include?(type) }
          # Proc expects keyword arguments or no arguments
          @callable.call(**kwargs)
        else
          # Proc expects positional arguments
          args = params.map { |_type, name| kwargs[name] }
          @callable.call(*args)
        end
      else
        raise ToolError, "Callable must be a Method or Proc"
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
          if @is_enabled.arity == 0
            @is_enabled.call
          else
            @is_enabled.call(context)
          end
        rescue StandardError => e
          warn "Error evaluating tool enabled state: #{e.message}"
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
      @callable.is_a?(Method) || @callable.is_a?(Proc)
    end

    ##
    # Check if tool has parameters defined
    #
    # @return [Boolean] true if tool has parameters, false otherwise
    def parameters?
      @parameters && @parameters[:properties]&.any?
    end

    ##
    # Check if tool has required parameters
    #
    # @return [Boolean] true if tool has required parameters, false otherwise
    def required_parameters?
      @parameters && @parameters[:required]&.any?
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
        # rubocop:disable Style/RedundantCondition
        if tool.is_a?(Hash)
          true # Simple hash tools are always enabled
        else
          tool.enabled?(context)
        end
        # rubocop:enable Style/RedundantCondition
      end
    end

    def to_h
      result = {
        type: "function",
        name: @name,
        function: {
          name: @name,
          description: @description,
          parameters: @parameters
        }
      }

      # Debug logging for to_h output
      if defined?(Rails) && Rails.logger && Rails.env.development?
        Rails.logger.info "🔧 [FunctionTool.to_h] Tool: #{@name}"
        Rails.logger.info "   Result: #{result.inspect}"
        Rails.logger.info "   Parameters in result: #{result.dig(:function, :parameters).inspect}"
        if result.dig(:function, :parameters, :properties)
          Rails.logger.info "   Properties: #{result.dig(:function, :parameters, :properties).keys.join(", ")}"
          Rails.logger.info "   Required: #{result.dig(:function, :parameters, :required) || "none"}"
        end
      end

      result
    end

    private

    def extract_name(callable)
      if callable.is_a?(Method)
        callable.name.to_s
      elsif callable.respond_to?(:name) && callable.name
        callable.name.to_s
      else
        "anonymous_function"
      end
    end

    def extract_description(_callable)
      # Try to extract from method comments or documentation
      "A function tool"
    end

    def extract_parameters(callable)
      # Extract parameter information from the callable
      properties = {}
      required = []

      if callable.respond_to?(:parameters)
        callable.parameters.each do |type, name|
          case type
          when :req, :keyreq
            properties[name] = { type: "string", description: "#{name} parameter", required: true }
            required << name
          when :opt, :key
            properties[name] = { type: "string", description: "#{name} parameter", required: false }
          end
        end
      end

      {
        type: "object",
        properties: properties,
        required: required
      }
    end
  end
end
