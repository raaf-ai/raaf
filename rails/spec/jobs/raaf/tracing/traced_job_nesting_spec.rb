# frozen_string_literal: true

require "rails_helper"

# Lives here rather than in the tracing gem's suite because TracedJob needs a
# real ActiveJob, which only the Rails side of the mono-repo has.
RSpec.describe RAAF::Tracing::TracedJob, type: :job do
  let(:captured_spans) { [] }

  let(:processor) do
    spans = captured_spans
    Class.new do
      define_method(:on_span_end) { |span| spans << span }
      define_method(:force_flush) { nil }
      define_method(:shutdown) { nil }
    end.new
  end

  let(:tracer) { double(processors: [processor]) }

  before do
    stub_const("InnerProbeJob", Class.new(described_class) do
      def perform
        :inner
      end
    end)

    stub_const("OuterProbeJob", Class.new(described_class) do
      # The nested job builds no tracer of its own, so hand it ours.
      class << self
        attr_accessor :shared_tracer
      end

      def perform
        inner = InnerProbeJob.new
        inner.instance_variable_set(:@tracer, self.class.shared_tracer)
        inner.perform_now

        Thread.current[:raaf_job_span]
      end
    end)

    OuterProbeJob.shared_tracer = tracer
  end

  after { Thread.current[:raaf_job_span] = nil }

  def run_outer
    job = OuterProbeJob.new
    job.instance_variable_set(:@tracer, tracer)
    [job, job.perform_now]
  end

  context "when one traced job runs inside another" do
    it "records the nested job under the caller" do
      run_outer

      outer_span = captured_spans.find { |s| s.name.include?("OuterProbeJob") }
      inner_span = captured_spans.find { |s| s.name.include?("InnerProbeJob") }

      expect(inner_span.parent_id).to eq(outer_span.span_id)
      expect(inner_span.trace_id).to eq(outer_span.trace_id)
    end

    it "hands the caller its own span context back" do
      job, job_span_after_nested_call = run_outer

      expect(job_span_after_nested_call).to eq(job)
    end
  end

  context "when a traced job runs on its own" do
    it "leaves no span context behind" do
      job = InnerProbeJob.new
      job.instance_variable_set(:@tracer, tracer)

      job.perform_now

      expect(Thread.current[:raaf_job_span]).to be_nil
    end
  end
end
