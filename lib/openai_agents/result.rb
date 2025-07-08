# frozen_string_literal: true

require "json"
require "time"

module OpenAIAgents
  # Base result class for all agent operations
  class Result
    attr_reader :success, :data, :error, :metadata, :timestamp

    def initialize(success:, data: nil, error: nil, metadata: {})
      @success = success
      @data = data
      @error = error
      @metadata = metadata.dup
      @timestamp = Time.now.utc
    end

    def success?
      @success
    end

    def failure?
      !@success
    end

    def error?
      !@success && @error
    end

    def to_h
      {
        success: @success,
        data: @data,
        error: @error,
        metadata: @metadata,
        timestamp: @timestamp.iso8601
      }
    end

    def to_json(*)
      JSON.generate(to_h, *)
    end

    def self.success(data = nil, metadata: {})
      new(success: true, data: data, metadata: metadata)
    end

    def self.failure(error, metadata: {})
      new(success: false, error: error, metadata: metadata)
    end
  end

  # Agent execution result
  class AgentResult < Result
    attr_reader :agent_name, :messages, :turns, :handoffs, :tool_calls

    def initialize(success:, agent_name:, messages: [], turns: 0, handoffs: [], tool_calls: [], **)
      @agent_name = agent_name
      @messages = messages.dup
      @turns = turns
      @handoffs = handoffs.dup
      @tool_calls = tool_calls.dup
      super(success: success, **)
    end

    def final_message
      @messages.last
    end

    def assistant_messages
      @messages.select { |msg| msg[:role] == "assistant" }
    end

    def user_messages
      @messages.select { |msg| msg[:role] == "user" }
    end

    def tool_messages
      @messages.select { |msg| msg[:role] == "tool" }
    end

    def conversation_length
      @messages.length
    end

    def total_handoffs
      @handoffs.length
    end

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

  # Tool execution result
  class ToolResult < Result
    attr_reader :tool_name, :input_args, :execution_time

    def initialize(success:, tool_name:, input_args: {}, execution_time: nil, **)
      @tool_name = tool_name
      @input_args = input_args.dup
      @execution_time = execution_time
      super(success: success, **)
    end

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

  # Streaming result for real-time responses
  class StreamingResult < Result
    attr_reader :chunks, :complete

    def initialize(success: true, chunks: [], complete: false, **)
      @chunks = chunks.dup
      @complete = complete
      super(success: success, **)
    end

    def add_chunk(chunk)
      @chunks << {
        content: chunk,
        timestamp: Time.now.utc.iso8601
      }
    end

    def complete!
      @complete = true
    end

    def complete?
      @complete
    end

    def full_content
      @chunks.map { |chunk| chunk[:content] }.join
    end

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

  # Handoff result
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

  # Validation result
  class ValidationResult < Result
    attr_reader :schema, :violations

    def initialize(success:, schema: nil, violations: [], **)
      @schema = schema
      @violations = violations.dup
      super(success: success, **)
    end

    def valid?
      success? && @violations.empty?
    end

    def invalid?
      !valid?
    end

    def violation_count
      @violations.length
    end

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

  # Batch result for multiple operations
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

    def add_result(result)
      @results << result
      @total_count = @results.length
      @success_count = @results.count(&:success?)
      @failure_count = @results.count(&:failure?)

      # Update overall success status
      @success = @failure_count.zero?
    end

    def success_rate
      return 0.0 if @total_count.zero?

      (@success_count.to_f / @total_count * 100).round(2)
    end

    def successful_results
      @results.select(&:success?)
    end

    def failed_results
      @results.select(&:failure?)
    end

    def each_result(&)
      @results.each(&)
    end

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

  # Run result class that matches Python implementation
  class RunResult < Result
    attr_reader :messages, :last_agent, :turns, :final_output, :last_response_id

    def initialize(success: true, messages: [], last_agent: nil, turns: 0, last_response_id: nil, **)
      @messages = messages.dup
      @last_agent = last_agent
      @turns = turns
      @last_response_id = last_response_id
      @final_output = extract_final_output(messages)

      super(success: success, data: {
        messages: @messages,
        last_agent: agent_name,
        turns: @turns,
        last_response_id: @last_response_id
      }, **)
    end

    def agent_name
      @last_agent&.name || "unknown"
    end

    def to_input_list
      @messages.dup
    end

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
        last_response_id: @last_response_id
      }
    end

    def self.success(messages: [], last_agent: nil, turns: 0, **)
      new(success: true, messages: messages, last_agent: last_agent, turns: turns, **)
    end

    def self.failure(error:, messages: [], last_agent: nil, turns: 0, **)
      new(success: false, error: error, messages: messages, last_agent: last_agent, turns: turns, **)
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

  # Result builder for complex operations
  class ResultBuilder
    def initialize
      @metadata = {}
      @start_time = Time.now.utc
    end

    def add_metadata(key, value)
      @metadata[key] = value
      self
    end

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
