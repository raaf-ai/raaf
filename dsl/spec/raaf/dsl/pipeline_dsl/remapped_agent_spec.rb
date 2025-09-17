# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RAAF::DSL::PipelineDSL::RemappedAgent do
  # Mock agent classes for testing
  let(:simple_agent_class) do
    Class.new do
      include RAAF::DSL::Pipelineable

      def self.name
        'SimpleAgent'
      end

      def self.required_fields
        [:data]
      end

      def self.provided_fields
        [:processed_data]
      end

      def self.requirements_met?(context)
        context.key?(:data) || context.key?('data')
      end

      def initialize(**context)
        @context = context
      end

      def run
        { processed_data: "processed_#{@context[:data]}" }
      end
    end
  end

  let(:company_enrichment_agent) do
    Class.new do
      include RAAF::DSL::Pipelineable

      def self.name
        'CompanyEnrichmentAgent'
      end

      def self.required_fields
        [:company]
      end

      def self.provided_fields
        [:enriched_company]
      end

      def self.requirements_met?(context)
        context.key?(:company) || context.key?('company')
      end

      def initialize(**context)
        @context = context
      end

      def run
        { enriched_company: { name: @context[:company][:name], enriched: true } }
      end
    end
  end

  let(:context) do
    ActiveSupport::HashWithIndifferentAccess.new({
      prospect: { name: 'Test Company' },
      search_results: ['result1', 'result2']
    })
  end

  describe '#initialize' do
    it 'creates a RemappedAgent with input mapping only' do
      remapped = described_class.new(
        company_enrichment_agent,
        input_mapping: { company: :prospect }
      )

      expect(remapped.agent_class).to eq(company_enrichment_agent)
      expect(remapped.input_mapping).to eq({ company: :prospect })
      expect(remapped.output_mapping).to eq({})
    end

    it 'creates a RemappedAgent with output mapping only' do
      remapped = described_class.new(
        simple_agent_class,
        output_mapping: { processed_data: :results }
      )

      expect(remapped.agent_class).to eq(simple_agent_class)
      expect(remapped.input_mapping).to eq({})
      expect(remapped.output_mapping).to eq({ processed_data: :results })
    end

    it 'creates a RemappedAgent with both input and output mapping' do
      remapped = described_class.new(
        company_enrichment_agent,
        input_mapping: { company: :prospect },
        output_mapping: { enriched_company: :enriched_prospect }
      )

      expect(remapped.input_mapping).to eq({ company: :prospect })
      expect(remapped.output_mapping).to eq({ enriched_company: :enriched_prospect })
    end
  end

  describe '#required_fields' do
    it 'returns mapped required fields for input remapping' do
      remapped = described_class.new(
        company_enrichment_agent,
        input_mapping: { company: :prospect }
      )

      # The agent requires :company, but the pipeline should provide :prospect
      expect(remapped.required_fields).to eq([:prospect])
    end

    it 'returns original fields when no input mapping' do
      remapped = described_class.new(
        simple_agent_class,
        output_mapping: { processed_data: :results }
      )

      expect(remapped.required_fields).to eq([:data])
    end

    it 'handles multiple mapped fields' do
      multi_requirement_agent = Class.new do
        include RAAF::DSL::Pipelineable

        def self.name
          'MultiRequirementAgent'
        end

        def self.required_fields
          [:company, :user, :config]
        end

        def self.provided_fields
          [:result]
        end
      end

      remapped = described_class.new(
        multi_requirement_agent,
        input_mapping: { company: :prospect, user: :current_user }
      )

      expect(remapped.required_fields).to include(:prospect, :current_user, :config)
    end
  end

  describe '#provided_fields' do
    it 'returns mapped provided fields for output remapping' do
      remapped = described_class.new(
        company_enrichment_agent,
        output_mapping: { enriched_company: :enriched_prospect }
      )

      expect(remapped.provided_fields).to eq([:enriched_prospect])
    end

    it 'returns original fields when no output mapping' do
      remapped = described_class.new(
        simple_agent_class,
        input_mapping: { data: :raw_data }
      )

      expect(remapped.provided_fields).to eq([:processed_data])
    end

    it 'handles multiple mapped output fields' do
      multi_output_agent = Class.new do
        include RAAF::DSL::Pipelineable

        def self.name
          'MultiOutputAgent'
        end

        def self.required_fields
          [:input]
        end

        def self.provided_fields
          [:results, :metadata, :summary]
        end
      end

      remapped = described_class.new(
        multi_output_agent,
        output_mapping: { results: :processed_results, metadata: :processing_info }
      )

      expect(remapped.provided_fields).to include(:processed_results, :processing_info, :summary)
    end
  end

  describe '#requirements_met?' do
    it 'checks requirements after input mapping is applied' do
      remapped = described_class.new(
        company_enrichment_agent,
        input_mapping: { company: :prospect }
      )

      context_with_prospect = { prospect: { name: 'Test' } }
      context_without_prospect = { other_data: 'value' }

      expect(remapped.requirements_met?(context_with_prospect)).to be true
      expect(remapped.requirements_met?(context_without_prospect)).to be false
    end
  end

  describe '#execute' do
    let(:agent_results) { [] }

    it 'applies input mapping before agent execution' do
      remapped = described_class.new(
        company_enrichment_agent,
        input_mapping: { company: :prospect }
      )

      result_context = remapped.execute(context, agent_results)

      # Should have enriched the company (mapped from prospect)
      expect(result_context[:enriched_company]).to eq({ name: 'Test Company', enriched: true })
    end

    it 'applies output mapping after agent execution' do
      test_context = { data: 'test_input' }
      remapped = described_class.new(
        simple_agent_class,
        output_mapping: { processed_data: :results }
      )

      result_context = remapped.execute(test_context, agent_results)

      # Output should be remapped from :processed_data to :results
      expect(result_context[:results]).to eq('processed_test_input')
      expect(result_context[:processed_data]).to be_nil
    end

    it 'applies both input and output mapping' do
      remapped = described_class.new(
        company_enrichment_agent,
        input_mapping: { company: :prospect },
        output_mapping: { enriched_company: :enriched_prospect }
      )

      result_context = remapped.execute(context, agent_results)

      # Input mapping: prospect -> company for agent
      # Output mapping: enriched_company -> enriched_prospect for pipeline
      expect(result_context[:enriched_prospect]).to eq({ name: 'Test Company', enriched: true })
      expect(result_context[:enriched_company]).to be_nil
    end

    it 'preserves unmapped fields in context' do
      test_context = {
        data: 'test_input',
        other_field: 'preserved_value',
        config: { setting: 'value' }
      }

      remapped = described_class.new(
        simple_agent_class,
        output_mapping: { processed_data: :results }
      )

      result_context = remapped.execute(test_context, agent_results)

      expect(result_context[:other_field]).to eq('preserved_value')
      expect(result_context[:config]).to eq({ setting: 'value' })
      expect(result_context[:results]).to eq('processed_test_input')
    end

    it 'handles ContextVariables objects' do
      context_vars = RAAF::DSL::ContextVariables.new(context)

      remapped = described_class.new(
        company_enrichment_agent,
        input_mapping: { company: :prospect }
      )

      result_context = remapped.execute(context_vars, agent_results)

      expect(result_context).to be_a(RAAF::DSL::ContextVariables)
      expect(result_context.get(:enriched_company)).to eq({ name: 'Test Company', enriched: true })
    end

    context 'with timeout and retry options' do
      it 'respects timeout configuration' do
        remapped = described_class.new(
          simple_agent_class,
          input_mapping: { data: :input },
          timeout: 1
        )

        # Create a slow agent that will timeout
        slow_agent = Class.new do
          include RAAF::DSL::Pipelineable

          def self.name
            'SlowAgent'
          end

          def self.required_fields
            [:data]
          end

          def self.provided_fields
            [:result]
          end

          def self.requirements_met?(context)
            true
          end

          def initialize(**context)
            @context = context
          end

          def run
            sleep(2) # This will cause timeout
            { result: 'done' }
          end
        end

        slow_remapped = described_class.new(slow_agent, timeout: 1)

        expect {
          slow_remapped.execute({ data: 'test' }, agent_results)
        }.to raise_error(Timeout::Error)
      end
    end
  end

  describe 'DSL operator integration' do
    it 'supports chaining with >>' do
      agent1 = simple_agent_class.with_mapping(output: { processed_data: :results })
      agent2 = simple_agent_class

      chained = agent1 >> agent2

      expect(chained).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
      expect(chained.first).to be_a(described_class)
      expect(chained.second).to eq(simple_agent_class)
    end

    it 'supports parallel execution with |' do
      agent1 = simple_agent_class.with_mapping(input: { data: :input1 })
      agent2 = simple_agent_class.with_mapping(input: { data: :input2 })

      parallel = agent1 | agent2

      expect(parallel).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
      expect(parallel.agents).to all(be_a(described_class))
    end

    it 'can be combined with other DSL methods' do
      remapped = simple_agent_class
        .with_mapping(input: { data: :raw_data })
        .timeout(30)
        .retry(3)

      expect(remapped).to be_a(described_class)
      expect(remapped.options[:timeout]).to eq(30)
      expect(remapped.options[:retry]).to eq(3)
    end
  end

  describe 'edge cases' do
    it 'handles empty mappings gracefully' do
      remapped = described_class.new(simple_agent_class)

      result_context = remapped.execute({ data: 'test' }, agent_results)

      expect(result_context[:processed_data]).to eq('processed_test')
    end

    it 'handles missing source fields in input mapping' do
      remapped = described_class.new(
        company_enrichment_agent,
        input_mapping: { company: :nonexistent_field }
      )

      # Should warn but not crash
      expect(RAAF.logger).to receive(:warn).with(/Input mapping failed/)

      result_context = remapped.execute({ other: 'data' }, agent_results)
      expect(result_context).to be_a(Hash)
    end

    it 'handles missing source fields in output mapping' do
      remapped = described_class.new(
        simple_agent_class,
        output_mapping: { nonexistent_field: :target }
      )

      result_context = remapped.execute({ data: 'test' }, agent_results)

      # Should have the original field, not the mapped one
      expect(result_context[:processed_data]).to eq('processed_test')
      expect(result_context[:target]).to be_nil
    end

    it 'preserves original context when agent execution fails' do
      failing_agent = Class.new do
        include RAAF::DSL::Pipelineable

        def self.name
          'FailingAgent'
        end

        def self.required_fields
          [:data]
        end

        def self.provided_fields
          [:result]
        end

        def self.requirements_met?(context)
          true
        end

        def initialize(**context)
          raise StandardError, 'Agent execution failed'
        end
      end

      remapped = described_class.new(failing_agent)

      expect {
        remapped.execute({ data: 'test' }, agent_results)
      }.to raise_error(StandardError, 'Agent execution failed')
    end
  end
end