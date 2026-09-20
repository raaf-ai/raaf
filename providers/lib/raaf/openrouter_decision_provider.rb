# frozen_string_literal: true

require_relative "jev_provider"

module RAAF
  module Models
    ##
    # Decision models served through OpenRouter's Decisions API
    #
    # OpenRouter routes decision models at +POST /api/alpha/decisions+, taking
    # the same +model+, +state+ and +questions+ body as TypeSafe's own endpoint
    # and normalising responses across the providers it carries. Model slugs
    # are prefixed with a tilde, as in +~typesafe/jev-latest+.
    #
    # This exists so that reaching a decision model does not require a separate
    # account with each vendor. It is not the chat-completions
    # {OpenRouterProvider}: that one speaks messages and tools, and would
    # reject these models.
    #
    # The endpoint is on OpenRouter's +alpha+ path, so treat its shape as
    # liable to move.
    #
    # @example
    #   provider = OpenRouterDecisionProvider.new(api_key: ENV["OPENROUTER_API_KEY"])
    #
    #   provider.noul(
    #     state: "Help! My payouts have been failing for 3 days.",
    #     instructions: "The message conveys urgency"
    #   ).probability
    #
    # @example Appearing on the OpenRouter leaderboards
    #   OpenRouterDecisionProvider.new(site_url: "https://example.com", site_name: "Example")
    #
    class OpenRouterDecisionProvider < JevProvider
      # Default API base URL
      API_BASE = "https://openrouter.ai/api"

      # Path of the Decisions endpoint, relative to the API base
      ENDPOINT_PATH = "/alpha/decisions"

      # Environment variable holding the API key
      API_KEY_ENV = "OPENROUTER_API_KEY"

      # Human-readable provider name
      PROVIDER_DISPLAY_NAME = "OpenRouter"

      # Model asked when the caller names none
      DEFAULT_MODEL = "~typesafe/jev-latest"

      # Response header carrying the request id
      REQUEST_ID_HEADER = "x-request-id"

      ##
      # @param site_url [String, nil] Your site URL, for the OpenRouter
      #   rankings (default: +OPENROUTER_SITE_URL+)
      # @param site_name [String, nil] Your site name, for the OpenRouter
      #   rankings (default: +OPENROUTER_SITE_NAME+)
      # @param options [Hash] Additional options passed to {JevProvider}
      #
      def initialize(site_url: nil, site_name: nil, **options)
        super(**options)

        @site_url = site_url || ENV.fetch("OPENROUTER_SITE_URL", nil)
        @site_name = site_name || ENV.fetch("OPENROUTER_SITE_NAME", nil)
      end

      private

      ##
      # The optional attribution headers OpenRouter ranks sites by
      #
      # @return [Hash{String => String}]
      #
      def extra_headers
        headers = {}
        headers["HTTP-Referer"] = @site_url if @site_url
        headers["X-Title"] = @site_name if @site_name
        headers
      end
    end
  end
end
