# frozen_string_literal: true

require_relative "errors"

module OpenAIAgents
  class FunctionTool
    attr_reader :name, :description, :parameters, :callable

    def initialize(callable, name: nil, description: nil, parameters: nil)
      @callable = callable
      @name = name || extract_name(callable)
      @description = description || extract_description(callable)
      @parameters = parameters || extract_parameters(callable)
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

    def to_h
      {
        type: "function",
        function: {
          name: @name,
          description: @description,
          parameters: @parameters
        }
      }
    end

    private

    def extract_name(callable)
      if callable.is_a?(Method)
        callable.name.to_s
      # rubocop:disable Lint/DuplicateBranch
      elsif callable.respond_to?(:name)
        callable.name.to_s
      # rubocop:enable Lint/DuplicateBranch
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
