# frozen_string_literal: true

require_relative "openai_compatible_provider"

module RAAF
  module Models
    ##
    # Nebius Token Factory provider (OpenAI-compatible)
    #
    # Nebius Token Factory (formerly Nebius AI Studio) serves 60+ open-weight
    # models through one OpenAI-compatible API — including the ones the France-only
    # hosts (Scaleway/OVH) don't carry: GLM (zai-org) and Kimi K2 (moonshotai),
    # plus DeepSeek and Qwen. Model ids use the HuggingFace "org/name" format
    # (e.g. "deepseek-ai/DeepSeek-R1-0528", "zai-org/GLM-4.6").
    #
    # ⚠️ DATA RESIDENCY: Nebius is a European AI cloud, but its *serverless*
    # endpoints may route outside the EU by default. EU-resident inference
    # requires a **dedicated endpoint** deployed in an EU region. Do NOT treat
    # this as GDPR-safe for prospect PII out of the box the way Scaleway/OVH are —
    # verify the endpoint region first, or point +api_base+ at your dedicated
    # EU endpoint. Use ScalewayProvider / OVHProvider for PII by default; reach
    # for Nebius when you need GLM/Kimi or a broader catalogue.
    #
    # This is a **gateway** provider: pick it explicitly (not auto-detected — the
    # "org/name" ids don't collide, but selection should be deliberate). The
    # catalogue is host-managed, so any non-empty model id is accepted;
    # SUPPORTED_MODELS is a documented reference, not an allow-list. Live list:
    # https://docs.tokenfactory.nebius.com/ai-models-inference/overview
    #
    # @example
    #   provider = NebiusProvider.new(api_key: ENV["NEBIUS_API_KEY"])
    #   provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "zai-org/GLM-4.6"
    #   )
    #
    class NebiusProvider < OpenAICompatibleProvider
      API_BASE = "https://api.tokenfactory.nebius.com/v1"
      API_KEY_ENV = "NEBIUS_API_KEY"
      PROVIDER_DISPLAY_NAME = "Nebius"
      USAGE_PROVIDER_KEY = "nebius"

      # Reference only — catalogue is host-managed and changes. Not enforced.
      SUPPORTED_MODELS = %w[
        deepseek-ai/DeepSeek-R1-0528
        deepseek-ai/DeepSeek-V3-0324
        Qwen/Qwen3-235B-A22B
        Qwen/Qwen3-32B
        zai-org/GLM-4.6
        zai-org/GLM-5.1
        moonshotai/Kimi-K2-Instruct
        meta-llama/Llama-3.3-70B-Instruct
      ].freeze

      ##
      # Gateway providers accept any model id from the remote catalogue.
      #
      # @param model [String] Model id (HuggingFace "org/name" format)
      # @raise [ArgumentError] only if the model id is blank
      #
      def validate_model(model)
        raise ArgumentError, "Model id is required for #{provider_name}" if model.nil? || model.to_s.empty?
      end
    end
  end
end
