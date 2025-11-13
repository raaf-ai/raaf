# frozen_string_literal: true

require 'securerandom'

module RAAF
  module Eval
    ##
    # Converts RAAF::RunResult objects to span-compatible format for evaluation.
    #
    # This adapter enables evaluation of fresh agent runs (from runner.run())
    # alongside historical span-based evaluation. It extracts agent configuration,
    # messages, and metadata from RunResult and converts them to the span format
    # expected by the evaluation engine.
    #
    # @example Convert RunResult to span format
    #   result = runner.run("What is 2+2?")
    #   span_data = RunResultAdapter.to_span(result, agent: agent)
    #   # => { agent_name: "Calculator", model: "gpt-4o", ... }
    #
    # @example Evaluate RunResult directly
    #   result = runner.run("Hello")
    #   evaluate_run_result(result, agent: agent)
    #     .with_configuration(temperature: 0.9)
    #     .run
    class RunResultAdapter
      class << self
        ##
        # Converts a RunResult to span-compatible hash suitable for evaluation.
        #
        # @param run_result [RAAF::RunResult] Result from runner.run()
        # @param agent [RAAF::Agent, nil] Optional agent for config extraction
        # @return [Hash] Span-compatible hash with agent config, messages, metadata
        #
        # @raise [ArgumentError] if run_result is nil or not a RunResult
        def to_span(run_result, agent: nil)
          validate_input!(run_result)

          {
            span_id: generate_span_id,
            trace_id: generate_trace_id,
            span_type: "agent",
            agent_name: extract_agent_name(run_result),
            model: extract_model(run_result, agent),
            instructions: extract_instructions(run_result, agent),
            parameters: extract_parameters(agent),
            input_messages: extract_input_messages(run_result),
            output_messages: extract_output_messages(run_result),
            metadata: build_metadata(run_result),
            source: "run_result",
            created_at: Time.now.utc
          }
        end

        private

        ##
        # Validates that the input is a valid RunResult object.
        #
        # @param run_result [Object] Object to validate
        # @raise [ArgumentError] if invalid
        def validate_input!(run_result)
          raise ArgumentError, "run_result cannot be nil" if run_result.nil?

          unless run_result.is_a?(RAAF::RunResult)
            raise ArgumentError, "Expected RAAF::RunResult, got #{run_result.class}"
          end
        end

        ##
        # Generates a unique span ID.
        #
        # @return [String] UUID for span identification
        def generate_span_id
          SecureRandom.uuid
        end

        ##
        # Generates a unique trace ID.
        #
        # @return [String] UUID for trace identification
        def generate_trace_id
          SecureRandom.uuid
        end

        ##
        # Extracts agent name from RunResult.
        #
        # @param run_result [RAAF::RunResult]
        # @return [String] Agent name or "unknown"
        def extract_agent_name(run_result)
          run_result.agent_name || "unknown"
        end

        ##
        # Extracts model name from agent or RunResult.
        #
        # Priority: agent.model > run_result.data[:model] > "unknown"
        #
        # @param run_result [RAAF::RunResult]
        # @param agent [RAAF::Agent, nil]
        # @return [String] Model identifier
        def extract_model(run_result, agent)
          return agent.model if agent&.model

          run_result.data&.dig(:model) || "unknown"
        end

        ##
        # Extracts agent instructions from agent or RunResult.
        #
        # Priority: agent.instructions > run_result.data[:instructions] > ""
        #
        # @param run_result [RAAF::RunResult]
        # @param agent [RAAF::Agent, nil]
        # @return [String] Agent instructions
        def extract_instructions(run_result, agent)
          return agent.instructions if agent&.instructions

          run_result.data&.dig(:instructions) || ""
        end

        ##
        # Extracts agent parameters (temperature, max_tokens, etc.).
        #
        # @param agent [RAAF::Agent, nil]
        # @return [Hash] Agent parameters or empty hash
        def extract_parameters(agent)
          return {} unless agent

          # Extract parameters from agent instance
          params = {}

          [:temperature, :max_tokens, :top_p, :frequency_penalty, :presence_penalty].each do |param|
            value = agent.instance_variable_get("@#{param}")
            params[param] = value if value
          end

          params
        end

        ##
        # Extracts input messages from RunResult.
        #
        # Returns all messages except the last (assistant) message.
        #
        # @param run_result [RAAF::RunResult]
        # @return [Array<Hash>] Input message history
        def extract_input_messages(run_result)
          messages = run_result.messages || []

          # If no messages, return empty array
          return [] if messages.empty?

          # Return all messages except the last one (which is the output)
          messages[0...-1]
        end

        ##
        # Extracts output message from RunResult.
        #
        # Returns the last message from the conversation.
        #
        # @param run_result [RAAF::RunResult]
        # @return [Array<Hash>] Output message(s)
        def extract_output_messages(run_result)
          messages = run_result.messages || []

          # Return empty array if no messages
          return [] if messages.empty?

          # Return the last message as an array
          [messages.last]
        end

        ##
        # Builds metadata from RunResult usage and execution data.
        #
        # @param run_result [RAAF::RunResult]
        # @return [Hash] Metadata including tokens, output, tools
        def build_metadata(run_result)
          metadata = {}

          # Token usage
          if run_result.usage
            metadata[:tokens] = run_result.usage[:total_tokens]
            metadata[:input_tokens] = run_result.usage[:input_tokens]
            metadata[:output_tokens] = run_result.usage[:output_tokens]

            # Reasoning tokens (for o1, o3, etc.)
            if run_result.usage[:output_tokens_details]
              metadata[:reasoning_tokens] = run_result.usage[:output_tokens_details][:reasoning_tokens]
            end
          end

          # Final output text
          metadata[:output] = run_result.final_output if run_result.final_output

          # Execution metadata
          metadata[:turns] = run_result.turns if run_result.turns
          metadata[:tool_results] = run_result.tool_results if run_result.tool_results && !run_result.tool_results.empty?

          # Compact to remove nil values
          metadata.compact
        end
      end
    end
  end
end
