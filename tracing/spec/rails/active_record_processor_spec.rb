# frozen_string_literal: true

require "spec_helper"

# Skip Rails-specific tests if Rails is not available
begin
  require "rails"
  require "active_record"
  require_relative "../../../../lib/raaf/tracing/active_record_processor"
  
  # Check if database connection is available
  ActiveRecord::Base.connection.migration_context.current_version
rescue LoadError, ActiveRecord::ConnectionNotDefined, ActiveRecord::NoDatabaseError => e
  puts "Skipping Rails tests: #{e.message}"
  return
end

RSpec.describe RAAF::Tracing::ActiveRecordProcessor do
  let(:processor) { described_class.new(sampling_rate: 1.0, batch_size: 1) }
  let(:trace_id) { "trace_#{SecureRandom.alphanumeric(32)}" }
  let(:span_id) { "span_#{SecureRandom.hex(12)}" }
  
  let(:test_span) do
    RAAF::Tracing::Span.new(
      name: "test_operation",
      trace_id: trace_id,
      kind: :llm
    ).tap do |span|
      span.instance_variable_set(:@span_id, span_id)
      span.instance_variable_set(:@start_time, Time.current)
      span.instance_variable_set(:@end_time, Time.current + 1.second)
      span.instance_variable_set(:@attributes, {
                                   "llm.request.model" => "gpt-4o",
                                   "llm.request.messages" => [{ role: "user", content: "Hello" }],
                                   "llm.usage.prompt_tokens" => 10,
                                   "llm.usage.completion_tokens" => 20
                                 })
      span.finish
    end
  end

  describe "#initialize" do
    context "with default parameters" do
      subject { described_class.new }

      it "sets default sampling rate" do
        expect(subject.sampling_rate).to eq(1.0)
      end

      it "sets default batch size" do
        expect(subject.batch_size).to eq(50)
      end
    end

    context "with custom parameters" do
      subject { described_class.new(sampling_rate: 0.5, batch_size: 100) }

      it "sets custom sampling rate" do
        expect(subject.sampling_rate).to eq(0.5)
      end

      it "sets custom batch size" do
        expect(subject.batch_size).to eq(100)
      end
    end

    context "when database tables do not exist" do
      before do
        allow(RAAF::Tracing::Trace).to receive(:table_exists?).and_return(false)
      end

      it "raises an error with helpful message" do
        expect { described_class.new }.to raise_error(
          /RAAF tracing tables not found/
        )
      end
    end
  end

  describe "#on_span_start" do
    it "creates trace record if it does not exist" do
      expect do
        processor.on_span_start(test_span)
      end.to change { RAAF::Tracing::Trace.count }.by(1)
      
      trace = RAAF::Tracing::Trace.find_by(trace_id: trace_id)
      expect(trace).to be_present
      expect(trace.workflow_name).to eq("test_operation")
      expect(trace.status).to eq("running")
    end

    it "does not create duplicate trace records" do
      processor.on_span_start(test_span)
      
      expect do
        processor.on_span_start(test_span)
      end.not_to(change { RAAF::Tracing::Trace.count })
    end

    context "with sampling rate less than 1.0" do
      let(:processor) { described_class.new(sampling_rate: 0.0) }

      it "skips processing when not sampled" do
        expect do
          processor.on_span_start(test_span)
        end.not_to(change { RAAF::Tracing::Trace.count })
      end
    end
  end

  describe "#on_span_end" do
    before do
      processor.on_span_start(test_span)
    end

    it "saves span to database" do
      expect do
        processor.on_span_end(test_span)
      end.to change { RAAF::Tracing::Span.count }.by(1)
      
      span = RAAF::Tracing::Span.find_by(span_id: span_id)
      expect(span).to be_present
      expect(span.name).to eq("test_operation")
      expect(span.kind).to eq("llm")
      expect(span.trace_id).to eq(trace_id)
    end

    it "saves span attributes correctly" do
      processor.on_span_end(test_span)
      
      span = RAAF::Tracing::Span.find_by(span_id: span_id)
      expect(span.attributes["llm.request.model"]).to eq("gpt-4o")
      expect(span.attributes["llm.usage.prompt_tokens"]).to eq(10)
      expect(span.attributes["llm.usage.completion_tokens"]).to eq(20)
    end

    it "calculates duration correctly" do
      processor.on_span_end(test_span)
      
      span = RAAF::Tracing::Span.find_by(span_id: span_id)
      expect(span.duration_ms).to be_within(50).of(1000) # ~1 second
    end

    context "with batch processing" do
      let(:processor) { described_class.new(batch_size: 2) }

      it "buffers spans until batch size is reached" do
        processor.on_span_end(test_span)
        
        expect(RAAF::Tracing::Span.count).to eq(0)
        
        # Second span should trigger batch processing
        second_span = test_span.dup
        second_span.instance_variable_set(:@span_id, "span_#{SecureRandom.hex(12)}")
        processor.on_span_end(second_span)
        
        expect(RAAF::Tracing::Span.count).to eq(2)
      end
    end
  end

  describe "#flush" do
    let(:processor) { described_class.new(batch_size: 10) }

    before do
      processor.on_span_start(test_span)
      processor.on_span_end(test_span)
    end

    it "forces immediate processing of buffered spans" do
      expect(RAAF::Tracing::Span.count).to eq(0)
      
      processor.flush
      
      expect(RAAF::Tracing::Span.count).to eq(1)
    end
  end

  describe "sampling behavior" do
    let(:processor) { described_class.new(sampling_rate: 0.5) }

    it "consistently samples the same trace ID" do
      # Test multiple times to ensure consistency
      5.times do
        result1 = processor.send(:should_sample?, trace_id)
        result2 = processor.send(:should_sample?, trace_id)
        expect(result1).to eq(result2)
      end
    end

    it "produces roughly correct sampling rate" do
      sampled_count = 0
      total_count = 1000
      
      total_count.times do |_i|
        test_trace_id = "trace_#{SecureRandom.alphanumeric(32)}"
        sampled_count += 1 if processor.send(:should_sample?, test_trace_id)
      end
      
      sampling_rate = sampled_count.to_f / total_count
      expect(sampling_rate).to be_within(0.1).of(0.5)
    end
  end

  describe "data sanitization" do
    let(:large_string) { "x" * 15_000 }
    let(:large_array) { (1..200).to_a }
    let(:nested_hash) { { user: { email: "test@example.com", nested: { deep: "value" } } } }

    before do
      test_span.instance_variable_set(:@attributes, {
                                        "large_string" => large_string,
                                        "large_array" => large_array,
                                        "nested_data" => nested_hash
                                      })
      processor.on_span_start(test_span)
    end

    it "truncates very long strings" do
      processor.on_span_end(test_span)
      
      span = RAAF::Tracing::Span.find_by(span_id: span_id)
      stored_value = span.attributes["large_string"]
      expect(stored_value.length).to be <= 10_000
      expect(stored_value).to end_with("...")
    end

    it "limits array sizes" do
      processor.on_span_end(test_span)
      
      span = RAAF::Tracing::Span.find_by(span_id: span_id)
      stored_array = span.attributes["large_array"]
      expect(stored_array.length).to be <= 100
    end

    it "flattens nested hashes" do
      processor.on_span_end(test_span)
      
      span = RAAF::Tracing::Span.find_by(span_id: span_id)
      nested_data = span.attributes["nested_data"]
      expect(nested_data).to have_key("user.email")
      expect(nested_data).to have_key("user.nested.deep")
    end
  end

  describe "error handling" do
    it "handles database errors gracefully" do
      allow(RAAF::Tracing::Span).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new)
      allow(Rails.logger).to receive(:warn)
      
      expect { processor.on_span_end(test_span) }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/Failed to save span/)
    end

    it "handles trace creation errors gracefully" do
      allow(RAAF::Tracing::Trace).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new)
      allow(Rails.logger).to receive(:warn)
      
      expect { processor.on_span_start(test_span) }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/Failed to create trace/)
    end
  end

  describe "#shutdown" do
    let(:processor) { described_class.new(batch_size: 10) }

    before do
      processor.on_span_start(test_span)
      processor.on_span_end(test_span)
    end

    it "flushes remaining spans on shutdown" do
      expect(RAAF::Tracing::Span.count).to eq(0)
      
      processor.shutdown
      
      expect(RAAF::Tracing::Span.count).to eq(1)
    end
  end
end