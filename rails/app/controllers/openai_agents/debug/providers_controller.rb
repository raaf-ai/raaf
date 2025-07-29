# frozen_string_literal: true

module RAAF
  module Debug
    # Controller for AI provider management and model discovery
    class ProvidersController < ApplicationController
      # GET /debug/providers
      def index
        @providers = discover_providers
        
        render json: { providers: @providers }
      end

      # GET /debug/providers/:provider/models
      def models
        provider_name = params[:provider]
        
        begin
          models = discover_models_for_provider(provider_name)
          render json: { models: models }
        rescue StandardError => e
          Rails.logger.error "Failed to load models for provider #{provider_name}: #{e.message}"
          render json: { error: "Failed to load models: #{e.message}" }, status: :unprocessable_entity
        end
      end

      private

      def discover_providers
        providers = []
        
        # OpenAI
        if openai_configured?
          providers << {
            name: "OpenAI",
            key: "openai",
            status: "available",
            description: "OpenAI GPT models"
          }
        end

        # Anthropic
        if anthropic_configured?
          providers << {
            name: "Anthropic",
            key: "anthropic", 
            status: "available",
            description: "Anthropic Claude models"
          }
        end

        # Add other providers as needed
        providers
      end

      def discover_models_for_provider(provider_name)
        case provider_name
        when "openai"
          discover_openai_models
        when "anthropic"
          discover_anthropic_models
        else
          []
        end
      end

      def discover_openai_models
        [
          { key: "gpt-4o", name: "GPT-4o", description: "Most capable model" },
          { key: "gpt-4o-mini", name: "GPT-4o Mini", description: "Fast and efficient" },
          { key: "gpt-4-turbo", name: "GPT-4 Turbo", description: "High performance" },
          { key: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", description: "Balanced performance" }
        ]
      end

      def discover_anthropic_models
        [
          { key: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", description: "Most capable model" },
          { key: "claude-3-haiku-20240307", name: "Claude 3 Haiku", description: "Fast and efficient" }
        ]
      end

      def openai_configured?
        ENV['OPENAI_API_KEY'].present?
      end

      def anthropic_configured?
        ENV['ANTHROPIC_API_KEY'].present?
      end
    end
  end
end