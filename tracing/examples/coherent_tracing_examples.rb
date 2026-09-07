#!/usr/bin/env ruby
# frozen_string_literal: true

# RAAF Coherent Tracing Examples
#
# This file demonstrates proper span hierarchy creation using the
# RAAF coherent tracing system with real-world scenarios.

require "bundler/setup"

# Simple processor for examples that doesn't require complex logger setup
class ExampleConsoleProcessor

  def on_span_start(span)
    puts "🟢 #{span.name} started (#{span.span_id[0..8]})"
  end

  def on_span_end(span)
    status_icon = span.status == :error ? "❌" : "✅"
    duration = span.duration ? "#{span.duration.round(2)}ms" : "unknown"
    parent_info = span.parent_id ? " [child of #{span.parent_id[0..8]}]" : " [root]"
    puts "#{status_icon} #{span.name} completed in #{duration}#{parent_info}"
  end

  def force_flush
    # No-op for examples
  end

  def shutdown
    # No-op for examples
  end

end

# Load tracing after setting up simple processor
require "raaf/tracing"

# Add our simple processor
RAAF::Tracing.add_trace_processor(ExampleConsoleProcessor.new)

puts "🚀 RAAF Coherent Tracing Examples"
puts "=" * 50

# Example 1: Basic Pipeline → Agent → Tool Hierarchy
puts "\n📝 Example 1: Basic Three-Level Hierarchy"

class DataPipeline

  include RAAF::Tracing::Traceable

  trace_as :pipeline

  attr_reader :name, :agents

  def initialize(name:, agents: [])
    @name = name
    @agents = agents
  end

  def execute
    with_tracing(:execute) do
      puts "   🔄 Pipeline #{name} executing with #{agents.size} agents"
      agents.each(&:run)
      "Pipeline completed successfully"
    end
  end

  def collect_span_attributes
    super.merge({
                  "pipeline.name" => name,
                  "pipeline.agents_count" => agents.size,
                  "pipeline.type" => "data_processing"
                })
  end

end

class DataAgent

  include RAAF::Tracing::Traceable

  trace_as :agent

  attr_reader :name, :tools, :parent_component

  def initialize(name:, tools: [], parent_component: nil)
    @name = name
    @tools = tools
    @parent_component = parent_component
  end

  def run
    with_tracing(:run) do
      puts "     🤖 Agent #{name} running with #{tools.size} tools"
      tools.each { |tool| tool.execute({ data: "sample_data" }) }
      "Agent processing completed"
    end
  end

  def collect_span_attributes
    super.merge({
                  "agent.name" => name,
                  "agent.model" => "gpt-4",
                  "agent.tools_count" => tools.size,
                  "agent.temperature" => 0.7
                })
  end

end

class CalculatorTool

  include RAAF::Tracing::Traceable

  trace_as :tool

  attr_reader :name, :parent_component

  def initialize(name:, parent_component: nil)
    @name = name
    @parent_component = parent_component
  end

  def execute(args)
    with_tracing(:execute, operation: "calculation") do
      puts "       🔧 Tool #{name} executing calculation"
      result = perform_calculation(args[:data])
      sleep(0.01) # Simulate processing time
      result
    end
  end

  def collect_span_attributes
    super.merge({
                  "tool.name" => name,
                  "tool.type" => "calculator",
                  "tool.version" => "1.0",
                  "tool.capabilities" => %w[add multiply analyze]
                })
  end

  private

  def perform_calculation(data)
    "Calculated result for #{data}"
  end

end

# Set up the hierarchy
calculator = CalculatorTool.new(name: "Scientific Calculator")
agent = DataAgent.new(
  name: "Data Analyzer",
  tools: [calculator],
  parent_component: nil # Will be set by pipeline
)
calculator.instance_variable_set(:@parent_component, agent)

pipeline = DataPipeline.new(
  name: "Main Data Pipeline",
  agents: [agent]
)
agent.instance_variable_set(:@parent_component, pipeline)

# Execute and create spans
RAAF::Tracing.trace("Basic Hierarchy Example") do
  result = pipeline.execute
  puts "   ✅ Result: #{result}"
end

