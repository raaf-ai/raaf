# frozen_string_literal: true

require_relative "openai_compatible_provider"

module RAAF
  module Models
    ##
    # Zhipu AI GLM provider (OpenAI-compatible)
    #
    # The GLM family (Z.ai / BigModel) is served through an OpenAI-compatible
    # endpoint. The default base URL targets the international Z.ai platform;
    # set +api_base+ to "https://open.bigmodel.cn/api/paas/v4" for the China
    # region. The API key comes from ZHIPUAI_API_KEY (Z_AI_API_KEY also honored).
    #
    # @example
    #   provider = GLMProvider.new(api_key: ENV["ZHIPUAI_API_KEY"])
    #   provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "glm-4.6"
    #   )
    #
    class GLMProvider < OpenAICompatibleProvider
      API_BASE = "https://api.z.ai/api/paas/v4"
      API_KEY_ENV = "ZHIPUAI_API_KEY"
      PROVIDER_DISPLAY_NAME = "GLM"
      USAGE_PROVIDER_KEY = "glm"

      SUPPORTED_MODELS = %w[
        glm-5
        glm-4.7
        glm-4.7-flash
        glm-4.6
        glm-4.6v
        glm-4.5
        glm-4.5-air
        glm-4.5-flash
        glm-4.5v
      ].freeze

      def initialize(api_key: nil, api_base: nil, **options)
        api_key ||= ENV.fetch("ZHIPUAI_API_KEY", nil) || ENV.fetch("Z_AI_API_KEY", nil)
        super
      end
    end
  end
end
