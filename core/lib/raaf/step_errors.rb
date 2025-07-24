# frozen_string_literal: true

require_relative "logging"

module RAAF

  module Errors

    ##
    # Base error class for step processing issues
    #
    class StepProcessingError < StandardError

      attr_reader :agent, :step_data

      def initialize(message, agent: nil, step_data: nil)
        super(message)
        @agent = agent
        @step_data = step_data
      end

    end

    ##
    # Error for model behavior that violates expectations
    #
    class ModelBehaviorError < StepProcessingError

      attr_reader :model_response

      def initialize(message, model_response: nil, **)
        super(message, **)
        @model_response = model_response
      end

    end

    ##
    # Error for user configuration or input issues
    #
    class UserError < StepProcessingError; end

    ##
    # Error for agent execution issues
    #
    class AgentError < StepProcessingError; end

    ##
    # Error for tool execution failures
    #
    class ToolExecutionError < StepProcessingError

      attr_reader :tool, :tool_arguments, :original_error

      def initialize(message, tool: nil, tool_arguments: nil, original_error: nil, **)
        super(message, **)
        @tool = tool
        @tool_arguments = tool_arguments
        @original_error = original_error
      end

      def tool_name
        @tool.respond_to?(:name) ? @tool.name : @tool.to_s
      end

    end

    ##
    # Error for handoff failures
    #
    class HandoffError < StepProcessingError

      attr_reader :source_agent, :target_agent, :handoff_data

      def initialize(message, source_agent: nil, target_agent: nil, handoff_data: nil, **)
        super(message, **)
        @source_agent = source_agent
        @target_agent = target_agent
        @handoff_data = handoff_data
      end

    end

    ##
    # Error for response processing failures
    #
    class ResponseProcessingError < StepProcessingError

      attr_reader :response

      def initialize(message, response: nil, **)
        super(message, **)
        @response = response
      end

    end

    ##
    # Error for circular handoff detection
    #
    class CircularHandoffError < HandoffError

      attr_reader :handoff_chain

      def initialize(message, handoff_chain: nil, **)
        super(message, **)
        @handoff_chain = handoff_chain
      end

    end

    ##
    # Error for maximum iterations exceeded
    #
    class MaxIterationsError < StepProcessingError

      attr_reader :max_iterations, :current_iterations

      def initialize(message, max_iterations: nil, current_iterations: nil, **)
        super(message, **)
        @max_iterations = max_iterations
        @current_iterations = current_iterations
      end

    end

  end

  ##
  # Error handling utilities for step processing
  #
  module ErrorHandling

    extend RAAF::Logger

    ##
    # Safely execute a block with comprehensive error handling
    #
    # @param context [Hash] Context information for error reporting
    # @param agent [Agent, nil] Current agent for error context
    # @yield Block to execute with error handling
    # @return [Object] Result of the block
    # @raise [StepProcessingError] Re-raised with context if block fails
    #
    def self.with_error_handling(context: {}, agent: nil)
      yield
    rescue Errors::StepProcessingError => e
      # Already a step processing error, just re-raise with additional context
      e.define_singleton_method(:context) { context }
      e.define_singleton_method(:agent) { agent } unless e.agent

      # Log with full context and stack trace
      log_exception(e, message: "Step processing error re-raised", context: context, agent: agent&.name)
      raise e
    rescue JSON::ParserError => e
      error = Errors::ResponseProcessingError.new(
        "Failed to parse JSON: #{e.message}",
        agent: agent
      )

      # Log original exception details
      log_exception(e, message: "JSON parsing failed", context: context, agent: agent&.name)
      raise error
    rescue NoMethodError => e
      error = if e.message.include?("undefined method") && e.message.include?("nil:NilClass")
                Errors::ModelBehaviorError.new(
                  "Unexpected nil value in model response: #{e.message}",
                  agent: agent
                )
              else
                Errors::AgentError.new(
                  "Agent execution error: #{e.message}",
                  agent: agent
                )
              end

      # Log original exception details
      log_exception(e, message: "NoMethodError in step processing", context: context, agent: agent&.name)
      raise error
    rescue StandardError => e
      error = Errors::StepProcessingError.new(
        "Unexpected error in step processing: #{e.message}",
        agent: agent
      )

      # Log original exception details
      log_exception(e, message: "Unexpected error in step processing", context: context, agent: agent&.name)
      raise error
    end

    ##
    # Create error-safe wrapper for tool execution
    #
    # @param tool [Object] Tool to execute
    # @param arguments [Hash] Tool arguments
    # @param agent [Agent] Current agent
    # @yield Block that executes the tool
    # @return [Object] Tool result or error message
    #
    def self.safe_tool_execution(tool:, arguments:, agent:, &)
      with_error_handling(context: { tool: tool, arguments: arguments }, agent: agent, &)
    rescue Errors::ToolExecutionError => e
      # Log the tool execution error with full context
      log_exception(e.original_error, message: "Tool execution failed",
                                      tool: e.tool_name, agent: agent&.name, arguments: arguments)

      # Convert to user-friendly error message
      "Error executing tool #{e.tool_name}: #{e.message}"
    rescue Errors::StepProcessingError => e
      # Already logged in with_error_handling, just return user-friendly message
      "Error: #{e.message}"
    end

    ##
    # Validate model response structure
    #
    # @param response [Hash] Model response to validate
    # @param agent [Agent] Current agent for context
    # @return [void]
    # @raise [ModelBehaviorError] If response is invalid
    #
    def self.validate_model_response(response, agent)
      if response.nil?
        raise Errors::ModelBehaviorError.new(
          "Model response is nil",
          agent: agent
        )
      end

      unless response.is_a?(Hash)
        raise Errors::ModelBehaviorError.new(
          "Model response is not a hash",
          model_response: response,
          agent: agent
        )
      end

      # Validate basic response structure
      return unless response[:output].nil? && response[:choices].nil? && response[:content].nil?

      raise Errors::ModelBehaviorError.new(
        "Model response missing expected content structure",
        model_response: response,
        agent: agent
      )
    end

    ##
    # Safely normalize agent identifier
    #
    # @param agent_id [Agent, String, nil] Agent identifier to normalize
    # @return [String, nil] Normalized agent name or nil
    #
    def self.safe_agent_name(agent_id)
      case agent_id
      when nil
        nil
      when String
        agent_id
      when Agent
        agent_id.name
      else
        agent_id.respond_to?(:name) ? agent_id.name : agent_id.to_s
      end
    end

  end

end
