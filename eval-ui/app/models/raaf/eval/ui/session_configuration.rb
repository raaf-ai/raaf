# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Represents a configuration variant for an evaluation session
      #
      # Each session can have multiple configurations to compare different
      # settings (model, temperature, prompts, etc.)
      #
      # @example Create a configuration
      #   config = session.configurations.create!(
      #     name: "GPT-4 with temp 0.7",
      #     configuration: {
      #       model: "gpt-4",
      #       temperature: 0.7,
      #       max_tokens: 1000,
      #       instructions: "You are a helpful assistant"
      #     }
      #   )
      #
      class SessionConfiguration < ApplicationRecord
        self.table_name = "raaf_eval_ui_session_configurations"

        # Associations
        belongs_to :session,
                   class_name: "RAAF::Eval::UI::Session",
                   foreign_key: :raaf_eval_ui_session_id,
                   inverse_of: :configurations

        has_many :results,
                 class_name: "RAAF::Eval::UI::SessionResult",
                 foreign_key: :raaf_eval_ui_session_configuration_id,
                 dependent: :destroy,
                 inverse_of: :configuration

        # Validations
        validates :name, presence: true, length: { maximum: 255 }
        validates :configuration, presence: true

        # Callbacks
        before_save :ensure_display_order

        # Scopes
        scope :ordered, -> { order(:display_order) }

        # Instance methods
        def model
          configuration["model"] || configuration[:model]
        end

        def provider
          configuration["provider"] || configuration[:provider]
        end

        def temperature
          configuration["temperature"] || configuration[:temperature]
        end

        def max_tokens
          configuration["max_tokens"] || configuration[:max_tokens]
        end

        def instructions
          configuration["instructions"] || configuration[:instructions]
        end

        # Get a configuration value by key (supports both string and symbol keys)
        def [](key)
          configuration[key.to_s] || configuration[key.to_sym]
        end

        # Set a configuration value
        def []=(key, value)
          configuration[key.to_s] = value
        end

        private

        def ensure_display_order
          self.display_order ||= session.configurations.maximum(:display_order).to_i + 1
        end
      end
    end
  end
end
