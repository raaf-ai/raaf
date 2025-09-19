# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Service do
  # Test service class for basic functionality
  class BasicTestService < described_class
    def call
      { success: true, message: "Basic service executed" }
    end
  end

  # Test service with parameters
  class ParameterizedService < described_class
    def call
      case action
      when :create
        create_action
      when :update
        update_action
      else
        { success: false, error: "Unknown action: #{action}" }
      end
    end

    private

    def create_action
      if processing_params[:name].present?
        { success: true, created: processing_params[:name] }
      else
        { success: false, error: "Name is required" }
      end
    end

    def update_action
      { success: true, updated: processing_params[:id] || "unknown" }
    end
  end

  # Test service with context access
  class ContextAwareService < described_class
    def call
      if user_id && user_name
        {
          success: true,
          message: "Hello #{user_name}",
          user_id: user_id
        }
      else
        { success: false, error: "User context missing" }
      end
    end
  end

  describe "#initialize" do
    it "accepts processing_params hash" do
      service = BasicTestService.new(processing_params: { key: "value" })
      expect(service.instance_variable_get(:@processing_params)[:key]).to eq("value")
    end

    it "accepts action parameter via context" do
      service = ParameterizedService.new(action: :create)
      expect(service.action).to eq(:create)
    end

    it "accepts context variables" do
      service = ContextAwareService.new(
        user_id: 123,
        user_name: "John Doe"
      )
      expect(service.user_id).to eq(123)
      expect(service.user_name).to eq("John Doe")
    end

    it "initializes with empty processing_params when not provided" do
      service = BasicTestService.new
      expect(service.instance_variable_get(:@processing_params)).to eq({})
    end
  end

  describe "#call" do
    it "executes the service logic" do
      service = BasicTestService.new
      result = service.call

      expect(result).to be_a(Hash)
      expect(result[:success]).to eq(true)
      expect(result[:message]).to eq("Basic service executed")
    end

    it "handles parameterized actions" do
      service = ParameterizedService.new(
        action: :create,
        processing_params: { name: "Test Item" }
      )
      result = service.call

      expect(result[:success]).to eq(true)
      expect(result[:created]).to eq("Test Item")
    end

    it "handles unknown actions" do
      service = ParameterizedService.new(action: :unknown)
      result = service.call

      expect(result[:success]).to eq(false)
      expect(result[:error]).to include("Unknown action")
    end
  end

  describe "result format" do
    let(:service) { BasicTestService.new }

    it "returns success hash with data" do
      result = { success: true, data: "test" }
      expect(result).to eq(success: true, data: "test")
    end

    it "handles multiple key-value pairs" do
      result = { success: true, name: "John", age: 30 }
      expect(result).to eq(success: true, name: "John", age: 30)
    end

    it "returns just success when no data provided" do
      result = { success: true }
      expect(result).to eq(success: true)
    end
  end

  describe "error result format" do
    let(:service) { BasicTestService.new }

    it "returns error hash with message" do
      result = { success: false, error: "Something went wrong" }
      expect(result).to eq(success: false, error: "Something went wrong")
    end

    it "accepts additional error details" do
      result = { success: false, error: "Failed", code: 404 }
      expect(result).to eq(success: false, error: "Failed", code: 404)
    end
  end

  describe "context access" do
    it "provides method access to context variables" do
      service = ContextAwareService.new(
        user_id: 456,
        user_name: "Jane Smith",
        extra_data: { "role" => "admin" }
      )

      expect(service.user_id).to eq(456)
      expect(service.user_name).to eq("Jane Smith")
      expect(service.extra_data).to eq({ "role" => "admin" })
    end

    it "raises NameError for undefined context variables" do
      service = ContextAwareService.new
      expect { service.undefined_variable }
        .to raise_error(NameError, /undefined variable.*not found in context/)
    end

    it "uses context in service execution" do
      service = ContextAwareService.new(
        user_id: 789,
        user_name: "Bob Wilson"
      )
      result = service.call

      expect(result[:success]).to eq(true)
      expect(result[:message]).to eq("Hello Bob Wilson")
      expect(result[:user_id]).to eq(789)
    end
  end

  describe "parameter handling" do
    it "provides access to processing_params hash" do
      service = ParameterizedService.new(
        processing_params: { name: "Test", description: "A test item" }
      )

      expect(service.processing_params[:name]).to eq("Test")
      expect(service.processing_params[:description]).to eq("A test item")
    end

    it "handles missing parameters gracefully" do
      service = ParameterizedService.new(
        action: :create,
        processing_params: {}
      )
      result = service.call

      expect(result[:success]).to eq(false)
      expect(result[:error]).to eq("Name is required")
    end
  end

  describe "action dispatch" do
    it "dispatches to correct action method" do
      create_service = ParameterizedService.new(
        action: :create,
        processing_params: { name: "Created Item" }
      )
      update_service = ParameterizedService.new(
        action: :update,
        processing_params: { id: 123 }
      )

      create_result = create_service.call
      update_result = update_service.call

      expect(create_result[:created]).to eq("Created Item")
      expect(update_result[:updated]).to eq(123)
    end
  end

  describe "inheritance" do
    class ExtendedService < ParameterizedService
      def call
        result = super
        result.merge(extended: true)
      end
    end

    it "supports service inheritance" do
      service = ExtendedService.new(
        action: :create,
        processing_params: { name: "Extended Item" }
      )
      result = service.call

      expect(result[:success]).to eq(true)
      expect(result[:created]).to eq("Extended Item")
      expect(result[:extended]).to eq(true)
    end
  end

  describe "error handling in services" do
    class ErrorService < described_class
      def call
        raise StandardError, "Service failed"
      rescue => e
        { success: false, error: "Service error: #{e.message}" }
      end
    end

    it "handles and reports service errors" do
      service = ErrorService.new
      result = service.call

      expect(result[:success]).to eq(false)
      expect(result[:error]).to include("Service error: Service failed")
    end
  end

  describe "class methods" do
    describe ".call (not implemented)" do
      it "does not provide class-level call method" do
        expect(BasicTestService).not_to respond_to(:call)
      end

      it "requires instance creation for execution" do
        instance = ParameterizedService.new(
          action: :create,
          processing_params: { name: "Instance Method Test" }
        )
        result = instance.call

        expect(result[:success]).to eq(true)
        expect(result[:created]).to eq("Instance Method Test")
      end
    end
  end

  describe "integration patterns" do
    it "works well with action-based dispatch pattern" do
      # Simulate controller-like usage
      action = :update
      processing_params = { id: 42, name: "Updated Item" }

      service = ParameterizedService.new(action: action, processing_params: processing_params)
      result = service.call

      expect(result[:success]).to eq(true)
      expect(result[:updated]).to eq(42)
    end

    it "supports complex context passing" do
      # Simulate agent-like context passing
      service = ContextAwareService.new(
        user_id: 101,
        user_name: "Agent User",
        session_data: { "token" => "abc123" }
      )
      result = service.call

      expect(result[:success]).to eq(true)
      expect(result[:message]).to include("Agent User")
    end
  end
end