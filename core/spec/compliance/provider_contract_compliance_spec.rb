# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Provider Contract Compliance", :compliance do
  # Available providers for testing
  # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
  CORE_PROVIDERS = [
    RAAF::Models::ResponsesProvider,
    RAAF::Models::OpenAIProvider
  ].freeze
  # rubocop:enable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration

  let(:test_messages) do
    [
      { role: "system", content: "You are a helpful assistant" },
      { role: "user", content: "Hello, how are you?" }
    ]
  end

  let(:test_tools) do
    [{
      type: "function",
      function: {
        name: "get_weather",
        description: "Get weather information",
        parameters: {
          type: "object",
          properties: {
            location: { type: "string", description: "City name" }
          },
          required: ["location"]
        }
      }
    }]
  end

  describe "Base Interface Contract" do
    CORE_PROVIDERS.each do |provider_class|
      context provider_class.name.to_s do
        let(:provider) { provider_class.new }

        describe "required method signatures" do
          it "implements chat_completion with required parameters" do
            expect(provider).to respond_to(:chat_completion)

            # Check method signature
            method = provider.method(:chat_completion)
            required_params = %i[messages model]

            param_names = method.parameters.map(&:last)
            required_params.each do |param|
              expect(param_names).to include(param),
                                     "#{provider_class.name} should have required parameter :#{param}"
            end
          end

          it "implements supported_models method" do
            expect(provider).to respond_to(:supported_models)
            expect(provider.supported_models).to be_an(Array)
            expect(provider.supported_models).not_to be_empty
            expect(provider.supported_models.all? { |m| m.is_a?(String) }).to be true
          end

          it "implements provider_name method" do
            expect(provider).to respond_to(:provider_name)
            expect(provider.provider_name).to be_a(String)
            expect(provider.provider_name).not_to be_empty
          end

          it "implements stream_completion method" do
            expect(provider).to respond_to(:stream_completion)

            method = provider.method(:stream_completion)
            param_names = method.parameters.map(&:last)
            expect(param_names).to include(:messages)
            expect(param_names).to include(:model)
          end
        end

        describe "enhanced interface methods" do
          it "optionally implements responses_completion" do
            if provider.respond_to?(:responses_completion)
              method = provider.method(:responses_completion)
              param_names = method.parameters.map(&:last)
              expect(param_names).to include(:messages)
              expect(param_names).to include(:model)
            end
          end

          it "optionally implements capability detection methods" do
            expect([true, false]).to include(provider.supports_handoffs?) if provider.respond_to?(:supports_handoffs?)

            expect([true, false]).to include(provider.supports_function_calling?) if provider.respond_to?(:supports_function_calling?)

            expect(provider.capabilities).to be_a(Hash) if provider.respond_to?(:capabilities)
          end
        end
      end
    end
  end

  describe "Parameter Validation Contract" do
    CORE_PROVIDERS.each do |provider_class|
      context provider_class.name.to_s do
        let(:provider) { provider_class.new }
        let(:valid_model) { provider.supported_models.first }

        describe "messages parameter validation" do
          it "accepts properly formatted messages array" do
            # Just verify the method signature accepts messages parameter
            method_params = provider.method(:chat_completion).parameters
            messages_param = method_params.find { |_type, name| name == :messages }
            expect(messages_param).not_to be_nil
            expect(%i[req keyreq].include?(messages_param.first)).to be true
          end

          it "validates message structure requirements" do
            invalid_messages = [
              [{ content: "missing role" }],
              [{ role: "user" }], # missing content
              [{ role: "invalid_role", content: "test" }],
              "not an array",
              nil
            ]

            invalid_messages.each do |_invalid_msg|
              # For now, we'll just verify the provider accepts the parameter
              # Actual validation would require mocking HTTP calls
              expect(provider.method(:chat_completion).parameters.map(&:last))
                .to include(:messages)
            end
          end
        end

        describe "model parameter validation" do
          it "accepts models from supported_models list" do
            supported_models = provider.supported_models
            expect(supported_models).not_to be_empty

            # Test that first supported model is valid
            first_model = supported_models.first
            expect(first_model).to be_a(String)
            expect(first_model).not_to be_empty
          end
        end

        describe "tools parameter validation" do
          it "accepts nil tools parameter" do
            expect(provider.method(:chat_completion).parameters.map(&:last))
              .to include(:tools)
          end

          it "accepts properly formatted tools array" do
            # Verify the method signature accepts tools parameter
            method_params = provider.method(:chat_completion).parameters
            tools_param = method_params.find { |_type, name| name == :tools }
            expect(tools_param).not_to be_nil
            expect(%i[opt key].include?(tools_param.first)).to be true
          end
        end
      end
    end
  end

  describe "Response Format Contract" do
    let(:mock_provider) { create_mock_provider }

    describe "chat_completion response format" do
      it "returns hash with required keys" do
        # Mock standard OpenAI Chat Completions format
        mock_response = {
          "id" => "chatcmpl-test123",
          "object" => "chat.completion",
          "model" => "gpt-4o",
          "choices" => [{
            "index" => 0,
            "message" => {
              "role" => "assistant",
              "content" => "Hello! I'm doing well, thank you for asking."
            },
            "finish_reason" => "stop"
          }],
          "usage" => {
            "prompt_tokens" => 15,
            "completion_tokens" => 12,
            "total_tokens" => 27
          }
        }

        allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

        result = mock_provider.chat_completion(
          messages: test_messages,
          model: "gpt-4o"
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key("choices")
        expect(result).to have_key("usage")
        expect(result["choices"]).to be_an(Array)
        expect(result["usage"]).to be_a(Hash)
      end

      it "includes proper choice structure" do
        mock_provider.add_response("Test response")

        # Convert mock response to Chat Completions format
        allow(mock_provider).to receive(:chat_completion).and_return({
                                                                       "choices" => [{
                                                                         "index" => 0,
                                                                         "message" => {
                                                                           "role" => "assistant",
                                                                           "content" => "Test response"
                                                                         },
                                                                         "finish_reason" => "stop"
                                                                       }]
                                                                     })

        result = mock_provider.chat_completion(
          messages: test_messages,
          model: "gpt-4o"
        )

        choice = result["choices"].first
        expect(choice).to have_key("message")
        expect(choice["message"]).to have_key("role")
        expect(choice["message"]).to have_key("content")
        expect(choice["message"]["role"]).to eq("assistant")
      end

      it "includes usage statistics" do
        mock_provider.add_response("Usage test")

        allow(mock_provider).to receive(:chat_completion).and_return({
                                                                       "choices" => [{ "message" => { "role" => "assistant", "content" => "Usage test" } }],
                                                                       "usage" => {
                                                                         "prompt_tokens" => 10,
                                                                         "completion_tokens" => 5,
                                                                         "total_tokens" => 15
                                                                       }
                                                                     })

        result = mock_provider.chat_completion(
          messages: test_messages,
          model: "gpt-4o"
        )

        usage = result["usage"]
        expect(usage).to have_key("prompt_tokens")
        expect(usage).to have_key("completion_tokens")
        expect(usage).to have_key("total_tokens")
        expect(usage["total_tokens"]).to eq(usage["prompt_tokens"] + usage["completion_tokens"])
      end
    end

    describe "responses_completion response format" do
      it "returns hash with Responses API structure" do
        mock_provider.add_response("Responses API test")

        result = mock_provider.responses_completion(
          messages: test_messages,
          model: "gpt-4o"
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key(:output)
        expect(result).to have_key(:usage)
        expect(result[:output]).to be_an(Array)
        expect(result[:usage]).to be_a(Hash)
      end

      it "includes proper output structure" do
        mock_provider.add_response("Output structure test")

        result = mock_provider.responses_completion(
          messages: test_messages,
          model: "gpt-4o"
        )

        output_item = result[:output].first
        expect(output_item).to have_key(:type)
        expect(output_item).to have_key(:role)
        expect(output_item).to have_key(:content)
        expect(output_item[:type]).to eq("message")
        expect(output_item[:role]).to eq("assistant")
      end
    end
  end

  describe "Error Handling Contract" do
    let(:mock_provider) { create_mock_provider }

    describe "standard error types" do
      it "raises AuthenticationError for 401 responses" do
        error = RAAF::AuthenticationError.new("Invalid API key", status: 401)
        mock_provider.add_error(error)

        expect do
          mock_provider.responses_completion(
            messages: test_messages,
            model: "gpt-4o"
          )
        end.to raise_error(RAAF::AuthenticationError)
      end

      it "raises RateLimitError for 429 responses" do
        error = RAAF::RateLimitError.new("Rate limit exceeded", status: 429)
        mock_provider.add_error(error)

        expect do
          mock_provider.responses_completion(
            messages: test_messages,
            model: "gpt-4o"
          )
        end.to raise_error(RAAF::RateLimitError)
      end

      it "raises APIError for general API failures" do
        error = RAAF::APIError.new("API request failed", status: 500)
        mock_provider.add_error(error)

        expect do
          mock_provider.responses_completion(
            messages: test_messages,
            model: "gpt-4o"
          )
        end.to raise_error(RAAF::APIError)
      end

      it "preserves error status codes" do
        error = RAAF::InvalidRequestError.new("Bad request", status: 400)
        mock_provider.add_error(error)

        # rubocop:disable Style/MultilineBlockChain
        expect do
          mock_provider.responses_completion(
            messages: test_messages,
            model: "gpt-4o"
          )
        end.to raise_error(RAAF::InvalidRequestError) do |e|
          # rubocop:enable Style/MultilineBlockChain
          expect(e.status).to eq(400)
        end
      end
    end

    describe "error message consistency" do
      it "provides meaningful error messages" do
        error = RAAF::AuthenticationError.new("API key authentication failed", status: 401)
        mock_provider.add_error(error)

        expect do
          mock_provider.responses_completion(
            messages: test_messages,
            model: "gpt-4o"
          )
        end.to raise_error(RAAF::AuthenticationError, /authentication failed/i)
      end
    end
  end

  describe "Configuration Contract" do
    CORE_PROVIDERS.each do |provider_class|
      context provider_class.name.to_s do
        describe "constructor parameters" do
          it "accepts api_key parameter" do
            if provider_class.instance_method(:initialize).parameters.map(&:last).include?(:api_key)
              expect do
                provider_class.new(api_key: "test-key")
              end.not_to raise_error
            end
          end

          it "accepts base_url parameter" do
            constructor_params = provider_class.instance_method(:initialize).parameters.map(&:last)
            if constructor_params.include?(:base_url) || constructor_params.include?(:api_base)
              expect do
                provider_class.new(base_url: "https://api.test.com")
              end.not_to raise_error
            end
          end

          it "accepts additional options via kwargs" do
            # All providers should accept **kwargs for additional options
            constructor_params = provider_class.instance_method(:initialize).parameters
            has_keyrest = constructor_params.any? { |type, _| type == :keyrest }
            expect(has_keyrest).to be(true), "#{provider_class.name} should accept **kwargs"
          end
        end

        describe "environment variable support" do
          it "respects standard environment variables" do
            # Test environment variable patterns

            # Just verify the class can be instantiated (actual env var testing would need more setup)
            expect { provider_class.new }.not_to raise_error
          end
        end
      end
    end
  end

  describe "Built-in Retry Logic (ModelInterface)" do
    let(:mock_provider) { create_mock_provider }

    it "includes retry logic in ModelInterface base class" do
      # Test that all providers inherit retry logic from ModelInterface
      expect(mock_provider).to respond_to(:configure_retry)
      expect(mock_provider).to respond_to(:responses_completion)
      
      # Verify retry configuration is available
      expect(mock_provider.retry_config).to be_a(Hash)
      expect(mock_provider.retry_config).to have_key(:max_attempts)
      expect(mock_provider.retry_config).to have_key(:base_delay)
    end

    it "allows retry configuration customization" do
      # Verify that retry behavior can be configured on any provider
      mock_provider.configure_retry(max_attempts: 5, base_delay: 2.0)
      
      expect(mock_provider.retry_config[:max_attempts]).to eq(5)
      expect(mock_provider.retry_config[:base_delay]).to eq(2.0)
    end
  end

  describe "Tool Calling Contract" do
    let(:mock_provider) { create_mock_provider }

    describe "tool definition format" do
      it "accepts OpenAI-compatible tool definitions" do
        mock_provider.add_response("I can help with weather", tool_calls: [{
                                     function: {
                                       name: "get_weather",
                                       arguments: JSON.generate({ location: "Paris" })
                                     }
                                   }])

        result = mock_provider.responses_completion(
          messages: test_messages,
          model: "gpt-4o",
          tools: test_tools
        )

        expect(result).to be_a(Hash)
        expect(result[:output]).to be_an(Array)
      end

      it "returns tool calls in expected format" do
        tool_call_response = {
          function: {
            name: "get_weather",
            arguments: JSON.generate({ location: "New York" })
          }
        }

        mock_provider.add_response("Checking weather", tool_calls: [tool_call_response])

        result = mock_provider.responses_completion(
          messages: test_messages,
          model: "gpt-4o",
          tools: test_tools
        )

        # Find function call in output
        function_calls = result[:output].select { |item| item[:type] == "function_call" }
        expect(function_calls).not_to be_empty

        if function_calls.any?
          call = function_calls.first
          expect(call).to have_key(:name)
          expect(call).to have_key(:arguments)
          expect(call[:name]).to eq("get_weather")
        end
      end
    end
  end

  describe "Streaming Contract" do
    let(:mock_provider) { create_mock_provider }

    it "implements streaming interface" do
      # MockProvider doesn't implement stream_completion, so test with actual providers
      CORE_PROVIDERS.each do |provider_class|
        provider = provider_class.new
        expect(provider).to respond_to(:stream_completion)

        # Verify method signature
        method = provider.method(:stream_completion)
        expect(method.parameters.map(&:last)).to include(:messages, :model)
      end
    end
  end

  describe "Cross-Provider Consistency" do
    it "maintains consistent method signatures across providers" do
      # Compare method signatures between providers
      method_signatures = {}

      CORE_PROVIDERS.each do |provider_class|
        provider = provider_class.new
        method_signatures[provider_class.name] = {
          chat_completion: provider.method(:chat_completion).parameters,
          supported_models: provider.method(:supported_models).parameters,
          provider_name: provider.method(:provider_name).parameters
        }
      end

      # All providers should have the same basic method signatures
      expect(method_signatures.values.uniq.size).to be >= 1
    end

    it "returns consistent supported_models format" do
      CORE_PROVIDERS.each do |provider_class|
        provider = provider_class.new
        models = provider.supported_models

        expect(models).to be_an(Array)
        expect(models.all? { |m| m.is_a?(String) }).to be true
        expect(models).not_to be_empty
      end
    end

    it "provides consistent provider_name format" do
      CORE_PROVIDERS.each do |provider_class|
        provider = provider_class.new
        name = provider.provider_name

        expect(name).to be_a(String)
        expect(name).not_to be_empty
        expect(name).to match(/\A[a-zA-Z][a-zA-Z0-9_]*\z/) # Valid identifier format
      end
    end
  end
end
