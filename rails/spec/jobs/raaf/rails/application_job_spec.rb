# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::ApplicationJob, type: :job do
  let(:captured_spans) { [] }

  let(:processor) do
    spans = captured_spans
    Class.new do
      define_method(:on_span_end) { |span| spans << span }
    end.new
  end

  let(:tracer) { double(processors: [processor]) }

  let(:outer_span) { { span_id: "span_outer", trace_id: "trace_outer" } }
  let(:outer_job) { double(current_span: outer_span) }

  before do
    stub_const("ProbeJob", Class.new(described_class) do
      class << self
        attr_accessor :job_span_during_perform
      end

      def perform
        self.class.job_span_during_perform = Thread.current[:raaf_job_span]
        :done
      end
    end)
  end

  after { Thread.current[:raaf_job_span] = nil }

  # perform_now on the class builds its own instance, so build ours to hand it
  # the tracer the span should be sent to.
  def run_probe
    job = ProbeJob.new
    job.instance_variable_set(:@tracer, tracer)
    job.perform_now
  end

  context "when run inside another job" do
    before { Thread.current[:raaf_job_span] = outer_job }

    it "records a job span under the enclosing job" do
      run_probe

      expect(captured_spans.size).to eq(1)
      span = captured_spans.first
      expect(span.kind).to eq(:job)
      expect(span.parent_id).to eq("span_outer")
      expect(span.trace_id).to eq("trace_outer")
    end

    it "captures the job identity and queue" do
      run_probe

      attributes = captured_spans.first.attributes
      expect(attributes["component.name"]).to eq("ProbeJob")
      expect(attributes["job.queue"]).to eq("default")
      expect(attributes["job.id"]).to be_present
    end

    it "makes itself the parent for anything nested deeper" do
      run_probe

      expect(ProbeJob.job_span_during_perform).to be_a(ProbeJob)
    end

    it "hands the enclosing job span back afterwards" do
      run_probe

      expect(Thread.current[:raaf_job_span]).to eq(outer_job)
    end

    # retry_on turns a raise under perform_now into a returned exception, so the
    # span is the only place the failure is visible.
    context "when the job raises" do
      before { allow_any_instance_of(ProbeJob).to receive(:perform).and_raise(ArgumentError, "boom") }

      it "records the failure on the span" do
        run_probe

        span = captured_spans.first
        expect(span.status).to eq(:error)
        expect(span.attributes["error.type"]).to eq("ArgumentError")
        expect(span.attributes["error.message"]).to eq("boom")
      end

      it "still hands the enclosing job span back" do
        run_probe

        expect(Thread.current[:raaf_job_span]).to eq(outer_job)
      end
    end
  end

  context "when run on its own" do
    it "records no span" do
      run_probe

      expect(captured_spans).to be_empty
    end

    it "still performs the work" do
      expect(run_probe).to eq(:done)
    end
  end
end
