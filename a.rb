require 'net/http'
require 'uri'
require 'json'

class OpenAIWebSearch
  BASE_URL = 'https://api.openai.com/v1/responses'
  
  def initialize(api_key)
    @api_key = api_key
  end
  
  # Create a response with web search tool
  def search_with_ai(query)
    uri = URI(BASE_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    
    # Request body with web_search tool enabled
    body = {
      model: "gpt-4o",
      input: query,
      tools: [
        {
          type: "web_search"
        }
      ]
    }
    
    request.body = body.to_json
    
    response = http.request(request)
    handle_response(response)
  end
  
  # Create a follow-up response using previous response ID
  def follow_up(query, previous_response_id)
    uri = URI(BASE_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    
    body = {
      model: "gpt-4o",
      input: query,
      previous_response_id: previous_response_id,
      tools: [
        {
          type: "web_search"
        }
      ]
    }
    
    request.body = body.to_json
    
    response = http.request(request)
    handle_response(response)
  end
  
  # Stream responses for real-time output
  def search_with_streaming(query)
    uri = URI(BASE_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    
    body = {
      model: "gpt-4o",
      input: query,
      stream: true,
      tools: [
        {
          type: "web_search"
        }
      ]
    }
    
    request.body = body.to_json
    
    # Handle SSE streaming
    http.request(request) do |response|
      response.read_body do |chunk|
        # Process Server-Sent Events
        chunk.split("\n").each do |line|
          if line.start_with?("data: ")
            data = line[6..-1]
            next if data == "[DONE]"
            
            begin
              event = JSON.parse(data)
              process_stream_event(event)
            rescue JSON::ParserError
              # Skip invalid JSON
            end
          end
        end
      end
    end
  end
  
  # Combine web search with other tools
  def multi_tool_search(query, file_ids = [])
    uri = URI(BASE_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    
    tools = [
      { type: "web_search" }
    ]
    
    # Add file search if file IDs provided
    if file_ids.any?
      tools << {
        type: "file_search",
        file_search: {
          file_ids: file_ids
        }
      }
    end
    
    body = {
      model: "gpt-4o",
      input: query,
      tools: tools
    }
    
    request.body = body.to_json
    
    response = http.request(request)
    handle_response(response)
  end
  
  private
  
  def handle_response(response)
    case response.code
    when '200'
      JSON.parse(response.body)
    when '401'
      raise "Authentication failed. Check your API key."
    when '429'
      raise "Rate limit exceeded. Please try again later."
    else
      raise "API Error: #{response.code} - #{response.body}"
    end
  end
  
  def process_stream_event(event)
    # Extract content from streaming event
    if event['output'] && event['output'][0] && event['output'][0]['content']
      content = event['output'][0]['content'][0]['text']
      print content if content
    end
  end
end

# Example usage
if __FILE__ == $0
  # Initialize the client
  client = OpenAIWebSearch.new(ENV['OPENAI_API_KEY'])
  
  begin
    # Example 1: Simple web search query
    puts "=== Simple Web Search ==="
    response = client.search_with_ai("What are the latest developments in Ruby 3.3?")
    puts JSON.pretty_generate(response)
    
    # Example 2: Follow-up question using previous context
    puts "\n=== Follow-up Query ==="
    follow_up_response = client.follow_up(
      "Can you provide more details about the performance improvements?",
      response['id']
    )
    puts JSON.pretty_generate(follow_up_response)
    
    # Example 3: Streaming response
    puts "\n=== Streaming Response ==="
    client.search_with_streaming("Search for the current weather in Tokyo")
    
    # Example 4: Multi-tool usage (web search + file search)
    # First, you would upload files and get their IDs
    # file_ids = ['file-abc123', 'file-def456']
    # response = client.multi_tool_search(
    #   "Compare the information in my files with current market trends",
    #   file_ids
    # )
    
  rescue => e
    puts "Error: #{e.message}"
  end
end

# Alternative implementation using HTTParty gem for cleaner syntax
# Uncomment if you prefer using HTTParty

# require 'httparty'
# 
# class OpenAIWebSearchHTTParty
#   include HTTParty
#   base_uri 'https://api.openai.com/v1'
#   
#   def initialize(api_key)
#     @options = {
#       headers: {
#         'Authorization' => "Bearer #{api_key}",
#
