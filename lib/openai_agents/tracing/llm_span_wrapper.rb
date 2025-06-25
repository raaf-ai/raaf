# frozen_string_literal: true

module OpenAIAgents
  module Tracing
    # Wrapper to ensure LLM span data is properly captured
    class LLMSpanWrapper
      def self.wrap_provider(provider, tracer)
        return provider unless tracer

        # Create a proxy that intercepts chat_completion calls
        wrapper = new(provider, tracer)

        # Return a proxy object that delegates to wrapper
        Class.new do
          define_method :chat_completion do |**kwargs|
            wrapper.chat_completion(**kwargs)
          end

          define_method :stream_completion do |**kwargs|
            wrapper.stream_completion(**kwargs)
          end

          # Delegate all other methods to the original provider
          define_method :method_missing do |method, *args, **kwargs, &block|
            if kwargs.empty?
              provider.send(method, *args, &block)
            else
              provider.send(method, *args, **kwargs, &block)
            end
          end

          define_method :respond_to_missing? do |method, include_private = false|
            provider.respond_to?(method, include_private)
          end
        end.new
      end

      def initialize(provider, tracer)
        @provider = provider
        @tracer = tracer
      end

      def chat_completion(**kwargs)
        # Start LLM span
        span = @tracer.start_span("llm", kind: :llm)

        # Debug logging
        Rails.logger.info "[LLM Wrapper] Starting LLM span with model: #{kwargs[:model]}"

        # Set request attributes
        span.set_attribute("llm.request.messages", kwargs[:messages]) if kwargs[:messages]

        span.set_attribute("llm.request.model", kwargs[:model]) if kwargs[:model]

        span.set_attribute("llm.request.tools", kwargs[:tools].map(&:name)) if kwargs[:tools]

        begin
          # Call the original provider
          response = @provider.chat_completion(**kwargs)

          Rails.logger.info "[LLM Wrapper] Response received: #{response.keys.inspect}"
          Rails.logger.info "[LLM Wrapper] Usage data: #{response["usage"].inspect}" if response["usage"]

          # Extract and set response attributes
          if response.is_a?(Hash)
            # Set usage data
            if response["usage"]
              span.set_attribute("llm.usage.input_tokens", response["usage"]["input_tokens"])
              span.set_attribute("llm.usage.output_tokens", response["usage"]["output_tokens"])
              span.set_attribute("llm.usage.total_tokens", response["usage"]["total_tokens"])

              # Also set in the format expected by cost manager
              span.set_attribute("llm", {
                                   "request" => {
                                     "model" => kwargs[:model] || response["model"],
                                     "messages" => kwargs[:messages]
                                   },
                                   "response" => response,
                                   "usage" => response["usage"]
                                 })

              Rails.logger.info "[LLM Wrapper] Set llm attribute with usage data"
            else
              Rails.logger.warn "[LLM Wrapper] No usage data in response!"
            end

            # Set response content
            if response["choices"]&.first
              choice = response["choices"].first
              if choice["message"]
                span.set_attribute("llm.response.content", choice["message"]["content"])
                span.set_attribute("llm.response.role", choice["message"]["role"])

                if choice["message"]["tool_calls"]
                  span.set_attribute("llm.response.tool_calls", choice["message"]["tool_calls"])
                end
              end

              span.set_attribute("llm.response.finish_reason", choice["finish_reason"])
            end
          end

          span.finish
          response
        rescue StandardError => e
          span.record_exception(e)
          span.finish(status: :error)
          raise
        end
      end

      def stream_completion(**)
        # For now, just delegate streaming without tracing
        # TODO: Implement streaming span capture
        @provider.stream_completion(**)
      end
    end
  end
end
