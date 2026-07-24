# frozen_string_literal: true

require_relative "openai_compatible_provider"

module RAAF
  module Models
    ##
    # Alibaba Qwen (DashScope) provider (OpenAI-compatible)
    #
    # Qwen models are served through Alibaba Cloud Model Studio / DashScope via
    # an OpenAI-compatible endpoint. The default base URL targets the
    # international region; set +api_base+ to
    # "https://dashscope.aliyuncs.com/compatible-mode/v1" for the China region.
    #
    # @example
    #   provider = QwenProvider.new(api_key: ENV["DASHSCOPE_API_KEY"])
    #   provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "qwen3-max"
    #   )
    #
    class QwenProvider < OpenAICompatibleProvider
      API_BASE = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
      API_KEY_ENV = "DASHSCOPE_API_KEY"
      PROVIDER_DISPLAY_NAME = "Qwen"
      USAGE_PROVIDER_KEY = "qwen"

      SUPPORTED_MODELS = %w[
        qwen3-max
        qwen3.7-max
        qwen3.7-plus
        qwen3.6-plus
        qwen3.5-plus
        qwen3.6-flash
        qwen3.5-flash
        qwen3-coder-plus
        qwen3-coder-flash
        qwen-max
        qwen-plus
        qwen-flash
        qwen-turbo
      ].freeze
    end
  end
end
