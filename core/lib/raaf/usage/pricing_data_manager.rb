# frozen_string_literal: true

require "net/http"
require "json"
require "singleton"

module RAAF
  module Usage
    # Manages dynamic LLM pricing data from Helicone API
    #
    # Provides automatic downloading, caching, and domain extraction from Helicone's
    # public LLM pricing data. Uses lazy loading with configurable TTL to balance
    # freshness with performance. Falls back gracefully when data is unavailable.
    #
    # @example Basic usage
    #   manager = PricingDataManager.instance
    #   pricing = manager.get_pricing("gpt-4o")
    #   # => { input: 2.50, output: 10.00, domain: "openai.com" } or nil
    #
    # @example Configure custom TTL
    #   config = RAAF::Configuration.new
    #   config.set("usage.pricing_data.ttl", 86400) # 24 hours
    #
    # @example Force refresh
    #   manager = PricingDataManager.instance
    #   manager.refresh! # Fetches fresh data from Helicone
    class PricingDataManager
      include Singleton

      DEFAULT_URL = "https://www.helicone.ai/api/llm-costs"
      DEFAULT_TTL = 604_800 # 7 days in seconds

      def initialize
        @mutex = Mutex.new
        @data = nil
        @last_fetch = nil
        @config = RAAF::Configuration.new
      end

      # Get pricing for a specific model
      #
      # @param model [String] Model identifier (e.g., "gpt-4o")
      # @return [Hash, nil] Pricing hash with :input, :output, :domain or nil if not found
      #
      # @example
      #   pricing = manager.get_pricing("gpt-4o")
      #   # => { input: 2.50, output: 10.00, domain: "openai.com" }
      def get_pricing(model)
        ensure_data_loaded

        @mutex.synchronize do
          @data&.dig(model)
        end
      end

      # Force refresh pricing data from Helicone API
      #
      # @return [Boolean] true if fetch succeeded, false otherwise
      def refresh!
        @mutex.synchronize do
          fetch_and_transform
        end
      end

      # Check if pricing data needs refresh based on TTL
      #
      # @return [Boolean] true if data is stale or missing
      def stale?
        return true if @data.nil? || @last_fetch.nil?

        Time.now - @last_fetch > ttl
      end

      # Get current data status
      #
      # @return [Hash] Status information
      def status
        {
          loaded: !@data.nil?,
          last_fetch: @last_fetch,
          stale: stale?,
          model_count: @data&.size || 0,
          ttl: ttl
        }
      end

      private

      # Ensure data is loaded and fresh
      def ensure_data_loaded
        return unless stale?

        @mutex.synchronize do
          # Double-check after acquiring mutex
          return unless stale?

          fetch_and_transform
        end
      end

      # Fetch data from Helicone and transform to RAAF format
      #
      # @return [Boolean] true if successful, false otherwise
      def fetch_and_transform
        raw_data = fetch_helicone_data
        return false unless raw_data

        @data = transform_helicone_data(raw_data)
        @last_fetch = Time.now
        true
      rescue StandardError => e
        RAAF.logger.error "Failed to fetch pricing data: #{e.message}"
        false
      end

      # Fetch raw data from Helicone API
      #
      # @return [Hash, nil] Raw Helicone response or nil on error
      def fetch_helicone_data
        url = URI(data_url)

        response = Net::HTTP.get_response(url)
        unless response.is_a?(Net::HTTPSuccess)
          RAAF.logger.warn "Helicone API returned #{response.code}"
          return nil
        end

        JSON.parse(response.body)
      rescue StandardError => e
        RAAF.logger.error "Failed to fetch from Helicone: #{e.message}"
        nil
      end

      # Transform Helicone data to RAAF CostCalculator format
      #
      # Helicone format:
      #   { "model": "gpt-4o", "input_cost_per_1m": 2.50, "output_cost_per_1m": 10.00 }
      #
      # RAAF format:
      #   { "gpt-4o" => { input: 2.50, output: 10.00, domain: "openai.com" } }
      #
      # @param raw_data [Hash] Raw Helicone response
      # @return [Hash] Transformed pricing data
      def transform_helicone_data(raw_data)
        data = raw_data.is_a?(Hash) ? raw_data["data"] : raw_data
        return {} unless data.is_a?(Array)

        data.each_with_object({}) do |item, result|
          model = item["model"]
          next unless model

          # Extract domain from provider (e.g., "OPENAI" -> "openai.com")
          domain = extract_domain(item["provider"])

          result[model] = {
            input: item["input_cost_per_1m"].to_f,
            output: item["output_cost_per_1m"].to_f,
            domain: domain
          }

          # Optional: Include cache costs if available
          if item["prompt_cache_read_per_1m"]
            result[model][:prompt_cache_read] = item["prompt_cache_read_per_1m"].to_f
          end
          if item["prompt_cache_write_per_1m"]
            result[model][:prompt_cache_write] = item["prompt_cache_write_per_1m"].to_f
          end
        end
      end

      # Extract domain from provider name
      #
      # Maps provider names to domains for email validation
      #
      # @param provider [String] Provider name from Helicone (e.g., "OPENAI")
      # @return [String] Domain name (e.g., "openai.com")
      def extract_domain(provider)
        return "" unless provider

        # Map common provider names to domains
        domain_map = {
          "OPENAI" => "openai.com",
          "ANTHROPIC" => "anthropic.com",
          "GOOGLE" => "google.com",
          "AZURE" => "microsoft.com",
          "COHERE" => "cohere.ai",
          "HUGGINGFACE" => "huggingface.co",
          "GROQ" => "groq.com",
          "PERPLEXITY" => "perplexity.ai"
        }

        provider_key = provider.to_s.upcase
        domain_map[provider_key] || "#{provider.downcase}.com"
      end

      # Get data URL from configuration or default
      #
      # @return [String] Helicone API URL
      def data_url
        @config.get("usage.pricing_data.url", DEFAULT_URL)
      end

      # Get TTL from configuration or default
      #
      # @return [Integer] TTL in seconds
      def ttl
        @config.get("usage.pricing_data.ttl", DEFAULT_TTL)
      end
    end
  end
end
