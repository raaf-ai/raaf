# frozen_string_literal: true

require "raaf-dsl"

module RAAF
  module Tools
    module API
      # ScrapFly Page Fetch Tool - Clean implementation using new DSL
      #
      # Advanced web scraping with JavaScript rendering and anti-bot bypass.
      # Provides superior content extraction compared to basic HTTP clients.
      #
      # Features:
      # - JavaScript rendering for dynamic content
      # - Anti-bot bypass for protected sites
      # - Multiple output formats (text, markdown, html)
      # - Screenshot capture capability
      # - Auto-scrolling for infinite scroll content
      #
      # @example Basic page fetch
      #   tool = RAAF::Tools::API::ScrapflyPageFetch.new
      #   result = tool.call(url: "https://example.com")
      #
      # @example Advanced fetch with options
      #   result = tool.call(
      #     url: "https://dynamic-site.com",
      #     render_js: true,
      #     format: "markdown",
      #     screenshot: true
      #   )
      #
      class ScrapflyPageFetch < RAAF::DSL::Tools::Tool::API
        endpoint "https://api.scrapfly.io/scrape"
        api_key ENV["SCRAPFLY_API_KEY"]
        timeout 45

        # Extract content from web page
        #
        # @param url [String] URL to fetch content from
        # @param render_js [Boolean] Enable JavaScript rendering
        # @param anti_bot [Boolean] Enable anti-bot bypass
        # @param country [String] Country for proxy routing
        # @param format [String] Output format: "text", "markdown", "html"
        # @param screenshot [Boolean] Capture screenshot
        # @param auto_scroll [Boolean] Auto-scroll for dynamic content
        # @param wait [Integer] Wait time in milliseconds after page load
        # @return [Hash] Extraction results
        #
        def call(url:, render_js: true, anti_bot: true, country: "US", 
                 format: "text", screenshot: false, auto_scroll: false, wait: 2000)
          
          # Validate URL
          unless valid_url?(url)
            return error_response("Invalid URL format")
          end

          # Check if URL is publicly accessible
          unless publicly_accessible_url?(url)
            return error_response("URL requires authentication or is restricted")
          end

          # Build request parameters
          params = {
            key: api_key,
            url: url,
            format: normalize_format(format),
            country: country,
            cache: true,
            timeout: 30000
          }

          # Add optional parameters
          params[:render_js] = true if render_js
          params[:anti_bot] = true if anti_bot
          params[:screenshot] = true if screenshot
          params[:auto_scroll] = true if auto_scroll
          params[:wait] = wait if wait > 0

          response = get(params: params)

          process_response(response, url, format)
        end

        # Tool configuration for agents
        def to_tool_definition
          {
            type: "function",
            function: {
              name: "scrapfly_page_fetch",
              description: "Extract content from web pages with JavaScript rendering and anti-bot bypass",
              parameters: {
                type: "object",
                properties: {
                  url: {
                    type: "string",
                    description: "The URL to fetch content from"
                  },
                  render_js: {
                    type: "boolean",
                    description: "Enable JavaScript rendering (default: true)"
                  },
                  anti_bot: {
                    type: "boolean",
                    description: "Enable anti-bot bypass (default: true)"
                  },
                  country: {
                    type: "string",
                    description: "Country for proxy routing (default: US)"
                  },
                  format: {
                    type: "string",
                    enum: ["text", "markdown", "html"],
                    description: "Output format (default: text)"
                  },
                  screenshot: {
                    type: "boolean",
                    description: "Capture screenshot (default: false)"
                  },
                  auto_scroll: {
                    type: "boolean",
                    description: "Auto-scroll for dynamic content (default: false)"
                  },
                  wait: {
                    type: "integer",
                    description: "Wait time in milliseconds after page load (default: 2000)"
                  }
                },
                required: ["url"]
              }
            }
          }
        end

        # Tool name for agent registration
        def name
          "scrapfly_page_fetch"
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

        # Check if URL is publicly accessible
        def publicly_accessible_url?(url)
          uri = URI.parse(url)
          domain = uri.host&.downcase
          path = uri.path&.downcase || ""
          
          # Restricted domains
          restricted_domains = %w[
            linkedin.com facebook.com twitter.com instagram.com
            github.com gitlab.com slack.com discord.com
            medium.com behance.net dribbble.com
          ]
          
          # Restricted path patterns
          restricted_patterns = %w[
            /login /signin /sign-in /signup /sign-up /register
            /account /profile /dashboard /admin /user/ /users/
            /member/ /members/ /private
          ]
          
          # Check restrictions
          return false if domain && restricted_domains.any? { |d| domain.include?(d) }
          return false if restricted_patterns.any? { |p| path.include?(p) }
          return false if domain&.match?(/\b(linkedin|facebook|twitter|instagram|github|gitlab)\b/)
          
          true
        rescue URI::InvalidURIError
          false
        end

        # Normalize output format
        def normalize_format(format)
          case format.to_s.downcase
          when "markdown", "md" then "markdown"
          when "html" then "html"
          else "text"
          end
        end

        # Process API response
        def process_response(response, url, format)
          if response[:error]
            return error_response("ScrapFly API error: #{response[:error]}")
          end

          if response["success"] && response["result"]
            result_data = response["result"]
            content = result_data["content"]
            
            if content && !content.empty?
              {
                success: true,
                url: url,
                content: clean_content(content, format),
                format: format,
                word_count: count_words(content),
                status_code: result_data["status_code"],
                screenshot_url: result_data["screenshot"],
                metadata: {
                  extracted_at: Time.now.iso8601,
                  content_length: content.length,
                  country: result_data["country"],
                  cache_hit: result_data["cache"]
                }
              }
            else
              error_response("ScrapFly returned empty content")
            end
          else
            error_response("ScrapFly API returned unsuccessful response")
          end
        end

        # Clean content based on format
        def clean_content(content, format)
          return content if format == "html"
          
          # Clean up excessive whitespace for text and markdown
          content
            .gsub(/\n{3,}/, "\n\n")
            .gsub(/[ \t]{2,}/, " ")
            .strip
        end

        # Count words in text
        def count_words(text)
          return 0 unless text.is_a?(String)
          text.split(/\s+/).length
        end

        # Generate error response
        def error_response(message)
          {
            success: false,
            error: message,
            url: nil,
            content: nil
          }
        end
      end
    end
  end
end