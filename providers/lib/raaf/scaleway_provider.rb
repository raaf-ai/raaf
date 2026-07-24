# frozen_string_literal: true

require_relative "openai_compatible_provider"

module RAAF
  module Models
    ##
    # Scaleway Generative APIs provider (OpenAI-compatible, EU-hosted)
    #
    # Scaleway serves open-weight models (Qwen, DeepSeek, Llama, gpt-oss, ...)
    # from data centres in Paris. Data stays in the EU and Scaleway does not
    # train on or retain request content, so this is a GDPR-friendly way to run
    # the Chinese-origin open-weight models (Qwen/DeepSeek) without sending
    # prospect PII to a China-hosted endpoint.
    #
    # This is a **gateway** provider: pick it explicitly (it is not auto-detected
    # from the model name, because ids like "qwen3-32b" collide with the vendor's
    # own China-direct API). The model catalogue is host-managed and changes over
    # time, so any non-empty model id is accepted — SUPPORTED_MODELS is a
    # documented reference, not an allow-list. Query the live catalogue at
    # GET https://api.scaleway.ai/v1/models for the authoritative list.
    #
    # @example
    #   provider = ScalewayProvider.new(api_key: ENV["SCW_SECRET_KEY"])
    #   provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "qwen3.5-397b-a17b"
    #   )
    #
    class ScalewayProvider < OpenAICompatibleProvider
      API_BASE = "https://api.scaleway.ai/v1"
      API_KEY_ENV = "SCW_SECRET_KEY"
      PROVIDER_DISPLAY_NAME = "Scaleway"
      USAGE_PROVIDER_KEY = "scaleway"

      # Reference only — catalogue is host-managed and changes. Not enforced.
      SUPPORTED_MODELS = %w[
        qwen3.5-397b-a17b
        qwen3-235b-a22b-instruct-2507
        qwen3-coder-30b-a3b-instruct
        deepseek-r1-distill-llama-70b
        llama-3.3-70b-instruct
        gpt-oss-120b
        gpt-oss-20b
        mistral-small-3.2-24b-instruct-2506
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
