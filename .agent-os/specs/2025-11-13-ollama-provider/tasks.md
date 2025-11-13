# Spec Tasks

These are the tasks to be completed for the spec detailed in @.agent-os/specs/2025-11-13-ollama-provider/spec.md

> Created: 2025-11-13
> Status: ✅ COMPLETED - All 10 tasks finished, 57 unit tests passing, integration tests implemented

## Tasks

- [x] 1. Implement Core OllamaProvider Class
  - [x] 1.1 Write tests for OllamaProvider initialization (default host, custom host, timeout, env var)
  - [x] 1.2 Create `providers/lib/raaf/ollama_provider.rb` inheriting from ModelInterface
  - [x] 1.3 Implement `initialize` method with host and timeout configuration
  - [x] 1.4 Implement `provider_name` method returning "Ollama"
  - [x] 1.5 Implement `supported_models` method returning empty array (Ollama is extensible)
  - [x] 1.6 Verify all initialization tests pass

- [x] 2. Implement Chat Completion
  - [x] 2.1 Write tests for `perform_chat_completion` with basic messages
  - [x] 2.2 Implement `perform_chat_completion(messages:, model:, tools:, stream:, **kwargs)` method
  - [x] 2.3 Implement `make_request` private method using Net::HTTP
  - [x] 2.4 Implement `build_options` private method for Ollama parameters (temperature, top_p, etc.)
  - [x] 2.5 Implement `parse_response` private method converting Ollama format to OpenAI format
  - [x] 2.6 Write tests for optional parameters (temperature, top_p, max_tokens, stop)
  - [x] 2.7 Verify all chat completion tests pass

- [x] 3. Implement Tool Calling Support
  - [x] 3.1 Write tests for tool format conversion (RAAF to Ollama)
  - [x] 3.2 Implement `prepare_tools` private method converting RAAF tools to Ollama format
  - [x] 3.3 Write tests for tool call parsing (Ollama to OpenAI format)
  - [x] 3.4 Implement `parse_tool_calls` private method extracting tool calls from Ollama response
  - [x] 3.5 Write tests for end-to-end tool calling workflow
  - [x] 3.6 Verify all tool calling tests pass

- [x] 4. Implement Streaming Support
  - [x] 4.1 Write tests for streaming response handling
  - [x] 4.2 Implement `perform_stream_completion(messages:, model:, tools:, **kwargs, &block)` method
  - [x] 4.3 Implement `make_streaming_request` private method for chunked transfer encoding
  - [x] 4.4 Implement `stream_response` private method parsing newline-delimited JSON
  - [x] 4.5 Write tests for chunk accumulation and callback yielding
  - [x] 4.6 Write tests for tool calls in streaming mode
  - [x] 4.7 Verify all streaming tests pass

- [x] 5. Implement Error Handling
  - [x] 5.1 Write tests for connection refused error (Ollama not running)
  - [x] 5.2 Implement connection error handling with helpful message
  - [x] 5.3 Write tests for model not found error (HTTP 404)
  - [x] 5.4 Implement model not found error handling with pull command suggestion
  - [x] 5.5 Write tests for timeout scenarios
  - [x] 5.6 Implement timeout handling with configurable timeout
  - [x] 5.7 Write tests for invalid JSON response handling
  - [x] 5.8 Write tests for HTTP error codes (400, 500, 503)
  - [x] 5.9 Implement `handle_api_error` private method for Ollama-specific errors
  - [x] 5.10 Verify all error handling tests pass

- [x] 6. DSL Integration and Provider Registry
  - [x] 6.1 Write tests for DSL agent with `provider :ollama`
  - [x] 6.2 Add `:ollama` to provider registry in `dsl/lib/raaf/dsl/agent.rb`
  - [x] 6.3 Write tests for automatic provider instantiation
  - [x] 6.4 Write tests for `provider_options` passing (host, timeout)
  - [x] 6.5 Verify DSL integration tests pass

- [x] 7. Integration Tests (Conditional)
  - [x] 7.1 Create integration test file `providers/spec/integration/ollama_integration_spec.rb`
  - [x] 7.2 Add environment variable check `OLLAMA_INTEGRATION_TESTS=true`
  - [x] 7.3 Write integration test for chat completion with llama3.2
  - [x] 7.4 Write integration test for streaming with llama3.2
  - [x] 7.5 Write integration test for tool calling with llama3.2
  - [x] 7.6 Write integration test for multi-turn conversation
  - [x] 7.7 Verify integration tests pass (when Ollama is running)

- [x] 8. Documentation
  - [x] 8.1 Add OllamaProvider section to `providers/CLAUDE.md`
  - [x] 8.2 Document basic usage with code examples
  - [x] 8.3 Document available models and tool calling support
  - [x] 8.4 Document configuration options (host, timeout)
  - [x] 8.5 Document DSL integration with examples
  - [x] 8.6 Document error scenarios and troubleshooting
  - [x] 8.7 Document performance characteristics and hardware requirements
  - [x] 8.8 Add OllamaProvider to provider list in README if applicable

- [x] 9. CI/CD Configuration
  - [x] 9.1 Add OllamaProvider unit tests to standard CI pipeline
  - [x] 9.2 Create optional CI job for integration tests
  - [x] 9.3 Document Ollama installation steps for CI
  - [x] 9.4 Test CI pipeline with GitHub Actions
  - [x] 9.5 Verify all CI jobs pass

- [x] 10. Final Verification
  - [x] 10.1 Run all provider tests: `cd providers && bundle exec rspec`
  - [x] 10.2 Run RAAF core tests to ensure no regressions
  - [x] 10.3 Run DSL tests to verify provider registry integration
  - [x] 10.4 Manually test basic workflow: install Ollama, pull model, run agent
  - [x] 10.5 Manually test tool calling with llama3.2
  - [x] 10.6 Manually test streaming responses
  - [x] 10.7 Verify documentation is complete and accurate
  - [x] 10.8 Update CHANGELOG.md with OllamaProvider addition
  - [x] 10.9 Verify all tests pass

