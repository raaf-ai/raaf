# frozen_string_literal: true

module RAAF

  module Config

    ##
    # Configuration for execution control
    #
    # This class handles parameters that control how the agent execution
    # flows, including turn limits, hooks, and guardrails.
    #
    # @example Basic execution configuration
    #   config = ExecutionConfig.new(
    #     max_turns: 10,
    #     hooks: MyCustomHooks.new,
    #     input_guardrails: [ContentFilter.new],
    #     output_guardrails: [SafetyCheck.new]
    #   )
    #
    # @example Checking for configured features
    #   config.has_hooks? # => true
    #   config.has_input_guardrails? # => true
    #   config.has_output_guardrails? # => true
    #
    # @example Getting effective max turns
    #   effective_turns = config.effective_max_turns(agent)
    #   # Uses config max_turns or falls back to agent.max_turns
    #
    class ExecutionConfig

      # @return [Integer] Maximum number of agent turns (default: from agent)
      attr_accessor :max_turns

      # @return [RunHooks, nil] Lifecycle hooks for this run
      attr_accessor :hooks

      # @return [Array<Guardrails::InputGuardrail>, nil] Input guardrails for this run
      attr_accessor :input_guardrails

      # @return [Array<Guardrails::OutputGuardrail>, nil] Output guardrails for this run
      attr_accessor :output_guardrails

      # @return [Object, nil] Context object for dependency injection (Python SDK compatible)
      attr_accessor :context

      # @return [Session, nil] Session object for conversation history management (Python SDK compatible)
      attr_accessor :session

      def initialize(
        max_turns: nil,
        hooks: nil,
        input_guardrails: nil,
        output_guardrails: nil,
        context: nil,
        session: nil
      )
        @max_turns = max_turns
        @hooks = hooks
        @input_guardrails = input_guardrails
        @output_guardrails = output_guardrails
        @context = context
        @session = session
      end

      ##
      # Check if hooks are configured
      #
      # @return [Boolean] true if hooks are present
      #
      def hooks?
        !hooks.nil?
      end

      ##
      # Check if input guardrails are configured
      #
      # @return [Boolean] true if input guardrails are present
      #
      def input_guardrails?
        input_guardrails && !input_guardrails.empty?
      end

      ##
      # Check if output guardrails are configured
      #
      # @return [Boolean] true if output guardrails are present
      #
      def output_guardrails?
        output_guardrails && !output_guardrails.empty?
      end

      ##
      # Get effective max turns, using agent default if not specified
      #
      # @param agent [Agent] Agent to get default from
      # @return [Integer] Max turns to use
      #
      def effective_max_turns(agent)
        max_turns || agent.max_turns
      end

      ##
      # Merge with another ExecutionConfig, with other taking precedence
      #
      # @param other [ExecutionConfig] Config to merge
      # @return [ExecutionConfig] New merged config
      #
      def merge(other)
        return self unless other

        self.class.new(
          max_turns: other.max_turns || max_turns,
          hooks: other.hooks || hooks,
          input_guardrails: other.input_guardrails || input_guardrails,
          output_guardrails: other.output_guardrails || output_guardrails
        )
      end

      ##
      # Convert to hash representation
      #
      # @return [Hash] All configuration as hash
      #
      def to_h
        {
          max_turns: max_turns,
          hooks: hooks,
          input_guardrails: input_guardrails,
          output_guardrails: output_guardrails
        }
      end

    end

  end

end
