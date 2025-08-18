# frozen_string_literal: true

require "raaf-dsl"
require "raaf/dsl/tools/tool"

module RAAF
  module Tools
    module API
      # Unified Web Page Fetch Tool with Intelligent Fallback
      #
      # This tool provides a unified interface for web page fetching with automatic
      # fallback between different scraping services based on availability and requirements.
      # It intelligently selects between ScrapFly (for JavaScript-heavy sites) and 
      # Tavily (for simpler content extraction) based on the target URL and configuration.
      #
      # @example Basic usage
      #   tool = RAAF::Tools::API::WebPageFetch.new
      #   result = tool.call(url: "https://example.com", prefer_service: "auto")
      #
      # @example With JavaScript rendering preference
      #   result = tool.call(
      #     url: "https://react-app.com",
      #     render_js: true,
      #     format: "markdown"
      #   )
      #
      class WebPageFetch < RAAF::DSL::Tools::Tool::API
        configure description: "Intelligently fetch web page content using the best available scraping service"
        
        # Note: Parameters are defined in to_tool_definition method below

        def initialize
          super
          @scrapfly_available = ENV["SCRAPFLY_API_KEY"].present?
          @tavily_available = ENV["TAVILY_API_KEY"].present?
          
          # Initialize service tools if available
          @scrapfly = ScrapflyPageFetch.new if @scrapfly_available
          @tavily = TavilySearch.new if @tavily_available
        end

        def enabled?
          @scrapfly_available || @tavily_available
        end

        def call(url:, prefer_service: "auto", render_js: false, format: "text", max_chars: 10000)
          return error_response("No scraping services available") unless enabled?
          return error_response("Invalid URL format") unless valid_url?(url)

          # Select the best service
          service = select_service(prefer_service, url, render_js)
          
          case service
          when :scrapfly
            fetch_with_scrapfly(url, render_js, format, max_chars)
          when :tavily
            fetch_with_tavily(url, format, max_chars)
          else
            error_response("Unable to determine scraping service")
          end
        rescue StandardError => e
          error_response("Failed to fetch page: #{e.message}")
        end

        private

        def valid_url?(url)
          uri = URI.parse(url)
          %w[http https].include?(uri.scheme)
        rescue URI::InvalidURIError
          false
        end

        def select_service(preference, url, render_js)
          case preference.to_s.downcase
          when "scrapfly"
            return :scrapfly if @scrapfly_available
            return :tavily if @tavily_available
          when "tavily"
            return :tavily if @tavily_available
            return :scrapfly if @scrapfly_available
          else # "auto"
            # Intelligent selection based on requirements
            if render_js && @scrapfly_available
              :scrapfly
            elsif requires_javascript?(url) && @scrapfly_available
              :scrapfly
            elsif complex_domain?(url) && @scrapfly_available
              :scrapfly
            elsif @scrapfly_available
              :scrapfly
            elsif @tavily_available
              :tavily
            end
          end
        end

        def requires_javascript?(url)
          js_patterns = [
            /\.app$/,
            /react|angular|vue/i,
            /spa\./,
            /dashboard|admin|app\./
          ]
          js_patterns.any? { |pattern| url.match?(pattern) }
        end

        def complex_domain?(url)
          complex_patterns = [
            /crunchbase\.com/,
            /bloomberg\.com/,
            /techcrunch\.com/,
            /salesforce\.com/
          ]
          complex_patterns.any? { |pattern| url.match?(pattern) }
        end

        def fetch_with_scrapfly(url, render_js, format, max_chars)
          result = @scrapfly.call(
            url: url,
            render_js: render_js,
            anti_bot: true,
            format: format,
            auto_scroll: render_js,
            wait: render_js ? 3000 : 1000
          )
          
          # Truncate if needed
          parsed = JSON.parse(result)
          if parsed["success"] && parsed["data"]["content"]&.length > max_chars
            parsed["data"]["content"] = parsed["data"]["content"][0...max_chars] + "..."
            parsed["data"]["truncated"] = true
          end
          parsed.to_json
        end

        def fetch_with_tavily(url, format, max_chars)
          # Tavily expects different parameters
          result = @tavily.call(
            query: url,
            search_depth: "basic",
            max_results: 1,
            include_raw_content: true
          )
          
          # Normalize response to match expected format
          parsed = JSON.parse(result)
          if parsed["success"]
            {
              success: true,
              data: {
                url: url,
                content: parsed["data"]["results"]&.first&.dig("content") || "",
                format: format,
                service_used: "tavily"
              }
            }.to_json
          else
            result
          end
        end

        def error_response(message)
          {
            success: false,
            error: message,
            available_services: {
              scrapfly: @scrapfly_available,
              tavily: @tavily_available
            }
          }.to_json
        end
      end
    end
  end
end