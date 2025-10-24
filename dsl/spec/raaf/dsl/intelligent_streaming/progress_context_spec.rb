# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/intelligent_streaming/progress_context"

RSpec.describe RAAF::DSL::IntelligentStreaming::ProgressContext do
  describe "#initialize" do
    it "creates an immutable context with basic parameters" do
      context = described_class.new(
        stream_number: 3,
        total_streams: 10,
        stream_data: [1, 2, 3]
      )

      expect(context.stream_number).to eq(3)
      expect(context.total_streams).to eq(10)
      expect(context.stream_data).to eq([1, 2, 3])
      expect(context.metadata).to eq({})
      expect(context).to be_frozen
    end

    it "creates context with metadata" do
      metadata = { agent: "TestAgent", timestamp: Time.now }
      context = described_class.new(
        stream_number: 1,
        total_streams: 5,
        stream_data: ["a", "b"],
        metadata: metadata
      )

      expect(context.metadata).to eq(metadata)
      expect(context.metadata).to be_frozen
    end

    it "freezes stream_data array" do
      data = [1, 2, 3]
      context = described_class.new(
        stream_number: 1,
        total_streams: 1,
        stream_data: data
      )

      expect(context.stream_data).to be_frozen
      expect { context.stream_data << 4 }.to raise_error(FrozenError)
    end
  end

  describe "#progress_percentage" do
    it "calculates correct percentage" do
      context = described_class.new(stream_number: 3, total_streams: 10)
      expect(context.progress_percentage).to eq(30.0)
    end

    it "handles first stream" do
      context = described_class.new(stream_number: 1, total_streams: 10)
      expect(context.progress_percentage).to eq(10.0)
    end

    it "handles last stream" do
      context = described_class.new(stream_number: 10, total_streams: 10)
      expect(context.progress_percentage).to eq(100.0)
    end

    it "rounds to 2 decimal places" do
      context = described_class.new(stream_number: 1, total_streams: 3)
      expect(context.progress_percentage).to eq(33.33)
    end

    it "returns 0.0 for zero total streams" do
      context = described_class.new(stream_number: 0, total_streams: 0)
      expect(context.progress_percentage).to eq(0.0)
    end
  end

  describe "#first_stream?" do
    it "returns true for first stream" do
      context = described_class.new(stream_number: 1, total_streams: 10)
      expect(context.first_stream?).to be(true)
    end

    it "returns false for other streams" do
      context = described_class.new(stream_number: 2, total_streams: 10)
      expect(context.first_stream?).to be(false)

      context = described_class.new(stream_number: 10, total_streams: 10)
      expect(context.first_stream?).to be(false)
    end
  end

  describe "#last_stream?" do
    it "returns true for last stream" do
      context = described_class.new(stream_number: 10, total_streams: 10)
      expect(context.last_stream?).to be(true)
    end

    it "returns false for other streams" do
      context = described_class.new(stream_number: 1, total_streams: 10)
      expect(context.last_stream?).to be(false)

      context = described_class.new(stream_number: 9, total_streams: 10)
      expect(context.last_stream?).to be(false)
    end

    it "handles single stream" do
      context = described_class.new(stream_number: 1, total_streams: 1)
      expect(context.first_stream?).to be(true)
      expect(context.last_stream?).to be(true)
    end
  end

  describe "#stream_size" do
    it "returns the size of stream_data" do
      context = described_class.new(
        stream_number: 1,
        total_streams: 1,
        stream_data: [1, 2, 3, 4, 5]
      )
      expect(context.stream_size).to eq(5)
    end

    it "returns 0 for empty stream_data" do
      context = described_class.new(
        stream_number: 1,
        total_streams: 1,
        stream_data: []
      )
      expect(context.stream_size).to eq(0)
    end
  end

  describe "#to_h" do
    it "converts context to hash" do
      context = described_class.new(
        stream_number: 3,
        total_streams: 10,
        stream_data: [1, 2, 3],
        metadata: { foo: "bar" }
      )

      hash = context.to_h

      expect(hash).to eq({
        stream_number: 3,
        total_streams: 10,
        stream_size: 3,
        progress_percentage: 30.0,
        first_stream: false,
        last_stream: false,
        metadata: { foo: "bar" }
      })
    end

    it "shows correct flags for first stream" do
      context = described_class.new(
        stream_number: 1,
        total_streams: 5,
        stream_data: ["a", "b"]
      )

      hash = context.to_h

      expect(hash[:first_stream]).to be(true)
      expect(hash[:last_stream]).to be(false)
      expect(hash[:stream_size]).to eq(2)
      expect(hash[:progress_percentage]).to eq(20.0)
    end

    it "shows correct flags for last stream" do
      context = described_class.new(
        stream_number: 5,
        total_streams: 5,
        stream_data: ["x"]
      )

      hash = context.to_h

      expect(hash[:first_stream]).to be(false)
      expect(hash[:last_stream]).to be(true)
      expect(hash[:stream_size]).to eq(1)
      expect(hash[:progress_percentage]).to eq(100.0)
    end
  end

  describe "#to_s" do
    it "provides human-readable representation" do
      context = described_class.new(
        stream_number: 3,
        total_streams: 10,
        stream_data: [1, 2, 3, 4, 5]
      )

      expect(context.to_s).to eq("Stream 3/10 (30.0%) - 5 items")
    end

    it "handles empty stream" do
      context = described_class.new(
        stream_number: 1,
        total_streams: 1,
        stream_data: []
      )

      expect(context.to_s).to eq("Stream 1/1 (100.0%) - 0 items")
    end
  end
end