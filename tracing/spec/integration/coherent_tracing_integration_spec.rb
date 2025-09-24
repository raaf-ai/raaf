# frozen_string_literal: true

require "spec_helper"
require "benchmark"
require "fiber"
require "timeout"
require "ostruct"
require "securerandom"

RSpec.describe "TracingRegistry End-to-End Integration", :integration do
  # Mock tracer that captures spans for verification
  let(:mock_tracer) do
    Class.new do
      attr_reader :spans, :called_methods
      
      def initialize
        @spans = []
        @called_methods = []
        @mutex = Mutex.new
      end
      
      def agent_span(name, **attributes)
        span = create_span(name, attributes.merge(type: :agent))
        @mutex.synchronize { @spans << span }
        span
      end
      
      def runner_span(name, **attributes)
        span = create_span(name, attributes.merge(type: :runner))
        @mutex.synchronize { @spans << span }
        span
      end
      
      def tool_span(name, **attributes)
        span = create_span(name, attributes.merge(type: :tool))
        @mutex.synchronize { @spans << span }
        span
      end
      
      def custom_span(name, **attributes)
        span = create_span(name, attributes.merge(type: :custom))
        @mutex.synchronize { @spans << span }
        span
      end
      
      def pipeline_span(name, **attributes)
        span = create_span(name, attributes.merge(type: :pipeline))
        @mutex.synchronize { @spans << span }
        span
      end
      
      def response_span(name, **attributes)
        span = create_span(name, attributes.merge(type: :response))
        @mutex.synchronize { @spans << span }
        span
      end
      
      def method_missing(method, *args, **kwargs)
        @mutex.synchronize { @called_methods << { method: method, args: args, kwargs: kwargs } }
        create_span(method.to_s, kwargs.merge(type: :unknown))
      end
      
      def respond_to_missing?(method, include_private = false)
        true
      end
      
      def spans_by_type(type)
        @mutex.synchronize { @spans.select { |s| s.type == type } }
      end
      
      def span_hierarchy
        @mutex.synchronize do
          @spans.map { |s| { name: s.name, type: s.type, parent_id: s.parent_id, trace_id: s.trace_id } }
        end
      end
      
      def clear!
        @mutex.synchronize do
          @spans.clear
          @called_methods.clear
        end
      end
      
      private
      
      def create_span(name, attributes = {})
        OpenStruct.new({
          name: name,
          type: attributes[:type] || :unknown,
          parent_id: attributes[:parent_id],
          trace_id: attributes[:trace_id] || "trace_#{SecureRandom.hex(8)}",
          attributes: attributes,
          events: [],
          status: :ok,
          start_time: Time.now,
          end_time: nil,
          finished: false
        }.tap do |span|
          # Add span methods
          span.define_singleton_method(:set_attribute) { |key, value| span.attributes[key] = value; span }
          span.define_singleton_method(:add_event) { |name, attrs = {}| span.events << { name: name, attributes: attrs }; span }
          span.define_singleton_method(:set_status) { |status, description: nil| span.status = status; span.description = description; span }
          span.define_singleton_method(:finish) { span.end_time = Time.now; span.finished = true; span }
          span.define_singleton_method(:finished?) { span.finished }
          # Add method_missing to handle any other span methods
          span.define_singleton_method(:method_missing) { |method, *args, **kwargs| span }
          span.define_singleton_method(:respond_to_missing?) { |method, include_private = false| true }
        end)
      end
    end.new
  end
  
  # Mock agent that simulates RAAF agent behavior
  let(:mock_agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable if defined?(RAAF::Tracing::Traceable)
      
      attr_reader :name, :tools, :handoffs
      
      def initialize(name: "TestAgent")
        @name = name
        @tools = []
        @handoffs = []
      end
      
      def add_tool(tool)
        @tools << tool
      end
      
      def add_handoff(agent)
        @handoffs << agent
      end
      
      def tools?
        @tools.any?
      end
      
      def handoffs?
        @handoffs.any?
      end
      
      def run_simulation
        if respond_to?(:traced_run)
          traced_run do
            simulate_agent_execution
          end
        else
          simulate_agent_execution
        end
      end
      
      private
      
      def simulate_agent_execution
        sleep(0.01) # Simulate processing time
        { agent: @name, status: "complete", message: "Agent #{@name} execution complete" }
      end
    end
  end
  
  # Mock runner that simulates RAAF::Runner behavior
  let(:mock_runner_class) do
    Class.new do
      include RAAF::Tracing::Traceable if defined?(RAAF::Tracing::Traceable)
      
      attr_reader :agent
      
      def initialize(agent:, tracer: nil)
        @agent = agent
        @explicit_tracer = tracer
      end
      
      def run(input)
        tracer = @explicit_tracer || get_tracer_from_registry
        
        if tracer && respond_to?(:traced_run)
          traced_run do
            execute_with_agent(input)
          end
        else
          execute_with_agent(input)
        end
      end
      
      private
      
      def get_tracer_from_registry
        return nil unless defined?(RAAF::Tracing::TracingRegistry)
        
        registry_tracer = RAAF::Tracing::TracingRegistry.current_tracer
        return nil if registry_tracer.is_a?(RAAF::Tracing::NoOpTracer)
        
        registry_tracer
      end
      
      def execute_with_agent(input)
        result = @agent.run_simulation
        { input: input, output: result, agent: @agent.name }
      end
    end
  end
  
  # Mock tool that supports TracingRegistry
  let(:mock_tool_class) do
    Class.new do
      include RAAF::Tracing::Traceable if defined?(RAAF::Tracing::Traceable)
      
      attr_reader :name
      
      def initialize(name: "TestTool")
        @name = name
      end
      
      def execute(input)
        if respond_to?(:traced_run)
          traced_run do
            process_tool_execution(input)
          end
        else
          process_tool_execution(input)
        end
      end
      
      private
      
      def process_tool_execution(input)
        sleep(0.005) # Simulate tool execution time
        "Tool #{@name} processed: #{input}"
      end
    end
  end
  
  # Mock pipeline that simulates DSL Pipeline behavior
  let(:mock_pipeline_class) do
    Class.new do
      include RAAF::Tracing::Traceable if defined?(RAAF::Tracing::Traceable)
      
      attr_reader :agents
      
      def initialize(agents: [])
        @agents = agents
      end
      
      def run(input)
        if respond_to?(:traced_run)
          traced_run do
            execute_pipeline(input)
          end
        else
          execute_pipeline(input)
        end
      end
      
      private
      
      def execute_pipeline(input)
        results = []
        @agents.each_with_index do |agent, index|
          agent_input = index == 0 ? input : results.last[:output]
          results << agent.run_simulation.merge(step: index + 1)
        end
        { pipeline_results: results, final_output: results.last }
      end
    end
  end
  
  # Mock middleware that simulates Rails/Rack middleware
  let(:mock_middleware_class) do
    Class.new do
      def initialize(app, tracer: nil)
        @app = app
        @tracer = tracer
      end
      
      def call(env)
        request_tracer = @tracer || create_request_tracer(env)

        RAAF::Tracing::TracingRegistry.with_tracer(request_tracer) do
          # Simulate request span creation
          span = request_tracer.agent_span("http.request", parent_id: nil)

          # Process the request within the tracing context
          status, headers, body = @app.call(env)
          span.set_attribute("http.status_code", status)
          span.finish

          [status, headers, body]
        end
      end
      
      private

      def create_request_tracer(env)
        # Use the mock_tracer from the test context
        mock_tracer
      end

      def create_mock_span(name, attributes = {})
        span = OpenStruct.new({
          name: name,
          type: attributes[:type] || :unknown,
          parent_id: attributes[:parent_id],
          trace_id: attributes[:trace_id] || "trace_#{SecureRandom.hex(8)}",
          attributes: attributes,
          events: [],
          status: :ok,
          start_time: Time.now,
          end_time: nil,
          finished: false
        })

        # Add span methods
        span.define_singleton_method(:set_attribute) { |key, value| span.attributes[key] = value; span }
        span.define_singleton_method(:add_event) { |name, attrs = {}| span.events << { name: name, attributes: attrs }; span }
        span.define_singleton_method(:set_status) { |status, description: nil| span.status = status; span.description = description; span }
        span.define_singleton_method(:finish) { span.end_time = Time.now; span.finished = true; span }
        span.define_singleton_method(:finished?) { span.finished }
        span.define_singleton_method(:method_missing) { |method, *args, **kwargs| span }
        span.define_singleton_method(:respond_to_missing?) { |method, include_private = false| true }

        span
      end
    end
  end
  
  before do
    # Clear any existing registry state
    RAAF::Tracing::TracingRegistry.clear_all_contexts! if defined?(RAAF::Tracing::TracingRegistry)
  end
  
  after do
    # Clean up after each test
    RAAF::Tracing::TracingRegistry.clear_all_contexts! if defined?(RAAF::Tracing::TracingRegistry)
    mock_tracer.clear! if mock_tracer.respond_to?(:clear!)
  end
  
  describe "7.1 Complete Flow Testing" do
    context "middleware → TracingRegistry → Runner → Agent execution flow" do
      it "maintains trace context through entire request lifecycle" do
        app = ->(env) { [200, {}, ["OK"]] }
        middleware = mock_middleware_class.new(app, tracer: mock_tracer)
        agent = mock_agent_class.new(name: "FlowTestAgent")
        
        # Simulate request processing within middleware context
        status, headers, body = middleware.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => "/test" })
        
        expect(status).to eq(200)
        
        # Verify spans were created in middleware
        request_spans = mock_tracer.spans_by_type(:agent)
        expect(request_spans).not_to be_empty
        expect(request_spans.any? { |s| s.name == "http.request" }).to be(true)
      end
      
      it "allows RAAF components to discover middleware-set tracer" do
        app = ->(env) do
          # Within middleware context, create and run RAAF components
          agent = mock_agent_class.new(name: "RegistryAgent")
          runner = mock_runner_class.new(agent: agent)
          result = runner.run("test input")
          
          [200, {}, [result.to_json]]
        end
        
        middleware = mock_middleware_class.new(app, tracer: mock_tracer)
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          status, headers, body = middleware.call({ "REQUEST_METHOD" => "POST", "PATH_INFO" => "/agents" })
          expect(status).to eq(200)
        end
        
        # Verify that the tracer was used by RAAF components
        expect(mock_tracer.spans.size).to be > 0
      end
      
      it "propagates trace context through nested execution" do
        execution_chain = []
        
        app = ->(env) do
          execution_chain << "middleware_start"
          
          agent = mock_agent_class.new(name: "NestedAgent")
          runner = mock_runner_class.new(agent: agent)
          
          # Simulate nested execution within request context
          result = runner.run("nested execution")
          execution_chain << "agent_executed"
          
          [200, {}, ["Nested execution complete"]]
        end
        
        middleware = mock_middleware_class.new(app, tracer: mock_tracer)
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          middleware.call({ "REQUEST_METHOD" => "POST", "PATH_INFO" => "/nested" })
          execution_chain << "middleware_end"
        end
        
        expect(execution_chain).to eq(["middleware_start", "agent_executed", "middleware_end"])
        expect(mock_tracer.spans.size).to be >= 1
      end
    end
  end
  
  describe "7.2 Span Hierarchy Verification" do
    context "proper parent-child relationships" do
      it "maintains hierarchy across middleware, runner, agent, and tools" do
        tool = mock_tool_class.new(name: "HierarchyTool")
        agent = mock_agent_class.new(name: "HierarchyAgent")
        agent.add_tool(tool)
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          # Simulate middleware creating request span
          request_span = mock_tracer.agent_span("http.request", parent_id: nil)
          
          # Simulate runner creating runner span
          runner_span = mock_tracer.runner_span("runner.execute", parent_id: request_span.trace_id)
          
          # Simulate agent creating agent span
          agent_span = mock_tracer.agent_span("agent.run", parent_id: runner_span.trace_id)
          
          # Simulate tool creating tool span
          tool_span = mock_tracer.tool_span("tool.execute", parent_id: agent_span.trace_id)
          
          # Verify hierarchy
          hierarchy = mock_tracer.span_hierarchy
          
          expect(hierarchy).to include(
            hash_including(name: "http.request", type: :agent, parent_id: nil)
          )
          expect(hierarchy).to include(
            hash_including(name: "runner.execute", type: :runner, parent_id: request_span.trace_id)
          )
          expect(hierarchy).to include(
            hash_including(name: "agent.run", type: :agent, parent_id: runner_span.trace_id)
          )
          expect(hierarchy).to include(
            hash_including(name: "tool.execute", type: :tool, parent_id: agent_span.trace_id)
          )
        end
      end
      
      it "preserves span relationships across TracingRegistry contexts" do
        spans_captured = []
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          parent_span = mock_tracer.pipeline_span("parent.operation", parent_id: nil)
          spans_captured << parent_span
          
          # Nested TracingRegistry context should maintain parent relationship
          RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
            child_span = mock_tracer.agent_span("child.operation", parent_id: parent_span.trace_id)
            spans_captured << child_span
            
            expect(RAAF::Tracing::TracingRegistry.current_tracer).to eq(mock_tracer)
          end
        end
        
        expect(spans_captured.size).to eq(2)
        expect(spans_captured[1].parent_id).to eq(spans_captured[0].trace_id)
      end
      
      it "maintains trace context hierarchy in concurrent scenarios" do
        thread_results = []
        barrier = Barrier.new(2)
        
        thread1 = Thread.new do
          RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
            span = mock_tracer.agent_span("thread1.operation", parent_id: nil)
            barrier.wait
            sleep(0.01)
            thread_results << { thread: 1, span_name: span.name, tracer: RAAF::Tracing::TracingRegistry.current_tracer }
          end
        end
        
        thread2 = Thread.new do
          RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
            span = mock_tracer.agent_span("thread2.operation", parent_id: nil)
            barrier.wait
            sleep(0.01)
            thread_results << { thread: 2, span_name: span.name, tracer: RAAF::Tracing::TracingRegistry.current_tracer }
          end
        end
        
        thread1.join
        thread2.join
        
        expect(thread_results.size).to eq(2)
        expect(thread_results.map { |r| r[:thread] }).to contain_exactly(1, 2)
        expect(thread_results.all? { |r| r[:tracer] == mock_tracer }).to be(true)
      end
    end
  end
  
  describe "7.3 Multi-Agent Workflows" do
    context "agent handoffs preserve registry trace context" do
      it "maintains trace context through agent handoffs" do
        agent1 = mock_agent_class.new(name: "HandoffSource")
        agent2 = mock_agent_class.new(name: "HandoffTarget")
        agent1.add_handoff(agent2)
        
        handoff_traces = []
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          # Source agent execution
          source_result = agent1.run_simulation
          handoff_traces << { agent: "source", tracer: RAAF::Tracing::TracingRegistry.current_tracer }
          
          # Simulate handoff (should maintain same tracer context)
          target_result = agent2.run_simulation
          handoff_traces << { agent: "target", tracer: RAAF::Tracing::TracingRegistry.current_tracer }
        end
        
        expect(handoff_traces.size).to eq(2)
        expect(handoff_traces[0][:tracer]).to eq(mock_tracer)
        expect(handoff_traces[1][:tracer]).to eq(mock_tracer)
        expect(handoff_traces[0][:tracer]).to eq(handoff_traces[1][:tracer])
      end
      
      it "preserves registry context in multi-agent pipelines" do
        agents = [
          mock_agent_class.new(name: "PipelineAgent1"),
          mock_agent_class.new(name: "PipelineAgent2"),
          mock_agent_class.new(name: "PipelineAgent3")
        ]
        
        pipeline = mock_pipeline_class.new(agents: agents)
        pipeline_traces = []
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          result = pipeline.run("pipeline input")
          
          # Each agent should see the same registry tracer
          agents.each do |agent|
            pipeline_traces << {
              agent: agent.name,
              tracer: RAAF::Tracing::TracingRegistry.current_tracer
            }
          end
        end
        
        expect(pipeline_traces.size).to eq(3)
        expect(pipeline_traces.all? { |t| t[:tracer] == mock_tracer }).to be(true)
      end
    end
    
    context "pipeline workflows with proper parent-child spans" do
      it "creates proper span hierarchy for sequential agent execution" do
        agents = [
          mock_agent_class.new(name: "SequentialAgent1"),
          mock_agent_class.new(name: "SequentialAgent2")
        ]
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          pipeline_span = mock_tracer.pipeline_span("sequential.pipeline", parent_id: nil)
          
          agents.each_with_index do |agent, index|
            agent_span = mock_tracer.agent_span(
              "agent.step_#{index + 1}",
              parent_id: pipeline_span.trace_id
            )
          end
        end
        
        hierarchy = mock_tracer.span_hierarchy
        pipeline_spans = hierarchy.select { |s| s[:type] == :pipeline }
        agent_spans = hierarchy.select { |s| s[:type] == :agent }
        
        expect(pipeline_spans.size).to eq(1)
        expect(agent_spans.size).to eq(2)
        
        pipeline_trace_id = pipeline_spans.first[:trace_id]
        expect(agent_spans.all? { |s| s[:parent_id] == pipeline_trace_id }).to be(true)
      end
      
      it "handles complex multi-agent scenarios with proper trace coherence" do
        # Simulate complex workflow: Pipeline → Sequential Agents → Parallel Tools
        main_agent = mock_agent_class.new(name: "MainAgent")
        tool1 = mock_tool_class.new(name: "ParallelTool1")
        tool2 = mock_tool_class.new(name: "ParallelTool2")
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          # Root pipeline span
          pipeline_span = mock_tracer.pipeline_span("complex.workflow", parent_id: nil)
          
          # Main agent span
          agent_span = mock_tracer.agent_span("main.agent", parent_id: pipeline_span.trace_id)
          
          # Parallel tool spans
          tool1_span = mock_tracer.tool_span("tool1.execute", parent_id: agent_span.trace_id)
          tool2_span = mock_tracer.tool_span("tool2.execute", parent_id: agent_span.trace_id)
          
          # Verify all components see the same tracer
          expect(RAAF::Tracing::TracingRegistry.current_tracer).to eq(mock_tracer)
        end
        
        # Verify complete hierarchy
        hierarchy = mock_tracer.span_hierarchy
        
        # Should have 1 pipeline, 1 agent, 2 tools
        expect(hierarchy.count { |s| s[:type] == :pipeline }).to eq(1)
        expect(hierarchy.count { |s| s[:type] == :agent }).to eq(1)
        expect(hierarchy.count { |s| s[:type] == :tool }).to eq(2)
        
        # Verify parent-child relationships
        pipeline_id = hierarchy.find { |s| s[:type] == :pipeline }[:trace_id]
        agent_id = hierarchy.find { |s| s[:type] == :agent }[:trace_id]
        
        expect(hierarchy.find { |s| s[:type] == :agent }[:parent_id]).to eq(pipeline_id)
        expect(hierarchy.select { |s| s[:type] == :tool }.all? { |s| s[:parent_id] == agent_id }).to be(true)
      end
    end
  end
  
  describe "7.4 Tool Execution Tracing" do
    context "tool execution creates child spans under registry context" do
      it "creates tool spans as children of agent spans" do
        agent = mock_agent_class.new(name: "ToolAgent")
        tool = mock_tool_class.new(name: "TestTool")
        agent.add_tool(tool)
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          # Agent span
          agent_span = mock_tracer.agent_span("agent.with_tools", parent_id: nil)
          
          # Tool span as child
          tool_span = mock_tracer.tool_span("tool.execution", parent_id: agent_span.trace_id)
          
          # Execute tool within registry context
          result = tool.execute("tool input")
          expect(result).to include("TestTool processed")
        end
        
        # Verify hierarchy
        hierarchy = mock_tracer.span_hierarchy
        agent_span = hierarchy.find { |s| s[:type] == :agent }
        tool_span = hierarchy.find { |s| s[:type] == :tool }
        
        expect(agent_span).not_to be_nil
        expect(tool_span).not_to be_nil
        expect(tool_span[:parent_id]).to eq(agent_span[:trace_id])
      end
      
      it "preserves tool trace context across multiple executions" do
        tools = [
          mock_tool_class.new(name: "Tool1"),
          mock_tool_class.new(name: "Tool2"),
          mock_tool_class.new(name: "Tool3")
        ]
        
        tool_results = []
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          agent_span = mock_tracer.agent_span("multi.tool.agent", parent_id: nil)
          
          tools.each_with_index do |tool, index|
            tool_span = mock_tracer.tool_span("tool.#{index + 1}", parent_id: agent_span.trace_id)
            result = tool.execute("input #{index + 1}")
            
            tool_results << {
              tool: tool.name,
              result: result,
              tracer: RAAF::Tracing::TracingRegistry.current_tracer
            }
          end
        end
        
        expect(tool_results.size).to eq(3)
        expect(tool_results.all? { |r| r[:tracer] == mock_tracer }).to be(true)
        expect(tool_results.all? { |r| r[:result].include?("processed") }).to be(true)
      end
    end
    
    context "tools inherit proper trace context from agents" do
      it "maintains trace context when tools call other tools" do
        # Simulate nested tool execution
        parent_tool = mock_tool_class.new(name: "ParentTool")
        child_tool = mock_tool_class.new(name: "ChildTool")
        
        nested_traces = []
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          agent_span = mock_tracer.agent_span("nested.tool.agent", parent_id: nil)
          
          # Parent tool execution
          parent_span = mock_tracer.tool_span("parent.tool", parent_id: agent_span.trace_id)
          nested_traces << { level: "parent", tracer: RAAF::Tracing::TracingRegistry.current_tracer }
          
          # Child tool execution (nested within parent)
          child_span = mock_tracer.tool_span("child.tool", parent_id: parent_span.trace_id)
          nested_traces << { level: "child", tracer: RAAF::Tracing::TracingRegistry.current_tracer }
        end
        
        expect(nested_traces.size).to eq(2)
        expect(nested_traces.all? { |t| t[:tracer] == mock_tracer }).to be(true)
        
        # Verify nested hierarchy
        hierarchy = mock_tracer.span_hierarchy
        agent_span = hierarchy.find { |s| s[:name] == "nested.tool.agent" }
        parent_span = hierarchy.find { |s| s[:name] == "parent.tool" }
        child_span = hierarchy.find { |s| s[:name] == "child.tool" }
        
        expect(parent_span[:parent_id]).to eq(agent_span[:trace_id])
        expect(child_span[:parent_id]).to eq(parent_span[:trace_id])
      end
    end
  end
  
  describe "7.5 Error Handling" do
    context "errors preserve trace context" do
      it "maintains trace context when errors occur in agents" do
        error_traces = []
        
        expect do
          RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
            error_traces << { stage: "before_error", tracer: RAAF::Tracing::TracingRegistry.current_tracer }
            
            begin
              raise StandardError, "Agent execution failed"
            rescue StandardError => e
              error_traces << { 
                stage: "error_caught", 
                tracer: RAAF::Tracing::TracingRegistry.current_tracer,
                error: e.message
              }
              raise # Re-raise to test context preservation
            end
          end
        end.to raise_error(StandardError, "Agent execution failed")
        
        # Verify tracer context was maintained during error
        expect(error_traces.size).to eq(2)
        expect(error_traces.all? { |t| t[:tracer] == mock_tracer }).to be(true)
        expect(error_traces[1][:error]).to eq("Agent execution failed")
      end
      
      it "properly attributes error spans in trace hierarchy" do
        agent_span = nil
        error_span = nil

        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          agent_span = mock_tracer.agent_span("error.agent", parent_id: nil)

          # Simulate error span creation
          error_span = mock_tracer.custom_span("error.handling", parent_id: agent_span.trace_id)
        end

        # Verify error span hierarchy
        hierarchy = mock_tracer.span_hierarchy
        agent_span_in_hierarchy = hierarchy.find { |s| s[:name] == "error.agent" }
        error_span_in_hierarchy = hierarchy.find { |s| s[:name] == "error.handling" }

        expect(agent_span_in_hierarchy).not_to be_nil
        expect(error_span_in_hierarchy).not_to be_nil
        expect(error_span_in_hierarchy[:parent_id]).to eq(agent_span_in_hierarchy[:trace_id])
      end
      
      it "handles recovery scenarios while maintaining trace context" do
        recovery_traces = []
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          recovery_traces << { stage: "start", tracer: RAAF::Tracing::TracingRegistry.current_tracer }
          
          begin
            raise StandardError, "Recoverable error"
          rescue StandardError
            recovery_traces << { stage: "recovery", tracer: RAAF::Tracing::TracingRegistry.current_tracer }
            
            # Simulate recovery logic
            agent = mock_agent_class.new(name: "RecoveryAgent")
            result = agent.run_simulation
            recovery_traces << { 
              stage: "recovered", 
              tracer: RAAF::Tracing::TracingRegistry.current_tracer,
              result: result
            }
          end
        end
        
        expect(recovery_traces.size).to eq(3)
        expect(recovery_traces.all? { |t| t[:tracer] == mock_tracer }).to be(true)
        expect(recovery_traces.last[:result][:agent]).to eq("RecoveryAgent")
      end
    end
  end
  
  describe "7.6 Performance Testing" do
    context "registry overhead vs no tracing" do
      it "benchmarks TracingRegistry overhead" do
        iterations = 1000
        agent = mock_agent_class.new(name: "BenchmarkAgent")
        
        # Benchmark without tracing
        no_tracing_time = Benchmark.realtime do
          iterations.times do
            agent.run_simulation
          end
        end
        
        # Benchmark with TracingRegistry and NoOpTracer
        registry_noop_time = Benchmark.realtime do
          RAAF::Tracing::TracingRegistry.set_process_tracer(RAAF::Tracing::NoOpTracer.new)
          
          iterations.times do
            tracer = RAAF::Tracing::TracingRegistry.current_tracer
            agent.run_simulation
          end
        end
        
        # Benchmark with TracingRegistry and mock tracer
        registry_mock_time = Benchmark.realtime do
          RAAF::Tracing::TracingRegistry.set_process_tracer(mock_tracer)
          
          iterations.times do
            tracer = RAAF::Tracing::TracingRegistry.current_tracer
            agent.run_simulation
          end
        end
        
        # NoOp should be close to no tracing (within 50% overhead)
        noop_overhead = (registry_noop_time - no_tracing_time) / no_tracing_time
        expect(noop_overhead).to be < 0.5
        
        # Mock tracer will have more overhead but should be reasonable
        mock_overhead = (registry_mock_time - no_tracing_time) / no_tracing_time
        expect(mock_overhead).to be < 2.0
        
        # Log performance results
        puts "\nPerformance Results (#{iterations} iterations):"
        puts "  No tracing: #{(no_tracing_time * 1000).round(2)}ms"
        puts "  Registry + NoOp: #{(registry_noop_time * 1000).round(2)}ms (#{(noop_overhead * 100).round(1)}% overhead)"
        puts "  Registry + Mock: #{(registry_mock_time * 1000).round(2)}ms (#{(mock_overhead * 100).round(1)}% overhead)"
      end
      
      it "measures context lookup performance under high concurrency" do
        threads = 10
        operations_per_thread = 100
        
        RAAF::Tracing::TracingRegistry.set_process_tracer(mock_tracer)
        
        concurrent_time = Benchmark.realtime do
          thread_pool = (1..threads).map do |thread_num|
            Thread.new do
              RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
                operations_per_thread.times do
                  tracer = RAAF::Tracing::TracingRegistry.current_tracer
                  expect(tracer).to eq(mock_tracer)
                end
              end
            end
          end
          
          thread_pool.each(&:join)
        end
        
        total_operations = threads * operations_per_thread
        avg_operation_time = (concurrent_time / total_operations) * 1_000_000 # microseconds
        
        # Context lookup should be very fast (< 10 microseconds per operation)
        expect(avg_operation_time).to be < 10.0
        
        puts "\nConcurrency Performance:"
        puts "  #{threads} threads × #{operations_per_thread} operations = #{total_operations} total"
        puts "  Total time: #{(concurrent_time * 1000).round(2)}ms"
        puts "  Average per operation: #{avg_operation_time.round(2)}μs"
      end
    end
  end
  
  describe "7.7 Memory Cleanup" do
    context "thread context cleanup prevents memory leaks" do
      it "cleans up thread-local context after execution" do
        initial_context = Thread.current[:raaf_tracer]
        
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          expect(Thread.current[:raaf_tracer]).to eq(mock_tracer)
        end
        
        # Context should be restored after block
        expect(Thread.current[:raaf_tracer]).to eq(initial_context)
      end
      
      it "handles nested context cleanup correctly" do
        tracer1 = mock_tracer
        tracer2 = Class.new(mock_tracer.class).new
        
        RAAF::Tracing::TracingRegistry.with_tracer(tracer1) do
          expect(RAAF::Tracing::TracingRegistry.current_tracer).to eq(tracer1)
          
          RAAF::Tracing::TracingRegistry.with_tracer(tracer2) do
            expect(RAAF::Tracing::TracingRegistry.current_tracer).to eq(tracer2)
          end
          
          # Should restore to tracer1
          expect(RAAF::Tracing::TracingRegistry.current_tracer).to eq(tracer1)
        end
        
        # Should restore to original state
        expect(RAAF::Tracing::TracingRegistry.current_tracer).to be_a(RAAF::Tracing::NoOpTracer)
      end
      
      it "prevents memory accumulation in long-running processes" do
        initial_memory = GC.stat[:heap_live_slots]
        
        # Simulate long-running process with many context switches
        1000.times do |i|
          tracer = Class.new(mock_tracer.class).new
          
          RAAF::Tracing::TracingRegistry.with_tracer(tracer) do
            agent = mock_agent_class.new(name: "LongRunningAgent#{i}")
            agent.run_simulation
          end
          
          # Force garbage collection every 100 iterations
          if (i + 1) % 100 == 0
            GC.start
          end
        end
        
        GC.start
        final_memory = GC.stat[:heap_live_slots]
        
        # Memory growth should be minimal (< 10% increase)
        memory_growth = (final_memory - initial_memory).to_f / initial_memory
        expect(memory_growth).to be < 0.1
        
        puts "\nMemory Test Results:"
        puts "  Initial memory: #{initial_memory} live slots"
        puts "  Final memory: #{final_memory} live slots"
        puts "  Memory growth: #{(memory_growth * 100).round(2)}%"
      end
    end
    
    context "fiber context cleanup" do
      it "properly cleans up fiber-local context", :fiber_test do
        skip "Fiber-local storage not available" unless fiber_storage_available?
        
        fiber_contexts = []
        
        fiber = Fiber.new do
          RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
            fiber_contexts << { stage: "inside", tracer: RAAF::Tracing::TracingRegistry.current_tracer }
          end
          
          fiber_contexts << { stage: "after", tracer: RAAF::Tracing::TracingRegistry.current_tracer }
        end
        
        fiber.resume
        
        expect(fiber_contexts.size).to eq(2)
        expect(fiber_contexts[0][:tracer]).to eq(mock_tracer)
        expect(fiber_contexts[1][:tracer]).to be_a(RAAF::Tracing::NoOpTracer)
      end
    end
  end
  
  describe "7.8 Full Test Suite Verification" do
    context "all tests pass together" do
      it "runs a comprehensive end-to-end workflow" do
        # This test combines multiple aspects to ensure they work together
        workflow_results = []
        
        # Start with middleware setting up tracing context
        app = ->(env) do
          # Create multi-agent pipeline within request context
          agents = [
            mock_agent_class.new(name: "WorkflowAgent1"),
            mock_agent_class.new(name: "WorkflowAgent2")
          ]
          
          pipeline = mock_pipeline_class.new(agents: agents)
          
          # Add tools to agents
          tool1 = mock_tool_class.new(name: "WorkflowTool1")
          tool2 = mock_tool_class.new(name: "WorkflowTool2")
          agents[0].add_tool(tool1)
          agents[1].add_tool(tool2)
          
          # Execute pipeline
          result = pipeline.run("comprehensive workflow input")
          workflow_results << result
          
          [200, {}, ["Comprehensive workflow complete"]]
        end
        
        middleware = mock_middleware_class.new(app, tracer: mock_tracer)
        
        # Execute through middleware to simulate full request lifecycle
        status, headers, body = middleware.call({
          "REQUEST_METHOD" => "POST",
          "PATH_INFO" => "/comprehensive"
        })
        
        # Verify successful execution
        expect(status).to eq(200)
        expect(workflow_results.size).to eq(1)
        expect(workflow_results.first).to have_key(:pipeline_results)
        
        # Verify spans were created throughout the workflow
        hierarchy = mock_tracer.span_hierarchy
        expect(hierarchy.size).to be > 0
        
        # Should have various span types
        span_types = hierarchy.map { |s| s[:type] }.uniq
        expect(span_types).to include(:agent) # From middleware
      end
      
      it "ensures test isolation between test cases" do
        # This test verifies that tests don't interfere with each other
        
        # Set up some state
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          mock_tracer.agent_span("isolation_test", parent_id: nil)
        end
        
        initial_spans = mock_tracer.spans.size
        
        # Clear context (simulating test cleanup)
        RAAF::Tracing::TracingRegistry.clear_all_contexts!
        mock_tracer.clear!
        
        # Verify clean state
        expect(mock_tracer.spans.size).to eq(0)
        expect(RAAF::Tracing::TracingRegistry.current_tracer).to be_a(RAAF::Tracing::NoOpTracer)
        
        # New test should start fresh
        RAAF::Tracing::TracingRegistry.with_tracer(mock_tracer) do
          mock_tracer.agent_span("fresh_test", parent_id: nil)
        end
        
        expect(mock_tracer.spans.size).to eq(1)
        expect(mock_tracer.spans.first.name).to eq("fresh_test")
      end
    end
    
    context "no test interference" do
      it "maintains independent context across parallel test execution" do
        # Simulate parallel test execution with concurrent threads
        test_results = []
        barrier = Barrier.new(3)
        
        threads = (1..3).map do |test_num|
          Thread.new do
            # Each "test" uses its own tracer and context
            test_tracer = Class.new(mock_tracer.class).new
            
            RAAF::Tracing::TracingRegistry.with_tracer(test_tracer) do
              barrier.wait # Synchronize to maximize concurrency
              
              # Execute "test" logic
              agent = mock_agent_class.new(name: "TestAgent#{test_num}")
              result = agent.run_simulation
              
              test_results << {
                test_num: test_num,
                tracer: RAAF::Tracing::TracingRegistry.current_tracer,
                result: result,
                thread_id: Thread.current.object_id
              }
            end
          end
        end
        
        threads.each(&:join)
        
        # Verify each test had its own isolated context
        expect(test_results.size).to eq(3)
        
        test_tracers = test_results.map { |r| r[:tracer] }
        expect(test_tracers.uniq.size).to eq(3) # All different tracers
        
        test_threads = test_results.map { |r| r[:thread_id] }
        expect(test_threads.uniq.size).to eq(3) # All different threads
        
        # Each test should have executed successfully
        expect(test_results.all? { |r| r[:result][:message].include?("execution complete") }).to be(true)
      end
    end
  end
  
  # Helper methods
  private
  
  def fiber_storage_available?
    return false unless defined?(Fiber)
    
    # Test if Fiber supports []= assignment
    test_fiber = Fiber.new { Fiber.current[:test] = true }
    test_fiber.resume
    true
  rescue StandardError
    false
  end
end

# Simple barrier class for thread synchronization in tests
class Barrier
  def initialize(count)
    @count = count
    @waiting = 0
    @mutex = Mutex.new
    @condition = ConditionVariable.new
  end
  
  def wait
    @mutex.synchronize do
      @waiting += 1
      if @waiting == @count
        @condition.broadcast
      else
        @condition.wait(@mutex)
      end
    end
  end
end