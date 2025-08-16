# frozen_string_literal: true

require_relative "../../dsl/tools/tool/native"

module RAAF
  module Tools
    module Native
      # DALL-E Image Generation Tool
      #
      # This tool provides access to OpenAI's DALL-E image generation capabilities.
      # It's a native OpenAI tool, meaning execution is handled entirely by OpenAI's API.
      #
      # @example Basic usage
      #   class CreativeAgent < RAAF::DSL::Agent
      #     tool :image_generator
      #
      #     instructions "Generate creative images based on user descriptions"
      #   end
      #
      # @example With configuration
      #   class ArtAgent < RAAF::DSL::Agent
      #     tool :image_generator do
      #       model "dall-e-3"
      #       size "1024x1024"
      #       quality "hd"
      #     end
      #   end
      #
      class ImageGenerator < RAAF::DSL::Tools::Tool::Native
        tool_name "image_generator"
        description "Generate images using DALL-E based on text descriptions"
        
        # DALL-E specific parameters
        parameter :prompt, 
                  type: :string, 
                  required: true,
                  description: "A text description of the desired image(s). Maximum 4000 characters for dall-e-3."
        
        parameter :model,
                  type: :string,
                  default: "dall-e-3",
                  enum: ["dall-e-2", "dall-e-3"],
                  description: "The model to use for image generation"
        
        parameter :n,
                  type: :integer,
                  default: 1,
                  minimum: 1,
                  maximum: 10,
                  description: "Number of images to generate (dall-e-3 only supports n=1)"
        
        parameter :size,
                  type: :string,
                  default: "1024x1024",
                  enum: ["256x256", "512x512", "1024x1024", "1792x1024", "1024x1792"],
                  description: "Size of the generated images. dall-e-3 supports additional sizes."
        
        parameter :quality,
                  type: :string,
                  default: "standard",
                  enum: ["standard", "hd"],
                  description: "Quality of the generated image (dall-e-3 only)"
        
        parameter :style,
                  type: :string,
                  default: "vivid",
                  enum: ["vivid", "natural"],
                  description: "Style of the generated image (dall-e-3 only). Vivid is more hyper-real and dramatic."
        
        parameter :response_format,
                  type: :string,
                  default: "url",
                  enum: ["url", "b64_json"],
                  description: "Format of the generated image data"

        # Override tool_type for image generation
        def self.tool_type
          "function"  # DALL-E is called as a function
        end

        # Provide additional configuration for OpenAI
        def self.openai_config
          {
            api_endpoint: "images/generations",
            requires_api_key: true,
            supports_streaming: false
          }
        end
      end
    end
  end
end