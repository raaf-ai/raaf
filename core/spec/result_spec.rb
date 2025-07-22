# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/result"

RSpec.describe RAAF::Result do
  describe ".success" do
    let(:data) { { message: "Hello world" } }

    it "creates a successful result with data" do
      result = described_class.success(data)

      expect(result.success?).to be true
      expect(result.failure?).to be false
      expect(result.data).to eq(data)
      expect(result.error).to be_nil
    end
  end

  describe ".failure" do
    let(:error_message) { "Something went wrong" }

    it "creates a failure result with string error" do
      result = described_class.failure(error_message)

      expect(result.success?).to be false
      expect(result.failure?).to be true
      expect(result.error).to eq(error_message)
      expect(result.data).to be_nil
    end
  end

  describe "basic functionality" do
    it "has success and failure states" do
      success_result = described_class.success("data")
      failure_result = described_class.failure("error")

      expect(success_result.success?).to be true
      expect(success_result.failure?).to be false

      expect(failure_result.success?).to be false
      expect(failure_result.failure?).to be true
    end
  end
end
