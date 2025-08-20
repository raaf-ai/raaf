# frozen_string_literal: true

require 'spec_helper'
require 'raaf/dsl/pipeline_dsl/iterating_agent'
require 'raaf/dsl/pipeline_dsl/agent_introspection'

RSpec.describe RAAF::DSL::PipelineDSL::IteratingAgent do
  # Mock agent classes for testing
  let(:mock_agent_class) do
    Class.new do
      def self.name
        "MockAgent"
      end
      
      def self.required_fields
        [:current_item]
      end
      
      def self.provided_fields
        [:processed_item]
      end
      
      def self.requirements_met?(context)
        context.key?(:current_item)
      end
      
      def initialize(**context)
        @context = context
      end
      
      def run
        item = @context[:current_item]
        {
          processed_item: "processed_#{item}",
          success: true
        }
      end
    end
  end

  let(:failing_agent_class) do
    Class.new do
      def self.name
        "FailingAgent"
      end
      
      def self.required_fields
        [:current_item]
      end
      
      def self.provided_fields
        [:processed_item]
      end
      
      def self.requirements_met?(context)
        context.key?(:current_item)
      end
      
      def initialize(**context)
        @context = context
      end
      
      def run
        raise "Simulated failure"
      end
    end
  end

  let(:context) do
    {
      items: ["item1", "item2", "item3"],
      other_data: "preserved"
    }
  end

  describe '#initialize' do
    it 'creates an iterating agent with required parameters' do
      agent = described_class.new(mock_agent_class, :items)
      expect(agent.agent_class).to eq(mock_agent_class)
      expect(agent.field).to eq(:items)
      expect(agent.options).to eq({})
    end

    it 'accepts options including parallel flag' do
      agent = described_class.new(mock_agent_class, :items, parallel: true, timeout: 30)
      expect(agent.options[:timeout]).to eq(30)
      expect(agent.instance_variable_get(:@parallel)).to be true
    end
  end

  describe '#parallel' do
    it 'enables parallel execution' do
      agent = described_class.new(mock_agent_class, :items)
      expect(agent.instance_variable_get(:@parallel)).to be false
      
      agent.parallel
      expect(agent.instance_variable_get(:@parallel)).to be true
    end

    it 'returns self for method chaining' do
      agent = described_class.new(mock_agent_class, :items)
      expect(agent.parallel).to eq(agent)
    end
  end

  describe 'configuration methods' do
    let(:agent) { described_class.new(mock_agent_class, :items) }

    it 'supports timeout configuration' do
      agent.timeout(60)
      expect(agent.options[:timeout]).to eq(60)
    end

    it 'supports retry configuration' do
      agent.retry(3)
      expect(agent.options[:retry]).to eq(3)
    end

    it 'supports limit configuration' do
      agent.limit(10)
      expect(agent.options[:limit]).to eq(10)
    end

    it 'supports method chaining' do
      result = agent.timeout(30).retry(2).limit(5).parallel
      expect(result).to eq(agent)
      expect(agent.options[:timeout]).to eq(30)
      expect(agent.options[:retry]).to eq(2)
      expect(agent.options[:limit]).to eq(5)
      expect(agent.instance_variable_get(:@parallel)).to be true
    end
  end

  describe '#required_fields' do
    it 'includes the iteration field and wrapped agent fields' do
      agent = described_class.new(mock_agent_class, :items)
      required = agent.required_fields
      
      expect(required).to include(:items)
      expect(required).to include(:current_item)
    end
  end

  describe '#provided_fields' do
    it 'generates output field name and includes wrapped agent fields' do
      agent = described_class.new(mock_agent_class, :items)
      provided = agent.provided_fields
      
      expect(provided).to include(:processed_items)
      expect(provided).to include(:processed_item)
    end
  end

  describe '#requirements_met?' do
    let(:agent) { described_class.new(mock_agent_class, :items) }

    it 'returns true when iteration field exists and is enumerable' do
      expect(agent.requirements_met?(context)).to be true
    end

    it 'returns false when iteration field is missing' do
      context_without_field = { other_data: "test" }
      expect(agent.requirements_met?(context_without_field)).to be false
    end

    it 'returns false when iteration field is not enumerable' do
      context_with_non_array = { items: "not_an_array" }
      expect(agent.requirements_met?(context_with_non_array)).to be false
    end
  end

  describe '#execute - sequential processing' do
    let(:agent) { described_class.new(mock_agent_class, :items) }

    it 'processes items sequentially by default' do
      allow(RAAF.logger).to receive(:info)
      allow(RAAF.logger).to receive(:debug)
      
      result_context = agent.execute(context)
      
      expect(result_context[:processed_items]).to be_an(Array)
      expect(result_context[:processed_items].length).to eq(3)
      expect(result_context[:processed_items]).to include(
        hash_including(processed_item: "processed_item1"),
        hash_including(processed_item: "processed_item2"),
        hash_including(processed_item: "processed_item3")
      )
      expect(result_context[:other_data]).to eq("preserved")
    end

    it 'maintains order in sequential processing' do
      allow(RAAF.logger).to receive(:info)
      allow(RAAF.logger).to receive(:debug)
      
      result_context = agent.execute(context)
      results = result_context[:processed_items]
      
      expect(results[0]).to include(processed_item: "processed_item1")
      expect(results[1]).to include(processed_item: "processed_item2")
      expect(results[2]).to include(processed_item: "processed_item3")
    end

    it 'handles empty arrays gracefully' do
      empty_context = { items: [], other_data: "preserved" }
      allow(RAAF.logger).to receive(:info)
      
      result_context = agent.execute(empty_context)
      
      expect(result_context[:other_data]).to eq("preserved")
      expect(result_context[:processed_items]).to be_nil
    end

    it 'applies limit when specified' do
      agent.limit(2)
      allow(RAAF.logger).to receive(:info)
      allow(RAAF.logger).to receive(:debug)
      
      result_context = agent.execute(context)
      
      expect(result_context[:processed_items].length).to eq(2)
    end

    it 'handles individual item failures gracefully' do
      agent = described_class.new(failing_agent_class, :items)
      allow(RAAF.logger).to receive(:info)
      allow(RAAF.logger).to receive(:debug)
      allow(RAAF.logger).to receive(:error)
      
      result_context = agent.execute(context)
      
      expect(result_context[:processed_items]).to be_an(Array)
      expect(result_context[:processed_items].length).to eq(3)
      result_context[:processed_items].each do |result|
        expect(result).to include(error: true)
      end
    end
  end

  describe '#execute - parallel processing' do
    let(:agent) { described_class.new(mock_agent_class, :items, parallel: true) }

    it 'processes items in parallel when enabled' do
      allow(RAAF.logger).to receive(:info)
      allow(RAAF.logger).to receive(:debug)
      
      result_context = agent.execute(context)
      
      expect(result_context[:processed_items]).to be_an(Array)
      expect(result_context[:processed_items].length).to eq(3)
      
      # All items should be processed, though order may vary
      processed_values = result_context[:processed_items].map { |r| r[:processed_item] }
      expect(processed_values).to contain_exactly(
        "processed_item1",
        "processed_item2", 
        "processed_item3"
      )
    end

    it 'handles parallel execution failures gracefully' do
      agent = described_class.new(failing_agent_class, :items, parallel: true)
      allow(RAAF.logger).to receive(:info)
      allow(RAAF.logger).to receive(:debug)
      allow(RAAF.logger).to receive(:error)
      
      result_context = agent.execute(context)
      
      expect(result_context[:processed_items]).to be_an(Array)
      expect(result_context[:processed_items].length).to eq(3)
      result_context[:processed_items].each do |result|
        expect(result).to include(error: true)
      end
    end
  end

  describe 'DSL operators' do
    let(:agent) { described_class.new(mock_agent_class, :items) }
    let(:next_agent) { mock_agent_class }

    it 'supports chaining with >>' do
      chained = agent >> next_agent
      expect(chained).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
    end

    it 'supports parallel execution with |' do
      parallel = agent | next_agent
      expect(parallel).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
    end
  end

  describe 'field name generation' do
    it 'generates appropriate output field names' do
      companies_agent = described_class.new(mock_agent_class, :companies)
      expect(companies_agent.provided_fields).to include(:processed_companies)

      items_agent = described_class.new(mock_agent_class, :items)
      expect(items_agent.provided_fields).to include(:processed_items)

      markets_agent = described_class.new(mock_agent_class, :markets)
      expect(markets_agent.provided_fields).to include(:processed_markets)
    end

    it 'generates appropriate singular field names for context' do
      agent = described_class.new(mock_agent_class, :companies)
      
      # Test the private method indirectly by checking context preparation
      context = { companies: ["company1"] }
      allow(RAAF.logger).to receive(:info)
      allow(RAAF.logger).to receive(:debug)
      
      # Mock the agent creation to inspect the context
      expect(mock_agent_class).to receive(:new) do |**kwargs|
        expect(kwargs).to include(:current_company)
        expect(kwargs[:current_company]).to eq("company1")
        expect(kwargs).to include(:current_item)
        expect(kwargs).to include(:item_index)
        mock_agent_class.allocate
      end.and_call_original
      
      agent.execute(context)
    end
  end

  describe 'context preparation' do
    let(:agent) { described_class.new(mock_agent_class, :items) }

    it 'provides current_item and item_index to each agent execution' do
      allow(RAAF.logger).to receive(:info)
      allow(RAAF.logger).to receive(:debug)
      
      # Mock agent creation to inspect context
      call_count = 0
      expect(mock_agent_class).to receive(:new).exactly(3).times do |**kwargs|
        expect(kwargs).to include(:current_item)
        expect(kwargs).to include(:item_index)
        expect(kwargs[:item_index]).to eq(call_count)
        expect(kwargs[:current_item]).to eq("item#{call_count + 1}")
        expect(kwargs[:other_data]).to eq("preserved")
        call_count += 1
        mock_agent_class.allocate
      end.and_call_original
      
      agent.execute(context)
    end
  end

  describe 'integration with pipeline DSL' do
    it 'can be created from agent classes using .each_over()' do
      # This tests the integration with AgentIntrospection
      expect(mock_agent_class).to respond_to(:each_over)
      
      iterating_agent = mock_agent_class.each_over(:items)
      expect(iterating_agent).to be_a(described_class)
      expect(iterating_agent.field).to eq(:items)
    end

    it 'supports fluent configuration from agent classes' do
      iterating_agent = mock_agent_class.each_over(:items).parallel.timeout(30).retry(2)
      
      expect(iterating_agent).to be_a(described_class)
      expect(iterating_agent.instance_variable_get(:@parallel)).to be true
      expect(iterating_agent.options[:timeout]).to eq(30)
      expect(iterating_agent.options[:retry]).to eq(2)
    end
  end

  describe 'custom output field API' do
    it 'supports custom output field with to: syntax' do
      iterating_agent = mock_agent_class.each_over(:items, to: :enriched_items)
      
      expect(iterating_agent).to be_a(described_class)
      expect(iterating_agent.field).to eq(:items)
      expect(iterating_agent.instance_variable_get(:@custom_output_field)).to eq(:enriched_items)
    end

    it 'supports :from marker syntax' do
      iterating_agent = mock_agent_class.each_over(:from, :companies, to: :analyzed_companies)
      
      expect(iterating_agent).to be_a(described_class)
      expect(iterating_agent.field).to eq(:companies)
      expect(iterating_agent.instance_variable_get(:@custom_output_field)).to eq(:analyzed_companies)
    end

    it 'generates custom output field names in provided_fields' do
      iterating_agent = mock_agent_class.each_over(:items, to: :custom_results)
      provided = iterating_agent.provided_fields
      
      expect(provided).to include(:custom_results)
      expect(provided).not_to include(:processed_items)
    end

    it 'uses custom output field in execution' do
      agent = described_class.new(mock_agent_class, :items, to: :custom_output)
      allow(RAAF.logger).to receive(:info)
      allow(RAAF.logger).to receive(:debug)
      
      result_context = agent.execute(context)
      
      expect(result_context).to have_key(:custom_output)
      expect(result_context).not_to have_key(:processed_items)
      expect(result_context[:custom_output]).to be_an(Array)
      expect(result_context[:custom_output].length).to eq(3)
    end

    it 'maintains backward compatibility without to: option' do
      iterating_agent = mock_agent_class.each_over(:items)
      
      expect(iterating_agent.instance_variable_get(:@custom_output_field)).to be_nil
      expect(iterating_agent.provided_fields).to include(:processed_items)
    end

    it 'supports custom output field with fluent configuration' do
      iterating_agent = mock_agent_class.each_over(:items, to: :results).parallel.timeout(60)
      
      expect(iterating_agent.instance_variable_get(:@custom_output_field)).to eq(:results)
      expect(iterating_agent.instance_variable_get(:@parallel)).to be true
      expect(iterating_agent.options[:timeout]).to eq(60)
    end

    it 'raises error for invalid :from syntax' do
      expect {
        mock_agent_class.each_over(:from, :items)
      }.to raise_error(ArgumentError, /Invalid syntax: :from marker requires input field/)
    end

    it 'raises error for invalid argument patterns' do
      expect {
        mock_agent_class.each_over(:items, :invalid, :args)
      }.to raise_error(ArgumentError, /Invalid each_over syntax/)
    end

    it 'handles string symbols correctly for custom fields' do
      iterating_agent = mock_agent_class.each_over(:items, to: 'custom_field')
      
      expect(iterating_agent.instance_variable_get(:@custom_output_field)).to eq(:custom_field)
    end
  end

  describe 'custom field name API (as: option)' do
    it 'supports custom field name with as: syntax' do
      iterating_agent = mock_agent_class.each_over(:search_terms, as: :query)
      
      expect(iterating_agent).to be_a(described_class)
      expect(iterating_agent.field).to eq(:search_terms)
      expect(iterating_agent.instance_variable_get(:@custom_field_name)).to eq(:query)
    end

    it 'supports combination of as: and to: options' do
      iterating_agent = mock_agent_class.each_over(:companies, as: :target_company, to: :analyzed_companies)
      
      expect(iterating_agent.field).to eq(:companies)
      expect(iterating_agent.instance_variable_get(:@custom_field_name)).to eq(:target_company)
      expect(iterating_agent.instance_variable_get(:@custom_output_field)).to eq(:analyzed_companies)
    end

    it 'supports :from syntax with as: and to: options' do
      iterating_agent = mock_agent_class.each_over(:from, :search_terms, as: :query, to: :companies)
      
      expect(iterating_agent.field).to eq(:search_terms)
      expect(iterating_agent.instance_variable_get(:@custom_field_name)).to eq(:query)
      expect(iterating_agent.instance_variable_get(:@custom_output_field)).to eq(:companies)
    end

    it 'provides custom field name to agent context during execution' do
      agent = described_class.new(mock_agent_class, :search_terms, as: :query)
      allow(RAAF.logger).to receive(:info)
      allow(RAAF.logger).to receive(:debug)
      
      context = { search_terms: ["ruby programming", "rails tutorial"] }
      
      # Mock agent creation to inspect the context it receives
      call_count = 0
      expect(mock_agent_class).to receive(:new).exactly(2).times do |**kwargs|
        expect(kwargs).to include(:query)  # Custom field name
        expect(kwargs).to include(:current_item)  # Always provided
        expect(kwargs).to include(:item_index)
        expect(kwargs[:query]).to eq(context[:search_terms][call_count])
        call_count += 1
        mock_agent_class.allocate
      end.and_call_original
      
      agent.execute(context)
    end

    it 'uses default singularized field name when as: not provided' do
      agent = described_class.new(mock_agent_class, :companies)
      allow(RAAF.logger).to receive(:info)
      allow(RAAF.logger).to receive(:debug)
      
      context = { companies: ["company1"] }
      
      # Mock agent creation to inspect the default field name
      expect(mock_agent_class).to receive(:new) do |**kwargs|
        expect(kwargs).to include(:company)  # Singularized field name
        expect(kwargs).not_to include(:companies)  # Original field not included
        expect(kwargs).to include(:current_item)
        expect(kwargs[:company]).to eq("company1")
        mock_agent_class.allocate
      end.and_call_original
      
      agent.execute(context)
    end

    it 'supports fluent configuration with as: option' do
      iterating_agent = mock_agent_class.each_over(:items, as: :item).parallel.timeout(60).retry(3)
      
      expect(iterating_agent.instance_variable_get(:@custom_field_name)).to eq(:item)
      expect(iterating_agent.instance_variable_get(:@parallel)).to be true
      expect(iterating_agent.options[:timeout]).to eq(60)
      expect(iterating_agent.options[:retry]).to eq(3)
    end

    it 'handles string symbols correctly for as: option' do
      iterating_agent = mock_agent_class.each_over(:items, as: 'custom_item')
      
      expect(iterating_agent.instance_variable_get(:@custom_field_name)).to eq(:custom_item)
    end

    it 'provides both custom and default field names in context' do
      agent = described_class.new(mock_agent_class, :search_terms, as: :query)
      context = { search_terms: ["term1"] }
      
      # Test the private method indirectly
      item_context = agent.send(:prepare_item_context, "term1", context, 0)
      
      expect(item_context).to include(:query)
      expect(item_context).to include(:current_item)
      expect(item_context).to include(:item_index)
      expect(item_context[:query]).to eq("term1")
      expect(item_context[:current_item]).to eq("term1")
      expect(item_context[:item_index]).to eq(0)
    end

    it 'executes successfully with custom field names' do
      agent = described_class.new(mock_agent_class, :search_terms, as: :query, to: :companies)
      allow(RAAF.logger).to receive(:info)
      allow(RAAF.logger).to receive(:debug)
      
      context = { search_terms: ["ruby", "rails"] }
      result = agent.execute(context)
      
      expect(result).to have_key(:companies)  # Custom output field
      expect(result).not_to have_key(:processed_search_terms)  # Default not used
      expect(result[:companies]).to be_an(Array)
      expect(result[:companies].length).to eq(2)
    end
  end
end