# Example 2: Multi-Agent Parallel Pipeline
puts "\n📝 Example 2: Multi-Agent Parallel Execution"

class ParallelPipeline

  include RAAF::Tracing::Traceable

  trace_as :pipeline

  attr_reader :agents

  def initialize(agents: [])
    @agents = agents
    agents.each { |agent| agent.instance_variable_set(:@parent_component, self) }
  end

  def execute
    with_tracing(:execute) do
      puts "   🔄 Parallel pipeline executing #{agents.size} agents"

      # Sequential execution for demo (parallel would complicate output)
      results = agents.map do |agent|
        agent.run
      end

      "All #{agents.size} agents completed: #{results.join(", ")}"
    end
  end

  def collect_span_attributes
    super.merge({
                  "pipeline.type" => "parallel",
                  "pipeline.agents_count" => agents.size,
                  "pipeline.execution_mode" => "parallel"
                })
  end

end

class SpecializedAgent

  include RAAF::Tracing::Traceable

  trace_as :agent

  attr_reader :name, :specialty, :parent_component

  def initialize(name:, specialty:, parent_component: nil)
    @name = name
    @specialty = specialty
    @parent_component = parent_component
  end

  def run
    with_tracing(:run) do
      puts "     🎯 Specialized agent #{name} (#{specialty}) processing"
      sleep(0.005) # Simulate processing
      "#{specialty} analysis completed"
    end
  end

  def collect_span_attributes
    super.merge({
                  "agent.name" => name,
                  "agent.specialty" => specialty,
                  "agent.model" => "gpt-4",
                  "agent.specialized" => true
                })
  end

end

# Create specialized agents
sentiment_agent = SpecializedAgent.new(
  name: "Sentiment Analyzer",
  specialty: "sentiment_analysis"
)
keyword_agent = SpecializedAgent.new(
  name: "Keyword Extractor",
  specialty: "keyword_extraction"
)
entity_agent = SpecializedAgent.new(
  name: "Entity Recognizer",
  specialty: "entity_recognition"
)

parallel_pipeline = ParallelPipeline.new(
  agents: [sentiment_agent, keyword_agent, entity_agent]
)

# Execute parallel pipeline
RAAF::Tracing.trace("Parallel Pipeline Example") do
  result = parallel_pipeline.execute
  puts "   ✅ Result: #{result}"
end

# Example 3: Nested Pipeline Architecture
puts "\n📝 Example 3: Nested Pipeline Architecture"

class MasterPipeline

  include RAAF::Tracing::Traceable

  trace_as :pipeline

  attr_reader :sub_pipelines

  def initialize(sub_pipelines: [])
    @sub_pipelines = sub_pipelines
    sub_pipelines.each { |pipeline| pipeline.instance_variable_set(:@parent_component, self) }
  end

  def execute
    with_tracing(:execute) do
      puts "   🏗️  Master pipeline orchestrating #{sub_pipelines.size} sub-pipelines"

      results = sub_pipelines.map.with_index do |pipeline, index|
        puts "     📋 Executing sub-pipeline #{index + 1}"
        pipeline.execute
      end

      "Master pipeline completed: #{results.size} sub-pipelines processed"
    end
  end

  def collect_span_attributes
    super.merge({
                  "pipeline.type" => "master",
                  "pipeline.sub_pipelines_count" => sub_pipelines.size,
                  "pipeline.orchestration" => true
                })
  end

end

class SubPipeline

  include RAAF::Tracing::Traceable

  trace_as :pipeline

  attr_reader :name, :agents, :parent_component

  def initialize(name:, agents: [], parent_component: nil)
    @name = name
    @agents = agents
    @parent_component = parent_component
    agents.each { |agent| agent.instance_variable_set(:@parent_component, self) }
  end

  def execute
    with_tracing(:execute) do
      puts "       🔧 Sub-pipeline #{name} executing #{agents.size} agents"
      agents.each(&:run)
      "Sub-pipeline #{name} completed"
    end
  end

  def collect_span_attributes
    super.merge({
                  "pipeline.name" => name,
                  "pipeline.type" => "sub_pipeline",
                  "pipeline.agents_count" => agents.size,
                  "pipeline.parent_type" => "master_pipeline"
                })
  end

