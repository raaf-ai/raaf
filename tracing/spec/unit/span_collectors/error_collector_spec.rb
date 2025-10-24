# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing::SpanCollectors::ErrorCollector do
  let(:collector) { described_class.new }

  describe "DSL declarations" do
    it "declares custom span attributes with lambdas" do
      custom_attrs = described_class.instance_variable_get(:@span_custom)
      expect(custom_attrs).to have_key(:has_errors)
      expect(custom_attrs).to have_key(:error_count)
      expect(custom_attrs).to have_key(:first_error_type)
    end

    it "declares result attributes" do
      result_attrs = described_class.instance_variable_get(:@result_custom)
      expect(result_attrs).to have_key(:recovery_status)
      expect(result_attrs).to have_key(:error_details)
    end
  end

  describe "#collect_attributes (error tracking)" do
    let(:component) do
      double("Component",
        class: double("ComponentClass", name: "TestAgent")
      )
    end

    context "with no errors" do
      before do
        allow(component).to receive(:respond_to?).and_return(false)
      end

      it "marks has_errors as false" do
        attributes = collector.collect_attributes(component)
        has_errors_key = attributes.keys.find { |k| k.end_with?(".has_errors") }
        expect(attributes[has_errors_key]).to eq("false")
      end

      it "sets error_count to 0" do
        attributes = collector.collect_attributes(component)
        error_count_key = attributes.keys.find { |k| k.end_with?(".error_count") }
        expect(attributes[error_count_key]).to eq("0")
      end
    end

    context "with errors tracked" do
      before do
        allow(component).to receive(:respond_to?).and_return(false)
        allow(component).to receive(:respond_to?).with(:get_errors).and_return(true)
        allow(component).to receive(:respond_to?).with(:get_error_count).and_return(true)

        errors = [
          { type: "RateLimitError", message: "Rate limit exceeded", timestamp: "2025-10-24T10:00:00Z" },
          { type: "TimeoutError", message: "Request timeout", timestamp: "2025-10-24T10:00:05Z" }
        ]
        allow(component).to receive(:get_errors).and_return(errors)
        allow(component).to receive(:get_error_count).and_return(2)
      end

      it "marks has_errors as true" do
        attributes = collector.collect_attributes(component)
        has_errors_key = attributes.keys.find { |k| k.end_with?(".has_errors") }
        expect(attributes[has_errors_key]).to eq("true")
      end

      it "captures error count" do
        attributes = collector.collect_attributes(component)
        error_count_key = attributes.keys.find { |k| k.end_with?(".error_count") }
        expect(attributes[error_count_key]).to eq("2")
      end

      it "captures first error type" do
        attributes = collector.collect_attributes(component)
        first_error_key = attributes.keys.find { |k| k.end_with?(".first_error_type") }
        expect(attributes[first_error_key]).to eq("RateLimitError")
      end
    end
  end

  describe "#collect_result (error recovery tracking)" do
    let(:component) do
      double("Component",
        class: double("ComponentClass", name: "TestAgent")
      )
    end

    context "with successful execution (no errors)" do
      let(:result) { { success: true } }

      it "sets recovery_status to success" do
        attributes = collector.collect_result(component, result)
        expect(attributes["result.recovery_status"]).to eq("success")
      end

      it "includes empty error_details" do
        attributes = collector.collect_result(component, result)
        expect(attributes["result.error_details"]).to eq({})
      end
    end

    context "with exception result" do
      let(:error) { RuntimeError.new("Operation failed") }

      it "sets recovery_status to failed" do
        attributes = collector.collect_result(component, error)
        expect(attributes["result.recovery_status"]).to eq("failed")
      end

      it "captures error type" do
        attributes = collector.collect_result(component, error)
        error_details = attributes["result.error_details"]
        expect(error_details["error_type"]).to eq("RuntimeError")
      end

      it "captures error message" do
        attributes = collector.collect_result(component, error)
        error_details = attributes["result.error_details"]
        expect(error_details["error_message"]).to eq("Operation failed")
      end
    end

    context "with retry tracking in result" do
      let(:result) do
        {
          success: true,
          recovery_attempt: 3,
          total_retry_delay_ms: 5000,
          recovered_after_attempt: 2
        }
      end

      it "sets recovery_status to recovered_after_retries" do
        attributes = collector.collect_result(component, result)
        expect(attributes["result.recovery_status"]).to eq("recovered_after_retries")
      end

      it "captures retry attempt details" do
        attributes = collector.collect_result(component, result)
        error_details = attributes["result.error_details"]
        expect(error_details["total_attempts"]).to eq(3)
        expect(error_details["successful_on_attempt"]).to eq(2)
        expect(error_details["total_backoff_ms"]).to eq(5000)
      end
    end

    context "with retry events array" do
      let(:result) do
        {
          success: false,
          retry_events: [
            {
              attempt: 1,
              error_type: "ConnectionError",
              error_message: "Connection refused",
              backoff_ms: 1000,
              timestamp: "2025-10-24T10:00:00Z"
            },
            {
              attempt: 2,
              error_type: "ConnectionError",
              error_message: "Connection refused",
              backoff_ms: 2000,
              timestamp: "2025-10-24T10:00:03Z"
            }
          ]
        }
      end

      it "includes retry events in error_details" do
        attributes = collector.collect_result(component, result)
        error_details = attributes["result.error_details"]
        expect(error_details["retry_events"]).to be_an(Array)
        expect(error_details["retry_events"].length).to eq(2)
      end

      it "preserves retry event details" do
        attributes = collector.collect_result(component, result)
        error_details = attributes["result.error_details"]
        first_retry = error_details["retry_events"].first
        expect(first_retry["attempt"]).to eq(1)
        expect(first_retry["error_type"]).to eq("ConnectionError")
        expect(first_retry["backoff_ms"]).to eq(1000)
      end
    end

    context "with partial success (some retries worked)" do
      let(:result) do
        {
          success: true,
          attempted_retries: 2,
          recovery_attempt: 2,
          final_status: "success"
        }
      end

      it "sets recovery_status to recovered_after_retries" do
        attributes = collector.collect_result(component, result)
        expect(attributes["result.recovery_status"]).to eq("recovered_after_retries")
      end
    end

    context "with stack trace in error" do
      let(:error) do
        begin
          raise RuntimeError.new("Deep error")
        rescue => e
          e
        end
      end

      it "includes stack trace in error_details" do
        attributes = collector.collect_result(component, error)
        error_details = attributes["result.error_details"]
        expect(error_details).to have_key("stack_trace")
        expect(error_details["stack_trace"]).to be_a(String)
        expect(error_details["stack_trace"].length).to be > 0
      end
    end

    context "with error response object" do
      let(:error_response) do
        double("ErrorResponse",
          failure?: true,
          error: double("Error",
            class: double("ErrorClass", name: "ApiError"),
            message: "API request failed",
            backtrace: ["line1", "line2"]
          )
        ).tap do |obj|
          allow(obj).to receive(:[]).with(:status_code).and_return(502)
          allow(obj).to receive(:[]).with("status_code").and_return(502)
        end
      end

      it "extracts error information from response object" do
        attributes = collector.collect_result(component, error_response)
        error_details = attributes["result.error_details"]
        expect(error_details["error_type"]).to eq("ApiError")
        expect(error_details["error_message"]).to eq("API request failed")
      end
    end
  end

  describe "component prefix" do
    it "generates correct prefix for error collector" do
      prefix = collector.send(:component_prefix)
      expect(prefix).to match(/error$/)
    end
  end

  describe "error classification" do
    context "with transient error types" do
      let(:result) do
        {
          success: false,
          error_type: "Timeout"
        }
      end

      it "classifies timeout as transient" do
        attributes = collector.collect_result(double("Comp", class: double(name: "Agent")), result)
        error_details = attributes["result.error_details"]
        expect(error_details["error_category"]).to eq("transient")
      end
    end

    context "with permanent error types" do
      let(:result) do
        {
          success: false,
          error_type: "AuthenticationError"
        }
      end

      it "classifies auth error as permanent" do
        attributes = collector.collect_result(double("Comp", class: double(name: "Agent")), result)
        error_details = attributes["result.error_details"]
        expect(error_details["error_category"]).to eq("permanent")
      end
    end
  end
end
