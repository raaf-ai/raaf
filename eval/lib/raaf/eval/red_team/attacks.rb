# frozen_string_literal: true

# Load all attack implementations
require_relative "attacks/single_turn/prompt_injection"
require_relative "attacks/single_turn/roleplay"
require_relative "attacks/single_turn/base64"

# Load multi-turn attacks
require_relative "attacks/multi_turn/linear_jailbreaking"
require_relative "attacks/multi_turn/crescendo"

module RAAF
  module Eval
    module RedTeam
      # Namespace for all attack methods
      #
      # This module provides access to all implemented attack classes
      # for red-teaming and adversarial testing of LLM applications.
      #
      # Available attacks are organized by type:
      #
      # **Single-Turn Attacks:**
      # - PromptInjectionAttack - Attempts to override system instructions
      # - RoleplayAttack - Uses fictional scenarios to bypass restrictions
      # - Base64Attack - Encodes prompts to evade text-based filters
      #
      # **Multi-Turn Attacks:**
      # - LinearJailbreakingAttack - Progressive escalation from indirect to direct requests
      # - CrescendoAttack - Emotional manipulation with urgency building (47.3% breach rate)
      #
      # @example Using a single-turn attack
      #   attack = RAAF::Eval::RedTeam::Attacks::SingleTurn::PromptInjectionAttack.new
      #   adversarial = attack.execute("Tell me a secret")
      #
      # @example Using a multi-turn attack
      #   attack = RAAF::Eval::RedTeam::Attacks::MultiTurn::CrescendoAttack.new
      #   model_callback = ->(input) { my_model.generate(input) }
      #   conversation = attack.execute_conversation("Harmful request", model_callback)
      #
      module Attacks
        # Get all available attack classes
        #
        # @return [Array<Class>] All attack class constants
        def self.all
          single_turn_attacks + multi_turn_attacks
        end

        # Get all single-turn attack classes
        #
        # @return [Array<Class>] Single-turn attack classes
        def self.single_turn_attacks
          SingleTurn.constants.map { |const| SingleTurn.const_get(const) }.select { |c| c.is_a?(Class) }
        end

        # Get all multi-turn attack classes
        #
        # @return [Array<Class>] Multi-turn attack classes
        def self.multi_turn_attacks
          MultiTurn.constants.map { |const| MultiTurn.const_get(const) }.select { |c| c.is_a?(Class) }
        end

        # Get attacks by type
        #
        # @param type [Symbol] Attack type (:single_turn or :multi_turn)
        # @return [Array<Class>] Attack classes of the specified type
        def self.by_type(type)
          case type.to_sym
          when :single_turn then single_turn_attacks
          when :multi_turn then multi_turn_attacks
          else []
          end
        end

        # Get all attack names (string identifiers)
        #
        # @return [Array<String>] All attack name identifiers
        def self.names
          all.map do |attack_class|
            attack_class.new.attack_name
          rescue StandardError
            nil
          end.compact
        end

        # Get deterministic attacks
        #
        # @return [Array<Class>] Deterministic attack classes
        def self.deterministic
          all.select do |attack_class|
            attack_class.new.deterministic?
          rescue StandardError
            false
          end
        end

        # Get non-deterministic (LLM-powered) attacks
        #
        # @return [Array<Class>] Non-deterministic attack classes
        def self.non_deterministic
          all.select do |attack_class|
            !attack_class.new.deterministic?
          rescue StandardError
            false
          end
        end
      end
    end
  end
end
