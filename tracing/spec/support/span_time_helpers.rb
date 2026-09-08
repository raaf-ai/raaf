# frozen_string_literal: true

require "time"

# Span timestamps come back as Time objects from the tracing pipeline, but the
# same specs also read timestamps off events, where they are ISO8601 strings.
# This accepts either so a spec can compare the two without caring which it got.
module SpanTimeHelpers

  def span_time(value)
    value.is_a?(Time) ? value : Time.parse(value.to_s).utc
  end

end
