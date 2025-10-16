# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl"

RSpec.describe RAAF::DSL::PipelineDSL::WrapperDSL do
  # Set mock API key for testing (tests don't actually call OpenAI)
  before(:all) do
    ENV['OPENAI_API_KEY'] = 'test-api-key-for-wrapper-hooks-spec'
  end

  after(:all) do
    ENV.delete('OPENAI_API_KEY')
  end

  # Create test agent with hooks
  let(:test_agent_class) do
    # Capture class reference for use in hooks
    klass = Class.new(RAAF::DSL::Agent) do
      include RAAF::DSL::Hooks::AgentHooks

      agent_name "TestAgent"

      context do
        required :input_data
        output :output_data
      end

      # Track hook executions
      class_variable_set(:@@hooks_executed, [])

      def self.hooks_executed
        class_variable_get(:@@hooks_executed)
      end

      def self.reset_hooks
        class_variable_set(:@@hooks_executed, [])
      end

      def run
        { output_data: "processed" }
      end
    end

    # Register hooks with captured class reference
    klass.before_execute do |context:, wrapper_type:, wrapper_config:, timestamp:, **|
      klass.hooks_executed << {
        hook: :before_execute,
        wrapper_type: wrapper_type,
        timestamp: timestamp,
        context_keys: context.keys,
        wrapper_config: wrapper_config
      }

      # Modify context to verify mutability
      context[:before_execute_ran] = true
    end

    klass.after_execute do |context:, wrapper_type:, wrapper_config:, timestamp:, duration_ms:, **|
      klass.hooks_executed << {
        hook: :after_execute,
        wrapper_type: wrapper_type,
        timestamp: timestamp,
        duration_ms: duration_ms,
        context_keys: context.keys,
        wrapper_config: wrapper_config
      }

      # Modify context to verify mutability
      context[:after_execute_ran] = true
    end

    klass
  end

  before do
    test_agent_class.reset_hooks
  end

  describe "Hook Execution Timing" do
    context "with ChainedAgent wrapper" do
      let(:chained_agent) { RAAF::DSL::PipelineDSL::ChainedAgent.new(test_agent_class, test_agent_class) }
      let(:context) { { input_data: "test" } }

      before do
        allow_any_instance_of(test_agent_class).to receive(:run).and_return({ output_data: "processed" })
      end

      it "executes before_execute hook before wrapper execution" do
        chained_agent.execute(context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:hook]).to eq(:before_execute)
        expect(context[:before_execute_ran]).to be true
      end

      it "executes after_execute hook after wrapper execution" do
        result = chained_agent.execute(context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.last[:hook]).to eq(:after_execute)
        expect(result[:after_execute_ran]).to be true
      end

      it "executes hooks in correct order" do
        chained_agent.execute(context)

        hooks = test_agent_class.hooks_executed
        # ChainedAgent wraps the entire chain in one set of hooks
        expect(hooks.map { |h| h[:hook] }).to eq([:before_execute, :after_execute])
      end

      it "provides wrapper_type parameter" do
        chained_agent.execute(context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_type]).to eq(:chained)
      end

      it "provides timestamp parameter" do
        chained_agent.execute(context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:timestamp]).to be_a(Time)
      end

      it "provides duration_ms in after_execute" do
        chained_agent.execute(context)

        hooks = test_agent_class.hooks_executed
        after_hook = hooks.find { |h| h[:hook] == :after_execute }
        expect(after_hook[:duration_ms]).to be_a(Numeric)
        expect(after_hook[:duration_ms]).to be >= 0
      end

      it "provides wrapper_config parameter" do
        chained_agent.execute(context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_config]).to be_a(Hash)
        expect(hooks.first[:wrapper_config]).to have_key(:first_agent)
        expect(hooks.first[:wrapper_config]).to have_key(:second_agent)
      end
    end
  end

  describe "Wrapper Type Verification" do
    let(:context) { { input_data: "test" } }

    before do
      allow_any_instance_of(test_agent_class).to receive(:run).and_return({ output_data: "processed" })
    end

    context "with BatchedAgent" do
      let(:batched_agent) { RAAF::DSL::PipelineDSL::BatchedAgent.new(test_agent_class, 2, array_field: :items) }
      let(:batched_context) { { input_data: "test", items: [{ id: 1 }, { id: 2 }] } }

      it "provides wrapper_type :batched" do
        batched_agent.execute(batched_context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_type]).to eq(:batched)
      end

      it "includes chunk_size in wrapper_config" do
        batched_agent.execute(batched_context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_config][:chunk_size]).to eq(2)
        expect(hooks.first[:wrapper_config][:input_field]).to eq(:items)
        expect(hooks.first[:wrapper_config][:output_field]).to eq(:items)
      end
    end

    context "with ChainedAgent" do
      let(:chained_agent) { RAAF::DSL::PipelineDSL::ChainedAgent.new(test_agent_class, test_agent_class) }

      it "provides wrapper_type :chained" do
        chained_agent.execute(context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_type]).to eq(:chained)
      end
    end

    context "with ParallelAgents" do
      let(:parallel_agents) { RAAF::DSL::PipelineDSL::ParallelAgents.new([test_agent_class, test_agent_class]) }

      it "provides wrapper_type :parallel" do
        parallel_agents.execute(context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_type]).to eq(:parallel)
      end

      it "includes agents count in wrapper_config" do
        parallel_agents.execute(context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_config][:agent_count]).to eq(2)
      end
    end

    context "with RemappedAgent" do
      let(:remapped_agent) do
        RAAF::DSL::PipelineDSL::RemappedAgent.new(
          test_agent_class,
          input_mapping: { input_data: :source_data },  # Map source_data → input_data
          output_mapping: { result_data: :output_data }  # Map output_data → result_data
        )
      end

      it "provides wrapper_type :remapped" do
        result_context = remapped_agent.execute({ source_data: "test" })

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_type]).to eq(:remapped)
      end

      it "includes mappings in wrapper_config" do
        remapped_agent.execute({ source_data: "test" })

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_config][:input_mapping]).to eq({ input_data: :source_data })
        expect(hooks.first[:wrapper_config][:output_mapping]).to eq({ result_data: :output_data })
      end
    end

    context "with ConfiguredAgent" do
      let(:configured_agent) do
        RAAF::DSL::PipelineDSL::ConfiguredAgent.new(
          test_agent_class,
          { max_retries: 3, timeout: 30 }
        )
      end

      it "provides wrapper_type :configured" do
        configured_agent.execute(context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_type]).to eq(:configured)
      end

      it "includes configuration in wrapper_config" do
        configured_agent.execute(context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_config][:options]).to eq({ max_retries: 3, timeout: 30 })
      end
    end

    context "with IteratingAgent" do
      let(:iterating_agent) do
        RAAF::DSL::PipelineDSL::IteratingAgent.new(
          test_agent_class,
          :items
        )
      end
      let(:iteration_context) { { input_data: "test", items: [{ id: 1 }, { id: 2 }] } }

      it "provides wrapper_type :iterating" do
        iterating_agent.execute(iteration_context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_type]).to eq(:iterating)
      end

      it "includes field in wrapper_config" do
        iterating_agent.execute(iteration_context)

        hooks = test_agent_class.hooks_executed
        expect(hooks.first[:wrapper_config][:field]).to eq(:items)
      end
    end
  end

  describe "Context Mutability" do
    let(:chained_agent) { RAAF::DSL::PipelineDSL::ChainedAgent.new(test_agent_class, test_agent_class) }
    let(:context) { { input_data: "test" } }

    before do
      allow_any_instance_of(test_agent_class).to receive(:run).and_return({ output_data: "processed" })
    end

    it "allows before_execute hook to modify context" do
      result = chained_agent.execute(context)

      expect(result[:before_execute_ran]).to be true
    end

    it "allows after_execute hook to modify context" do
      result = chained_agent.execute(context)

      expect(result[:after_execute_ran]).to be true
    end

    it "preserves context modifications through wrapper execution" do
      result = chained_agent.execute(context)

      expect(result[:before_execute_ran]).to be true
      expect(result[:after_execute_ran]).to be true
      expect(result[:input_data]).to eq("test")
      expect(result[:output_data]).to eq("processed")
    end
  end

  describe "Hook Parameters Validation" do
    let(:chained_agent) { RAAF::DSL::PipelineDSL::ChainedAgent.new(test_agent_class, test_agent_class) }
    let(:context) { { input_data: "test" } }

    before do
      allow_any_instance_of(test_agent_class).to receive(:run).and_return({ output_data: "processed" })
    end

    it "provides context parameter with all required keys" do
      chained_agent.execute(context)

      hooks = test_agent_class.hooks_executed
      expect(hooks.first[:context_keys]).to include(:input_data)
    end

    it "provides wrapper_type as symbol" do
      chained_agent.execute(context)

      hooks = test_agent_class.hooks_executed
      expect(hooks.first[:wrapper_type]).to be_a(Symbol)
    end

    it "provides wrapper_config as hash" do
      chained_agent.execute(context)

      hooks = test_agent_class.hooks_executed
      expect(hooks.first[:wrapper_config]).to be_a(Hash)
    end

    it "provides timestamp as Time object" do
      chained_agent.execute(context)

      hooks = test_agent_class.hooks_executed
      expect(hooks.first[:timestamp]).to be_a(Time)
    end

    it "provides duration_ms in after_execute as positive number" do
      chained_agent.execute(context)

      hooks = test_agent_class.hooks_executed
      after_hook = hooks.find { |h| h[:hook] == :after_execute }
      expect(after_hook[:duration_ms]).to be_a(Numeric)
      expect(after_hook[:duration_ms]).to be >= 0
    end
  end

  describe "Hook Guard Clauses" do
    let(:batched_agent_class) do
      klass = Class.new(RAAF::DSL::Agent) do
        include RAAF::DSL::Hooks::AgentHooks

        agent_name "BatchedTestAgent"

        context do
          required :items
          output :processed_items
        end

        class_variable_set(:@@hook_executions, 0)

        def self.hook_executions
          class_variable_get(:@@hook_executions)
        end

        def self.reset
          class_variable_set(:@@hook_executions, 0)
        end

        def run
          { processed_items: ["item1", "item2"] }
        end
      end

      # Register hook with captured class reference
      klass.before_execute do |context:, wrapper_type:, **|
        # Only run for batched execution
        next unless wrapper_type == :batched

        klass.class_variable_set(
          :@@hook_executions,
          klass.class_variable_get(:@@hook_executions) + 1
        )
      end

      klass
    end

    before do
      batched_agent_class.reset
    end

    it "allows guard clauses to skip hook execution for non-matching wrapper types" do
      # Execute with non-batched wrapper
      chained = RAAF::DSL::PipelineDSL::ChainedAgent.new(batched_agent_class, batched_agent_class)
      allow_any_instance_of(batched_agent_class).to receive(:run).and_return({ processed_items: ["item1"] })

      chained.execute({ items: [{ id: 1 }] })

      # Hook should not have executed for non-batched wrapper
      expect(batched_agent_class.hook_executions).to eq(0)
    end

    it "executes hook for matching wrapper type" do
      # Execute with batched wrapper
      batched = RAAF::DSL::PipelineDSL::BatchedAgent.new(
        batched_agent_class,
        2,
        array_field: :items
      )
      allow_any_instance_of(batched_agent_class).to receive(:run).and_return({ processed_items: ["item1"] })

      batched.execute({ items: [{ id: 1 }, { id: 2 }] })

      # Hook should have executed once for batched wrapper
      expect(batched_agent_class.hook_executions).to eq(1)
    end
  end

  describe "Multiple Hook Execution" do
    let(:multi_hook_agent_class) do
      klass = Class.new(RAAF::DSL::Agent) do
        include RAAF::DSL::Hooks::AgentHooks

        agent_name "MultiHookAgent"

        context do
          required :input_data
          output :output_data
        end

        class_variable_set(:@@execution_order, [])

        def self.execution_order
          class_variable_get(:@@execution_order)
        end

        def self.reset
          class_variable_set(:@@execution_order, [])
        end

        def run
          self.class.execution_order << :run
          { output_data: "processed" }
        end
      end

      # Register hooks with captured class reference
      klass.before_execute do |**|
        klass.execution_order << :before_1
      end

      klass.before_execute do |**|
        klass.execution_order << :before_2
      end

      klass.after_execute do |**|
        klass.execution_order << :after_1
      end

      klass.after_execute do |**|
        klass.execution_order << :after_2
      end

      klass
    end

    before do
      multi_hook_agent_class.reset
    end

    it "executes multiple hooks in order" do
      chained = RAAF::DSL::PipelineDSL::ChainedAgent.new(multi_hook_agent_class, multi_hook_agent_class)
      allow_any_instance_of(multi_hook_agent_class).to receive(:run).and_call_original

      chained.execute({ input_data: "test" })

      order = multi_hook_agent_class.execution_order
      # ChainedAgent wraps entire chain in one set of hooks
      # Hooks fire once, then both agent instances run sequentially
      expect(order).to eq([
        :before_1, :before_2, :run, :run, :after_1, :after_2
      ])
    end
  end
end
