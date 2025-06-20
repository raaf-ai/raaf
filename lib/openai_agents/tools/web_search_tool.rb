# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "cgi"
require_relative "../function_tool"

module OpenAIAgents
  module Tools
    class WebSearchTool < FunctionTool
      def initialize(api_key: nil, search_engine: "duckduckgo", max_results: 5)
        @api_key = api_key || ENV.fetch("SEARCH_API_KEY", nil)
        @search_engine = search_engine.downcase
        @max_results = max_results

        super(method(:search_web),
              name: "web_search",
              description: "Search the web for information",
              parameters: web_search_parameters)
      end

      def search_web(query:, num_results: nil)
        num_results ||= @max_results

        case @search_engine
        when "duckduckgo"
          search_duckduckgo(query, num_results)
        when "google"
          search_google(query, num_results)
        when "bing"
          search_bing(query, num_results)
        else
          raise ArgumentError, "Unsupported search engine: #{@search_engine}"
        end
      end

      private

      def web_search_parameters
        {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search query string"
            },
            num_results: {
              type: "integer",
              description: "Number of results to return (default: #{@max_results})",
              minimum: 1,
              maximum: 20
            }
          },
          required: ["query"]
        }
      end

      def search_duckduckgo(query, num_results)
        # DuckDuckGo Instant Answer API
        encoded_query = CGI.escape(query)
        uri = URI("https://api.duckduckgo.com/?q=#{encoded_query}&format=json&no_html=1&skip_disambig=1")

        response = make_http_request(uri)
        data = JSON.parse(response.body)

        results = parse_duckduckgo_results(data, num_results)

        if results.empty?
          # Fallback to web scraping approach (simplified)
          search_duckduckgo_web(query, num_results)
        else
          format_search_results(results, query)
        end
      rescue StandardError => e
        "Error searching DuckDuckGo: #{e.message}"
      end

      def search_duckduckgo_web(query, num_results)
        # Simplified web scraping approach
        encoded_query = CGI.escape(query)
        uri = URI("https://duckduckgo.com/html/?q=#{encoded_query}")

        response = make_http_request(uri)

        # Basic HTML parsing to extract results
        results = []
        response.body.scan(%r{<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>([^<]*)</a>}) do |url, title|
          results << {
            title: title.strip,
            url: url,
            snippet: "No snippet available"
          }
          break if results.length >= num_results
        end

        format_search_results(results, query)
      rescue StandardError => e
        "Error searching DuckDuckGo web: #{e.message}"
      end

      def search_google(query, num_results)
        return "Google search requires an API key. Set SEARCH_API_KEY environment variable." unless @api_key

        # Google Custom Search API
        encoded_query = CGI.escape(query)
        cx = ENV["GOOGLE_CSE_ID"] || "your-custom-search-engine-id"
        uri = URI("https://www.googleapis.com/customsearch/v1" \
                  "?key=#{@api_key}&cx=#{cx}&q=#{encoded_query}&num=#{num_results}")

        response = make_http_request(uri)
        data = JSON.parse(response.body)

        return "Google search error: #{data["error"]["message"]}" if data["error"]

        results = parse_google_results(data)
        format_search_results(results, query)
      rescue StandardError => e
        "Error searching Google: #{e.message}"
      end

      def search_bing(query, num_results)
        return "Bing search requires an API key. Set SEARCH_API_KEY environment variable." unless @api_key

        # Bing Web Search API
        encoded_query = CGI.escape(query)
        uri = URI("https://api.bing.microsoft.com/v7.0/search?q=#{encoded_query}&count=#{num_results}")

        response = make_http_request(uri, { "Ocp-Apim-Subscription-Key" => @api_key })
        data = JSON.parse(response.body)

        return "Bing search error: #{data["error"]["message"]}" if data["error"]

        results = parse_bing_results(data)
        format_search_results(results, query)
      rescue StandardError => e
        "Error searching Bing: #{e.message}"
      end

      def make_http_request(uri, headers = {})
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true if uri.scheme == "https"
        http.read_timeout = 10
        http.open_timeout = 10

        request = Net::HTTP::Get.new(uri.request_uri)
        request["User-Agent"] = "OpenAI-Agents-Ruby/1.0"
        headers.each { |key, value| request[key] = value }

        response = http.request(request)

        raise "HTTP request failed: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

        response
      end

      def parse_duckduckgo_results(data, num_results)
        results = []

        # Parse different types of DuckDuckGo results
        if data["AbstractText"] && !data["AbstractText"].empty?
          results << {
            title: data["AbstractSource"] || "DuckDuckGo",
            url: data["AbstractURL"] || "",
            snippet: data["AbstractText"]
          }
        end

        data["RelatedTopics"]&.each do |topic|
          next unless topic["Text"] && topic["FirstURL"]

          results << {
            title: topic["Text"].split(" - ").first || "Related Topic",
            url: topic["FirstURL"],
            snippet: topic["Text"]
          }

          break if results.length >= num_results
        end

        results.first(num_results)
      end

      def parse_google_results(data)
        results = []

        data["items"]&.each do |item|
          results << {
            title: item["title"],
            url: item["link"],
            snippet: item["snippet"] || "No snippet available"
          }
        end

        results
      end

      def parse_bing_results(data)
        results = []

        if data["webPages"] && data["webPages"]["value"]
          data["webPages"]["value"].each do |item|
            results << {
              title: item["name"],
              url: item["url"],
              snippet: item["snippet"] || "No snippet available"
            }
          end
        end

        results
      end

      def format_search_results(results, query)
        return "No search results found for query: '#{query}'" if results.empty?

        output = "Search results for '#{query}':\n\n"

        results.each_with_index do |result, index|
          output += "#{index + 1}. #{result[:title]}\n"
          output += "   URL: #{result[:url]}\n"
          output += "   #{result[:snippet]}\n\n"
        end

        output += "Found #{results.length} results."
        output
      end
    end
  end
end
