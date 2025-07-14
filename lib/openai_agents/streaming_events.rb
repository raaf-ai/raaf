# frozen_string_literal: true

require "json"

module OpenAIAgents
  ##
  # StreamingEvents module for real-time response processing
  #
  # This module provides event classes and handlers for processing streaming
  # responses from the OpenAI API, matching the Python implementation exactly.
  # It supports incremental content delivery, function calls, and comprehensive
  # event sequencing.
  #
  # @example Basic streaming usage
  #   ChatCompletionStreamHandler.handle_stream(response, stream) do |event|
  #     case event
  #     when ResponseCreatedEvent
  #       puts "Stream started"
  #     when ResponseTextDeltaEvent
  #       print event.delta
  #     when ResponseCompletedEvent
  #       puts "\nStream completed"
  #     end
  #   end
  #
  # @example Event sequence for text response
  #   1. ResponseCreatedEvent - Stream initialization
  #   2. ResponseOutputItemAddedEvent - New output item
  #   3. ResponseContentPartAddedEvent - Content part started
  #   4. ResponseTextDeltaEvent(s) - Incremental text chunks
  #   5. ResponseContentPartDoneEvent - Content part completed
  #   6. ResponseOutputItemDoneEvent - Output item completed
  #   7. ResponseCompletedEvent - Stream finished
  #
  # @see https://platform.openai.com/docs/api-reference/responses OpenAI Responses API
  #
  module StreamingEvents
    ##
    # Event fired when a streaming response is created
    #
    # Marks the beginning of a streaming response session and provides
    # the initial response metadata.
    #
    class ResponseCreatedEvent
      attr_reader :response, :type, :sequence_number

      def initialize(response:, sequence_number:)
        @response = response
        @type = "response.created"
        @sequence_number = sequence_number
      end

      def to_h
        {
          response: @response,
          type: @type,
          sequence_number: @sequence_number
        }
      end
    end

    class ResponseOutputItemAddedEvent
      attr_reader :item, :output_index, :type, :sequence_number

      def initialize(item:, output_index:, sequence_number:)
        @item = item
        @output_index = output_index
        @type = "response.output_item.added"
        @sequence_number = sequence_number
      end

      def to_h
        {
          item: @item,
          output_index: @output_index,
          type: @type,
          sequence_number: @sequence_number
        }
      end
    end

    class ResponseOutputItemDoneEvent
      attr_reader :item, :output_index, :type, :sequence_number

      def initialize(item:, output_index:, sequence_number:)
        @item = item
        @output_index = output_index
        @type = "response.output_item.done"
        @sequence_number = sequence_number
      end

      def to_h
        {
          item: @item,
          output_index: @output_index,
          type: @type,
          sequence_number: @sequence_number
        }
      end
    end

    class ResponseContentPartAddedEvent
      attr_reader :content_index, :item_id, :output_index, :part, :type, :sequence_number

      def initialize(content_index:, item_id:, output_index:, part:, sequence_number:)
        @content_index = content_index
        @item_id = item_id
        @output_index = output_index
        @part = part
        @type = "response.content_part.added"
        @sequence_number = sequence_number
      end

      def to_h
        {
          content_index: @content_index,
          item_id: @item_id,
          output_index: @output_index,
          part: @part,
          type: @type,
          sequence_number: @sequence_number
        }
      end
    end

    class ResponseContentPartDoneEvent
      attr_reader :content_index, :item_id, :output_index, :part, :type, :sequence_number

      def initialize(content_index:, item_id:, output_index:, part:, sequence_number:)
        @content_index = content_index
        @item_id = item_id
        @output_index = output_index
        @part = part
        @type = "response.content_part.done"
        @sequence_number = sequence_number
      end

      def to_h
        {
          content_index: @content_index,
          item_id: @item_id,
          output_index: @output_index,
          part: @part,
          type: @type,
          sequence_number: @sequence_number
        }
      end
    end

    class ResponseTextDeltaEvent
      attr_reader :content_index, :delta, :item_id, :output_index, :type, :sequence_number

      def initialize(content_index:, delta:, item_id:, output_index:, sequence_number:)
        @content_index = content_index
        @delta = delta
        @item_id = item_id
        @output_index = output_index
        @type = "response.output_text.delta"
        @sequence_number = sequence_number
      end

      def to_h
        {
          content_index: @content_index,
          delta: @delta,
          item_id: @item_id,
          output_index: @output_index,
          type: @type,
          sequence_number: @sequence_number
        }
      end
    end

    class ResponseRefusalDeltaEvent
      attr_reader :content_index, :delta, :item_id, :output_index, :type, :sequence_number

      def initialize(content_index:, delta:, item_id:, output_index:, sequence_number:)
        @content_index = content_index
        @delta = delta
        @item_id = item_id
        @output_index = output_index
        @type = "response.refusal.delta"
        @sequence_number = sequence_number
      end

      def to_h
        {
          content_index: @content_index,
          delta: @delta,
          item_id: @item_id,
          output_index: @output_index,
          type: @type,
          sequence_number: @sequence_number
        }
      end
    end

    class ResponseFunctionCallArgumentsDeltaEvent
      attr_reader :delta, :item_id, :output_index, :type, :sequence_number

      def initialize(delta:, item_id:, output_index:, sequence_number:)
        @delta = delta
        @item_id = item_id
        @output_index = output_index
        @type = "response.function_call_arguments.delta"
        @sequence_number = sequence_number
      end

      def to_h
        {
          delta: @delta,
          item_id: @item_id,
          output_index: @output_index,
          type: @type,
          sequence_number: @sequence_number
        }
      end
    end

    class ResponseCompletedEvent
      attr_reader :response, :type, :sequence_number

      def initialize(response:, sequence_number:)
        @response = response
        @type = "response.completed"
        @sequence_number = sequence_number
      end

      def to_h
        {
          response: @response,
          type: @type,
          sequence_number: @sequence_number
        }
      end
    end

    ##
    # Streaming state management
    #
    # Tracks the state of a streaming response including content parts,
    # function calls, and refusals. Used internally by the stream handler
    # to maintain consistency across events.
    #
    class StreamingState
      attr_accessor :started, :text_content_index_and_output, :refusal_content_index_and_output, :function_calls

      def initialize
        @started = false
        @text_content_index_and_output = nil
        @refusal_content_index_and_output = nil
        @function_calls = {}
      end
    end

    ##
    # Sequence number generator
    #
    # Provides sequential numbering for streaming events to ensure
    # proper ordering and allow clients to detect missing events.
    #
    class SequenceNumber
      def initialize
        @sequence_number = 0
      end

      def get_and_increment
        num = @sequence_number
        @sequence_number += 1
        num
      end
    end

    ##
    # Stream handler for chat completion chunks
    #
    # Converts OpenAI Chat Completions streaming responses into
    # structured events that match the Responses API format.
    # Handles text content, function calls, and refusals.
    #
    # @example Processing a stream
    #   response = { id: "resp_123", model: "gpt-4o" }
    #   ChatCompletionStreamHandler.handle_stream(response, stream) do |event|
    #     case event.type
    #     when "response.created"
    #       setup_ui_for_response(event.response)
    #     when "response.output_text.delta"
    #       append_text_to_ui(event.delta)
    #     when "response.completed"
    #       finalize_response(event.response)
    #     end
    #   end
    #
    class ChatCompletionStreamHandler
      FAKE_RESPONSES_ID = "fake-responses-id"

      def self.handle_stream(response, stream, &)
        usage = nil
        state = StreamingState.new
        sequence_number = SequenceNumber.new

        stream.each do |chunk|
          unless state.started
            state.started = true
            yield ResponseCreatedEvent.new(
              response: response,
              sequence_number: sequence_number.get_and_increment
            )
          end

          # Handle usage if present
          usage = chunk["usage"] if chunk["usage"]

          next unless chunk["choices"] && chunk["choices"][0] && chunk["choices"][0]["delta"]

          delta = chunk["choices"][0]["delta"]

          # Handle text content
          if delta["content"]
            unless state.text_content_index_and_output
              # Initialize text content tracking
              state.text_content_index_and_output = [
                state.refusal_content_index_and_output ? 1 : 0,
                {
                  "text" => "",
                  "type" => "output_text",
                  "annotations" => []
                }
              ]

              # Start new assistant message
              assistant_item = {
                "id" => FAKE_RESPONSES_ID,
                "content" => [],
                "role" => "assistant",
                "type" => "message",
                "status" => "in_progress"
              }

              # Notify start of new output message
              yield ResponseOutputItemAddedEvent.new(
                item: assistant_item,
                output_index: 0,
                sequence_number: sequence_number.get_and_increment
              )

              yield ResponseContentPartAddedEvent.new(
                content_index: state.text_content_index_and_output[0],
                item_id: FAKE_RESPONSES_ID,
                output_index: 0,
                part: {
                  "text" => "",
                  "type" => "output_text",
                  "annotations" => []
                },
                sequence_number: sequence_number.get_and_increment
              )
            end

            # Emit text delta
            yield ResponseTextDeltaEvent.new(
              content_index: state.text_content_index_and_output[0],
              delta: delta["content"],
              item_id: FAKE_RESPONSES_ID,
              output_index: 0,
              sequence_number: sequence_number.get_and_increment
            )

            # Accumulate text
            state.text_content_index_and_output[1]["text"] += delta["content"]
          end

          # Handle refusals
          if delta["refusal"]
            unless state.refusal_content_index_and_output
              # Initialize refusal tracking
              state.refusal_content_index_and_output = [
                state.text_content_index_and_output ? 1 : 0,
                {
                  "refusal" => "",
                  "type" => "refusal"
                }
              ]

              # Start new assistant message if needed
              assistant_item = {
                "id" => FAKE_RESPONSES_ID,
                "content" => [],
                "role" => "assistant",
                "type" => "message",
                "status" => "in_progress"
              }

              yield ResponseOutputItemAddedEvent.new(
                item: assistant_item,
                output_index: 0,
                sequence_number: sequence_number.get_and_increment
              )

              yield ResponseContentPartAddedEvent.new(
                content_index: state.refusal_content_index_and_output[0],
                item_id: FAKE_RESPONSES_ID,
                output_index: 0,
                part: {
                  "text" => "",
                  "type" => "output_text",
                  "annotations" => []
                },
                sequence_number: sequence_number.get_and_increment
              )
            end

            # Emit refusal delta
            yield ResponseRefusalDeltaEvent.new(
              content_index: state.refusal_content_index_and_output[0],
              delta: delta["refusal"],
              item_id: FAKE_RESPONSES_ID,
              output_index: 0,
              sequence_number: sequence_number.get_and_increment
            )

            # Accumulate refusal
            state.refusal_content_index_and_output[1]["refusal"] += delta["refusal"]
          end

          # Handle tool calls
          next unless delta["tool_calls"]

          delta["tool_calls"].each do |tc_delta|
            index = tc_delta["index"]
            state.function_calls[index] ||= {
              "id" => FAKE_RESPONSES_ID,
              "arguments" => "",
              "name" => "",
              "type" => "function_call",
              "call_id" => ""
            }

            if tc_delta["function"]
              state.function_calls[index]["arguments"] += tc_delta["function"]["arguments"] || ""
              state.function_calls[index]["name"] += tc_delta["function"]["name"] || ""
            end
            state.function_calls[index]["call_id"] += tc_delta["id"] || ""
          end
        end

        # Send end events for content parts
        function_call_starting_index = 0

        if state.text_content_index_and_output
          function_call_starting_index += 1
          yield ResponseContentPartDoneEvent.new(
            content_index: state.text_content_index_and_output[0],
            item_id: FAKE_RESPONSES_ID,
            output_index: 0,
            part: state.text_content_index_and_output[1],
            sequence_number: sequence_number.get_and_increment
          )
        end

        if state.refusal_content_index_and_output
          function_call_starting_index += 1
          yield ResponseContentPartDoneEvent.new(
            content_index: state.refusal_content_index_and_output[0],
            item_id: FAKE_RESPONSES_ID,
            output_index: 0,
            part: state.refusal_content_index_and_output[1],
            sequence_number: sequence_number.get_and_increment
          )
        end

        # Send events for function calls
        state.function_calls.each_value do |function_call|
          # Output item added for function call
          yield ResponseOutputItemAddedEvent.new(
            item: {
              "id" => FAKE_RESPONSES_ID,
              "call_id" => function_call["call_id"],
              "arguments" => function_call["arguments"],
              "name" => function_call["name"],
              "type" => "function_call"
            },
            output_index: function_call_starting_index,
            sequence_number: sequence_number.get_and_increment
          )

          # Arguments delta
          yield ResponseFunctionCallArgumentsDeltaEvent.new(
            delta: function_call["arguments"],
            item_id: FAKE_RESPONSES_ID,
            output_index: function_call_starting_index,
            sequence_number: sequence_number.get_and_increment
          )

          # Output item done
          yield ResponseOutputItemDoneEvent.new(
            item: {
              "id" => FAKE_RESPONSES_ID,
              "call_id" => function_call["call_id"],
              "arguments" => function_call["arguments"],
              "name" => function_call["name"],
              "type" => "function_call"
            },
            output_index: function_call_starting_index,
            sequence_number: sequence_number.get_and_increment
          )

          function_call_starting_index += 1
        end

        # Build final response
        outputs = []

        if state.text_content_index_and_output || state.refusal_content_index_and_output
          assistant_msg = {
            "id" => FAKE_RESPONSES_ID,
            "content" => [],
            "role" => "assistant",
            "type" => "message",
            "status" => "completed"
          }

          assistant_msg["content"] << state.text_content_index_and_output[1] if state.text_content_index_and_output

          if state.refusal_content_index_and_output
            assistant_msg["content"] << state.refusal_content_index_and_output[1]
          end

          outputs << assistant_msg

          # Send output item done for assistant message
          yield ResponseOutputItemDoneEvent.new(
            item: assistant_msg,
            output_index: 0,
            sequence_number: sequence_number.get_and_increment
          )
        end

        state.function_calls.each_value do |function_call|
          outputs << function_call
        end

        # Create final response
        final_response = response.dup
        final_response["output"] = outputs

        if usage
          final_response["usage"] = {
            "input_tokens" => usage["prompt_tokens"],
            "output_tokens" => usage["completion_tokens"],
            "total_tokens" => usage["total_tokens"],
            "output_tokens_details" => {
              "reasoning_tokens" => usage.dig("completion_tokens_details", "reasoning_tokens") || 0
            },
            "input_tokens_details" => {
              "cached_tokens" => usage.dig("prompt_tokens_details", "cached_tokens") || 0
            }
          }
        end

        # Send completed event
        yield ResponseCompletedEvent.new(
          response: final_response,
          sequence_number: sequence_number.get_and_increment
        )
      end
    end
  end
end
