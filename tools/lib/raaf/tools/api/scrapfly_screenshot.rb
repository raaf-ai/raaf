# frozen_string_literal: true

require "raaf-dsl"
require "raaf/dsl/tools/tool"

module RAAF
  module Tools
    module API
      # ScrapFly Screenshot Tool - Web page screenshot capture using new DSL
      #
      # Captures high-quality screenshots of web pages with customizable options.
      # Supports different formats, viewport sizes, and capture modes.
      #
      # @example Basic screenshot
      #   tool = RAAF::Tools::API::ScrapflyScreenshot.new
      #   result = tool.call(url: "https://example.com")
      #
      # @example Full page screenshot with custom viewport
      #   result = tool.call(
      #     url: "https://example.com",
      #     full_page: true,
      #     width: 1920,
      #     height: 1080,
      #     format: "png"
      #   )
      #
      class ScrapflyScreenshot < RAAF::DSL::Tools::Tool::API
        endpoint "https://api.scrapfly.io/scrape"
        api_key ENV["SCRAPFLY_API_KEY"]
        timeout 45

        # Capture screenshot of web page
        #
        # @param url [String] URL to capture screenshot of
        # @param width [Integer] Viewport width in pixels
        # @param height [Integer] Viewport height in pixels
        # @param full_page [Boolean] Capture full page or just viewport
        # @param format [String] Image format: "png", "jpeg", "webp"
        # @param quality [Integer] Image quality for JPEG (1-100)
        # @param wait [Integer] Wait time in milliseconds before capture
        # @param country [String] Country for proxy routing
        # @return [Hash] Screenshot capture results
        #
        def call(url:, width: 1280, height: 720, full_page: false, format: "png", 
                 quality: 90, wait: 2000, country: "US")
          
          # Validate inputs
          unless valid_url?(url)
            return error_response("Invalid URL format")
          end

          unless valid_format?(format)
            return error_response("Invalid format. Must be png, jpeg, or webp")
          end

          # Build screenshot request
          params = {
            key: api_key,
            url: url,
            screenshot: true,
            screenshot_options: build_screenshot_options(width, height, full_page, format, quality),
            country: country,
            wait: wait,
            timeout: 30000,
            render_js: true  # Screenshots usually need JS rendering
          }

          response = get(params: params)
          process_screenshot_response(response, url)
        end

        # Tool configuration for agents
        def to_tool_definition
          {
            type: "function",
            function: {
              name: "scrapfly_screenshot",
              description: "Capture high-quality screenshots of web pages",
              parameters: {
                type: "object",
                properties: {
                  url: {
                    type: "string",
                    description: "The URL to capture screenshot of"
                  },
                  width: {
                    type: "integer",
                    minimum: 320,
                    maximum: 3840,
                    description: "Viewport width in pixels (default: 1280)"
                  },
                  height: {
                    type: "integer", 
                    minimum: 240,
                    maximum: 2160,
                    description: "Viewport height in pixels (default: 720)"
                  },
                  full_page: {
                    type: "boolean",
                    description: "Capture full page or just viewport (default: false)"
                  },
                  format: {
                    type: "string",
                    enum: ["png", "jpeg", "webp"],
                    description: "Image format (default: png)"
                  },
                  quality: {
                    type: "integer",
                    minimum: 1,
                    maximum: 100,
                    description: "Image quality for JPEG (1-100, default: 90)"
                  },
                  wait: {
                    type: "integer",
                    description: "Wait time in milliseconds before capture (default: 2000)"
                  },
                  country: {
                    type: "string",
                    description: "Country for proxy routing (default: US)"
                  }
                },
                required: ["url"]
              }
            }
          }
        end

        # Tool name for agent registration
        def name
          "scrapfly_screenshot"
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

        # Validate image format
        def valid_format?(format)
          %w[png jpeg webp].include?(format.to_s.downcase)
        end

        # Build screenshot options
        def build_screenshot_options(width, height, full_page, format, quality)
          options = {
            viewport: {
              width: width,
              height: height
            },
            format: format.downcase,
            full_page: full_page
          }

          # Add quality for JPEG format
          if format.downcase == "jpeg"
            options[:quality] = quality.clamp(1, 100)
          end

          options
        end

        # Process screenshot API response
        def process_screenshot_response(response, url)
          if response[:error]
            return error_response("ScrapFly screenshot error: #{response[:error]}")
          end

          if response["success"] && response["result"]
            result_data = response["result"]
            screenshot_url = result_data["screenshot"]
            
            if screenshot_url && !screenshot_url.empty?
              {
                success: true,
                url: url,
                screenshot_url: screenshot_url,
                page_title: result_data["title"],
                page_status: result_data["status_code"],
                metadata: {
                  captured_at: Time.now.iso8601,
                  viewport_size: "#{result_data['screenshot_width']}x#{result_data['screenshot_height']}",
                  file_size: result_data["screenshot_size"],
                  content_type: determine_content_type(screenshot_url),
                  country: result_data["country"]
                }
              }
            else
              error_response("Screenshot was not generated")
            end
          else
            error_response("ScrapFly screenshot returned unsuccessful response")
          end
        end

        # Determine content type from URL or format
        def determine_content_type(screenshot_url)
          case screenshot_url
          when /\.png/i then "image/png"
          when /\.jpe?g/i then "image/jpeg"  
          when /\.webp/i then "image/webp"
          else "image/png"
          end
        end

        # Generate error response
        def error_response(message)
          {
            success: false,
            error: message,
            url: nil,
            screenshot_url: nil
          }
        end
      end
    end
  end
end