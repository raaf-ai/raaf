# frozen_string_literal: true

require_relative "openai_compatible_provider"

module RAAF
  module Models
    ##
    # OVHcloud AI Endpoints provider (OpenAI-compatible, EU-hosted)
    #
    # OVHcloud serves open-weight models (Qwen, DeepSeek, Llama, Mistral,
    # gpt-oss, ...) from data centres in Gravelines, France. Data stays in the
    # EU and is not used for training, making it a GDPR-friendly host for the
    # Chinese-origin open-weight models (Qwen/DeepSeek) without routing prospect
    # PII to a China-hosted endpoint.
    #
    # This is a **gateway** provider: pick it explicitly (it is not auto-detected
    # from the model name, because ids like "qwen3-32b" collide with the vendor's
    # own China-direct API). The catalogue is host-managed, so any non-empty
    # model id is accepted — SUPPORTED_MODELS is a documented reference, not an
    # allow-list. See https://endpoints.ai.cloud.ovh.net/catalog for the live list.
    #
    # @example
    #   provider = OVHProvider.new(api_key: ENV["OVHCLOUD_API_KEY"])
    #   provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "qwen3-32b"
    #   )
    #
    class OVHProvider < OpenAICompatibleProvider
      API_BASE = "https://oai.endpoints.kepler.ai.cloud.ovh.net/v1"
      API_KEY_ENV = "OVHCLOUD_API_KEY"
      PROVIDER_DISPLAY_NAME = "OVHcloud"
      USAGE_PROVIDER_KEY = "ovhcloud"

      # Reference only — catalogue is host-managed and changes. Not enforced.
      SUPPORTED_MODELS = %w[
        qwen3-32b
        qwen3-coder-30b-a3b-instruct
        qwen2.5-coder-32b-instruct
        qwen2.5-vl-72b-instruct
        deepseek-r1-distill-llama-70b
        llama-3.3-70b-instruct
        mistral-small-3.2-24b-instruct-2506
        mixtral-8x7b-instruct-v0.1
        gpt-oss-120b
        gpt-oss-20b
      ].freeze

      ##
      # Gateway providers accept any model id from the remote catalogue.
      #
      # @param model [String] Model id
      # @raise [ArgumentError] only if the model id is blank
      #
      def validate_model(model)
        raise ArgumentError, "Model id is required for #{provider_name}" if model.nil? || model.to_s.empty?
      end
    end
  end
end
