# frozen_string_literal: true

module RAAF
  module Eval
    module RedTeam
      # Base class for all attack methods in red-teaming framework
      #
      # Attacks represent adversarial techniques used to expose vulnerabilities
      # in LLM applications. There are two main attack categories:
      #
      # 1. Single-Turn Attacks:
      #    - Execute in one shot without iterative refinement
      #    - Can be deterministic (encoding-based) or LLM-powered
      #    - Examples: Base64, PromptInjection, Roleplay, Leetspeak
      #
      # 2. Multi-Turn Attacks:
      #    - Execute over multiple conversational turns
      #    - Refine strategy based on model responses
      #    - Examples: LinearJailbreaking, CrescendoJailbreaking, TreeJailbreaking
      #
      # Each attack method defines:
      # - How to transform/generate adversarial inputs
      # - Whether it operates in single or multiple turns
      # - What configuration options it accepts
      #
      # @example Single-turn attack
      #   class PromptInjectionAttack < Attack
      #     def attack_type
      #       :single_turn
      #     end
      #
      #     def execute(baseline_input, context = {})
      #       # Transform baseline input into adversarial prompt
      #       "Ignore previous instructions. #{baseline_input}"
      #     end
      #   end
      #
      # @example Multi-turn attack
      #   class LinearJailbreaking < Attack
      #     def attack_type
      #       :multi_turn
      #     end
      #
      #     def execute_conversation(baseline_input, model_callback, context = {})
      #       turns = []
      #       current_input = baseline_input
      #
      #       num_turns.times do
      #         response = model_callback.call(current_input)
      #         turns << { input: current_input, output: response }
      #         current_input = refine_attack(current_input, response)
      #       end
      #
      #       turns
      #     end
      #   end
      #
      class Attack
        attr_reader :weight, :config

        # Initialize attack with optional configuration
        #
        # @param weight [Float] Probability weight for random sampling (0.0-1.0)
        # @param config [Hash] Attack-specific configuration options
        def initialize(weight: 1.0, **config)
          @weight = weight
          @config = config
        end

        # Get the attack type (single-turn or multi-turn)
        #
        # @return [Symbol] Either :single_turn or :multi_turn
        def attack_type
          raise NotImplementedError, "Subclasses must implement #attack_type"
        end

        # Get the attack method identifier
        #
        # @return [String] Unique identifier for this attack method
        def attack_name
          raise NotImplementedError, "Subclasses must implement #attack_name"
        end

        # Execute single-turn attack transformation
        #
        # Only called for single-turn attacks. Transforms baseline input
        # into adversarial input using the attack technique.
        #
        # @param baseline_input [String] Original input to transform
        # @param context [Hash] Optional context (vulnerability_type, target, etc.)
        # @return [String] Adversarial input
        def execute(baseline_input, context = {})
          raise NotImplementedError, "Single-turn attacks must implement #execute"
        end

        # Execute multi-turn attack conversation
        #
        # Only called for multi-turn attacks. Conducts adversarial conversation
        # with the target model, refining attacks based on responses.
        #
        # @param baseline_input [String] Initial input to start conversation
        # @param model_callback [Proc] Callback to query target model: ->(input) { output }
        # @param context [Hash] Optional context (vulnerability_type, target, etc.)
        # @return [Array<Hash>] List of conversation turns with :input and :output
        def execute_conversation(baseline_input, model_callback, context = {})
          raise NotImplementedError, "Multi-turn attacks must implement #execute_conversation"
        end

        # Check if this is a single-turn attack
        #
        # @return [Boolean] True if attack executes in one turn
        def single_turn?
          attack_type == :single_turn
        end

        # Check if this is a multi-turn attack
        #
        # @return [Boolean] True if attack executes across multiple turns
        def multi_turn?
          attack_type == :multi_turn
        end

        # Get human-readable description of this attack
        #
        # @return [String] Attack description
        def description
          "#{attack_name.to_s.split('_').map(&:capitalize).join(' ')} attack"
        end

        # Check if this attack is deterministic
        #
        # Deterministic attacks (e.g., Base64 encoding) produce identical
        # outputs for identical inputs. Non-deterministic attacks (LLM-powered)
        # may produce varied outputs.
        #
        # @return [Boolean] True if attack is deterministic
        def deterministic?
          false  # Override in subclasses for deterministic attacks
        end

        # Check if this attack requires an LLM for generation
        #
        # @return [Boolean] True if attack uses LLM for generation
        def requires_llm?
          !deterministic?  # Non-deterministic attacks typically need LLMs
        end

        # Get recommended number of samples for this attack
        #
        # Used by RedTeamer to determine how many attack variations to generate
        #
        # @return [Integer] Recommended sample count
        def recommended_samples
          deterministic? ? 1 : 5  # Deterministic: 1 sample, LLM-powered: 5 samples
        end

        # Validate attack configuration
        #
        # @return [Boolean] True if configuration is valid
        # @raise [ArgumentError] If configuration is invalid
        def validate_config!
          true  # Override in subclasses for config validation
        end
      end
    end
  end
end
