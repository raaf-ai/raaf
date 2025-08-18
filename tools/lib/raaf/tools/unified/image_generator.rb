# frozen_string_literal: true

require_relative "../../../../../lib/raaf/tool/native"

module RAAF
  module Tools
    module Unified
      # Native OpenAI Image Generator Tool (DALL-E)
      #
      # Generates images using OpenAI's DALL-E model based on text descriptions.
      #
      class ImageGeneratorTool < RAAF::Tool::Native
        configure name: "dalle",
                 description: "Generate images from text descriptions using DALL-E"

        def initialize(model: "dall-e-3", quality: "standard", style: "vivid", **options)
          super(**options)
          @model = model
          @quality = quality
          @style = style
        end

        native_config do
          option :dalle, true
        end

        def to_tool_definition
          {
            type: "dalle",
            dalle: {
              model: @model,
              quality: @quality,
              style: @style
            }
          }
        end
      end
    end
  end
end