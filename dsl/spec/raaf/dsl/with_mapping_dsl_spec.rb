# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'with_mapping DSL method' do
  # Create a test agent that includes Pipelineable
  let(:test_agent_class) do
    Class.new do
      include RAAF::DSL::Pipelineable

      def self.name
        'TestAgent'
      end

      def self.required_fields
        [:input_data]
      end

      def self.provided_fields
        [:output_data]
      end

      def initialize(**context)
        @context = context
      end

      def run
        { output_data: "processed_#{@context[:input_data]}" }
      end
    end
  end

  describe '.with_mapping' do
    context 'with shorthand syntax (input only)' do
      it 'creates a RemappedAgent with input mapping' do
        remapped = test_agent_class.with_mapping(input_data: :raw_data)

        expect(remapped).to be_a(RAAF::DSL::PipelineDSL::RemappedAgent)
        expect(remapped.agent_class).to eq(test_agent_class)
        expect(remapped.input_mapping).to eq({ input_data: :raw_data })
        expect(remapped.output_mapping).to eq({})
      end

      it 'supports multiple field mappings in shorthand syntax' do
        remapped = test_agent_class.with_mapping(
          input_data: :raw_data,
          config: :settings
        )

        expect(remapped.input_mapping).to eq({
          input_data: :raw_data,
          config: :settings
        })
        expect(remapped.output_mapping).to eq({})
      end
    end

    context 'with full syntax (input and output)' do
      it 'creates a RemappedAgent with both input and output mapping' do
        remapped = test_agent_class.with_mapping(
          input: { input_data: :raw_data },
          output: { output_data: :results }
        )

        expect(remapped).to be_a(RAAF::DSL::PipelineDSL::RemappedAgent)
        expect(remapped.input_mapping).to eq({ input_data: :raw_data })
        expect(remapped.output_mapping).to eq({ output_data: :results })
      end

      it 'supports input-only mapping with full syntax' do
        remapped = test_agent_class.with_mapping(
          input: { input_data: :raw_data }
        )

        expect(remapped.input_mapping).to eq({ input_data: :raw_data })
        expect(remapped.output_mapping).to eq({})
      end

      it 'supports output-only mapping with full syntax' do
        remapped = test_agent_class.with_mapping(
          output: { output_data: :results }
        )

        expect(remapped.input_mapping).to eq({})
        expect(remapped.output_mapping).to eq({ output_data: :results })
      end

      it 'handles empty mappings gracefully' do
        remapped = test_agent_class.with_mapping(
          input: {},
          output: {}
        )

        expect(remapped.input_mapping).to eq({})
        expect(remapped.output_mapping).to eq({})
      end
    end

    context 'edge cases' do
      it 'handles nil mapping config' do
        remapped = test_agent_class.with_mapping(nil)

        expect(remapped.input_mapping).to eq({})
        expect(remapped.output_mapping).to eq({})
      end

      it 'handles empty mapping config' do
        remapped = test_agent_class.with_mapping({})

        expect(remapped.input_mapping).to eq({})
        expect(remapped.output_mapping).to eq({})
      end
    end

    context 'DSL integration' do
      it 'can be chained with other DSL methods' do
        remapped = test_agent_class
          .with_mapping(input_data: :raw_data)
          .timeout(30)

        expect(remapped).to be_a(RAAF::DSL::PipelineDSL::RemappedAgent)
        expect(remapped.options[:timeout]).to eq(30)
        expect(remapped.input_mapping).to eq({ input_data: :raw_data })
      end

      it 'can be combined with retry and limit' do
        remapped = test_agent_class
          .with_mapping(
            input: { input_data: :raw_data },
            output: { output_data: :results }
          )
          .retry(3)
          .limit(100)

        expect(remapped.options[:retry]).to eq(3)
        expect(remapped.options[:limit]).to eq(100)
      end

      it 'supports chaining with the >> operator' do
        agent1 = test_agent_class.with_mapping(input_data: :raw_data)
        agent2 = test_agent_class

        chained = agent1 >> agent2

        expect(chained).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
        expect(chained.first).to be_a(RAAF::DSL::PipelineDSL::RemappedAgent)
        expect(chained.second).to eq(test_agent_class)
      end

      it 'supports parallel execution with the | operator' do
        agent1 = test_agent_class.with_mapping(input_data: :source1)
        agent2 = test_agent_class.with_mapping(input_data: :source2)

        parallel = agent1 | agent2

        expect(parallel).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
        expect(parallel.agents).to all(be_a(RAAF::DSL::PipelineDSL::RemappedAgent))
      end
    end
  end

  describe 'real-world usage patterns' do
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

        def initialize(**context)
          @context = context
        end

        def run
          {
            enriched_company: {
              name: @context[:company][:name],
              enriched: true,
              data_source: 'external_api'
            }
          }
        end
      end
    end

    it 'supports the original use case from the problem statement' do
      # This matches the exact syntax from the user's request
      remapped = company_enrichment_agent.with_mapping(company: :prospect)

      expect(remapped).to be_a(RAAF::DSL::PipelineDSL::RemappedAgent)
      expect(remapped.input_mapping).to eq({ company: :prospect })
      expect(remapped.output_mapping).to eq({})

      # Verify it can be used in pipeline chains
      another_agent = test_agent_class
      chained = test_agent_class >> remapped >> another_agent

      expect(chained).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
    end

    it 'supports complex enterprise scenarios' do
      # Scenario: Data processor that expects different field names
      data_processor = Class.new do
        include RAAF::DSL::Pipelineable

        def self.name
          'DataProcessor'
        end

        def self.required_fields
          [:dataset, :configuration, :user_context]
        end

        def self.provided_fields
          [:processed_results, :metadata]
        end
      end

      # Map multiple input fields and rename outputs
      remapped = data_processor.with_mapping(
        input: {
          dataset: :raw_data,
          configuration: :processing_settings,
          user_context: :current_user
        },
        output: {
          processed_results: :analysis_data,
          metadata: :processing_info
        }
      )

      expect(remapped.input_mapping).to eq({
        dataset: :raw_data,
        configuration: :processing_settings,
        user_context: :current_user
      })

      expect(remapped.output_mapping).to eq({
        processed_results: :analysis_data,
        metadata: :processing_info
      })
    end
  end
end