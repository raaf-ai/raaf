# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Parameter Remapping Integration', type: :integration do
  # Define test agents that simulate the real-world use case
  let(:prospect_data_gatherer) do
    Class.new(RAAF::DSL::Agent) do
      def self.name
        'ProspectDataGatherer'
      end

      def self.required_fields
        [:prospect_id]
      end

      def self.provided_fields
        [:prospect]
      end

      def self.requirements_met?(context)
        context.key?(:prospect_id)
      end

      def initialize(**context)
        @context = context
      end

      def run
        {
          prospect: {
            id: @context[:prospect_id],
            name: 'Test Company Inc',
            industry: 'Technology',
            size: 'Medium'
          }
        }
      end
    end
  end

  let(:prospect_search) do
    Class.new(RAAF::DSL::Agent) do
      def self.name
        'ProspectSearch'
      end

      def self.required_fields
        [:prospect]
      end

      def self.provided_fields
        [:prospect, :search_metadata]
      end

      def self.requirements_met?(context)
        context.key?(:prospect)
      end

      def initialize(**context)
        @context = context
      end

      def run
        # Enhance the prospect with search results
        enhanced_prospect = @context[:prospect].dup
        enhanced_prospect[:contacts] = [
          { name: 'John Doe', role: 'CEO' },
          { name: 'Jane Smith', role: 'CTO' }
        ]

        {
          prospect: enhanced_prospect,
          search_metadata: {
            search_time: Time.now,
            sources: ['linkedin', 'company_website']
          }
        }
      end
    end
  end

  let(:company_generic_enrichment) do
    Class.new(RAAF::DSL::Agent) do
      def self.name
        'CompanyGenericEnrichment'
      end

      def self.required_fields
        [:company]
      end

      def self.provided_fields
        [:enriched_company]
      end

      def self.requirements_met?(context)
        context.key?(:company)
      end

      def initialize(**context)
        @context = context
      end

      def run
        company = @context[:company]
        {
          enriched_company: {
            id: company[:id],
            name: company[:name],
            industry: company[:industry],
            size: company[:size],
            # Add enrichment data
            financial_data: {
              revenue: '10M-50M',
              growth_rate: '15%'
            },
            technology_stack: ['Ruby', 'PostgreSQL', 'AWS'],
            enriched_at: Time.now
          }
        }
      end
    end
  end

  let(:prospect_scoring) do
    Class.new(RAAF::DSL::Agent) do
      def self.name
        'ProspectScoring'
      end

      def self.required_fields
        [:prospect]
      end

      def self.provided_fields
        [:prospect_score]
      end

      def self.requirements_met?(context)
        context.key?(:prospect) && context[:prospect].is_a?(Hash)
      end

      def initialize(**context)
        @context = context
      end

      def run
        prospect = @context[:prospect]

        # Calculate score based on enriched data
        base_score = 50
        base_score += 20 if prospect[:financial_data]
        base_score += 15 if prospect[:technology_stack]
        base_score += 10 if prospect[:contacts]&.any?

        {
          prospect_score: {
            overall_score: base_score,
            breakdown: {
              company_data: prospect[:financial_data] ? 20 : 0,
              tech_match: prospect[:technology_stack] ? 15 : 0,
              contact_availability: prospect[:contacts]&.any? ? 10 : 0
            },
            scored_at: Time.now
          }
        }
      end
    end
  end

  describe 'ProspectEnrichmentPipeline with parameter remapping' do
    let(:pipeline_class) do
      # Create pipeline class that uses parameter remapping
      Class.new(RAAF::Pipeline) do
        # Use parameter remapping to reuse CompanyGenericEnrichment
        # It expects :company but receives :prospect from previous step
        flow prospect_data_gatherer >>
             prospect_search >>
             company_generic_enrichment.with_mapping(
               input: { company: :prospect },
               output: { enriched_company: :prospect }
             ) >>
             prospect_scoring

        context do
          required :prospect_id
        end
      end
    end

    before do
      # Stub the pipeline class to use our test agents
      stub_const('ProspectDataGatherer', prospect_data_gatherer)
      stub_const('ProspectSearch', prospect_search)
      stub_const('CompanyGenericEnrichment', company_generic_enrichment)
      stub_const('ProspectScoring', prospect_scoring)
    end

    it 'successfully executes pipeline with parameter remapping' do
      pipeline = pipeline_class.new(prospect_id: 123)

      result = pipeline.run

      expect(result[:success]).to be true

      # Verify the prospect was enriched by the company enrichment agent
      expect(result[:prospect]).to be_a(Hash)
      expect(result[:prospect][:name]).to eq('Test Company Inc')
      expect(result[:prospect][:financial_data]).to be_present
      expect(result[:prospect][:technology_stack]).to be_present
      expect(result[:prospect][:enriched_at]).to be_present

      # Verify scoring used the enriched prospect
      expect(result[:prospect_score]).to be_a(Hash)
      expect(result[:prospect_score][:overall_score]).to eq(95) # 50 + 20 + 15 + 10
      expect(result[:prospect_score][:breakdown][:company_data]).to eq(20)
      expect(result[:prospect_score][:breakdown][:tech_match]).to eq(15)
    end

    it 'validates pipeline correctly with parameter remapping' do
      # Pipeline validation should pass despite the parameter remapping
      expect { pipeline_class.new(prospect_id: 123) }.not_to raise_error
    end

    it 'fails validation when required fields are missing' do
      expect {
        pipeline_class.new(wrong_param: 'value')
      }.to raise_error(ArgumentError, /prospect_id/)
    end
  end

  describe 'Complex pipeline with multiple remappings' do
    let(:data_loader) do
      Class.new(RAAF::DSL::Agent) do
        def self.name
          'DataLoader'
        end

        def self.required_fields
          [:source]
        end

        def self.provided_fields
          [:raw_data]
        end

        def self.requirements_met?(context)
          context.key?(:source)
        end

        def initialize(**context)
          @context = context
        end

        def run
          {
            raw_data: {
              customers: [
                { name: 'Customer A', type: 'enterprise' },
                { name: 'Customer B', type: 'startup' }
              ],
              metrics: { total: 2, active: 2 }
            }
          }
        end
      end
    end

    let(:data_processor) do
      Class.new(RAAF::DSL::Agent) do
        def self.name
          'DataProcessor'
        end

        def self.required_fields
          [:input_data, :config]
        end

        def self.provided_fields
          [:processed_data]
        end

        def self.requirements_met?(context)
          context.key?(:input_data) && context.key?(:config)
        end

        def initialize(**context)
          @context = context
        end

        def run
          data = @context[:input_data]
          config = @context[:config]

          {
            processed_data: {
              filtered_customers: data[:customers].select { |c| c[:type] == config[:filter] },
              summary: "Processed #{data[:customers].length} customers"
            }
          }
        end
      end
    end

    let(:report_generator) do
      Class.new(RAAF::DSL::Agent) do
        def self.name
          'ReportGenerator'
        end

        def self.required_fields
          [:data]
        end

        def self.provided_fields
          [:report]
        end

        def self.requirements_met?(context)
          context.key?(:data)
        end

        def initialize(**context)
          @context = context
        end

        def run
          data = @context[:data]
          {
            report: {
              title: 'Customer Analysis Report',
              content: data[:summary],
              customer_count: data[:filtered_customers]&.length || 0,
              generated_at: Time.now
            }
          }
        end
      end
    end

    let(:complex_pipeline) do
      Class.new(RAAF::Pipeline) do
        flow data_loader >>
             data_processor.with_mapping(
               input: { input_data: :raw_data, config: :processing_config },
               output: { processed_data: :analysis_results }
             ) >>
             report_generator.with_mapping(
               input: { data: :analysis_results }
             )

        context do
          required :source
          optional processing_config: { filter: 'enterprise' }
        end
      end
    end

    it 'handles multiple parameter remappings in sequence' do
      pipeline = complex_pipeline.new(
        source: 'database',
        processing_config: { filter: 'enterprise' }
      )

      result = pipeline.run

      expect(result[:success]).to be true
      expect(result[:report]).to be_a(Hash)
      expect(result[:report][:title]).to eq('Customer Analysis Report')
      expect(result[:report][:customer_count]).to eq(1) # Only enterprise customers
      expect(result[:analysis_results]).to be_present
    end
  end

  describe 'Error handling in parameter remapping' do
    let(:failing_enrichment) do
      Class.new(RAAF::DSL::Agent) do
        def self.name
          'FailingEnrichment'
        end

        def self.required_fields
          [:company]
        end

        def self.provided_fields
          [:enriched_company]
        end

        def self.requirements_met?(context)
          context.key?(:company)
        end

        def initialize(**context)
          raise StandardError, 'Enrichment service unavailable'
        end
      end
    end

    it 'propagates errors from remapped agents' do
      pipeline_class = Class.new(RAAF::Pipeline) do
        flow prospect_data_gatherer >>
             failing_enrichment.with_mapping(input: { company: :prospect })

        context do
          required :prospect_id
        end
      end

      pipeline = pipeline_class.new(prospect_id: 123)

      expect {
        pipeline.run
      }.to raise_error(StandardError, 'Enrichment service unavailable')
    end
  end

  describe 'Performance with parameter remapping' do
    it 'does not significantly impact performance' do
      simple_pipeline = Class.new(RAAF::Pipeline) do
        flow prospect_data_gatherer >> prospect_search

        context do
          required :prospect_id
        end
      end

      remapped_pipeline = Class.new(RAAF::Pipeline) do
        flow prospect_data_gatherer >>
             prospect_search.with_mapping(
               input: { prospect: :prospect },
               output: { prospect: :prospect }
             )

        context do
          required :prospect_id
        end
      end

      # Measure execution time for both pipelines
      simple_time = Benchmark.realtime do
        10.times { simple_pipeline.new(prospect_id: 123).run }
      end

      remapped_time = Benchmark.realtime do
        10.times { remapped_pipeline.new(prospect_id: 123).run }
      end

      # Remapped pipeline should not be more than 20% slower
      expect(remapped_time).to be < (simple_time * 1.2)
    end
  end
end