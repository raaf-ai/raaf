# Database Schema

This is the database schema implementation for the spec detailed in @.agent-os/specs/2025-11-12-opentelemetry-protocol-support/spec.md

> Created: 2025-11-12
> Version: 1.0.0

## Schema Changes

**No database schema changes required.**

### Rationale

OpenTelemetry protocol support is purely an export/transport mechanism. All span data continues to be stored in RAAF's existing storage systems:

1. **In-Memory Storage:** Existing `SpanTracer` and processor architecture
2. **Rails Storage:** Existing `raaf-rails` database tables (if used)
3. **External Storage:** OTLP backends handle their own storage

The OTLP exporter operates as a processor that reads from RAAF's existing span storage and exports to external backends. No new database tables or migrations are needed.

## OTLP Backend Storage (External)

While RAAF itself requires no schema changes, OTLP backends store trace data in their own formats:

### Jaeger Storage Schema (Reference)

```
Traces Collection (NoSQL/Cassandra/Elasticsearch)
- trace_id (primary key)
- span_id
- parent_span_id
- operation_name
- start_time
- duration
- tags (key-value pairs)
- logs (structured events)
- process (service metadata)
- references (parent relationships)
```

### Grafana Tempo Storage (Reference)

```
Tempo uses block-based storage (Parquet files)
- trace_id (indexed)
- spans (compressed Protobuf)
- metadata (service, duration, tags for search)
```

## Configuration Storage (Optional Future Enhancement)

If we want to persist OTLP configuration in Rails applications, we could add:

```ruby
# OPTIONAL - Not required for Phase 1
class CreateRaafOtlpConfigurations < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_otlp_configurations do |t|
      t.string :name, null: false
      t.string :endpoint, null: false
      t.string :protocol, default: 'http', null: false
      t.jsonb :headers, default: {}
      t.integer :batch_size, default: 100
      t.integer :timeout, default: 10
      t.boolean :enabled, default: true
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :raaf_otlp_configurations, :name, unique: true
    add_index :raaf_otlp_configurations, :enabled
  end
end
```

**Status:** Deferred to Phase 2 - Not needed for initial implementation.

## Data Migration

**No data migration required.**

Existing RAAF traces remain in their current storage locations. OTLP export is forward-looking only - we export new spans as they're created.

### Optional: Historical Export

If users want to export historical traces to OTLP backends:

```ruby
# lib/raaf/tracing/otlp_historical_export.rb
module RAAF
  module Tracing
    class OTelHistoricalExporter
      def export_historical_traces(start_time:, end_time:)
        # Query existing spans from RAAF storage
        spans = query_spans(start_time, end_time)

        # Export to OTLP backend
        exporter = OTelExporter.new
        spans.each_slice(100) do |batch|
          exporter.export_batch(batch)
        end
      end
    end
  end
end
```

**Status:** Nice-to-have, not required for MVP.

## Summary

- ✅ **No database schema changes needed**
- ✅ **No migrations required**
- ✅ **OTLP backends handle their own storage**
- ⏭️ **Optional configuration storage deferred to Phase 2**
- ⏭️ **Optional historical export deferred to Phase 2**
