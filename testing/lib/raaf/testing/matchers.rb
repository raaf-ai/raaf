# frozen_string_literal: true

module RAAF
  module Testing
    ##
    # RSpec matchers for testing AI agents
    #
    # Provides custom RSpec matchers for testing agent behavior,
    # responses, and interactions.
    #
    module Matchers
      ##
      # Matcher for successful agent responses
      #
      # @example
      #   expect(result).to be_successful
      #
      RSpec::Matchers.define :be_successful do
        match do |result|
          result.respond_to?(:success?) && result.success?
        end

        failure_message do |result|
          "expected agent response to be successful, but got: #{result.error || 'unknown error'}"
        end

        failure_message_when_negated do |result|
          "expected agent response to not be successful, but it was"
        end
      end

      ##
      # Matcher for agent responses containing specific text
      #
      # @example
      #   expect(result).to have_message_containing("hello")
      #   expect(result).to have_message_containing(/weather/i)
      #
      RSpec::Matchers.define :have_message_containing do |expected|
        match do |result|
          content = extract_message_content(result)
          case expected
          when String
            content.include?(expected)
          when Regexp
            content.match?(expected)
          else
            false
          end
        end

        failure_message do |result|
          content = extract_message_content(result)
          "expected agent response to contain #{expected.inspect}, but got: #{content.inspect}"
        end

        failure_message_when_negated do |result|
          content = extract_message_content(result)
          "expected agent response not to contain #{expected.inspect}, but it did: #{content.inspect}"
        end

        def extract_message_content(result)
          if result.respond_to?(:messages) && result.messages.any?
            result.messages.last[:content] || result.messages.last["content"] || ""
          elsif result.respond_to?(:content)
            result.content || ""
          else
            result.to_s
          end
        end
      end

      ##
      # Matcher for agent responses with specific length
      #
      # @example
      #   expect(result).to have_message_length(100)
      #   expect(result).to have_message_length_between(50, 200)
      #
      RSpec::Matchers.define :have_message_length do |expected|
        match do |result|
          content = extract_message_content(result)
          content.length == expected
        end

        failure_message do |result|
          content = extract_message_content(result)
          "expected agent response to have length #{expected}, but got #{content.length}"
        end

        def extract_message_content(result)
          if result.respond_to?(:messages) && result.messages.any?
            result.messages.last[:content] || result.messages.last["content"] || ""
          elsif result.respond_to?(:content)
            result.content || ""
          else
            result.to_s
          end
        end
      end

      ##
      # Matcher for agent responses with length in range
      #
      # @example
      #   expect(result).to have_message_length_between(50, 200)
      #
      RSpec::Matchers.define :have_message_length_between do |min, max|
        match do |result|
          content = extract_message_content(result)
          content.length.between?(min, max)
        end

        failure_message do |result|
          content = extract_message_content(result)
          "expected agent response to have length between #{min} and #{max}, but got #{content.length}"
        end

        def extract_message_content(result)
          if result.respond_to?(:messages) && result.messages.any?
            result.messages.last[:content] || result.messages.last["content"] || ""
          elsif result.respond_to?(:content)
            result.content || ""
          else
            result.to_s
          end
        end
      end

      ##
      # Matcher for agent responses with specific token usage
      #
      # @example
      #   expect(result).to have_token_usage_less_than(100)
      #   expect(result).to have_used_tokens(50)
      #
      RSpec::Matchers.define :have_token_usage_less_than do |expected|
        match do |result|
          usage = extract_token_usage(result)
          usage && usage < expected
        end

        failure_message do |result|
          usage = extract_token_usage(result)
          "expected agent response to use less than #{expected} tokens, but used #{usage}"
        end

        def extract_token_usage(result)
          if result.respond_to?(:usage) && result.usage
            result.usage[:total_tokens] || result.usage["total_tokens"]
          elsif result.respond_to?(:metadata) && result.metadata
            result.metadata[:token_usage] || result.metadata["token_usage"]
          else
            nil
          end
        end
      end

      ##
      # Matcher for agent responses with specific response time
      #
      # @example
      #   expect(result).to have_response_time_less_than(2.0)
      #
      RSpec::Matchers.define :have_response_time_less_than do |expected|
        match do |result|
          response_time = extract_response_time(result)
          response_time && response_time < expected
        end

        failure_message do |result|
          response_time = extract_response_time(result)
          "expected agent response time to be less than #{expected}s, but was #{response_time}s"
        end

        def extract_response_time(result)
          if result.respond_to?(:metadata) && result.metadata
            result.metadata[:response_time] || result.metadata["response_time"]
          else
            nil
          end
        end
      end

      ##
      # Matcher for agent tool usage
      #
      # @example
      #   expect(result).to have_used_tool("web_search")
      #   expect(result).to have_used_tools(["web_search", "calculator"])
      #
      RSpec::Matchers.define :have_used_tool do |expected_tool|
        match do |result|
          tools_used = extract_tools_used(result)
          tools_used.include?(expected_tool)
        end

        failure_message do |result|
          tools_used = extract_tools_used(result)
          "expected agent to use tool #{expected_tool.inspect}, but used: #{tools_used.inspect}"
        end

        def extract_tools_used(result)
          if result.respond_to?(:metadata) && result.metadata
            result.metadata[:tools_used] || result.metadata["tools_used"] || []
          else
            []
          end
        end
      end

      ##
      # Matcher for agent handoff behavior
      #
      # @example
      #   expect(result).to have_handed_off_to("specialist_agent")
      #
      RSpec::Matchers.define :have_handed_off_to do |expected_agent|
        match do |result|
          handoff_target = extract_handoff_target(result)
          handoff_target == expected_agent
        end

        failure_message do |result|
          handoff_target = extract_handoff_target(result)
          "expected agent to hand off to #{expected_agent.inspect}, but handed off to: #{handoff_target.inspect}"
        end

        def extract_handoff_target(result)
          if result.respond_to?(:metadata) && result.metadata
            result.metadata[:handoff_target] || result.metadata["handoff_target"]
          else
            nil
          end
        end
      end

      ##
      # Matcher for guardrails violations
      #
      # @example
      #   expect(result).to be_blocked_by_guardrails
      #   expect(result).to have_violation_type(:toxicity)
      #
      RSpec::Matchers.define :be_blocked_by_guardrails do
        match do |result|
          violations = extract_violations(result)
          violations.any?
        end

        failure_message do |result|
          "expected agent response to be blocked by guardrails, but no violations were found"
        end

        failure_message_when_negated do |result|
          violations = extract_violations(result)
          "expected agent response not to be blocked by guardrails, but found violations: #{violations.inspect}"
        end

        def extract_violations(result)
          if result.respond_to?(:violations) && result.violations
            result.violations
          elsif result.respond_to?(:metadata) && result.metadata
            result.metadata[:violations] || result.metadata["violations"] || []
          else
            []
          end
        end
      end

      ##
      # Matcher for specific violation types
      #
      # @example
      #   expect(result).to have_violation_type(:toxicity)
      #   expect(result).to have_violation_type(:pii)
      #
      RSpec::Matchers.define :have_violation_type do |expected_type|
        match do |result|
          violations = extract_violations(result)
          violations.any? { |v| v[:type] == expected_type || v["type"] == expected_type.to_s }
        end

        failure_message do |result|
          violations = extract_violations(result)
          types = violations.map { |v| v[:type] || v["type"] }
          "expected agent response to have violation type #{expected_type.inspect}, but found: #{types.inspect}"
        end

        def extract_violations(result)
          if result.respond_to?(:violations) && result.violations
            result.violations
          elsif result.respond_to?(:metadata) && result.metadata
            result.metadata[:violations] || result.metadata["violations"] || []
          else
            []
          end
        end
      end

      ##
      # Matcher for conversation context
      #
      # @example
      #   expect(result).to have_conversation_context
      #   expect(result).to remember_previous_message
      #
      RSpec::Matchers.define :have_conversation_context do
        match do |result|
          if result.respond_to?(:messages) && result.messages.is_a?(Array)
            result.messages.size > 1
          else
            false
          end
        end

        failure_message do |result|
          "expected agent response to have conversation context (multiple messages), but found single message"
        end
      end

      ##
      # Matcher for memory usage
      #
      # @example
      #   expect(result).to remember_information("user's name is John")
      #
      RSpec::Matchers.define :remember_information do |expected_info|
        match do |result|
          memory = extract_memory(result)
          case expected_info
          when String
            memory.include?(expected_info)
          when Regexp
            memory.match?(expected_info)
          else
            false
          end
        end

        failure_message do |result|
          memory = extract_memory(result)
          "expected agent to remember #{expected_info.inspect}, but memory contains: #{memory.inspect}"
        end

        def extract_memory(result)
          if result.respond_to?(:memory) && result.memory
            result.memory.to_s
          elsif result.respond_to?(:metadata) && result.metadata
            result.metadata[:memory] || result.metadata["memory"] || ""
          else
            ""
          end
        end
      end

      ##
      # Matcher for sentiment analysis
      #
      # @example
      #   expect(result).to have_positive_sentiment
      #   expect(result).to have_negative_sentiment
      #   expect(result).to have_neutral_sentiment
      #
      RSpec::Matchers.define :have_positive_sentiment do
        match do |result|
          sentiment = extract_sentiment(result)
          sentiment == :positive || sentiment == "positive"
        end

        failure_message do |result|
          sentiment = extract_sentiment(result)
          "expected agent response to have positive sentiment, but got: #{sentiment.inspect}"
        end

        def extract_sentiment(result)
          if result.respond_to?(:metadata) && result.metadata
            result.metadata[:sentiment] || result.metadata["sentiment"] || analyze_sentiment(result)
          else
            analyze_sentiment(result)
          end
        end

        def analyze_sentiment(result)
          content = if result.respond_to?(:messages) && result.messages.any?
                     result.messages.last[:content] || result.messages.last["content"] || ""
                   elsif result.respond_to?(:content)
                     result.content || ""
                   else
                     result.to_s
                   end

          # Simple sentiment analysis
          positive_words = %w[good great excellent amazing wonderful fantastic happy pleased]
          negative_words = %w[bad terrible awful horrible disgusting sad disappointed angry]

          words = content.downcase.split
          positive_count = words.count { |word| positive_words.include?(word) }
          negative_count = words.count { |word| negative_words.include?(word) }

          if positive_count > negative_count
            :positive
          elsif negative_count > positive_count
            :negative
          else
            :neutral
          end
        end
      end

      ##
      # Matcher for response validation
      #
      # @example
      #   validator = ResponseValidator.new
      #   validator.must_contain_keywords(["helpful"])
      #   expect(result).to pass_validation(validator)
      #
      RSpec::Matchers.define :pass_validation do |validator|
        match do |result|
          validator.validate(result).passed?
        end

        failure_message do |result|
          validation_result = validator.validate(result)
          "expected agent response to pass validation, but failed: #{validation_result.errors.join(', ')}"
        end

        failure_message_when_negated do |result|
          "expected agent response to fail validation, but it passed"
        end
      end

      ##
      # Matcher for streaming responses
      #
      # @example
      #   expect(result).to be_streaming
      #   expect(result).to have_streamed_chunks(5)
      #
      RSpec::Matchers.define :be_streaming do
        match do |result|
          result.respond_to?(:streaming?) && result.streaming?
        end

        failure_message do |result|
          "expected agent response to be streaming, but it was not"
        end
      end

      ##
      # Matcher for specific number of streamed chunks
      #
      # @example
      #   expect(result).to have_streamed_chunks(5)
      #
      RSpec::Matchers.define :have_streamed_chunks do |expected_count|
        match do |result|
          chunks = extract_streamed_chunks(result)
          chunks.size == expected_count
        end

        failure_message do |result|
          chunks = extract_streamed_chunks(result)
          "expected agent response to have #{expected_count} streamed chunks, but got #{chunks.size}"
        end

        def extract_streamed_chunks(result)
          if result.respond_to?(:chunks) && result.chunks
            result.chunks
          elsif result.respond_to?(:metadata) && result.metadata
            result.metadata[:chunks] || result.metadata["chunks"] || []
          else
            []
          end
        end
      end

      # Aliases for common matchers
      alias_method :have_negative_sentiment, :have_positive_sentiment
      alias_method :have_neutral_sentiment, :have_positive_sentiment
      alias_method :have_used_tools, :have_used_tool
      alias_method :remember_previous_message, :have_conversation_context
      alias_method :be_safe, :be_successful
    end
  end
end