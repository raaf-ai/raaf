# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-11-12-opentelemetry-protocol-support/spec.md

> Created: 2025-11-12
> Version: 1.0.0

## Technical Requirements

### Functional Requirements

1. **OTLP Protocol Implementation**
   - Support OTLP/HTTP protocol (primary) using `opentelemetry-exporter-otlp` gem
   - Optional OTLP/gRPC support for high-throughput scenarios
   - Implement exponential backoff for failed exports
   - Support batch export with configurable batch size
   - Handle network errors gracefully without losing spans

2. **Span Format Conversion**
   - Convert RAAF span structure to OpenTelemetry ResourceSpans format
   - Map RAAF attributes to OTel semantic conventions for AI/LLM:
     - `gen_ai.system` (openai, anthropic, etc.)
     - `gen_ai.request.model` (gpt-4o, claude-3-5-sonnet, etc.)
     - `gen_ai.request.temperature`
     - `gen_ai.request.max_tokens`
     - `gen_ai.response.finish_reason`
     - `gen_ai.usage.prompt_tokens`
     - `gen_ai.usage.completion_tokens`
   - Preserve RAAF-specific attributes as custom attributes (raaf.*)
   - Convert RAAF events to OTel span events
   - Handle nested spans with correct parent-child relationships

3. **Configuration Interface**
   - Environment variable support:
     - `OTEL_EXPORTER_OTLP_ENDPOINT` - Backend endpoint URL
     - `OTEL_EXPORTER_OTLP_PROTOCOL` - http/protobuf or grpc (default: http/protobuf)
     - `OTEL_EXPORTER_OTLP_HEADERS` - Custom headers for authentication
     - `OTEL_TRACES_EXPORTER` - Enable/disable (default: otlp)
     - `RAAF_OTLP_BATCH_SIZE` - Spans per batch (default: 100)
     - `RAAF_OTLP_TIMEOUT` - Export timeout in seconds (default: 10)
   - Programmatic configuration:
     ```ruby
     RAAF::Tracing.configure do |config|
       config.add_processor(
         RAAF::Tracing::OTelExporter.new(
           endpoint: "http://localhost:4318/v1/traces",
           protocol: :http,
           headers: { "Authorization" => "Bearer token" },
           batch_size: 100,
           timeout: 10
         )
       )
     end
     ```

4. **Backend Compatibility**
   - Jaeger: Support Jaeger's OTLP receiver (port 4318 for HTTP, 4317 for gRPC)
   - Grafana Tempo: Support Tempo's OTLP endpoint
   - OpenTelemetry Collector: Full compatibility with OTel Collector
   - Cloud Providers: Support managed services (Datadog, New Relic, Honeycomb, etc.)

### Non-Functional Requirements

1. **Performance**
   - OTLP export should add < 5ms latency to span processing
   - Batch export should handle 1000+ spans/second
   - Async export to not block agent execution
   - Memory usage should scale linearly with batch size

2. **Reliability**
   - Failed exports should not crash application
   - Implement retry logic with exponential backoff (3 retries max)
   - Log export failures for debugging
   - Support circuit breaker pattern for persistent failures

3. **Observability**
   - Log OTLP export success/failure with metrics
   - Track export duration and batch size
   - Monitor export queue depth
   - Alert on high export failure rates

## Approach Options

### Option A: Use opentelemetry-sdk Gem (Recommended)

**Description:** Leverage the official OpenTelemetry Ruby SDK and exporter gems

**Pros:**
- Official implementation, maintained by OTel community
- Full protocol compliance guaranteed
- Automatic updates as OTel spec evolves
- Includes batching, retry logic, and error handling
- Supports both HTTP and gRPC protocols

**Cons:**
- Additional dependency (but well-maintained)
- May have features RAAF doesn't need
- Need to map RAAF concepts to OTel SDK concepts

**Implementation:**
```ruby
# Gemfile
gem 'opentelemetry-sdk', '~> 1.3'
gem 'opentelemetry-exporter-otlp', '~> 0.26'

# lib/raaf/tracing/otel_exporter.rb
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'

module RAAF
  module Tracing
    class OTelExporter < BaseProcessor
      def initialize(endpoint: ENV['OTEL_EXPORTER_OTLP_ENDPOINT'], **options)
        @exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(
          endpoint: endpoint,
          headers: options[:headers] || {},
          compression: options[:compression] || 'gzip'
        )
        @formatter = OTelFormatter.new
      end

      def process_span(span)
        otel_span = @formatter.to_otlp_span(span)
        @exporter.export([otel_span])
      end

      def shutdown
        @exporter.shutdown
      end
    end
  end
end
```

