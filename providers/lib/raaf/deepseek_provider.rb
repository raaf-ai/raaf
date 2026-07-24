# frozen_string_literal: true

require_relative "openai_compatible_provider"

module RAAF
  module Models
    ##
    # DeepSeek API provider (OpenAI-compatible)
    #
    # DeepSeek exposes an OpenAI-compatible endpoint at https://api.deepseek.com.
    # `deepseek-chat` (non-thinking) and `deepseek-reasoner` (thinking) are the
    # long-standing aliases; the V4 line (`deepseek-v4-flash`, `deepseek-v4-pro`)
    # is the current generation, with the aliases mapping onto V4 flash.
    #
    # @example
    #   provider = DeepSeekProvider.new(api_key: ENV["DEEPSEEK_API_KEY"])
    #   provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "deepseek-v4-pro"
    #   )
    #
    class DeepSeekProvider < OpenAICompatibleProvider
      API_BASE = "https://api.deepseek.com"
      API_KEY_ENV = "DEEPSEEK_API_KEY"
      PROVIDER_DISPLAY_NAME = "DeepSeek"
      USAGE_PROVIDER_KEY = "deepseek"

      SUPPORTED_MODELS = %w[
        deepseek-v4-pro
        deepseek-v4-flash
        deepseek-chat
        deepseek-reasoner
      ].freeze
    end
  end
end
