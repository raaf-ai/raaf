# frozen_string_literal: true

require "raaf-dsl"

module RAAF
  module Tools
    module API
      # ScrapFly Extraction Tool - Structured data extraction using new DSL
      #
      # Extracts structured data from web pages using ScrapFly's AI-powered
      # extraction API. Provides clean, structured data extraction for specific
      # fields and patterns.
      #
      # @example Basic data extraction
      #   tool = RAAF::Tools::API::ScrapflyExtract.new
      #   result = tool.call(
      #     url: "https://company.com/about",
      #     fields: ["company_name", "description", "contact_email"]
      #   )
      #
      # @example Product page extraction
      #   result = tool.call(
      #     url: "https://store.com/product/123",
      #     fields: ["title", "price", "description", "availability"],
      #     schema: {
      #       price: { type: "number", description: "Product price" },
      #       availability: { type: "boolean", description: "In stock status" }
      #     }
      #   )
      #
      class ScrapflyExtract < RAAF::DSL::Tools::Tool::API
        endpoint "https://api.scrapfly.io/extraction"
        api_key ENV["SCRAPFLY_API_KEY"]
        timeout 45

        # Extract structured data from web page
        #
        # @param url [String] URL to extract data from
        # @param fields [Array<String>] Fields to extract
        # @param schema [Hash] Schema defining field types and descriptions
        # @param render_js [Boolean] Enable JavaScript rendering
        # @param country [String] Country for proxy routing
        # @return [Hash] Extracted structured data
        #
        def call(url:, fields:, schema: {}, render_js: true, country: "US")
          # Validate inputs
          unless valid_url?(url)
            return error_response("Invalid URL format")
          end

          unless fields.is_a?(Array) && fields.any?
            return error_response("Fields must be a non-empty array")
          end

          # Build extraction request
          params = {
            key: api_key,
            url: url,
            extraction_template: build_extraction_template(fields, schema),
            country: country,
            timeout: 30000
          }

          params[:render_js] = true if render_js

          response = post(json: params)
          process_extraction_response(response, url, fields)
        end

        # Tool configuration for agents
        def to_tool_definition
          {
            type: "function",
            function: {
              name: "scrapfly_extract",
              description: "Extract structured data from web pages using AI-powered extraction",
              parameters: {
                type: "object",
                properties: {
                  url: {
                    type: "string",
                    description: "The URL to extract data from"
                  },
                  fields: {
                    type: "array",
                    items: { type: "string" },
                    description: "List of fields to extract (e.g., ['title', 'price', 'description'])"
                  },
                  schema: {
                    type: "object",
                    description: "Schema defining field types and descriptions"
                  },
                  render_js: {
                    type: "boolean",
                    description: "Enable JavaScript rendering (default: true)"
                  },
                  country: {
                    type: "string",
                    description: "Country for proxy routing (default: US)"
                  }
                },
                required: ["url", "fields"]
              }
            }
          }
        end

        # Tool name for agent registration
        def name
          "scrapfly_extract"
        end

        # Check if tool is enabled
        def enabled?
          !api_key.nil? && !api_key.empty?
        end

        private

        # Validate URL format
        def valid_url?(url)
          uri = URI.parse(url)
          %w[http https].include?(uri.scheme)
        rescue URI::InvalidURIError
          false
        end

        # Build extraction template from fields and schema
        def build_extraction_template(fields, schema)
          template = {}
          
          fields.each do |field|
            field_config = schema[field] || schema[field.to_sym] || {}
            
            template[field] = {
              type: field_config[:type] || "string",
              description: field_config[:description] || "Extract #{field.gsub('_', ' ')}"
            }

            # Add additional schema properties
            template[field][:required] = field_config[:required] if field_config.key?(:required)
            template[field][:enum] = field_config[:enum] if field_config[:enum]
            template[field][:format] = field_config[:format] if field_config[:format]
          end

          template
        end

        # Process extraction API response
        def process_extraction_response(response, url, requested_fields)
          if response[:error]
            return error_response("ScrapFly extraction error: #{response[:error]}")
          end

          if response["success"] && response["result"]
            result_data = response["result"]
            extracted_data = result_data["data"] || {}
            
            {
              success: true,
              url: url,
              extracted_data: extracted_data,
              fields_found: count_found_fields(extracted_data, requested_fields),
              fields_requested: requested_fields,
              confidence_score: result_data["confidence"],
              metadata: {
                extracted_at: Time.now.iso8601,
                extraction_method: "ai_powered",
                page_status: result_data["status_code"],
                processing_time: result_data["processing_time"]
              }
            }
          else
            error_response("ScrapFly extraction returned unsuccessful response")
          end
        end

        # Count how many requested fields were found
        def count_found_fields(extracted_data, requested_fields)
          requested_fields.count do |field|
            value = extracted_data[field] || extracted_data[field.to_s]
            value && !value.to_s.empty?
          end
        end

        # Generate error response
        def error_response(message)
          {
            success: false,
            error: message,
            url: nil,
            extracted_data: {},
            fields_found: 0
          }
        end
      end
    end
  end
end