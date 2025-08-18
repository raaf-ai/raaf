# frozen_string_literal: true

require_relative "../../../../../lib/raaf/tool/api"

module RAAF
  module Tools
    module Unified
      # Base class for ScrapFly tools
      class ScrapflyBaseTool < RAAF::Tool::API
        endpoint "https://api.scrapfly.io"
        api_key_env "SCRAPFLY_API_KEY"
        timeout 30

        protected

        def base_params
          {
            key: api_key,
            asp: true,  # Anti-scraping protection
            render_js: true  # JavaScript rendering
          }
        end
      end

      # ScrapFly Page Fetch Tool
      #
      # Fetches and extracts content from web pages with anti-scraping protection
      #
      class ScrapflyPageFetchTool < ScrapflyBaseTool
        configure name: "scrapfly_page_fetch",
                 description: "Fetch and extract content from web pages with anti-scraping protection"

        parameters do
          property :url, type: "string", description: "URL to fetch"
          property :format, type: "string",
                  enum: ["raw", "text", "markdown", "json"],
                  description: "Output format"
          property :country, type: "string",
                  description: "Country code for geo-located request"
          property :wait_for_selector, type: "string",
                  description: "CSS selector to wait for before extraction"
          required :url
        end

        def call(url:, format: "markdown", country: nil, wait_for_selector: nil)
          params = base_params.merge(
            url: url,
            format: format
          )

          params[:country] = country if country
          params[:wait_for_selector] = wait_for_selector if wait_for_selector

          response = get("/scrape", params: params)
          extract_content(response, format)
        end

        private

        def extract_content(response, format)
          return response unless response.is_a?(Hash)

          case format
          when "markdown"
            response.dig("result", "markdown") || response.dig("result", "content")
          when "text"
            response.dig("result", "text") || response.dig("result", "content")
          when "json"
            response.dig("result", "structured_data") || response
          else
            response.dig("result", "content") || response
          end
        end
      end

      # ScrapFly Extract Tool
      #
      # Extracts structured data from web pages using AI extraction
      #
      class ScrapflyExtractTool < ScrapflyBaseTool
        configure name: "scrapfly_extract",
                 description: "Extract structured data from web pages using AI"

        parameters do
          property :url, type: "string", description: "URL to extract from"
          property :fields, type: "array",
                  items: { type: "string" },
                  description: "Fields to extract (e.g., ['title', 'price', 'description'])"
          property :schema, type: "object",
                  description: "JSON schema for extraction"
          required :url
        end

        def call(url:, fields: [], schema: nil)
          params = base_params.merge(
            url: url,
            extraction_template: build_template(fields, schema)
          )

          response = get("/extract", params: params)
          response.dig("result", "extracted_data") || response
        end

        private

        def build_template(fields, schema)
          return schema if schema

          # Build simple template from fields
          template = {}
          fields.each do |field|
            template[field] = {
              selector: "auto",
              type: "text"
            }
          end
          template
        end
      end

      # ScrapFly Screenshot Tool
      #
      # Takes screenshots of web pages with various options
      #
      class ScrapflyScreenshotTool < ScrapflyBaseTool
        configure name: "scrapfly_screenshot",
                 description: "Take screenshots of web pages"

        parameters do
          property :url, type: "string", description: "URL to screenshot"
          property :format, type: "string",
                  enum: ["png", "jpg", "webp"],
                  description: "Image format"
          property :full_page, type: "boolean",
                  description: "Capture full page or viewport only"
          property :width, type: "integer",
                  description: "Viewport width in pixels"
          property :height, type: "integer",
                  description: "Viewport height in pixels"
          property :wait_for_selector, type: "string",
                  description: "CSS selector to wait for before screenshot"
          required :url
        end

        def call(url:, format: "png", full_page: true, width: 1920, height: 1080, wait_for_selector: nil)
          params = base_params.merge(
            url: url,
            screenshot: true,
            screenshot_format: format,
            screenshot_full_page: full_page,
            screenshot_width: width,
            screenshot_height: height
          )

          params[:wait_for_selector] = wait_for_selector if wait_for_selector

          response = get("/screenshot", params: params)
          
          {
            url: url,
            screenshot_url: response.dig("result", "screenshot_url"),
            format: format,
            dimensions: "#{width}x#{height}",
            full_page: full_page
          }
        end
      end
    end
  end
end