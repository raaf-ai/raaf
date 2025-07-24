# frozen_string_literal: true

module RAAF

  module StreamingEvents

    # Base event class
    class StreamEvent

      attr_reader :timestamp, :event_id

      def initialize
        @timestamp = Time.now.utc
        @event_id = SecureRandom.uuid
      end

      def to_h
        {
          event_id: @event_id,
          timestamp: @timestamp,
          type: self.class.name.split("::").last.downcase
        }
      end

    end

    # Agent lifecycle events
    class AgentStartEvent < StreamEvent

      attr_reader :agent

      def initialize(agent:)
        super()
        @agent = agent
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          agent_id: @agent.object_id
        )
      end

    end

    class AgentFinishEvent < StreamEvent

      attr_reader :agent, :result

      def initialize(agent:, result:)
        super()
        @agent = agent
        @result = result
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          agent_id: @agent.object_id,
          turn_count: @result.turn_count
        )
      end

    end

    class AgentHandoffEvent < StreamEvent

      attr_reader :from_agent, :to_agent, :reason

      def initialize(from_agent:, to_agent:, reason: nil)
        super()
        @from_agent = from_agent
        @to_agent = to_agent
        @reason = reason
      end

      def to_h
        super.merge(
          from_agent: @from_agent.name,
          to_agent: @to_agent.name,
          reason: @reason
        )
      end

    end

    # Message events
    class MessageStartEvent < StreamEvent

      attr_reader :agent, :message

      def initialize(agent:, message:)
        super()
        @agent = agent
        @message = message
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          message_role: @message[:role],
          message_preview: (@message[:content] || "")[0..100]
        )
      end

    end

    class MessageCompleteEvent < StreamEvent

      attr_reader :agent, :message

      def initialize(agent:, message:)
        super()
        @agent = agent
        @message = message
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          message_role: @message[:role],
          message_length: (@message[:content] || "").length
        )
      end

    end

    # Tool events
    class ToolCallEvent < StreamEvent

      attr_reader :agent, :tool_call

      def initialize(agent:, tool_call:)
        super()
        @agent = agent
        @tool_call = tool_call
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          tool_name: @tool_call["function"]["name"],
          tool_call_id: @tool_call["id"]
        )
      end

    end

    class ToolExecutionStartEvent < StreamEvent

      attr_reader :agent, :tool_call

      def initialize(agent:, tool_call:)
        super()
        @agent = agent
        @tool_call = tool_call
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          tool_name: @tool_call["function"]["name"],
          tool_call_id: @tool_call["id"],
          arguments: @tool_call["function"]["arguments"]
        )
      end

    end

    class ToolExecutionCompleteEvent < StreamEvent

      attr_reader :agent, :tool_call, :result

      def initialize(agent:, tool_call:, result:)
        super()
        @agent = agent
        @tool_call = tool_call
        @result = result
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          tool_name: @tool_call["function"]["name"],
          tool_call_id: @tool_call["id"],
          result_preview: @result.to_s[0..200]
        )
      end

    end

    class ToolExecutionErrorEvent < StreamEvent

      attr_reader :agent, :tool_call, :error

      def initialize(agent:, tool_call:, error:)
        super()
        @agent = agent
        @tool_call = tool_call
        @error = error
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          tool_name: @tool_call["function"]["name"],
          tool_call_id: @tool_call["id"],
          error_message: @error.message,
          error_class: @error.class.name
        )
      end

    end

    # Guardrail events
    class GuardrailStartEvent < StreamEvent

      attr_reader :agent, :guardrail, :type

      def initialize(agent:, guardrail:, type:)
        super()
        @agent = agent
        @guardrail = guardrail
        @type = type # :input or :output
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          guardrail_name: @guardrail.name,
          guardrail_type: @type
        )
      end

    end

    class GuardrailCompleteEvent < StreamEvent

      attr_reader :agent, :guardrail, :type, :result

      def initialize(agent:, guardrail:, type:, result:)
        super()
        @agent = agent
        @guardrail = guardrail
        @type = type
        @result = result
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          guardrail_name: @guardrail.name,
          guardrail_type: @type,
          tripwire_triggered: @result.tripwire_triggered,
          output_info: @result.output_info
        )
      end

    end

    # Raw streaming events (from LLM provider)
    class RawContentDeltaEvent < StreamEvent

      attr_reader :agent, :delta

      def initialize(agent:, delta:)
        super()
        @agent = agent
        @delta = delta
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          delta: @delta
        )
      end

    end

    class RawToolCallStartEvent < StreamEvent

      attr_reader :agent, :tool_call

      def initialize(agent:, tool_call:)
        super()
        @agent = agent
        @tool_call = tool_call
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          tool_call_id: @tool_call["id"],
          tool_name: @tool_call["function"]["name"]
        )
      end

    end

    class RawToolCallDeltaEvent < StreamEvent

      attr_reader :agent, :tool_call_id, :delta

      def initialize(agent:, tool_call_id:, delta:)
        super()
        @agent = agent
        @tool_call_id = tool_call_id
        @delta = delta
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          tool_call_id: @tool_call_id,
          delta: @delta
        )
      end

    end

    class RawFinishEvent < StreamEvent

      attr_reader :agent, :finish_reason

      def initialize(agent:, finish_reason:)
        super()
        @agent = agent
        @finish_reason = finish_reason
      end

      def to_h
        super.merge(
          agent_name: @agent.name,
          finish_reason: @finish_reason
        )
      end

    end

    # Error events
    class StreamErrorEvent < StreamEvent

      attr_reader :error

      def initialize(error:)
        super()
        @error = error
      end

      def to_h
        super.merge(
          error_message: @error.message,
          error_class: @error.class.name,
          error_backtrace: @error.backtrace&.first(5)
        )
      end

    end

    # Event filtering helpers
    class EventFilter

      def self.by_type(*types)
        ->(event) { types.any? { |type| event.is_a?(type) } }
      end

      def self.by_agent(agent_name)
        lambda { |event|
          event.respond_to?(:agent) && event.agent&.name == agent_name
        }
      end

      def self.semantic_only
        by_type(
          AgentStartEvent, AgentFinishEvent, AgentHandoffEvent,
          MessageStartEvent, MessageCompleteEvent,
          ToolCallEvent, ToolExecutionStartEvent, ToolExecutionCompleteEvent, ToolExecutionErrorEvent,
          GuardrailStartEvent, GuardrailCompleteEvent,
          StreamErrorEvent
        )
      end

      def self.raw_only
        by_type(
          RawContentDeltaEvent, RawToolCallStartEvent, RawToolCallDeltaEvent, RawFinishEvent
        )
      end

      def self.tool_events
        by_type(
          ToolCallEvent, ToolExecutionStartEvent, ToolExecutionCompleteEvent, ToolExecutionErrorEvent
        )
      end

      def self.combine(*filters)
        ->(event) { filters.all? { |filter| filter.call(event) } }
      end

    end

  end

end
