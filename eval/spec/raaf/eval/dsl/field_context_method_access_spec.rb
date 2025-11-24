# frozen_string_literal: true

RSpec.describe RAAF::Eval::DSL::FieldContext, "method access support" do
  # Mock object that simulates RunResult behavior (method access only)
  class MockRunResult
    attr_reader :usage, :messages, :latency_ms

    def initialize
      @usage = {
        input_tokens: 32,
        output_tokens: 30,
        total_tokens: 62
      }
      @messages = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there!" }
      ]
      @latency_ms = 245
    end
  end

  let(:run_result) { MockRunResult.new }
  let(:result_hash) do
    {
      result: run_result,
      configuration: { model: "sonar", temperature: 0.7 }
    }
  end

  describe "extracting nested values from objects with method access" do
    context "when accessing usage.total_tokens from RunResult-like object" do
      subject(:field_context) do
        described_class.new("result.usage.total_tokens", result_hash)
      end

      it "successfully extracts the value via method chain" do
        expect(field_context.value).to eq(62)
      end

      it "confirms the field exists" do
        expect(field_context.field_exists?("result.usage.total_tokens")).to be true
      end
    end

    context "when accessing usage.input_tokens from RunResult-like object" do
      subject(:field_context) do
        described_class.new("result.usage.input_tokens", result_hash)
      end

      it "successfully extracts the value" do
        expect(field_context.value).to eq(32)
      end
    end

    context "when accessing usage.output_tokens from RunResult-like object" do
      subject(:field_context) do
        described_class.new("result.usage.output_tokens", result_hash)
      end

      it "successfully extracts the value" do
        expect(field_context.value).to eq(30)
      end
    end

    context "when accessing latency_ms from RunResult-like object" do
      subject(:field_context) do
        described_class.new("result.latency_ms", result_hash)
      end

      it "successfully extracts the value" do
        expect(field_context.value).to eq(245)
      end
    end

    context "when accessing messages from RunResult-like object" do
      subject(:field_context) do
        described_class.new("result.messages", result_hash)
      end

      it "successfully extracts the array" do
        expect(field_context.value).to be_an(Array)
        expect(field_context.value.length).to eq(2)
      end
    end
  end

  describe "mixed hash and method access" do
    let(:mixed_result) do
      {
        run_result: run_result,
        metadata: {
          run_id: "test-123",
          timestamp: Time.now.iso8601
        }
      }
    end

    context "when navigating through hash then method access" do
      subject(:field_context) do
        described_class.new("run_result.usage.total_tokens", mixed_result)
      end

      it "successfully extracts the value" do
        expect(field_context.value).to eq(62)
      end
    end

    context "when accessing pure hash nested field" do
      subject(:field_context) do
        described_class.new("metadata.run_id", mixed_result)
      end

      it "successfully extracts the value" do
        expect(field_context.value).to eq("test-123")
      end
    end
  end

  describe "backward compatibility with hash-only access" do
    let(:pure_hash_result) do
      {
        usage: {
          input_tokens: 100,
          output_tokens: 200,
          total_tokens: 300
        },
        latency_ms: 500
      }
    end

    context "when accessing nested hash fields" do
      subject(:field_context) do
        described_class.new("usage.total_tokens", pure_hash_result)
      end

      it "still works with hash-style access" do
        expect(field_context.value).to eq(300)
      end
    end
  end

  describe "error handling for non-existent fields" do
    context "when field doesn't exist on object" do
      it "raises FieldNotFoundError" do
        expect do
          described_class.new("result.nonexistent_field", result_hash)
        end.to raise_error(RAAF::Eval::DSL::FieldNotFoundError)
      end
    end

    context "when nested field doesn't exist" do
      it "raises FieldNotFoundError" do
        expect do
          described_class.new("result.usage.invalid_token_count", result_hash)
        end.to raise_error(RAAF::Eval::DSL::FieldNotFoundError)
      end
    end
  end
end