end

class ProcessingAgent

  include RAAF::Tracing::Traceable

  trace_as :agent

  attr_reader :name, :process_type, :parent_component

  def initialize(name:, process_type:, parent_component: nil)
    @name = name
    @process_type = process_type
    @parent_component = parent_component
  end

  def run
    with_tracing(:run) do
      puts "         🔄 Processing agent #{name} (#{process_type})"
      sleep(0.003) # Simulate processing
      "#{process_type} processing completed"
    end
  end

  def collect_span_attributes
    super.merge({
                  "agent.name" => name,
                  "agent.process_type" => process_type,
                  "agent.model" => "gpt-4",
                  "agent.nested_level" => 2
                })
  end

end

# Create nested pipeline structure
ingestion_agents = [
  ProcessingAgent.new(name: "Data Validator", process_type: "validation"),
  ProcessingAgent.new(name: "Data Transformer", process_type: "transformation")
]

analysis_agents = [
  ProcessingAgent.new(name: "Pattern Detector", process_type: "pattern_analysis"),
  ProcessingAgent.new(name: "Anomaly Detector", process_type: "anomaly_detection")
]

output_agents = [
  ProcessingAgent.new(name: "Report Generator", process_type: "report_generation")
]

ingestion_pipeline = SubPipeline.new(
  name: "Data Ingestion",
  agents: ingestion_agents
)

analysis_pipeline = SubPipeline.new(
  name: "Data Analysis",
  agents: analysis_agents
)

output_pipeline = SubPipeline.new(
  name: "Output Generation",
  agents: output_agents
)

master_pipeline = MasterPipeline.new(
  sub_pipelines: [ingestion_pipeline, analysis_pipeline, output_pipeline]
)

# Execute nested pipeline
RAAF::Tracing.trace("Nested Pipeline Example") do
  result = master_pipeline.execute
  puts "   ✅ Result: #{result}"
end

# Example 4: Complex Multi-Tool Agent
puts "\n📝 Example 4: Complex Multi-Tool Agent"

class ComplexAgent

  include RAAF::Tracing::Traceable

  trace_as :agent

  attr_reader :name, :tools, :parent_component

  def initialize(name:, tools: [], parent_component: nil)
    @name = name
    @tools = tools
    @parent_component = parent_component
    tools.each { |tool| tool.instance_variable_set(:@parent_component, self) }
  end

  def analyze_data(data)
    with_tracing(:analyze_data, data_size: data.length) do
      puts "     🧠 Complex agent #{name} analyzing data"

      # Use multiple tools in sequence
      validation_result = @tools[0].execute({ data: data, operation: "validate" })
      processing_result = @tools[1].execute({ data: validation_result, operation: "process" })
      analysis_result = @tools[2].execute({ data: processing_result, operation: "analyze" })

      "Data analysis completed: #{analysis_result}"
    end
  end

  def collect_span_attributes
    super.merge({
                  "agent.name" => name,
                  "agent.type" => "complex_analyzer",
                  "agent.tools_count" => tools.size,
                  "agent.model" => "gpt-4",
                  "agent.capabilities" => %w[validation processing analysis]
                })
  end

end

class AdvancedTool

  include RAAF::Tracing::Traceable

  trace_as :tool

  attr_reader :name, :tool_type, :parent_component

  def initialize(name:, tool_type:, parent_component: nil)
    @name = name
    @tool_type = tool_type
    @parent_component = parent_component
  end

  def execute(args)
    with_tracing(:execute, operation: args[:operation]) do
      puts "       🛠️  Advanced tool #{name} (#{tool_type}) executing #{args[:operation]}"
      sleep(0.002) # Simulate processing

      case args[:operation]
      when "validate"
        "Validation passed for #{args[:data]}"
      when "process"
        "Processed data: #{args[:data]}"
      when "analyze"
        "Analysis complete: insights from #{args[:data]}"
      else
        "Operation #{args[:operation]} completed"
      end
    end
  end

  def collect_span_attributes
    super.merge({
                  "tool.name" => name,
                  "tool.type" => tool_type,
                  "tool.version" => "2.0",
                  "tool.advanced" => true
                })
  end

end

