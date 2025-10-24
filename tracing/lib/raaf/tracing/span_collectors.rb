# frozen_string_literal: true

require_relative "span_collectors/base_collector"
require_relative "span_collectors/agent_collector"
require_relative "span_collectors/llm_collector"
require_relative "span_collectors/tool_collector"
require_relative "span_collectors/error_collector"
require_relative "span_collectors/pipeline_collector"
require_relative "span_collectors/job_collector"
require_relative "span_collectors/dsl/agent_collector"

# RAAF Tracing Span Collectors
#
# The RAAF tracing system uses specialized collectors to extract meaningful attributes
# from different types of components during execution. Each collector implements a DSL
# for defining extraction patterns and provides comprehensive visibility into component
# behavior, execution context, and results.
#
# @overview Available Collectors
#   - BaseCollector: Foundation class with DSL and automatic discovery
#   - AgentCollector: Comprehensive dialog and execution tracking for core agents
#   - DSL::AgentCollector: Context and configuration tracking for DSL-based agents
#   - ToolCollector: Tool execution details, results, and agent context
#   - PipelineCollector: Multi-agent orchestration and flow analysis
#   - JobCollector: Background job execution and queue information
#
# @example Automatic collector selection
#   agent = RAAF::Agent.new(name: "Assistant")
#   collector = SpanCollectors.collector_for(agent)
#   # => #<SpanCollectors::AgentCollector>
#
#   attributes = collector.collect_attributes(agent)
#   # => {"agent.name" => "Assistant", "agent.model" => "gpt-4o", ...}
#
# @example Custom collector with DSL
#   class MyComponentCollector < BaseCollector
#     span :name, :version  # Direct attribute extraction
#     span status: ->(comp) { comp.running? ? "active" : "idle" }
#
#     result execution_time: ->(result, comp) { result.duration }
#   end
#
# @example Dialog and conversation tracking
#   # AgentCollector automatically captures:
#   collector = SpanCollectors::AgentCollector.new
#   attrs = collector.collect_attributes(agent)
#
#   JSON.parse(attrs["agent.conversation_messages"])
#   # => [{"role" => "user", "content" => "Hello"}, ...]
#
#   JSON.parse(attrs["agent.tool_executions"])
#   # => [{"name" => "search", "arguments" => "{\"query\": \"weather\"}"}]
#
#   JSON.parse(attrs["agent.conversation_stats"])
#   # => {"total_messages" => 4, "tool_calls" => 2}
#
# @see BaseCollector For DSL methods and extension patterns
# @see AgentCollector For comprehensive agent dialog collection
# @see RAAF::Tracing::SpanTracer For integration with the main tracing system
#
# @since 1.0.0
# @author RAAF Team
module RAAF
  module Tracing
    # Span Collectors provide intelligent attribute extraction for different component types
    # using a powerful DSL and automatic discovery system.
    module SpanCollectors
      # Intelligent collector discovery that selects the most appropriate collector
      # for a given component based on class name analysis and inheritance patterns.
      # This method provides automatic collector selection with specialized handling
      # for different agent types and component patterns.
      #
      # @param component [Object] The component that needs a collector
      # @return [BaseCollector] Appropriate collector instance specialized for the component type
      #
      # @example Automatic selection for different component types
      #   # Core agents get comprehensive dialog collection
      #   agent = RAAF::Agent.new(name: "Assistant")
      #   SpanCollectors.collector_for(agent)  # => AgentCollector
      #
      #   # DSL agents get context and configuration tracking
      #   dsl_agent = MyDSLAgent.new(query: "search")
      #   SpanCollectors.collector_for(dsl_agent)  # => DSL::AgentCollector
      #
      #   # Tools get execution and result tracking
      #   tool = MySearchTool.new
      #   SpanCollectors.collector_for(tool)  # => ToolCollector
      #
      #   # Pipelines get orchestration flow analysis
      #   pipeline = DataProcessingPipeline.new
      #   SpanCollectors.collector_for(pipeline)  # => PipelineCollector
      #
      # @note Selection strategy (in order):
      #   1. Exact class name matching (RAAF::Agent, RAAF::DSL::Agent)
      #   2. Direct collector name mapping (ClassNameCollector)
      #   3. Pattern-based suffix matching (*Tool, *Pipeline, *Job)
      #   4. Fallback to BaseCollector for unknown types
      #
      # @note Special handling for agent hierarchies to select appropriate dialog collection
      def self.collector_for(component)
        class_name = component.class.name

        # Handle specific agent types with different data requirements
        case class_name
        when "RAAF::DSL::Agent"
          return DSL::AgentCollector.new
        when "RAAF::Agent"
          return AgentCollector.new
        end

        # Standard naming convention for other components
        collector_name = "#{class_name.split('::').last}Collector"
        if const_defined?(collector_name)
          const_get(collector_name).new
        else
          # Pattern-based fallback
          base_name = class_name.split('::').last
          return ToolCollector.new if base_name.end_with?('Tool')
          return PipelineCollector.new if base_name.end_with?('Pipeline')
          return JobCollector.new if base_name.end_with?('Job')

          # Ultimate fallback
          BaseCollector.new
        end
      end
    end
  end
end