### Option B: Custom OTLP Implementation

**Description:** Implement OTLP protocol directly using Faraday/HTTP

**Pros:**
- No additional dependencies
- Full control over implementation
- Can optimize for RAAF-specific use cases
- Smaller footprint

**Cons:**
- Need to maintain protocol implementation
- Must track OTel spec changes manually
- Reinventing well-solved problems
- Higher risk of bugs and incompatibilities

**Rationale for Rejection:** Custom implementation provides no significant benefits over the official SDK while introducing maintenance burden and compatibility risks.

### Option C: Hybrid Approach - Thin Wrapper

**Description:** Use opentelemetry-sdk for export, custom formatter for RAAF-specific logic

**Pros:**
- Leverage OTel SDK for protocol handling
- Custom logic only for RAAF → OTel mapping
- Balanced approach

**Cons:**
- Still adds dependency
- More complexity than Option A

**Rationale for Rejection:** Option A already provides flexibility for custom formatting via the formatter class, making this hybrid unnecessary.

## Selected Approach: Option A (opentelemetry-sdk)

**Rationale:**
1. **Standards Compliance:** Using official SDK ensures 100% protocol compliance
2. **Maintenance:** OTel community maintains protocol implementation
3. **Features:** Get batching, retry, compression, etc. for free
4. **Future-Proof:** Automatic support for new OTel features
5. **Trust:** Official implementation reduces compatibility concerns

## External Dependencies

### New Gems

- **opentelemetry-sdk (~> 1.3)**
  - Purpose: Core OpenTelemetry SDK for span creation and management
  - Justification: Official Ruby implementation, required for OTel integration
  - License: Apache 2.0 (compatible)
  - Maintenance: Active, maintained by OTel community

- **opentelemetry-exporter-otlp (~> 0.26)**
  - Purpose: OTLP protocol exporter (HTTP and gRPC)
  - Justification: Official exporter for OTLP protocol
  - License: Apache 2.0 (compatible)
  - Maintenance: Active, part of opentelemetry-ruby repository

- **opentelemetry-semantic_conventions (~> 1.10)** (optional)
  - Purpose: Standard attribute names for AI/LLM traces
  - Justification: Provides constants for gen_ai.* attributes
  - License: Apache 2.0 (compatible)
  - Maintenance: Active, updated with OTel spec

### Backend Options (For Testing/Documentation)

- **Jaeger** (Docker image: jaegertracing/all-in-one:latest)
  - Purpose: Local development and testing backend
  - Justification: Most popular open-source tracing backend
  - Used for: Integration tests, documentation examples

- **Grafana Tempo** (Docker image: grafana/tempo:latest)
  - Purpose: Alternative backend for testing
  - Justification: Cloud-native, cost-effective option
  - Used for: Documentation examples

## Architecture Diagrams

### Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      RAAF Application                        │
│                                                              │
│  ┌──────────────┐                                           │
│  │ RAAF::Agent  │ ──> Executes                              │
│  └──────────────┘                                           │
│         │                                                    │
│         v                                                    │
│  ┌──────────────┐                                           │
│  │RAAF::Runner  │ ──> Manages execution & tracing           │
│  └──────────────┘                                           │
│         │                                                    │
│         v                                                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         RAAF::Tracing::SpanTracer                    │  │
│  │  ┌──────────────────────────────────────────┐        │  │
│  │  │  Creates spans with RAAF-specific data   │        │  │
│  │  └──────────────────────────────────────────┘        │  │
│  └──────────────────────────────────────────────────────┘  │
│         │                                                    │
│         v                                                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           Span Processors (Parallel)                 │  │
│  │  ┌────────────────┐  ┌──────────────┐  ┌──────────┐ │  │
│  │  │ ConsoleProc    │  │ OpenAIProc   │  │ OTelExp  │ │  │
│  │  │ (existing)     │  │ (existing)   │  │ (NEW)    │ │  │
│  │  └────────────────┘  └──────────────┘  └──────────┘ │  │
│  └──────────────────────────────────────────────────────┘  │
│                                              │               │
└──────────────────────────────────────────────┼──────────────┘
                                               │
                                               v
                        ┌──────────────────────────────────┐
                        │   RAAF::Tracing::OTelExporter    │
                        │  ┌────────────────────────────┐  │
                        │  │  OTelFormatter             │  │
                        │  │  (RAAF → OTel mapping)     │  │
                        │  └────────────────────────────┘  │
                        │             │                     │
                        │             v                     │
                        │  ┌────────────────────────────┐  │
                        │  │ opentelemetry-exporter-otlp│  │
                        │  │ (Official OTel SDK)        │  │
                        │  └────────────────────────────┘  │
                        └──────────────────────────────────┘
                                       │
                                       │ OTLP/HTTP or OTLP/gRPC
                                       v
                        ┌──────────────────────────────────┐
                        │   OTLP-Compatible Backend        │
                        │  ┌────────────────────────────┐  │
                        │  │ Jaeger / Tempo / Datadog   │  │
                        │  │ New Relic / Honeycomb      │  │
                        │  │ OTel Collector             │  │
                        │  └────────────────────────────┘  │
                        └──────────────────────────────────┘
```

### Data Flow

```
RAAF Span Format                   OTel ResourceSpans Format
┌────────────────────┐            ┌─────────────────────────────┐
│ span_id            │            │ resource:                   │
│ trace_id           │            │   attributes:               │
│ parent_id          │   ────>    │     service.name: "raaf"    │
│ name               │            │ scope_spans:                │
│ start_time         │            │   - scope:                  │
│ end_time           │            │       name: "raaf-tracing"  │
│ attributes:        │            │     spans:                  │
│   model: "gpt-4o"  │            │       - span_id             │
│   temperature: 0.7 │            │         trace_id            │
│   tokens: {...}    │            │         parent_span_id      │
│ events: [...]      │            │         name                │
│ status: {...}      │            │         start_time_unix_nano│
│                    │            │         end_time_unix_nano  │
└────────────────────┘            │         attributes:         │
                                  │           gen_ai.system     │
                                  │           gen_ai.request... │
                                  │           raaf.agent_name   │
                                  │         events: [...]       │
                                  │         status: {...}       │
                                  └─────────────────────────────┘
