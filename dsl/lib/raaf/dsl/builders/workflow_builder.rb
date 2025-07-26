# frozen_string_literal: true

module RAAF
  module DSL
    ##
    # Workflow builder for DSL-based workflow construction
    #
    # Provides a fluent interface for building complex multi-agent workflows
    # using declarative syntax with support for conditional flows, parallel
    # execution, and advanced workflow patterns.
    #
    class WorkflowBuilder
      include RAAF::Logger

      @@count = 0

      # @return [String] Workflow name
      attr_reader :workflow_name

      # @return [Hash] Workflow configuration
      attr_reader :config

      # @return [Hash] Workflow agents
      attr_reader :agents

      # @return [Array<Hash>] Workflow flows
      attr_reader :flows

      ##
      # Initialize workflow builder
      #
      # @param name [String] Workflow name
      #
      def initialize(name = nil)
        @workflow_name = name
        @config = {}
        @agents = {}
        @flows = []
        @conditions = {}
        @variables = {}
        @hooks = {}
        @@count += 1
      end

      ##
      # Set workflow name
      #
      # @param name [String] Workflow name
      #
      def name(name)
        @workflow_name = name
      end

      ##
      # Set workflow description
      #
      # @param description [String] Workflow description
      #
      def description(description)
        @config[:description] = description
      end

      ##
      # Set workflow version
      #
      # @param version [String] Workflow version
      #
      def version(version)
        @config[:version] = version
      end

      ##
      # Set workflow timeout
      #
      # @param timeout [Integer] Timeout in seconds
      #
      def timeout(timeout)
        @config[:timeout] = timeout
      end

      ##
      # Set workflow retry policy
      #
      # @param policy [Hash] Retry policy
      #
      def retry_policy(**policy)
        @config[:retry_policy] = policy
      end

      ##
      # Define an agent within the workflow
      #
      # @param name [Symbol] Agent name
      # @param options [Hash] Agent options
      # @param block [Proc] Agent definition block
      #
      def agent(name, **options, &block)
        if block_given?
          builder = AgentBuilder.new(name.to_s)
          builder.instance_eval(&block)
          @agents[name] = builder.build
        else
          @agents[name] = options[:agent] || options
        end
      end

      ##
      # Define workflow flow
      #
      # @param block [Proc] Flow definition block
      #
      def flow(&block)
        flow_builder = FlowBuilder.new(self)
        flow_builder.instance_eval(&block)
        @flows = flow_builder.flows
      end

      ##
      # Define parallel execution
      #
      # @param agents [Array<Symbol>] Agent names to execute in parallel
      # @param options [Hash] Parallel execution options
      #
      def parallel(*agents, **options)
        @flows << {
          type: :parallel,
          agents: agents,
          options: options
        }
      end

      ##
      # Define sequential execution
      #
      # @param agents [Array<Symbol>] Agent names to execute sequentially
      # @param options [Hash] Sequential execution options
      #
      def sequential(*agents, **options)
        @flows << {
          type: :sequential,
          agents: agents,
          options: options
        }
      end

      ##
      # Define conditional execution
      #
      # @param condition [Proc] Condition block
      # @param options [Hash] Conditional execution options
      #
      def conditional(condition, **options, &block)
        conditional_builder = ConditionalBuilder.new(condition, options)
        conditional_builder.instance_eval(&block)
        @flows << conditional_builder.build
      end

      ##
      # Define loop execution
      #
      # @param condition [Proc] Loop condition
      # @param options [Hash] Loop options
      #
      def loop(condition, **options, &block)
        loop_builder = LoopBuilder.new(condition, options)
        loop_builder.instance_eval(&block)
        @flows << loop_builder.build
      end

      ##
      # Define workflow variable
      #
      # @param name [Symbol] Variable name
      # @param value [Object] Variable value
      #
      def variable(name, value)
        @variables[name] = value
      end

      ##
      # Define workflow condition
      #
      # @param name [Symbol] Condition name
      # @param condition [Proc] Condition block
      #
      def condition(name, &condition)
        @conditions[name] = condition
      end

      ##
      # Define before hook
      #
      # @param block [Proc] Before hook block
      #
      def before(&block)
        @hooks[:before] = block
      end

      ##
      # Define after hook
      #
      # @param block [Proc] After hook block
      #
      def after(&block)
        @hooks[:after] = block
      end

      ##
      # Define error handler
      #
      # @param block [Proc] Error handler block
      #
      def on_error(&block)
        @hooks[:error] = block
      end

      ##
      # Define completion handler
      #
      # @param block [Proc] Completion handler block
      #
      def on_completion(&block)
        @hooks[:completion] = block
      end

      ##
      # Build the workflow
      #
      # @return [Workflow] Configured workflow
      #
      def build
        validate_configuration!

        workflow = RAAF::Workflow.new(
          name: @workflow_name,
          **@config
        )

        # Add agents
        @agents.each do |name, agent|
          workflow.add_agent(name, agent)
        end

        # Add flows
        @flows.each do |flow|
          workflow.add_flow(flow)
        end

        # Add variables
        @variables.each do |name, value|
          workflow.set_variable(name, value)
        end

        # Add conditions
        @conditions.each do |name, condition|
          workflow.add_condition(name, condition)
        end

        # Add hooks
        @hooks.each do |event, hook|
          case event
          when :before
            workflow.before_execution(&hook)
          when :after
            workflow.after_execution(&hook)
          when :error
            workflow.on_error(&hook)
          when :completion
            workflow.on_completion(&hook)
          end
        end

        log_info("Workflow built successfully", workflow_name: @workflow_name, agents: @agents.size)
        workflow
      end

      ##
      # Get builder statistics
      #
      # @return [Hash] Builder statistics
      def statistics
        {
          name: @workflow_name,
          agents_count: @agents.size,
          flows_count: @flows.size,
          conditions_count: @conditions.size,
          variables_count: @variables.size,
          hooks_count: @hooks.size
        }
      end

      ##
      # Get total count of workflows built
      #
      # @return [Integer] Total count
      def self.count
        @@count
      end

      ##
      # Reset count
      #
      def self.reset_count!
        @@count = 0
      end

      private

      def validate_configuration!
        errors = []

        errors << "Workflow name is required" unless @workflow_name
        errors << "At least one agent is required" if @agents.empty?
        errors << "At least one flow is required" if @flows.empty?

        # Validate agents exist in flows
        @flows.each do |flow|
          case flow[:type]
          when :parallel, :sequential
            flow[:agents].each do |agent_name|
              errors << "Agent '#{agent_name}' not found in workflow" unless @agents.key?(agent_name)
            end
          end
        end

        raise DSL::ValidationError, errors.join(", ") if errors.any?
      end
    end

    ##
    # Builder for defining workflow flows between agents
    #
    # This inner class handles the construction of workflow flows, defining
    # how agents connect and hand off work to each other. It provides a
    # fluent interface for building complex agent interaction patterns.
    #
    # @example Sequential flow
    #   flow.start_with(:agent1)
    #   flow.from(:agent1) { to :agent2 }
    #   flow.from(:agent2) { to :agent3 }
    #
    # @example Conditional flow
    #   flow.from(:agent1) do
    #     to :agent2, when: :condition1
    #     to :agent3, when: :condition2
    #     default :agent4
    #   end
    #
    # @api private
    class FlowBuilder
      attr_reader :flows

      def initialize(workflow_builder)
        @workflow_builder = workflow_builder
        @flows = []
        @current_flow = nil
      end

      def start_with(agent_name)
        @flows << {
          type: :start,
          agent: agent_name
        }
      end

      def from(agent_name, &block)
        @current_flow = {
          type: :transition,
          from: agent_name,
          transitions: []
        }

        instance_eval(&block) if block_given?
        @flows << @current_flow
      end

      def to(agent_name, **options)
        return unless @current_flow

        @current_flow[:transitions] << {
          to: agent_name,
          condition: options[:if],
          unless: options[:unless],
          options: options.except(:if, :unless)
        }
      end

      def end_with(agent_name)
        @flows << {
          type: :end,
          agent: agent_name
        }
      end

      def fork(options = {}, &block)
        fork_builder = ForkBuilder.new
        fork_builder.instance_eval(&block)

        @flows << {
          type: :fork,
          branches: fork_builder.branches,
          options: options
        }
      end

      def join(agents, **options)
        @flows << {
          type: :join,
          agents: agents,
          options: options
        }
      end
    end

    ##
    # Builder for parallel agent execution (fork/join)
    #
    # This inner class handles the construction of parallel execution flows
    # where multiple agents can run concurrently. It supports both fire-and-forget
    # parallel execution and synchronized join operations.
    #
    # @example Basic fork
    #   fork.branch(:agent1)
    #   fork.branch(:agent2)
    #   fork.branch(:agent3)
    #
    # @example Fork with join
    #   fork.branch(:data_agent)
    #   fork.branch(:analysis_agent)
    #   fork.join(:summary_agent)
    #
    # @api private
    class ForkBuilder
      attr_reader :branches

      def initialize
        @branches = []
      end

      def branch(name, &block)
        branch_builder = BranchBuilder.new(name)
        branch_builder.instance_eval(&block)
        @branches << branch_builder.build
      end
    end

    ##
    # Builder for individual branches within parallel execution
    #
    # This inner class constructs individual branches that execute within
    # a fork operation. Each branch can contain multiple sequential steps
    # that run independently of other branches.
    #
    # @example Single-step branch
    #   branch(:data_processing) do
    #     step :data_agent
    #   end
    #
    # @example Multi-step branch
    #   branch(:analysis_pipeline) do
    #     step :fetch_agent
    #     step :transform_agent
    #     step :analyze_agent
    #   end
    #
    # @api private
    class BranchBuilder
      def initialize(name)
        @name = name
        @steps = []
      end

      def step(agent_name, **options)
        @steps << {
          agent: agent_name,
          options: options
        }
      end

      def build
        {
          name: @name,
          steps: @steps
        }
      end
    end

    ##
    # Builder for conditional workflow execution
    #
    # This inner class handles the construction of conditional flows where
    # different agents or sequences execute based on runtime conditions.
    # It supports if-then-else logic within workflows.
    #
    # @example Simple conditional
    #   conditional(:high_priority?) do
    #     then { step :urgent_agent }
    #     else { step :normal_agent }
    #   end
    #
    # @example Complex conditional with multiple steps
    #   conditional(:needs_analysis?) do
    #     then do
    #       step :data_agent
    #       step :analysis_agent
    #       step :report_agent
    #     end
    #     else do
    #       step :summary_agent
    #     end
    #   end
    #
    # @api private
    class ConditionalBuilder
      def initialize(condition, options)
        @condition = condition
        @options = options
        @then_steps = []
        @else_steps = []
      end

      def then(&block)
        @then_builder = ConditionalStepBuilder.new
        @then_builder.instance_eval(&block)
        @then_steps = @then_builder.steps
      end

      def else(&block)
        @else_builder = ConditionalStepBuilder.new
        @else_builder.instance_eval(&block)
        @else_steps = @else_builder.steps
      end

      def build
        {
          type: :conditional,
          condition: @condition,
          then_steps: @then_steps,
          else_steps: @else_steps,
          options: @options
        }
      end
    end

    ##
    # Builder for steps within conditional branches
    #
    # This inner class constructs the sequence of steps that execute within
    # either the 'then' or 'else' branch of a conditional. It supports both
    # sequential and parallel step execution within conditional branches.
    #
    # @example Sequential steps
    #   execute :agent1
    #   execute :agent2
    #   execute :agent3
    #
    # @example Mixed sequential and parallel
    #   execute :setup_agent
    #   parallel :data_agent1, :data_agent2, :data_agent3
    #   execute :summary_agent
    #
    # @api private
    class ConditionalStepBuilder
      attr_reader :steps

      def initialize
        @steps = []
      end

      def execute(agent_name, **options)
        @steps << {
          type: :execute,
          agent: agent_name,
          options: options
        }
      end

      def parallel(*agents, **options)
        @steps << {
          type: :parallel,
          agents: agents,
          options: options
        }
      end

      def sequential(*agents, **options)
        @steps << {
          type: :sequential,
          agents: agents,
          options: options
        }
      end
    end

    ##
    # Builder for loop-based workflow execution
    #
    # This inner class handles the construction of loops within workflows,
    # allowing agents to execute repeatedly based on conditions. It supports
    # both while-style loops and iterative processing patterns.
    #
    # @example Simple loop
    #   loop(:has_more_data?) do
    #     step :process_agent
    #   end
    #
    # @example Multi-step loop
    #   loop(:needs_refinement?) do
    #     step :analyze_agent
    #     step :refine_agent
    #     step :validate_agent
    #   end
    #
    # @example Loop with max iterations
    #   loop(:continue_processing?, max_iterations: 10) do
    #     step :iteration_agent
    #   end
    #
    # @api private
    class LoopBuilder
      def initialize(condition, options)
        @condition = condition
        @options = options
        @steps = []
      end

      def step(agent_name, **options)
        @steps << {
          agent: agent_name,
          options: options
        }
      end

      def parallel(*agents, **options)
        @steps << {
          type: :parallel,
          agents: agents,
          options: options
        }
      end

      def sequential(*agents, **options)
        @steps << {
          type: :sequential,
          agents: agents,
          options: options
        }
      end

      def build
        {
          type: :loop,
          condition: @condition,
          steps: @steps,
          options: @options
        }
      end
    end
  end
end
