# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # EvaluationConfiguration defines configuration variants to test against baseline.
      class EvaluationConfiguration < ActiveRecord::Base
        self.table_name = "evaluation_configurations"

        # Associations
        belongs_to :evaluation_run, class_name: "RAAF::Eval::Models::EvaluationRun"
        has_one :evaluation_result, dependent: :destroy, class_name: "RAAF::Eval::Models::EvaluationResult"

        # Validations
        validates :name, presence: true
        validates :configuration_type, presence: true,
                                       inclusion: { in: %w[model_change parameter_change prompt_change provider_change combined] }
        validates :configuration_changes, presence: true

        # Scopes
        scope :by_type, ->(type) { where(configuration_type: type) }
        scope :ordered, -> { order(:execution_order) }

        ##
        # Get model from the configuration's changes
        # @return [String, nil]
        def model
          configuration_changes&.dig("model")
        end

        ##
        # Get provider from changes
        # @return [String, nil]
        def provider
          configuration_changes&.dig("provider")
        end

        ##
        # Get parameters from changes
        # @return [Hash, nil]
        def parameters
          configuration_changes&.dig("parameters")
        end

        ##
        # Get instructions from changes
        # @return [String, nil]
        def instructions
          configuration_changes&.dig("instructions")
        end

        ##
        # Check if configuration changes model
        # @return [Boolean]
        def changes_model?
          configuration_changes&.key?("model")
        end

        ##
        # Check if configuration changes provider
        # @return [Boolean]
        def changes_provider?
          configuration_changes&.key?("provider")
        end

        ##
        # Check if configuration changes parameters
        # @return [Boolean]
        def changes_parameters?
          configuration_changes&.key?("parameters")
        end

        ##
        # Check if configuration changes instructions/prompt
        # @return [Boolean]
        def changes_prompt?
          configuration_changes&.key?("instructions")
        end
      end
    end
  end
end
