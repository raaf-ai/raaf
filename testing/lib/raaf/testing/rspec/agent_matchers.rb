# frozen_string_literal: true

module RAAF
  module Testing
    module RSpec
      ##
      # RSpec matchers for testing RAAF agents
      #
      # This module provides matchers specifically designed for testing
      # agent behavior, responses, and execution patterns.
      #
      module AgentMatchers
        ##
        # Match agents that respond with specific content patterns
        #
        # @param pattern [String, Regexp] Pattern to match against response content
        #
        # @example
        #   expect(result).to have_response_containing("weather")
        #   expect(result).to have_response_containing(/temperature.*\d+/)
        #
        ::RSpec::Matchers.define :have_response_containing do |pattern|
          match do |result|
            content = extract_response_content(result)
            return false unless content
            
            if pattern.is_a?(Regexp)
              content =~ pattern
            else
              content.include?(pattern.to_s)
            end
          end
          
          failure_message do |result|
            content = extract_response_content(result)
            "Expected response to contain #{pattern.inspect}, but got: #{content.inspect}"
          end
          
          def extract_response_content(result)
            if result.respond_to?(:messages) && result.messages&.last
              result.messages.last[:content]
            elsif result.respond_to?(:content)
              result.content
            elsif result.is_a?(Hash) && result[:content]
              result[:content]
            elsif result.is_a?(String)
              result
            else
              nil
            end
          end
        end

        ##
        # Match agents that complete within expected time
        #
        # @param max_duration [Numeric] Maximum duration in seconds
        #
        # @example
        #   expect { agent.run("test") }.to complete_within(5.0)
        #
        ::RSpec::Matchers.define :complete_within do |max_duration|
          supports_block_expectations
          
          match do |block|
            start_time = Time.now
            begin
              @result = block.call
              @actual_duration = Time.now - start_time
              @actual_duration <= max_duration
            rescue => e
              @error = e
              false
            end
          end
          
          failure_message do
            if @error
              "Expected block to complete within #{max_duration}s, but raised error: #{@error.message}"
            else
              "Expected block to complete within #{max_duration}s, but took #{@actual_duration}s"
            end
          end
        end

        ##
        # Match agents that handle errors gracefully
        #
        # @param error_type [Class, String] Expected error type or message pattern
        #
        # @example
        #   expect(result).to handle_error_gracefully
        #   expect(result).to handle_error_gracefully(ArgumentError)
        #
        ::RSpec::Matchers.define :handle_error_gracefully do |error_type = nil|
          match do |result|
            # Check if result indicates error handling
            if result.respond_to?(:success?)
              return false if result.success?
            elsif result.respond_to?(:success)
              return false if result.success == true
            elsif result.is_a?(Hash)
              return false if result[:success] == true
            end
            
            # Check for error information
            has_error_info = result.respond_to?(:error) && result.error ||
                           result.respond_to?(:errors) && result.errors ||
                           (result.is_a?(Hash) && (result[:error] || result[:errors]))
                           
            return false unless has_error_info
            
            # If specific error type specified, check it
            if error_type
              actual_error = result.respond_to?(:error) ? result.error : 
                           result.is_a?(Hash) ? result[:error] : nil
                           
              if error_type.is_a?(Class)
                actual_error.is_a?(error_type)
              else
                actual_error.to_s.include?(error_type.to_s)
              end
            else
              true
            end
          end
          
          failure_message do |result|
            if error_type
              "Expected result to handle #{error_type} gracefully, but didn't match error pattern"
            else
              "Expected result to handle error gracefully, but no error information found"
            end
          end
        end

        ##
        # Match agent results with specific metadata
        #
        # @param expected_metadata [Hash] Expected metadata key-value pairs
        #
        # @example
        #   expect(result).to have_metadata(model: "gpt-4o", tokens: 150)
        #
        ::RSpec::Matchers.define :have_metadata do |expected_metadata|
          match do |result|
            metadata = extract_metadata(result)
            return false unless metadata
            
            expected_metadata.all? do |key, expected_value|
              metadata[key] == expected_value
            end
          end
          
          failure_message do |result|
            metadata = extract_metadata(result)
            "Expected result to have metadata #{expected_metadata.inspect}, " \
            "but got #{metadata.inspect}"
          end
          
          def extract_metadata(result)
            if result.respond_to?(:metadata)
              result.metadata
            elsif result.respond_to?(:usage)
              result.usage
            elsif result.is_a?(Hash) && result[:metadata]
              result[:metadata]
            elsif result.is_a?(Hash) && result[:usage]
              result[:usage]
            else
              {}
            end
          end
        end

        ##
        # Match conversation results with expected turn count
        #
        # @param expected_turns [Integer] Expected number of conversation turns
        #
        # @example
        #   expect(result).to have_conversation_turns(3)
        #
        ::RSpec::Matchers.define :have_conversation_turns do |expected_turns|
          match do |result|
            turns = count_conversation_turns(result)
            turns == expected_turns
          end
          
          failure_message do |result|
            turns = count_conversation_turns(result)
            "Expected #{expected_turns} conversation turns, but got #{turns}"
          end
          
          def count_conversation_turns(result)
            if result.respond_to?(:messages)
              result.messages&.count { |msg| msg[:role] == "assistant" } || 0
            elsif result.respond_to?(:turns)
              result.turns
            elsif result.is_a?(Hash) && result[:messages]
              result[:messages].count { |msg| msg[:role] == "assistant" }
            else
              0
            end
          end
        end

        ##
        # Match results indicating agent handoff occurred
        #
        # @param from_agent [String] Expected source agent name
        # @param to_agent [String] Expected target agent name
        #
        # @example
        #   expect(result).to have_agent_handoff(from: "Researcher", to: "Writer")
        #
        ::RSpec::Matchers.define :have_agent_handoff do |from: nil, to: nil|
          match do |result|
            handoff_info = extract_handoff_info(result)
            return false unless handoff_info
            
            matches_from = from.nil? || handoff_info[:from] == from
            matches_to = to.nil? || handoff_info[:to] == to
            
            matches_from && matches_to
          end
          
          failure_message do |result|
            handoff_info = extract_handoff_info(result)
            expected = { from: from, to: to }.compact
            "Expected agent handoff #{expected.inspect}, but got #{handoff_info.inspect}"
          end
          
          def extract_handoff_info(result)
            if result.respond_to?(:handoff_info)
              result.handoff_info
            elsif result.respond_to?(:agent_transitions)
              result.agent_transitions&.last
            elsif result.is_a?(Hash) && result[:handoff]
              result[:handoff]
            else
              # Try to detect handoff from messages or tool calls
              detect_handoff_from_messages(result)
            end
          end
          
          def detect_handoff_from_messages(result)
            return nil unless result.respond_to?(:messages) && result.messages
            
            # Look for transfer tool calls
            result.messages.each do |message|
              next unless message[:tool_calls]
              
              message[:tool_calls].each do |tool_call|
                function_name = tool_call.dig(:function, :name)
                if function_name&.start_with?("transfer_to_")
                  target_agent = function_name.sub("transfer_to_", "")
                  return { from: nil, to: target_agent }
                end
              end
            end
            
            nil
          end
        end

        ##
        # Match results with final agent being specific agent
        #
        # @param agent_name [String] Expected final agent name
        #
        # @example
        #   expect(result).to have_final_agent("Writer")
        #
        ::RSpec::Matchers.define :have_final_agent do |agent_name|
          match do |result|
            final_agent = extract_final_agent(result)
            final_agent == agent_name
          end
          
          failure_message do |result|
            final_agent = extract_final_agent(result)
            "Expected final agent to be #{agent_name.inspect}, but was #{final_agent.inspect}"
          end
          
          def extract_final_agent(result)
            if result.respond_to?(:last_agent)
              result.last_agent&.name
            elsif result.respond_to?(:final_agent)
              result.final_agent
            elsif result.is_a?(Hash) && result[:final_agent]
              result[:final_agent]
            else
              nil
            end
          end
        end

        ##
        # Match results that include specific tool results
        #
        # @param expected_results [Hash, Array] Expected tool result content
        #
        # @example
        #   expect(result).to have_tool_results_containing("weather data")
        #   expect(result).to have_tool_results_containing([4, 8, 12])
        #
        ::RSpec::Matchers.define :have_tool_results_containing do |expected_content|
          match do |result|
            tool_results = extract_tool_results(result)
            return false if tool_results.empty?
            
            if expected_content.is_a?(Array)
              tool_results.any? { |result| expected_content.all? { |item| result.include?(item) } }
            else
              tool_results.any? { |result| result.to_s.include?(expected_content.to_s) }
            end
          end
          
          failure_message do |result|
            tool_results = extract_tool_results(result)
            "Expected tool results to contain #{expected_content.inspect}, " \
            "but got #{tool_results.inspect}"
          end
          
          def extract_tool_results(result)
            if result.respond_to?(:tool_results)
              result.tool_results || []
            elsif result.respond_to?(:messages) && result.messages
              tool_results = []
              result.messages.each do |message|
                if message[:tool_calls]
                  message[:tool_calls].each do |tool_call|
                    tool_results << tool_call[:result] if tool_call[:result]
                  end
                end
              end
              tool_results
            else
              []
            end
          end
        end
      end
    end
  end
end