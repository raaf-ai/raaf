# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Tracing::SpanRecord, type: :model do
  describe ".error_signatures" do
    let(:trace) do
      RAAF::Rails::Tracing::TraceRecord.create!(
        trace_id: "trace_#{SecureRandom.hex(16)}",
        workflow_name: "Fleet",
        status: "failed",
        started_at: 3.hours.ago
      )
    end

    # The exception lives in an `exception` event, which is where
    # SpanRecord#error_details reads it from.
    def failure(exception: "Faraday::TimeoutError", message: "execution expired",
                name: "Company::EnrichAgent", kind: "tool", started_at: 10.minutes.ago,
                trace_id: nil)
      described_class.create!(
        span_id: "span_#{SecureRandom.hex(12)}",
        trace_id: trace_id || trace.trace_id,
        name: name,
        kind: kind,
        status: "error",
        start_time: started_at,
        end_time: started_at + 1,
        duration_ms: 1000,
        events: [{ "name" => "exception",
                   "attributes" => { "exception.type" => exception,
                                     "exception.message" => message } }]
      )
    end

    def window
      1.hour.ago..Time.current
    end

    it "groups by exception class and message, most frequent first" do
      3.times { failure }
      failure(exception: "JSON::ParserError", message: "unexpected token")

      rows = described_class.error_signatures(timeframe: window)

      expect(rows.map { |row| row.values_at(:exception, :count) })
        .to eq([["Faraday::TimeoutError", 3], ["JSON::ParserError", 1]])
    end

    # One timeout per upstream host is several problems, not one.
    it "keeps two failures of the same class apart when the message differs" do
      failure(message: "crm_upsert exceeded 4000ms")
      failure(message: "web_search did not respond")

      expect(described_class.error_signatures(timeframe: window).size).to eq(2)
    end

    it "counts the distinct traces a signature touched" do
      other = RAAF::Rails::Tracing::TraceRecord.create!(
        trace_id: "trace_#{SecureRandom.hex(16)}", workflow_name: "Fleet",
        status: "failed", started_at: 3.hours.ago
      )
      2.times { failure }
      failure(trace_id: other.trace_id)

      expect(described_class.error_signatures(timeframe: window).first[:traces]).to eq(2)
    end

    it "names the agent most of the failures came from" do
      2.times { failure(name: "Company::EnrichAgent") }
      failure(name: "Market::ScoutAgent")

      expect(described_class.error_signatures(timeframe: window).first[:agent])
        .to eq("Company::EnrichAgent")
    end

    it "reports the newest occurrence as last seen" do
      failure(started_at: 50.minutes.ago)
      newest = failure(started_at: 2.minutes.ago)

      row = described_class.error_signatures(timeframe: window).first

      expect(row[:span_id]).to eq(newest.span_id)
      expect(row[:last_seen]).to be_within(1.second).of(newest.start_time)
    end

    it "reports the oldest occurrence as first seen" do
      oldest = failure(started_at: 50.minutes.ago)
      failure(started_at: 2.minutes.ago)

      row = described_class.error_signatures(timeframe: window).first

      expect(row[:first_seen]).to be_within(1.second).of(oldest.start_time)
    end

    # Traceable's fail_span writes flat error.* attributes and adds no
    # exception event, which is the path every job, agent and tool takes.
    it "reads a failure recorded as error attributes rather than as an event" do
      described_class.create!(
        span_id: "span_#{SecureRandom.hex(12)}", trace_id: trace.trace_id,
        name: "run.workflow.job.AiEvaluationMetricsJob.perform", kind: "job", status: "error",
        start_time: 10.minutes.ago, end_time: 10.minutes.ago + 1, duration_ms: 1000,
        span_attributes: { "error.type" => "ActiveRecord::RecordInvalid",
                           "error.message" => "Validation failed: Period must exist" }
      )

      row = described_class.error_signatures(timeframe: window).first

      expect(row).to include(exception: "ActiveRecord::RecordInvalid",
                             message: "Validation failed: Period must exist")
    end

    it "names the agent readably where the span name is instrumentation" do
      described_class.create!(
        span_id: "span_#{SecureRandom.hex(12)}", trace_id: trace.trace_id,
        name: "run.workflow.job.AiEvaluationMetricsJob.perform", kind: "job", status: "error",
        start_time: 10.minutes.ago, end_time: 10.minutes.ago + 1, duration_ms: 1000,
        span_attributes: { "error.type" => "RuntimeError", "error.message" => "boom" }
      )

      expect(described_class.error_signatures(timeframe: window).first[:agent])
        .to eq("AiEvaluationMetricsJob")
    end

    it "ignores spans that did not fail" do
      failure
      described_class.create!(
        span_id: "span_#{SecureRandom.hex(12)}", trace_id: trace.trace_id,
        name: "Company::EnrichAgent", kind: "tool", status: "ok",
        start_time: 10.minutes.ago, end_time: 10.minutes.ago + 1, duration_ms: 1000
      )

      expect(described_class.error_signatures(timeframe: window).sum { |row| row[:count] }).to eq(1)
    end

    it "labels a failure that recorded no exception rather than dropping it" do
      described_class.create!(
        span_id: "span_#{SecureRandom.hex(12)}", trace_id: trace.trace_id,
        name: "Company::EnrichAgent", kind: "tool", status: "error",
        start_time: 10.minutes.ago, end_time: 10.minutes.ago + 1, duration_ms: 1000
      )

      row = described_class.error_signatures(timeframe: window).first

      expect(row).to include(exception: "Error", message: "No message recorded")
    end

    describe "the trend against the preceding window" do
      it "is the percentage change when the signature fired before" do
        2.times { failure(started_at: 90.minutes.ago) }
        6.times { failure(started_at: 10.minutes.ago) }

        expect(described_class.error_signatures(timeframe: window).first[:trend]).to eq(200)
      end

      it "is negative when the signature is subsiding" do
        4.times { failure(started_at: 90.minutes.ago) }
        failure(started_at: 10.minutes.ago)

        expect(described_class.error_signatures(timeframe: window).first[:trend]).to eq(-75)
      end

      it "is zero when the signature has not moved" do
        failure(started_at: 90.minutes.ago)
        failure(started_at: 10.minutes.ago)

        expect(described_class.error_signatures(timeframe: window).first[:trend]).to eq(0)
      end

      # "new" is a different fact from "up 100%", and the one worth reading
      # differently, so it must not be reported as a number.
      it "is nil when the signature did not fire in the preceding window" do
        failure(started_at: 10.minutes.ago)

        expect(described_class.error_signatures(timeframe: window).first[:trend]).to be_nil
      end
    end

    it "keeps only the most frequent signatures up to the limit" do
      failure(message: "a")
      failure(message: "b")
      failure(message: "c")

      expect(described_class.error_signatures(timeframe: window, limit: 2).size).to eq(2)
    end

    it "is empty when nothing failed" do
      expect(described_class.error_signatures(timeframe: window)).to eq([])
    end
  end
end
