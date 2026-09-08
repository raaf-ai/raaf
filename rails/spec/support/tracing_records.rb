# frozen_string_literal: true

# Writes tracing rows the way the tracer writes them.
#
# A span's token counts, model and per-call fee live both in its recorded
# payload and in native columns, and every cost or usage answer reads the
# columns -- a span created from a payload alone is invisible to all of them.
# RAAF::Tracing::ActiveRecordProcessor derives one from the other on write,
# from the same RAAF::Tracing::SpanUsage this does.
module TracingRecords
  def create_trace(workflow_name: "Fleet", status: "completed", started_at: 2.hours.ago, **attributes)
    RAAF::Rails::Tracing::TraceRecord.create!(
      { trace_id: "trace_#{SecureRandom.hex(16)}",
        workflow_name: workflow_name,
        status: status,
        started_at: started_at }.merge(attributes)
    )
  end

  def create_span(attributes)
    payload = attributes[:span_attributes] || attributes["span_attributes"] || {}

    RAAF::Rails::Tracing::SpanRecord.create!(
      { span_id: "span_#{SecureRandom.hex(12)}" }
        .merge(attributes)
        .merge(billing_columns_for(payload))
    )
  end

  private

  def billing_columns_for(payload)
    usage = RAAF::Tracing::SpanUsage.from_attributes(payload)

    { input_tokens: usage[:input],
      output_tokens: usage[:output],
      total_tokens: usage[:total],
      agent_model: usage[:model],
      call_fee_cents: RAAF::Tracing::SpanUsage.fee_cents_from(payload) }.compact
  end
end

RSpec.configure do |config|
  config.include TracingRecords
end
