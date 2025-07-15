# frozen_string_literal: true

# Example of how to integrate the new logging system into existing code

module RubyAIAgentsFactory
  class Runner
    # Example of how to replace existing puts statements with structured logging

    def run_with_logging(messages)
      RubyAIAgentsFactory::Logging.agent_start(@agent.name, run_id: generate_run_id)

      start_time = Time.current

      begin
        result = run_conversation(messages)

        duration = ((Time.current - start_time) * 1000).round(2)
        RubyAIAgentsFactory::Logging.agent_end(@agent.name, duration: duration,
                                                     message_count: result.messages.count)

        result
      rescue StandardError => e
        RubyAIAgentsFactory::Logging.error("Agent run failed",
                                    agent: @agent.name,
                                    error: e.message,
                                    error_class: e.class.name)
        raise
      end
    end

    private

    def log_tool_call(tool_name, input)
      RubyAIAgentsFactory::Logging.tool_call(tool_name,
                                      input_size: input.to_s.length,
                                      tool_type: tool_name.class.name)
    end

    def log_handoff(from_agent, to_agent, reason = nil)
      RubyAIAgentsFactory::Logging.handoff(from_agent.name, to_agent.name,
                                    reason: reason)
    end

    def log_api_call(method, url, duration, response_code)
      RubyAIAgentsFactory::Logging.api_call(method, url,
                                     duration: duration,
                                     response_code: response_code)
    end
  end

  # Example for tracing system
  module Tracing
    class OpenAIProcessor
      def send_trace_batch(traces)
        start_time = Time.current

        begin
          response = http_client.post(traces)
          duration = ((Time.current - start_time) * 1000).round(2)

          RubyAIAgentsFactory::Logging.debug("Trace batch sent",
                                      trace_count: traces.count,
                                      duration_ms: duration,
                                      response_code: response.code)
        rescue StandardError => e
          RubyAIAgentsFactory::Logging.api_error(e,
                                          operation: "send_trace_batch",
                                          trace_count: traces.count)
          raise
        end
      end
    end
  end
end

# Configuration examples for different environments

# config/environments/development.rb
# RubyAIAgentsFactory::Logging.configure do |config|
#   config.log_level = :debug
#   config.log_format = :text
#   config.log_output = :console
# end

# config/environments/production.rb
# RubyAIAgentsFactory::Logging.configure do |config|
#   config.log_level = :info
#   config.log_format = :json
#   config.log_output = :rails
# end

# config/environments/test.rb
# RubyAIAgentsFactory::Logging.configure do |config|
#   config.log_level = :error
#   config.log_output = :file
#   config.log_file = "log/test_openai_agents.log"
# end