```

## Implementation Details

### OTelFormatter Mapping

```ruby
module RAAF
  module Tracing
    class OTelFormatter
      # Map RAAF span to OpenTelemetry ResourceSpans
      def to_otlp_span(raaf_span)
        {
          resource: build_resource(raaf_span),
          scope_spans: [
            {
              scope: build_scope,
              spans: [build_span(raaf_span)]
            }
          ]
        }
      end

      private

      def build_resource(raaf_span)
        {
          attributes: [
            { key: 'service.name', value: { string_value: 'raaf' } },
            { key: 'service.version', value: { string_value: RAAF::VERSION } },
            { key: 'telemetry.sdk.name', value: { string_value: 'raaf' } },
            { key: 'telemetry.sdk.language', value: { string_value: 'ruby' } },
            { key: 'telemetry.sdk.version', value: { string_value: RAAF::VERSION } }
          ]
        }
      end

      def build_scope
        {
          name: 'raaf-tracing',
          version: RAAF::Tracing::VERSION
        }
      end

      def build_span(raaf_span)
        {
          span_id: encode_span_id(raaf_span[:span_id]),
          trace_id: encode_trace_id(raaf_span[:trace_id]),
          parent_span_id: raaf_span[:parent_id] ? encode_span_id(raaf_span[:parent_id]) : nil,
          name: raaf_span[:name],
          kind: map_span_kind(raaf_span[:span_kind]),
          start_time_unix_nano: time_to_nano(raaf_span[:start_time]),
          end_time_unix_nano: time_to_nano(raaf_span[:end_time]),
          attributes: build_attributes(raaf_span[:attributes]),
          events: build_events(raaf_span[:events]),
          status: build_status(raaf_span[:status])
        }
      end

      def build_attributes(raaf_attrs)
        otel_attrs = []

        # Map standard AI attributes
        if raaf_attrs[:model]
          otel_attrs << { key: 'gen_ai.request.model', value: { string_value: raaf_attrs[:model] } }
        end

        if raaf_attrs[:provider]
          otel_attrs << { key: 'gen_ai.system', value: { string_value: raaf_attrs[:provider] } }
        end

        if raaf_attrs[:temperature]
          otel_attrs << { key: 'gen_ai.request.temperature', value: { double_value: raaf_attrs[:temperature] } }
        end

        # Map token usage
        if raaf_attrs[:usage]
          otel_attrs << { key: 'gen_ai.usage.prompt_tokens', value: { int_value: raaf_attrs[:usage][:prompt_tokens] } }
          otel_attrs << { key: 'gen_ai.usage.completion_tokens', value: { int_value: raaf_attrs[:usage][:completion_tokens] } }
        end

        # Preserve RAAF-specific attributes with raaf.* prefix
        raaf_attrs.each do |key, value|
          next if [:model, :provider, :temperature, :usage].include?(key)
          otel_attrs << { key: "raaf.#{key}", value: to_otel_value(value) }
        end

        otel_attrs
      end

      def map_span_kind(raaf_kind)
        case raaf_kind
        when 'agent' then :SPAN_KIND_INTERNAL
        when 'response' then :SPAN_KIND_CLIENT
        when 'tool' then :SPAN_KIND_INTERNAL
        else :SPAN_KIND_UNSPECIFIED
        end
      end

      # Convert Time to nanoseconds since Unix epoch
      def time_to_nano(time)
        return nil unless time
        time.to_i * 1_000_000_000 + time.nsec
      end

      # Encode span/trace IDs to OTLP format (16 bytes for span, 32 for trace)
      def encode_span_id(id)
        # Implementation depends on RAAF's ID format
        # OTLP expects 8-byte (16 hex chars) span IDs
        id.to_s.rjust(16, '0')[0..15]
      end

      def encode_trace_id(id)
        # OTLP expects 16-byte (32 hex chars) trace IDs
        id.to_s.rjust(32, '0')[0..31]
      end
    end
  end
end
```

### Configuration Example

```ruby
# config/initializers/raaf_tracing.rb (Rails)
# or in application bootstrap code

RAAF::Tracing.configure do |config|
  # Existing processors continue to work
  config.add_processor(RAAF::Tracing::ConsoleProcessor.new) if Rails.env.development?
  config.add_processor(RAAF::Tracing::OpenAIProcessor.new) if ENV['OPENAI_API_KEY']

  # NEW: Add OTLP export if enabled
  if ENV['OTEL_EXPORTER_OTLP_ENDPOINT']
    config.add_processor(
      RAAF::Tracing::OTelExporter.new(
        endpoint: ENV['OTEL_EXPORTER_OTLP_ENDPOINT'],
        protocol: ENV['OTEL_EXPORTER_OTLP_PROTOCOL']&.to_sym || :http,
        headers: parse_otel_headers(ENV['OTEL_EXPORTER_OTLP_HEADERS']),
        batch_size: ENV['RAAF_OTLP_BATCH_SIZE']&.to_i || 100,
        timeout: ENV['RAAF_OTLP_TIMEOUT']&.to_i || 10
      )
    )
  end
end

def parse_otel_headers(headers_string)
  return {} unless headers_string
  headers_string.split(',').each_with_object({}) do |header, hash|
    key, value = header.split('=')
    hash[key.strip] = value.strip
  end
end
```

## Performance Considerations

1. **Async Export:** Use background threads for OTLP export to not block agent execution
2. **Batching:** Export spans in batches of 100 (configurable) to reduce network overhead
3. **Compression:** Enable gzip compression for HTTP exports (reduces payload size by ~70%)
4. **Retry Logic:** Exponential backoff with max 3 retries to handle transient failures
5. **Circuit Breaker:** Disable OTLP export temporarily if failure rate exceeds threshold

## Security Considerations

1. **Authentication:** Support custom headers for API key/token authentication
2. **TLS:** Use HTTPS for OTLP/HTTP endpoints by default
3. **PII Redaction:** Leverage existing RAAF PII detection before export
4. **Secrets:** Never log OTLP endpoint credentials or headers
5. **Network Isolation:** Support private network endpoints for enterprise deployments
