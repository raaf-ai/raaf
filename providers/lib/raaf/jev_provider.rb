# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
# DecisionInterface is required from the raaf-core gem

module RAAF
  module Models
    ##
    # TypeSafe Jev decision model provider
    #
    # Jev is a "System One" model: it evaluates a piece of state and returns
    # typed answers with calibrated probabilities in a single forward pass,
    # rather than generating text. It implements {DecisionInterface}, not
    # {ModelInterface} - there is no chat, no tool calling and no streaming.
    #
    # Every question in a request is evaluated in parallel, so asking several
    # questions about one state costs roughly one question's latency.
    #
    # == Wire format
    #
    # Request and response shapes follow TypeSafe's SDKs: a body of +model+,
    # +state+ and +questions+, and a response of +model+, +usage+ and +answers+
    # keyed by question name.
    #
    # @example
    #   provider = JevProvider.new(api_key: ENV["TYPESAFE_API_KEY"])
    #
    #   result = provider.decide(
    #     state: "I've been trying to connect my Stripe account for 3 days and it keeps failing.",
    #     questions: {
    #       is_urgent: Decision::Noul.new(instructions: "The message conveys urgency or time-sensitivity")
    #     }
    #   )
    #
    #   result[:is_urgent].probability # => 0.999
    #
    # @see https://docs.typesafe.ai/concepts/system-one
    #
    class JevProvider < DecisionInterface
      # Default API base URL
      API_BASE = "https://api.typesafe.ai/v1"

      # Path of the System One endpoint, relative to the API base
      ENDPOINT_PATH = "/systemone"

      # Environment variable holding the API key
      API_KEY_ENV = "TYPESAFE_API_KEY"

      # Human-readable provider name
      PROVIDER_DISPLAY_NAME = "Jev"

      # Model asked when the caller names none
      DEFAULT_MODEL = "jev-latest"

      # Response keys that may wrap the answers, checked in order before
      # falling back to reading them off the top level
      ANSWER_ENVELOPE_KEYS = %w[answers questions results].freeze

      # Response keys that belong to the envelope rather than to an answer
      ENVELOPE_METADATA_KEYS = %w[id model object usage created created_at latency_ms].freeze

      # Response header carrying the request id, worth quoting in a support request
      REQUEST_ID_HEADER = "x-typesafe-request-id"

      ##
      # @param api_key [String, nil] TypeSafe API key (default: +TYPESAFE_API_KEY+)
      # @param api_base [String, nil] API base URL (default: {API_BASE})
      # @param model [String, nil] Model id (default: {DEFAULT_MODEL})
      # @param timeout [Numeric] Read timeout in seconds (default: 10)
      # @param open_timeout [Numeric] Connect timeout in seconds (default: 5)
      # @param options [Hash] Additional options passed to {DecisionInterface}
      # @raise [AuthenticationError] If no API key is available
      #
      def initialize(api_key: nil, api_base: nil, model: nil, timeout: 10, open_timeout: 5, **options)
        super(api_key: api_key, api_base: api_base, model: model, **options)

        @api_key ||= ENV.fetch(API_KEY_ENV, nil)
        @api_base ||= API_BASE
        @timeout = timeout
        @open_timeout = open_timeout

        raise AuthenticationError, "#{PROVIDER_DISPLAY_NAME} API key is required" unless @api_key
      end

      ##
      # @return [String] {PROVIDER_DISPLAY_NAME}
      #
      def provider_name
        PROVIDER_DISPLAY_NAME
      end

      ##
      # @return [String] {DEFAULT_MODEL}
      #
      def default_model
        DEFAULT_MODEL
      end

      ##
      # Answers the questions using Jev
      #
      # @param state [String, Hash, Array] What to decide about
      # @param questions [Hash{String => Decision::Question}] Built questions by name
      # @param model [String, nil] Model id to ask
      # @param kwargs [Hash] Additional body parameters passed through to the API
      # @return [Decision::Result]
      # @raise [APIError] If the request fails
      # @raise [Decision::MalformedAnswerError] If an answer is missing or unreadable
      #
      def perform_decision(state:, questions:, model:, **kwargs)
        body = {
          model: model || default_model,
          state: state,
          questions: questions.transform_values(&:to_request)
        }.merge(kwargs)

        response, headers = post(body)
        build_result(response, questions, body[:model], headers)
      end

      private

      ##
      # POSTs to the System One endpoint
      #
      # @param body [Hash] Request body
      # @return [Array(Hash, Net::HTTPResponse)] Parsed body and the response
      # @raise [APIError] If the request fails
      #
      def post(body)
        uri = URI("#{@api_base}#{ENDPOINT_PATH}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = @timeout
        http.open_timeout = @open_timeout

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = body.to_json

        response = http.request(request)
        handle_api_error(response) unless response.code.start_with?("2")

        [RAAF::Utils.parse_json(response.body), response]
      end

      ##
      # Turns a response body into answers
      #
      # @param response [Hash] Parsed response body
      # @param questions [Hash{String => Decision::Question}] The questions asked
      # @param model [String] The model that was asked
      # @param headers [Net::HTTPResponse, nil] The response, for its headers
      # @return [Decision::Result]
      # @raise [Decision::MalformedAnswerError] If an answer is missing
      #
      def build_result(response, questions, model, headers = nil)
        bodies = answer_bodies(response)

        answers = questions.each_with_object({}) do |(name, question), result|
          body = bodies[name] || bodies[name.to_sym]
          raise Decision::MalformedAnswerError, "#{provider_name} did not answer question #{name.inspect}" if body.nil?

          result[name] = question.parse(body)
        end

        Decision::Result.new(
          answers: answers,
          model: response["model"] || model,
          provider: provider_name,
          raw: response,
          usage: response["usage"],
          request_id: headers && headers[REQUEST_ID_HEADER]
        )
      end

      ##
      # Finds the answers within the response
      #
      # TypeSafe's published example shows answers keyed by question name at
      # the top level alongside envelope metadata, so an explicit wrapper is
      # preferred when present and the top level is read otherwise, with the
      # known metadata keys removed.
      #
      # @param response [Hash] Parsed response body
      # @return [Hash] Answer bodies by question name
      #
      def answer_bodies(response)
        return {} unless response.is_a?(Hash)

        ANSWER_ENVELOPE_KEYS.each do |key|
          wrapped = response[key]
          return wrapped if wrapped.is_a?(Hash)
        end

        response.reject { |key, _value| ENVELOPE_METADATA_KEYS.include?(key.to_s) }
      end

      ##
      # Raises the matching RAAF error for a failed response
      #
      # @param response [Net::HTTPResponse] The error response
      # @raise [AuthenticationError, RateLimitError, ServerError, APIError]
      #
      def handle_api_error(response)
        case response.code.to_i
        when 401, 403
          raise AuthenticationError, "Invalid #{provider_name} API key"
        when 429
          retry_after = response["retry-after-ms"] || response["retry-after"] || response["x-ratelimit-reset"]
          raise RateLimitError, "#{provider_name} rate limit exceeded. Retry after: #{retry_after}"
        when 500..599
          raise ServerError, "Server error from #{provider_name}: #{response.code}"
        else
          raise APIError, "API error from #{provider_name}: #{response.code} - #{error_message(response)}"
        end
      end

      ##
      # The API's error message, from wherever it put it
      #
      # Validation failures come back FastAPI-shaped, as a +detail+ array of
      # +loc+/+msg+ entries, which reads as nothing useful unless it is walked.
      #
      # @param response [Net::HTTPResponse] The error response
      # @return [String] The error message, or the raw body
      #
      def error_message(response)
        parsed = JSON.parse(response.body.to_s)
        return response.body unless parsed.is_a?(Hash)

        message_from(parsed["error"]) || message_from(parsed["message"]) ||
          message_from(parsed["detail"]) || response.body
      rescue JSON::ParserError
        response.body
      end

      ##
      # @param value [Object] An error, message or detail field
      # @return [String, nil] Its message, when it has one
      #
      def message_from(value)
        case value
        when String then value.empty? ? nil : value
        when Hash then message_from(value["message"] || value["msg"])
        when Array then message_from(value.filter_map { |entry| validation_entry(entry) }.join("; "))
        end
      end

      ##
      # @param entry [Object] One FastAPI validation error
      # @return [String, nil] The field path and message
      #
      def validation_entry(entry)
        return unless entry.is_a?(Hash) && entry["msg"].is_a?(String)

        location = entry["loc"]
        path = location.is_a?(Array) ? location.reject { |item| item == "body" }.join(".") : ""
        path.empty? ? entry["msg"] : "#{path}: #{entry['msg']}"
      end
    end
  end
end