# Create complex agent with multiple tools
validator_tool = AdvancedTool.new(
  name: "Data Validator Pro",
  tool_type: "validation"
)

processor_tool = AdvancedTool.new(
  name: "Neural Processor",
  tool_type: "processing"
)

analyzer_tool = AdvancedTool.new(
  name: "Deep Analyzer",
  tool_type: "analysis"
)

complex_agent = ComplexAgent.new(
  name: "AI Research Assistant",
  tools: [validator_tool, processor_tool, analyzer_tool]
)

# Execute complex analysis
RAAF::Tracing.trace("Complex Agent Example") do
  result = complex_agent.analyze_data("Sample research data for analysis")
  puts "   ✅ Result: #{result}"
end

# Example 5: Error Handling and Recovery
puts "\n📝 Example 5: Error Handling and Recovery"

class ResilientPipeline

  include RAAF::Tracing::Traceable

  trace_as :pipeline

  attr_reader :agents

  def initialize(agents: [])
    @agents = agents
    agents.each { |agent| agent.instance_variable_set(:@parent_component, self) }
  end

  def execute_with_recovery
    with_tracing(:execute_with_recovery) do
      puts "   🛡️  Resilient pipeline starting with recovery capability"

      successful_agents = []
      failed_agents = []

      agents.each do |agent|
        result = agent.run
        successful_agents << { agent: agent.name, result: result }
        puts "     ✅ Agent #{agent.name} succeeded"
      rescue StandardError => e
        failed_agents << { agent: agent.name, error: e.message }
        puts "     ❌ Agent #{agent.name} failed: #{e.message}"
        # Continue processing other agents
      end

      {
        successful: successful_agents.size,
        failed: failed_agents.size,
        total: agents.size,
        details: { successful: successful_agents, failed: failed_agents }
      }
    end
  end

  def collect_span_attributes
    super.merge({
                  "pipeline.type" => "resilient",
                  "pipeline.agents_count" => agents.size,
                  "pipeline.recovery_enabled" => true
                })
  end

end

class UnreliableAgent

  include RAAF::Tracing::Traceable

  trace_as :agent

  attr_reader :name, :failure_rate, :parent_component

  def initialize(name:, failure_rate: 0.0, parent_component: nil)
    @name = name
    @failure_rate = failure_rate
    @parent_component = parent_component
  end

  def run
    with_tracing(:run) do
      puts "     🎲 Unreliable agent #{name} (failure rate: #{(failure_rate * 100).to_i}%)"

      raise StandardError, "Simulated failure in agent #{name}" if rand < failure_rate

      sleep(0.005) # Simulate processing
      "Agent #{name} completed successfully"
    end
  end

  def collect_span_attributes
    super.merge({
                  "agent.name" => name,
                  "agent.failure_rate" => failure_rate,
                  "agent.type" => "unreliable",
                  "agent.model" => "gpt-3.5"
                })
  end

end

# Create agents with different failure rates
reliable_agent = UnreliableAgent.new(name: "Reliable Agent", failure_rate: 0.0)
somewhat_reliable_agent = UnreliableAgent.new(name: "Somewhat Reliable Agent", failure_rate: 0.3)
unreliable_agent = UnreliableAgent.new(name: "Unreliable Agent", failure_rate: 0.8)

resilient_pipeline = ResilientPipeline.new(
  agents: [reliable_agent, somewhat_reliable_agent, unreliable_agent]
)

# Execute with error handling
RAAF::Tracing.trace("Error Handling Example") do
  result = resilient_pipeline.execute_with_recovery
  puts "   📊 Pipeline Result: #{result[:successful]}/#{result[:total]} agents succeeded"
end

# Final flush to ensure all traces are sent
puts "\n🏁 Flushing traces..."
RAAF::Tracing.force_flush
sleep(1) # Allow time for processing

puts "\n✨ All examples completed!"
puts "💡 Check your OpenAI traces dashboard at: https://platform.openai.com/traces"
puts "🔍 Look for the following trace groups:"
puts "   - Basic Hierarchy Example"
puts "   - Parallel Pipeline Example"
puts "   - Nested Pipeline Example"
puts "   - Complex Agent Example"
puts "   - Error Handling Example"
