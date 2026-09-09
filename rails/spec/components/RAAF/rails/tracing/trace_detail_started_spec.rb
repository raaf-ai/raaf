# frozen_string_literal: true

require "rails_helper"

# Every time on the trace page is relative to the trace: the waterfall is
# offsets from its origin, the rows read "4 minutes ago". None of that lines a
# trace up against an application log, an incident window or a deploy, which
# is the usual reason for opening one.
RSpec.describe RAAF::Rails::Tracing::TraceDetail, type: :component do
  let(:started) { Time.zone.parse("2026-09-08 14:32:07") }

  let(:trace) do
    RAAF::Rails::Tracing::TraceRecord.create!(
      trace_id: "trace_#{SecureRandom.hex(16)}", workflow_name: "Scout",
      status: "completed", started_at: started, ended_at: started + 3
    )
  end

  it "carries an absolute start time in the summary bar" do
    stats = described_class.new(trace: trace, params: {}).send(:summary_stats)

    expect(stats.first).to include(label: "started", value: "2026-09-08 14:32:07")
  end

  it "leads with when it ran, before how big and how long it was" do
    labels = described_class.new(trace: trace, params: {}).send(:summary_stats)
                            .map { |stat| stat[:label] }

    expect(labels.first(3)).to eq(%w[started spans duration])
  end

  # A trace with no recorded start has no start to print, and "—" in a
  # timestamp slot reads as a clock that failed rather than as an unset field.
  it "drops the stat entirely for a trace that never recorded a start" do
    trace.update_columns(started_at: nil)

    stats = described_class.new(trace: trace, params: {}).send(:summary_stats)

    expect(stats.map { |stat| stat[:label] }).not_to include("started")
  end
end
