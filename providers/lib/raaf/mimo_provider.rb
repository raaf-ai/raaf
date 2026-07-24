# frozen_string_literal: true

require_relative "openai_compatible_provider"

module RAAF
  module Models
    ##
    # Xiaomi MiMo provider (OpenAI-compatible)
    #
    # The Xiaomi MiMo API Open Platform exposes an OpenAI-compatible endpoint at
    # https://api.xiaomimimo.com/v1. Note the API model ids (`mimo-v2.5-pro`,
    # `mimo-v2.5`) differ from the open-weight Hugging Face checkpoint names
    # (`MiMo-7B`, `MiMo-VL-7B`), which are for self-hosting.
    #
    # @example
    #   provider = MimoProvider.new(api_key: ENV["MIMO_API_KEY"])
    #   provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "mimo-v2.5-pro"
    #   )
    #
    class MimoProvider < OpenAICompatibleProvider
      API_BASE = "https://api.xiaomimimo.com/v1"
      API_KEY_ENV = "MIMO_API_KEY"
      PROVIDER_DISPLAY_NAME = "MiMo"
      USAGE_PROVIDER_KEY = "mimo"

      SUPPORTED_MODELS = %w[
        mimo-v2.5-pro
        mimo-v2.5
        mimo-v2-pro
        mimo-v2-flash
      ].freeze
    end
  end
end
