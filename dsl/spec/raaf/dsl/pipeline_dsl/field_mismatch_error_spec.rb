# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::PipelineDSL::FieldMismatchError do
  # The error is constructed by ChainedAgent#validate_field_compatibility! with the
  # producer component, the consumer component, the fields the consumer still needs,
  # and the fields the surrounding pipeline can supply from its context block.
  let(:producer) do
    Class.new do
      def self.name = "ProducerAgent"
      def self.provided_fields = %i[id name]
      def self.required_fields = []
    end
  end

  let(:consumer) do
    Class.new do
      def self.name = "ConsumerAgent"
      def self.provided_fields = []
      def self.required_fields = %i[id name email status]
    end
  end

  describe "#initialize" do
    it "builds its message from the producer and consumer field declarations" do
      error = described_class.new(producer, consumer, %i[email status])

      expect(error.message).to include("Pipeline Field Mismatch Error!")
      expect(error.message).to include("ConsumerAgent requires fields: #{consumer.required_fields.inspect}")
      expect(error.message).to include("ProducerAgent only provides: #{producer.provided_fields.inspect}")
    end

    it "defaults the pipeline context fields to an empty list" do
      error = described_class.new(producer, consumer, %i[email status])

      expect(error.message).to include("Missing fields that must be provided: [:email, :status]")
      expect(error.message).not_to include("available from pipeline context")
    end
  end

  describe "the remediation guidance" do
    it "lists the fields that no source can supply along with fixes" do
      error = described_class.new(producer, consumer, %i[email status])

      expect(error.message).to include("Missing fields that must be provided: [:email, :status]")
      expect(error.message).to include("Update ProducerAgent's result_transform to provide: [:email, :status]")
      expect(error.message).to include("Or update ConsumerAgent to not require these fields")
      expect(error.message).to include("Or add an intermediate agent that provides the transformation")
    end

    it "points at the pipeline context for fields the context can supply" do
      error = described_class.new(producer, consumer, %i[email status], %i[email status])

      expect(error.message).to include("These fields are available from pipeline context: [:email, :status]")
      expect(error.message).to include("Make sure they are declared in the pipeline's context block")
      expect(error.message).not_to include("Missing fields that must be provided")
    end

    it "separates context-provided fields from genuinely missing ones" do
      error = described_class.new(producer, consumer, %i[email status], [:email])

      expect(error.message).to include("Missing fields that must be provided: [:status]")
      expect(error.message).to include("available from pipeline context: [:email]")
    end

    it "omits both sections when nothing is missing" do
      error = described_class.new(producer, consumer, [])

      expect(error.message).not_to include("Missing fields that must be provided")
      expect(error.message).not_to include("available from pipeline context")
    end
  end

  describe "agent name extraction" do
    it "uses the class name for a plain agent class" do
      error = described_class.new(producer, consumer, [:email])

      expect(error.message).to include("ProducerAgent only provides")
    end

    it "reports the last agent of a chained producer" do
      chain = RAAF::DSL::PipelineDSL::ChainedAgent.new(consumer, producer)
      error = described_class.new(chain, consumer, [:email])

      expect(error.message).to include("ProducerAgent only provides")
    end

    it "joins every branch of a parallel producer" do
      parallel = RAAF::DSL::PipelineDSL::ParallelAgents.new([producer, consumer])
      allow(parallel).to receive(:provided_fields).and_return(%i[id name])
      error = described_class.new(parallel, consumer, [:email])

      expect(error.message).to include("(ProducerAgent | ConsumerAgent) only provides")
    end

    it "unwraps a batched producer" do
      batched = RAAF::DSL::PipelineDSL::BatchedAgent.new(producer, 10, array_field: :items)
      allow(batched).to receive(:provided_fields).and_return(%i[id name])
      error = described_class.new(batched, consumer, [:email])

      expect(error.message).to include("ProducerAgent only provides")
    end

    it "unwraps an iterating producer" do
      iterating = RAAF::DSL::PipelineDSL::IteratingAgent.new(producer, :items)
      allow(iterating).to receive(:provided_fields).and_return(%i[id name])
      error = described_class.new(iterating, consumer, [:email])

      expect(error.message).to include("ProducerAgent only provides")
    end

    it "unwraps a remapped producer" do
      remapped = RAAF::DSL::PipelineDSL::RemappedAgent.new(producer, input_mapping: { a: :b })
      allow(remapped).to receive(:provided_fields).and_return(%i[id name])
      error = described_class.new(remapped, consumer, [:email])

      expect(error.message).to include("ProducerAgent only provides")
    end

    it "unwraps a configured producer" do
      configured = RAAF::DSL::PipelineDSL::ConfiguredAgent.new(producer, { timeout: 5 })
      error = described_class.new(configured, consumer, [:email])

      expect(error.message).to include("ProducerAgent only provides")
    end

    it "falls back to the object's own name for anything else" do
      other = double("component", name: "AnonymousComponent", provided_fields: [])
      error = described_class.new(other, consumer, [:email])

      expect(error.message).to include("AnonymousComponent only provides")
    end
  end

  describe "inheritance" do
    it "inherits from StandardError" do
      expect(described_class).to be < StandardError
    end

    it "can be rescued as a StandardError" do
      expect do
        raise described_class.new(producer, consumer, [:email])
      end.to raise_error(StandardError, /Pipeline Field Mismatch Error!/)
    end

    it "can be rescued specifically" do
      expect do
        raise described_class.new(producer, consumer, [:email])
      end.to raise_error(described_class, /ConsumerAgent requires fields/)
    end
  end

  describe "raised from a chained agent" do
    it "reports the fields the consumer cannot get from the producer" do
      chain = RAAF::DSL::PipelineDSL::ChainedAgent.new(producer, consumer)

      expect { chain.validate_with_pipeline_context([]) }
        .to raise_error(described_class, /Missing fields that must be provided/)
    end

    it "stays silent once the pipeline context covers the gap" do
      chain = RAAF::DSL::PipelineDSL::ChainedAgent.new(producer, consumer)

      expect { chain.validate_with_pipeline_context(%i[email status]) }.not_to raise_error
    end
  end
end
