# frozen_string_literal: true

require "json"
require "time"

module RAAF

  ##
  # Base result class for all agent operations
  #
  # Provides a standardized way to represent operation results throughout
  # the RAAF system, including success/failure status, data payload,
  # error information, and metadata.
  #
  # @example Creating a successful result
  #   result = Result.success({ message: "Hello" }, metadata: { duration: 1.5 })
  #   result.success? # => true
  #   result.data     # => { message: "Hello" }
  #
  # @example Creating a failure result
  #   result = Result.failure("Something went wrong", metadata: { attempt: 1 })
  #   result.failure? # => true
  #   result.error    # => "Something went wrong"
  #
  # @example Serializing results
  #   result.to_h     # => Hash representation
  #   result.to_json  # => JSON string
  #
  class Result

    # @return [Boolean] Whether the operation was successful
    attr_reader :success

    # @return [Object, nil] The result data payload
    attr_reader :data

    # @return [String, Exception, nil] Error information if operation failed
    attr_reader :error

    # @return [Hash] Additional metadata about the operation
    attr_reader :metadata

    # @return [Time] When the result was created
    attr_reader :timestamp

    ##
    # Initialize a new result
    #
    # @param success [Boolean] Whether the operation succeeded
    # @param data [Object, nil] The result data
    # @param error [String, Exception, nil] Error information
    # @param metadata [Hash] Additional metadata
    #
    def initialize(success:, data: nil, error: nil, metadata: {})
      @success = success
      @data = data
      @error = error
      @metadata = metadata.dup
      @timestamp = Time.now.utc
    end

    ##
    # Check if the operation was successful
    #
    # @return [Boolean] true if successful
    #
    def success?
      @success
    end

    ##
    # Check if the operation failed
    #
    # @return [Boolean] true if failed
    #
    def failure?
      !@success
    end

    ##
    # Check if the operation failed with an error
    #
    # @return [Boolean] true if failed and has error information
    #
    def error?
      !@success && @error
    end

    ##
    # Convert result to hash representation
    #
    # @return [Hash] Hash containing all result data
    #
    def to_h
      {
        success: @success,
        data: @data,
        error: @error,
        metadata: @metadata,
        timestamp: @timestamp.iso8601
      }
    end

    ##
    # Convert result to JSON string
    #
    # @param args [Array] JSON generation options
    # @return [String] JSON representation
    #
    def to_json(*)
      JSON.generate(to_h, *)
    end

    ##
    # Create a successful result
    #
    # @param data [Object, nil] The success data
    # @param metadata [Hash] Additional metadata
    # @return [Result] New successful result
    #
    def self.success(data = nil, metadata: {})
      new(success: true, data: data, metadata: metadata)
    end

    ##
    # Create a failure result
    #
    # @param error [String, Exception] The error information
    # @param metadata [Hash] Additional metadata
    # @return [Result] New failure result
    #
    def self.failure(error, metadata: {})
      new(success: false, error: error, metadata: metadata)
    end

  end

  ##
  # Agent execution result
  #
  # Specialized result class for agent conversation executions, containing
  # conversation history, turn count, handoff information, and tool usage.
  #
  # @example Creating a successful agent result
  #   result = AgentResult.success(
  #     agent_name: "Assistant",
  #     messages: [
  #       { role: "user", content: "Hello" },
  #       { role: "assistant", content: "Hi there!" }
  #     ],
  #     turns: 1,
  #     tool_calls: ["search_web"]
  #   )
  #
  # @example Analyzing conversation statistics
  #   result.conversation_length # => 2
  #   result.total_tool_calls    # => 1
  #   result.assistant_messages  # => messages from assistant
  #
  class AgentResult < Result

    # @return [String] Name of the agent that produced this result
    attr_reader :agent_name

    # @return [Array<Hash>] Complete conversation message history
    attr_reader :messages

    # @return [Integer] Number of conversation turns executed
    attr_reader :turns

    # @return [Array<Hash>] Record of agent handoffs that occurred
    attr_reader :handoffs

    # @return [Array<String>] List of tools that were called
    attr_reader :tool_calls

    ##
    # Initialize agent result
    #
    # @param success [Boolean] Whether the agent execution succeeded
    # @param agent_name [String] Name of the executing agent
    # @param messages [Array<Hash>] Conversation messages
    # @param turns [Integer] Number of turns executed
    # @param handoffs [Array<Hash>] Handoff records
    # @param tool_calls [Array<String>] Tools that were called
    # @param kwargs [Hash] Additional arguments passed to parent
    #
    def initialize(success:, agent_name:, messages: [], turns: 0, handoffs: [], tool_calls: [], **)
      @agent_name = agent_name
      @messages = messages.dup
      @turns = turns
      @handoffs = handoffs.dup
      @tool_calls = tool_calls.dup
      super(success: success, **)
    end

    ##
    # Get the final message in the conversation
    #
    # @return [Hash, nil] The last message or nil if no messages
    #
    def final_message
      @messages.last
    end

    ##
    # Get all assistant messages from the conversation
    #
    # @return [Array<Hash>] Messages where role is "assistant"
    #
    def assistant_messages
      @messages.select { |msg| msg[:role] == "assistant" }
    end

    ##
    # Get all user messages from the conversation
    #
    # @return [Array<Hash>] Messages where role is "user"
    #
    def user_messages
      @messages.select { |msg| msg[:role] == "user" }
    end

    ##
    # Get all tool result messages from the conversation
    #
    # @return [Array<Hash>] Messages where role is "tool"
    #
    def tool_messages
      @messages.select { |msg| msg[:role] == "tool" }
    end

    ##
    # Get the total number of messages in the conversation
    #
    # @return [Integer] Total message count
    #
    def conversation_length
      @messages.length
    end

    ##
    # Get the total number of handoffs that occurred
    #
    # @return [Integer] Total handoff count
    #
    def total_handoffs
      @handoffs.length
    end

    ##
    # Get the total number of tool calls made
    #
    # @return [Integer] Total tool call count
    #
    def total_tool_calls
      @tool_calls.length
    end

    def to_h
      super.merge({
                    agent_name: @agent_name,
                    messages: @messages,
                    turns: @turns,
                    handoffs: @handoffs,
                    tool_calls: @tool_calls,
                    stats: {
                      conversation_length: conversation_length,
                      total_handoffs: total_handoffs,
                      total_tool_calls: total_tool_calls
                    }
                  })
    end

    def self.success(agent_name:, **)
      new(success: true, agent_name: agent_name, **)
    end

    def self.failure(agent_name:, error:, **)
      new(success: false, agent_name: agent_name, error: error, **)
    end

  end

  ##
  # Tool execution result
  #
  # Specialized result class for tool function executions, including
  # timing information, input arguments, and execution outcomes.
  #
  # @example Creating a successful tool result
  #   result = ToolResult.success(
  #     tool_name: "search_web",
  #     data: "Search results found",
  #     input_args: { query: "Ruby programming" },
  #     execution_time: 0.25
  #   )
  #
  # @example Handling tool failures
  #   result = ToolResult.failure(
  #     tool_name: "broken_tool",
  #     error: "Network timeout",
  #     input_args: { url: "http://example.com" }
  #   )
  #
  class ToolResult < Result

    # @return [String] Name of the tool that was executed
    attr_reader :tool_name

    # @return [Hash] Arguments that were passed to the tool
    attr_reader :input_args

    # @return [Float, nil] Execution time in seconds
    attr_reader :execution_time

    ##
    # Initialize tool result
    #
    # @param success [Boolean] Whether the tool execution succeeded
    # @param tool_name [String] Name of the executed tool
    # @param input_args [Hash] Arguments passed to the tool
    # @param execution_time [Float, nil] Execution time in seconds
    # @param kwargs [Hash] Additional arguments passed to parent
    #
    def initialize(success:, tool_name:, input_args: {}, execution_time: nil, **)
      @tool_name = tool_name
      @input_args = input_args.dup
      @execution_time = execution_time
      super(success: success, **)
    end

    ##
    # Get execution time in milliseconds
    #
    # @return [Float, nil] Execution time in milliseconds, or nil if not recorded
    #
    def execution_time_ms
      return nil unless @execution_time

      (@execution_time * 1000).round(2)
    end

    def to_h
      super.merge({
                    tool_name: @tool_name,
                    input_args: @input_args,
                    execution_time_ms: execution_time_ms
                  })
    end

    def self.success(tool_name:, data: nil, **)
      new(success: true, tool_name: tool_name, data: data, **)
    end

    def self.failure(tool_name:, error:, **)
      new(success: false, tool_name: tool_name, error: error, **)
    end

  end

  ##
  # Streaming result for real-time responses
  #
  # Handles incremental content delivery for streaming API responses,
  # allowing real-time updates as content is generated.
  #
  # @example Building a streaming result
  #   result = StreamingResult.new
  #   result.add_chunk("Hello")
  #   result.add_chunk(" world")
  #   result.complete!
  #   result.full_content # => "Hello world"
  #
  # @example Checking completion status
  #   result.complete? # => true
  #   result.chunk_count # => 2
  #
  class StreamingResult < Result

    # @return [Array<Hash>] Array of content chunks with timestamps
    attr_reader :chunks

    # @return [Boolean] Whether the stream is complete
    attr_reader :complete

    ##
    # Initialize streaming result
    #
    # @param success [Boolean] Whether the operation is successful
    # @param chunks [Array<Hash>] Initial chunks
    # @param complete [Boolean] Whether the stream is complete
    # @param kwargs [Hash] Additional arguments passed to parent
    #
    def initialize(success: true, chunks: [], complete: false, **)
      @chunks = chunks.dup
      @complete = complete
      super(success: success, **)
    end

    ##
    # Add a new content chunk to the stream
    #
    # @param chunk [String] The content chunk to add
    #
    def add_chunk(chunk)
      @chunks << {
        content: chunk,
        timestamp: Time.now.utc.iso8601
      }
    end

    ##
    # Mark the stream as complete
    #
    def complete!
      @complete = true
    end

    ##
    # Check if the stream is complete
    #
    # @return [Boolean] true if streaming is finished
    #
    def complete?
      @complete
    end

    ##
    # Get the complete content by joining all chunks
    #
    # @return [String] Full content from all chunks
    #
    def full_content
      @chunks.map { |chunk| chunk[:content] }.join
    end

    ##
    # Get the number of chunks received
    #
    # @return [Integer] Total chunk count
    #
    def chunk_count
      @chunks.length
    end

    def to_h
      super.merge({
                    chunks: @chunks,
                    complete: @complete,
                    full_content: full_content,
                    chunk_count: chunk_count
                  })
    end

  end

  ##
  # Handoff result
  #
  # Represents the outcome of transferring control from one agent to another,
  # including the source and target agents, reason for handoff, and any
  # associated data.
  #
  # @example Successful handoff
  #   result = HandoffResult.success(
  #     from_agent: "Assistant",
  #     to_agent: "Specialist",
  #     reason: "User needs expert help",
  #     handoff_data: { context: "programming question" }
  #   )
  #
  class HandoffResult < Result

    attr_reader :from_agent, :to_agent, :reason, :handoff_data

    def initialize(success:, from_agent:, to_agent:, reason: nil, handoff_data: {}, **)
      @from_agent = from_agent
      @to_agent = to_agent
      @reason = reason
      @handoff_data = handoff_data.dup
      super(success: success, **)
    end

    def to_h
      super.merge({
                    from_agent: @from_agent,
                    to_agent: @to_agent,
                    reason: @reason,
                    handoff_data: @handoff_data
                  })
    end

    def self.success(from_agent:, to_agent:, **)
      new(success: true, from_agent: from_agent, to_agent: to_agent, **)
    end

    def self.failure(from_agent:, to_agent:, error:, **)
      new(success: false, from_agent: from_agent, to_agent: to_agent, error: error, **)
    end

  end

  ##
  # Validation result
  #
  # Represents the outcome of validating data against a schema or set of rules,
  # including detailed violation information when validation fails.
  #
  # @example Successful validation
  #   result = ValidationResult.valid(
  #     data: { name: "John", age: 30 },
  #     schema: user_schema
  #   )
  #
  # @example Failed validation
  #   result = ValidationResult.invalid(
  #     violations: [
  #       { field: "age", message: "must be positive" },
  #       { field: "email", message: "is required" }
  #     ],
  #     schema: user_schema
  #   )
  #   result.violation_messages # => ["must be positive", "is required"]
  #
  class ValidationResult < Result

    attr_reader :schema, :violations

    def initialize(success:, schema: nil, violations: [], **)
      @schema = schema
      @violations = violations.dup
      super(success: success, **)
    end

    ##
    # Check if validation passed
    #
    # @return [Boolean] true if successful and no violations
    #
    def valid?
      success? && @violations.empty?
    end

    ##
    # Check if validation failed
    #
    # @return [Boolean] true if validation failed
    #
    def invalid?
      !valid?
    end

    ##
    # Get the number of validation violations
    #
    # @return [Integer] Number of violations
    #
    def violation_count
      @violations.length
    end

    ##
    # Get human-readable violation messages
    #
    # @return [Array<String>] Array of violation messages
    #
    def violation_messages
      @violations.map { |v| v[:message] || v.to_s }
    end

    def to_h
      super.merge({
                    schema: @schema,
                    violations: @violations,
                    valid: valid?,
                    violation_count: violation_count
                  })
    end

    def self.valid(data: nil, schema: nil, **)
      new(success: true, data: data, schema: schema, **)
    end

    def self.invalid(violations:, schema: nil, **)
      new(success: false, violations: violations, schema: schema, **)
    end

  end

  ##
  # Batch result for multiple operations
  #
  # Aggregates results from multiple operations, providing statistics
  # and access to individual results. Useful for batch processing scenarios.
  #
  # @example Creating a batch result
  #   results = [
  #     Result.success("Operation 1"),
  #     Result.failure("Error in operation 2"),
  #     Result.success("Operation 3")
  #   ]
  #   batch = BatchResult.new(results: results)
  #   batch.success_rate # => 66.67
  #   batch.successful_results.size # => 2
  #
  # @example Adding results dynamically
  #   batch = BatchResult.new
  #   batch.add_result(Result.success("First"))
  #   batch.add_result(Result.failure("Second"))
  #   batch.success? # => false (has failures)
  #
  class BatchResult < Result

    attr_reader :results, :total_count, :success_count, :failure_count

    def initialize(results: [])
      @results = results.dup
      @total_count = @results.length
      @success_count = @results.count(&:success?)
      @failure_count = @results.count(&:failure?)

      overall_success = @failure_count.zero?
      super(success: overall_success)
    end

    ##
    # Add a result to the batch
    #
    # @param result [Result] Result to add to the batch
    #
    def add_result(result)
      @results << result
      @total_count = @results.length
      @success_count = @results.count(&:success?)
      @failure_count = @results.count(&:failure?)

      # Update overall success status
      @success = @failure_count.zero?
    end

    ##
    # Calculate success rate as percentage
    #
    # @return [Float] Success rate as percentage (0.0 to 100.0)
    #
    def success_rate
      return 0.0 if @total_count.zero?

      (@success_count.to_f / @total_count * 100).round(2)
    end

    ##
    # Get all successful results
    #
    # @return [Array<Result>] Results that succeeded
    #
    def successful_results
      @results.select(&:success?)
    end

    ##
    # Get all failed results
    #
    # @return [Array<Result>] Results that failed
    #
    def failed_results
      @results.select(&:failure?)
    end

    ##
    # Iterate over all results
    #
    # @yield [result] Each result in the batch
    #
    def each_result(&)
      @results.each(&)
    end

    ##
    # Access result by index
    #
    # @param index [Integer] Index of result to retrieve
    # @return [Result, nil] Result at the given index
    #
    def [](index)
      @results[index]
    end

    def to_h
      super.merge({
                    results: @results.map(&:to_h),
                    total_count: @total_count,
                    success_count: @success_count,
                    failure_count: @failure_count,
                    success_rate: success_rate
                  })
    end

  end

  ##
  # Run result class that matches Python implementation
  #
  # Represents the complete result of an agent conversation run,
  # compatible with the Python RAAF SDK. Contains the
  # full conversation history, agent information, and usage statistics.
  #
  # @example Creating a run result
  #   result = RunResult.success(
  #     messages: conversation_messages,
  #     last_agent: agent,
  #     turns: 3,
  #     usage: { total_tokens: 150 }
  #   )
  #
  # @example Extracting final output
  #   result.final_output           # => String content
  #   result.final_output_as(:json) # => Parsed JSON
  #   result.to_input_list          # => Messages for next run
  #
  class RunResult < Result

    attr_reader :messages, :last_agent, :turns, :final_output, :last_response_id, :usage

    def initialize(success: true, messages: [], last_agent: nil, turns: 0, last_response_id: nil, usage: nil, **)
      @messages = messages.dup
      @last_agent = last_agent
      @turns = turns
      @last_response_id = last_response_id
      @usage = usage
      @final_output = extract_final_output(messages)

      super(success: success, data: {
        messages: @messages,
        last_agent: agent_name,
        turns: @turns,
        last_response_id: @last_response_id,
        usage: @usage
      }, **)
    end

    def agent_name
      @last_agent&.name || "unknown"
    end

    def to_input_list
      @messages.dup
    end

    ##
    # Get final output in specified format
    #
    # @param type [Symbol, String] Format to convert to (:string, :json)
    # @return [Object] Final output in requested format
    #
    def final_output_as(type)
      case type.to_s.downcase
      when "string"
        @final_output.to_s
      when "json"
        begin
          JSON.parse(@final_output.to_s)
        rescue JSON::ParserError
          @final_output
        end
      else
        @final_output
      end
    end

    def to_h
      {
        messages: @messages,
        last_agent: @last_agent,
        turns: @turns,
        final_output: @final_output,
        last_response_id: @last_response_id,
        usage: @usage
      }
    end

    def self.success(messages: [], last_agent: nil, turns: 0, usage: nil, **)
      new(success: true, messages: messages, last_agent: last_agent, turns: turns, usage: usage, **)
    end

    def self.failure(error:, messages: [], last_agent: nil, turns: 0, usage: nil, **)
      new(success: false, error: error, messages: messages, last_agent: last_agent, turns: turns, usage: usage, **)
    end

    private

    def extract_final_output(messages)
      # Find the last assistant message content
      assistant_messages = messages.select { |msg| msg[:role] == "assistant" }
      return "" if assistant_messages.empty?

      last_message = assistant_messages.last
      last_message[:content] || ""
    end

  end

  ##
  # Result builder for complex operations
  #
  # Provides a fluent interface for building results with automatic
  # timing and metadata collection. Useful for operations that need
  # to accumulate data before creating the final result.
  #
  # @example Building a complex result
  #   builder = ResultBuilder.new
  #   builder.add_metadata(:user_id, "123")
  #          .add_metadata(:operation, "search")
  #
  #   result = builder.build_success("Search completed")
  #   # Result includes duration_ms and metadata
  #
  # @example Building tool results
  #   builder = ResultBuilder.new
  #   result = builder.build_tool_success(
  #     tool_name: "calculator",
  #     data: 42
  #   )
  #
  class ResultBuilder

    def initialize
      @metadata = {}
      @start_time = Time.now.utc
    end

    ##
    # Add metadata to the result
    #
    # @param key [Symbol, String] Metadata key
    # @param value [Object] Metadata value
    # @return [ResultBuilder] Self for chaining
    #
    def add_metadata(key, value)
      @metadata[key] = value
      self
    end

    ##
    # Merge a hash of metadata
    #
    # @param hash [Hash] Metadata to merge
    # @return [ResultBuilder] Self for chaining
    #
    def merge_metadata(hash)
      @metadata.merge!(hash)
      self
    end

    def build_success(data = nil, result_class: Result)
      duration = Time.now.utc - @start_time
      @metadata[:duration_ms] = (duration * 1000).round(2)

      result_class.success(data, metadata: @metadata)
    end

    def build_failure(error, result_class: Result)
      duration = Time.now.utc - @start_time
      @metadata[:duration_ms] = (duration * 1000).round(2)

      result_class.failure(error, metadata: @metadata)
    end

    def build_agent_success(agent_name:, **)
      duration = Time.now.utc - @start_time
      @metadata[:duration_ms] = (duration * 1000).round(2)

      AgentResult.success(agent_name: agent_name, metadata: @metadata, **)
    end

    def build_agent_failure(agent_name:, error:, **)
      duration = Time.now.utc - @start_time
      @metadata[:duration_ms] = (duration * 1000).round(2)

      AgentResult.failure(agent_name: agent_name, error: error, metadata: @metadata, **)
    end

    def build_tool_success(tool_name:, data: nil, **)
      duration = Time.now.utc - @start_time
      execution_time = duration
      @metadata[:duration_ms] = (duration * 1000).round(2)

      ToolResult.success(
        tool_name: tool_name,
        data: data,
        execution_time: execution_time,
        metadata: @metadata,
        **
      )
    end

    def build_tool_failure(tool_name:, error:, **)
      duration = Time.now.utc - @start_time
      execution_time = duration
      @metadata[:duration_ms] = (duration * 1000).round(2)

      ToolResult.failure(
        tool_name: tool_name,
        error: error,
        execution_time: execution_time,
        metadata: @metadata,
        **
      )
    end

  end

end
