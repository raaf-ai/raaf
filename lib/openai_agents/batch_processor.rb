# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "tempfile"
require "securerandom"
require_relative "errors"

module OpenAIAgents
  ##
  # BatchProcessor - Process multiple requests efficiently using OpenAI's Batch API
  #
  # The Batch API allows you to submit a collection of API requests to be processed
  # asynchronously at a 50% discount compared to regular API calls. Ideal for
  # processing large datasets, evaluations, and bulk operations.
  #
  # == Features
  #
  # * Submit batches of chat completion requests
  # * Monitor batch job progress and status
  # * Retrieve results when processing is complete
  # * 50% cost savings compared to individual API calls
  # * Support for up to 50,000 requests per batch
  # * Automatic retry and error handling
  #
  # == Basic Usage
  #
  #   # Create batch processor
  #   processor = OpenAIAgents::BatchProcessor.new
  #
  #   # Prepare batch requests
  #   requests = [
  #     { model: "gpt-4.1", messages: [{ role: "user", content: "Hello" }] },
  #     { model: "gpt-4.1", messages: [{ role: "user", content: "How are you?" }] }
  #   ]
  #
  #   # Submit batch
  #   batch = processor.submit_batch(requests, description: "My batch job")
  #
  #   # Wait for completion and get results
  #   results = processor.wait_for_completion(batch["id"])
  #
  # == Advanced Usage
  #
  #   # Submit with custom completion window
  #   batch = processor.submit_batch(requests, completion_window: "24h")
  #
  #   # Monitor progress
  #   processor.check_status(batch["id"]) do |status|
  #     puts "Progress: #{status["request_counts"]["completed"]}/#{status["request_counts"]["total"]}"
  #   end
  #
  class BatchProcessor
    BASE_URL = "https://api.openai.com/v1"

    ##
    # Initializes a new BatchProcessor
    #
    # @param api_key [String, nil] OpenAI API key (defaults to ENV["OPENAI_API_KEY"])
    # @param api_base [String] Base URL for API calls
    def initialize(api_key: nil, api_base: BASE_URL)
      @api_key = api_key || ENV.fetch("OPENAI_API_KEY", nil)
      @api_base = api_base

      raise ArgumentError, "OpenAI API key is required" unless @api_key
    end

    ##
    # Submits a batch of requests for processing
    #
    # @param requests [Array<Hash>] Array of request objects with model, messages, etc.
    # @param description [String, nil] Optional description for the batch
    # @param completion_window [String] Time window for completion ("24h" default)
    # @param metadata [Hash, nil] Optional metadata for the batch
    # @return [Hash] Batch object with id, status, etc.
    # @raise [BatchError] if submission fails
    #
    # @example Submit basic batch
    #   requests = [
    #     { model: "gpt-4.1", messages: [{ role: "user", content: "Hello" }] },
    #     { model: "gpt-4.1", messages: [{ role: "user", content: "Goodbye" }] }
    #   ]
    #   batch = processor.submit_batch(requests)
    #
    # @example Submit with options
    #   batch = processor.submit_batch(
    #     requests,
    #     description: "Customer support responses",
    #     completion_window: "24h",
    #     metadata: { department: "support", version: "1.0" }
    #   )
    def submit_batch(requests, description: nil, completion_window: "24h", metadata: nil)
      raise ArgumentError, "Requests array cannot be empty" if requests.empty?
      raise ArgumentError, "Maximum 50,000 requests per batch" if requests.length > 50_000

      # Create JSONL file for batch requests
      jsonl_file = create_batch_file(requests)

      begin
        # Upload the file
        file_response = upload_file(jsonl_file.path)
        file_id = file_response["id"]

        # Create the batch
        batch_data = {
          input_file_id: file_id,
          endpoint: "/v1/chat/completions",
          completion_window: completion_window
        }
        batch_data[:description] = description if description
        batch_data[:metadata] = metadata if metadata

        response = make_request("POST", "/batches", batch_data)

        response
      ensure
        jsonl_file&.close
        jsonl_file&.unlink
      end
    end

    ##
    # Checks the status of a batch job
    #
    # @param batch_id [String] ID of the batch to check
    # @return [Hash] Batch status object
    # @raise [BatchError] if status check fails
    #
    # @example Check batch status
    #   status = processor.check_status("batch_abc123")
    #   puts status["status"] # => "in_progress", "completed", "failed", etc.
    def check_status(batch_id)
      response = make_request("GET", "/batches/#{batch_id}")

      yield(response) if block_given?

      response
    end

    ##
    # Waits for a batch to complete and returns the results
    #
    # @param batch_id [String] ID of the batch to wait for
    # @param poll_interval [Integer] Seconds between status checks (default: 30)
    # @param max_wait_time [Integer] Maximum time to wait in seconds (default: 1 hour)
    # @return [Array<Hash>] Array of results from the batch
    # @raise [BatchError] if batch fails or times out
    #
    # @example Wait for completion
    #   results = processor.wait_for_completion("batch_abc123")
    #   results.each { |result| puts result["response"]["choices"][0]["message"]["content"] }
    def wait_for_completion(batch_id, poll_interval: 30, max_wait_time: 3600)
      start_time = Time.now

      loop do
        status = check_status(batch_id)

        case status["status"]
        when "completed"
          return retrieve_results(status["output_file_id"])
        when "failed", "expired", "cancelled"
          raise BatchError, "Batch #{batch_id} #{status["status"]}: #{status.dig("errors", 0, "message")}"
        when "in_progress", "validating", "finalizing"
          # Continue waiting
        else
          raise BatchError, "Unknown batch status: #{status["status"]}"
        end

        # Check timeout
        if Time.now - start_time > max_wait_time
          raise BatchError, "Batch #{batch_id} timed out after #{max_wait_time} seconds"
        end

        sleep(poll_interval)
      end
    end

    ##
    # Retrieves results from a completed batch
    #
    # @param output_file_id [String] ID of the output file from completed batch
    # @return [Array<Hash>] Array of result objects
    # @raise [BatchError] if retrieval fails
    def retrieve_results(output_file_id)
      # Download the output file
      file_content = download_file(output_file_id)

      # Parse JSONL results
      results = []
      file_content.each_line do |line|
        line = line.strip
        next if line.empty?

        result = JSON.parse(line)
        results << result
      end

      results
    end

    ##
    # Lists all batches with optional filtering
    #
    # @param limit [Integer] Number of batches to return (default: 20)
    # @param after [String, nil] Batch ID to start after for pagination
    # @return [Hash] List of batches with pagination info
    def list_batches(limit: 20, after: nil)
      params = { limit: limit }
      params[:after] = after if after

      query_string = params.map { |k, v| "#{k}=#{v}" }.join("&")
      path = "/batches"
      path += "?#{query_string}" unless query_string.empty?

      make_request("GET", path)
    end

    ##
    # Cancels a batch that is in progress
    #
    # @param batch_id [String] ID of the batch to cancel
    # @return [Hash] Updated batch object
    # @raise [BatchError] if cancellation fails
    def cancel_batch(batch_id)
      make_request("POST", "/batches/#{batch_id}/cancel")
    end

    private

    def create_batch_file(requests)
      temp_file = Tempfile.new(["batch_requests", ".jsonl"])

      requests.each_with_index do |request, index|
        batch_request = {
          custom_id: "request-#{index}",
          method: "POST",
          url: "/v1/chat/completions",
          body: request
        }

        temp_file.puts(JSON.generate(batch_request))
      end

      temp_file.flush
      temp_file
    end

    def upload_file(file_path)
      uri = URI("#{@api_base}/files")

      # Create multipart form data
      boundary = "----WebKitFormBoundary#{SecureRandom.hex(16)}"

      file_content = File.read(file_path)
      body = []
      body << "--#{boundary}"
      body << 'Content-Disposition: form-data; name="purpose"'
      body << ""
      body << "batch"
      body << "--#{boundary}"
      body << 'Content-Disposition: form-data; name="file"; filename="batch.jsonl"'
      body << "Content-Type: application/json"
      body << ""
      body << file_content
      body << "--#{boundary}--"

      post_body = body.join("\r\n")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request.body = post_body

      response = http.request(request)
      handle_response(response)
    end

    def download_file(file_id)
      uri = URI("#{@api_base}/files/#{file_id}/content")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri.path)
      request["Authorization"] = "Bearer #{@api_key}"

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise BatchError, "Failed to download file: #{response.code} #{response.body}"
      end

      response.body
    end

    def make_request(method, path, data = nil)
      uri = URI("#{@api_base}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = case method.upcase
                when "GET"
                  Net::HTTP::Get.new(uri.path)
                when "POST"
                  req = Net::HTTP::Post.new(uri.path)
                  req["Content-Type"] = "application/json"
                  req.body = JSON.generate(data) if data
                  req
                else
                  raise ArgumentError, "Unsupported HTTP method: #{method}"
                end

      request["Authorization"] = "Bearer #{@api_key}"

      response = http.request(request)
      handle_response(response)
    end

    def handle_response(response)
      case response.code
      when "200", "201"
        JSON.parse(response.body)
      when "400"
        error_data = begin
          JSON.parse(response.body)
        rescue StandardError
          {}
        end
        raise BatchError, "Bad request: #{error_data.dig("error", "message") || response.body}"
      when "401"
        raise AuthenticationError, "Invalid API key"
      when "429"
        raise RateLimitError, "Rate limit exceeded"
      when "500", "502", "503", "504"
        raise ServerError, "Server error: #{response.code}"
      else
        raise BatchError, "API error: #{response.code} #{response.body}"
      end
    end
  end
end
