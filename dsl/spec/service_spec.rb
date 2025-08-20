# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RAAF::DSL::Service do
  # Test service implementation
  let(:test_service_class) do
    Class.new(RAAF::DSL::Service) do
      context do
        required :name
        optional age: 25, city: "Unknown"
      end

      def self.provided_fields
        [:processed_name, :metadata]
      end

      def call
        {
          processed_name: name.upcase,
          metadata: { age: age, city: city, processed_at: Time.current }
        }
      end
    end
  end

  let(:simple_service_class) do
    Class.new(RAAF::DSL::Service) do
      def call
        { result: "simple" }
      end
    end
  end

  describe '#initialize' do
    it 'initializes with context arguments' do
      service = test_service_class.new(name: "John", age: 30)
      
      expect(service.name).to eq("John")
      expect(service.age).to eq(30)
      expect(service.city).to eq("Unknown") # default value
    end

    it 'applies defaults from context configuration' do
      service = test_service_class.new(name: "Jane")
      
      expect(service.name).to eq("Jane")
      expect(service.age).to eq(25) # default from context
      expect(service.city).to eq("Unknown") # default from context
    end

    it 'raises error for missing required context' do
      expect {
        test_service_class.new(age: 30) # missing required 'name'
      }.to raise_error(ArgumentError, /Missing required context: name/)
    end
  end

  describe '#call' do
    it 'raises NotImplementedError for abstract base service' do
      service = described_class.new
      
      expect { service.call }.to raise_error(NotImplementedError, /must implement #call method/)
    end

    it 'executes the service logic' do
      service = test_service_class.new(name: "test", age: 35, city: "NYC")
      
      result = service.call
      
      expect(result[:processed_name]).to eq("TEST")
      expect(result[:metadata][:age]).to eq(35)
      expect(result[:metadata][:city]).to eq("NYC")
    end
  end

  describe 'context access' do
    let(:service) { test_service_class.new(name: "Bob", age: 40) }

    it 'provides direct access to context variables' do
      expect(service.name).to eq("Bob")
      expect(service.age).to eq(40)
      expect(service.city).to eq("Unknown")
    end

    it 'provides context accessor methods' do
      expect(service.get(:name)).to eq("Bob")
      expect(service.has?(:name)).to be_truthy
      expect(service.has?(:nonexistent)).to be_falsey
    end

    it 'provides context as hash' do
      context_hash = service.context_hash
      
      expect(context_hash[:name]).to eq("Bob")
      expect(context_hash[:age]).to eq(40)
      expect(context_hash[:city]).to eq("Unknown")
    end
  end

  describe 'class methods' do
    describe '.required_fields' do
      it 'returns required fields from context configuration' do
        expect(test_service_class.required_fields).to include(:name)
        expect(test_service_class.required_fields).to include(:age) # has default
        expect(test_service_class.required_fields).to include(:city) # has default
      end

      it 'returns empty array for service without context config' do
        expect(simple_service_class.required_fields).to eq([])
      end
    end

    describe '.externally_required_fields' do
      it 'returns only required fields without defaults' do
        expect(test_service_class.externally_required_fields).to eq([:name])
      end
    end

    describe '.provided_fields' do
      it 'returns fields provided by the service' do
        expect(test_service_class.provided_fields).to eq([:processed_name, :metadata])
      end

      it 'returns empty array by default' do
        expect(simple_service_class.provided_fields).to eq([])
      end
    end

    describe '.requirements_met?' do
      it 'returns true when all requirements are met' do
        context = { name: "test", age: 25, city: "NYC" }
        expect(test_service_class.requirements_met?(context)).to be_truthy
      end

      it 'returns true when required fields with defaults are missing' do
        context = { name: "test" } # age and city have defaults
        expect(test_service_class.requirements_met?(context)).to be_truthy
      end

      it 'returns false when externally required fields are missing' do
        context = { age: 25, city: "NYC" } # missing required 'name'
        expect(test_service_class.requirements_met?(context)).to be_falsey
      end
    end
  end

  describe 'pipeline integration' do
    it 'includes PipelineIntegration module' do
      expect(described_class.ancestors).to include(RAAF::DSL::PipelineIntegration)
    end

    it 'supports chaining operator' do
      chain = test_service_class >> simple_service_class
      expect(chain).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
    end

    it 'supports parallel operator' do
      parallel = test_service_class | simple_service_class
      expect(parallel).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
    end

    it 'supports iterator pattern' do
      iterator = test_service_class.each_over(:items)
      expect(iterator).to be_a(RAAF::DSL::PipelineDSL::IteratingAgent)
    end

    it 'supports configuration methods' do
      configured = test_service_class.timeout(30)
      expect(configured).to be_a(RAAF::DSL::PipelineDSL::ConfiguredAgent)
    end
  end

  describe 'string representation' do
    let(:service) { test_service_class.new(name: "Test") }

    it 'provides service name' do
      expect(service.service_name).to match(/Service$/)
    end

    it 'provides detailed string representation' do
      service_string = service.to_s
      expect(service_string).to include(service.class.name)
      expect(service_string).to include("context_keys")
    end
  end

  describe 'context configuration DSL' do
    let(:advanced_service_class) do
      Class.new(RAAF::DSL::Service) do
        context do
          required :product, :company
          optional max_results: 10, timeout: 30
        end

        def call
          {
            product_name: product.name,
            company_name: company.name,
            config: { max_results: max_results, timeout: timeout }
          }
        end
      end
    end

    it 'handles complex context requirements' do
      product = double("Product", name: "Test Product")
      company = double("Company", name: "Test Company")
      
      service = advanced_service_class.new(product: product, company: company)
      result = service.call
      
      expect(result[:product_name]).to eq("Test Product")
      expect(result[:company_name]).to eq("Test Company")
      expect(result[:config][:max_results]).to eq(10)
      expect(result[:config][:timeout]).to eq(30)
    end
  end

  describe 'error handling' do
    let(:failing_service_class) do
      Class.new(RAAF::DSL::Service) do
        context do
          required :input
        end

        def call
          raise StandardError, "Service failed"
        end
      end
    end

    it 'propagates service execution errors' do
      service = failing_service_class.new(input: "test")
      
      expect { service.call }.to raise_error(StandardError, "Service failed")
    end

    it 'validates context during initialization' do
      expect {
        failing_service_class.new # missing required input
      }.to raise_error(ArgumentError, /Missing required context: input/)
    end
  end

  describe 'inheritance' do
    let(:base_service_class) do
      Class.new(RAAF::DSL::Service) do
        context do
          optional timeout: 60
        end

        def call
          { base: "called", timeout: timeout }
        end
      end
    end

    let(:derived_service_class) do
      Class.new(base_service_class) do
        context do
          required :name
          optional retries: 3
        end

        def call
          result = super
          result.merge(name: name, retries: retries, derived: "called")
        end
      end
    end

    it 'inherits context configuration from parent' do
      service = derived_service_class.new(name: "test")
      result = service.call
      
      expect(result[:base]).to eq("called")
      expect(result[:derived]).to eq("called")
      expect(result[:name]).to eq("test")
      expect(result[:timeout]).to eq(60) # inherited default
      expect(result[:retries]).to eq(3) # own default
    end

    it 'maintains separate field requirements' do
      # Base class only needs timeout (has default)
      expect(base_service_class.externally_required_fields).to eq([])
      
      # Derived class requires name
      expect(derived_service_class.externally_required_fields).to eq([:name])
    end
  end
end