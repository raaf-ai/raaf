# Spec Requirements Document

> Spec: OpenTelemetry Protocol Support
> Created: 2025-11-12
> Status: Planning

## Overview

Implement OpenTelemetry (OTel) protocol support in RAAF to enable interoperability with industry-standard observability tools and backends. This feature will allow RAAF traces and spans to be exported to any OTLP-compatible system (Jaeger, Tempo, Datadog, New Relic, etc.) while maintaining backward compatibility with existing RAAF infrastructure.

## User Stories

### Story 1: DevOps Engineer Wants Unified Observability

As a DevOps engineer running RAAF-powered applications in production, I want to send RAAF traces to our existing observability platform (Jaeger/Grafana/Datadog), so that I can monitor AI agent behavior alongside traditional application metrics in a single dashboard.

**Workflow:**
1. Configure RAAF to export traces via OTLP protocol
2. Point OTLP exporter to existing Jaeger/Tempo/Datadog endpoint
3. View RAAF agent traces in familiar observability UI
4. Correlate AI agent behavior with application performance
5. Set up alerts based on AI agent metrics

**Problem Solved:** Eliminates need for separate monitoring systems for AI agents vs traditional application code.

### Story 2: RAAF Developer Wants Standards Compliance

As a RAAF framework developer, I want to use OpenTelemetry standard protocol for tracing, so that RAAF integrates seamlessly with the broader observability ecosystem and benefits from evolving OTel AI conventions.

**Workflow:**
1. Export RAAF spans using OTLP/HTTP or OTLP/gRPC protocol
2. Leverage OpenTelemetry semantic conventions for AI/LLM traces
3. Use standard OTel SDKs and libraries for export
4. Validate against OpenTelemetry specification compliance
5. Participate in OTel AI working group discussions

**Problem Solved:** Future-proofs RAAF tracing against industry standards and reduces custom protocol maintenance.

### Story 3: Application Developer Wants Flexible Backend Choice

As an application developer using RAAF, I want to choose my preferred trace storage backend (local Jaeger, cloud Tempo, managed Datadog), so that I can optimize for cost, performance, and existing infrastructure.

**Workflow:**
1. Enable OTLP export in RAAF configuration
2. Configure endpoint for chosen backend (environment variable)
3. Optionally keep existing RAAF processors (Console, OpenAI) alongside OTLP
4. Switch backends by changing configuration without code changes
5. Use backend's native query/visualization tools

**Problem Solved:** Provides flexibility without vendor lock-in to RAAF's built-in tracing storage.

## Spec Scope

### In Scope

1. **OTLP Exporter Implementation**
   - OTLP/HTTP protocol support (primary)
   - OTLP/gRPC protocol support (optional)
   - Integration with opentelemetry-exporter-otlp gem

2. **Span Format Conversion**
   - Map RAAF span structure to OpenTelemetry ResourceSpans format
   - Implement OTel semantic conventions for AI/LLM attributes
   - Preserve RAAF-specific attributes as custom attributes

3. **Configuration Interface**
   - Environment variable configuration (OTEL_EXPORTER_OTLP_ENDPOINT, etc.)
   - Programmatic configuration via RAAF::Tracing.configure
   - Optional OTLP export alongside existing processors

4. **Backend Compatibility**
   - Jaeger compatibility validation
   - Grafana Tempo compatibility validation
   - OpenTelemetry Collector compatibility

5. **Documentation**
   - Setup guide for common backends (Jaeger, Tempo)
   - Configuration reference
   - Migration guide from RAAF-only tracing

### Out of Scope

1. **Custom Backend Implementation** - Use existing OTLP-compatible backends, don't build new storage
2. **Query/Fetch API Migration** - Keep existing RAAF query APIs, OTLP is export-only for now
3. **Metrics and Logs** - Focus on traces/spans only (OTel supports metrics/logs but defer for Phase 2)
4. **Automatic Instrumentation** - RAAF already has instrumentation, no need to re-instrument
5. **Breaking Changes** - Maintain full backward compatibility with existing RAAF tracing

## Expected Deliverable

### Testable Outcomes (Browser/Integration Tests)

1. **OTLP Export Functionality**
   - RAAF agent executes and generates spans
   - Spans are exported to OTLP endpoint via HTTP
   - Spans appear in Jaeger UI with correct structure
   - Span attributes match OpenTelemetry conventions

2. **Configuration Flexibility**
   - Can enable/disable OTLP export via environment variable
   - Can configure OTLP endpoint via OTEL_EXPORTER_OTLP_ENDPOINT
   - Can run OTLP exporter alongside existing processors (Console, OpenAI)
   - Can switch between HTTP and gRPC protocols via configuration

3. **Backward Compatibility**
   - Existing RAAF tracing code works unchanged
   - Console and OpenAI processors continue to function
   - RAAF-eval can still query local spans if OTLP-only mode not enabled
   - No performance degradation when OTLP export disabled

### Code Deliverables

1. **New Classes/Modules**
   - `RAAF::Tracing::OTelExporter` - Main OTLP exporter processor
   - `RAAF::Tracing::OTelFormatter` - Span format converter
   - `RAAF::Tracing::OTelConfig` - Configuration management

2. **Updated Documentation**
   - `raaf/tracing/OPENTELEMETRY.md` - Setup and usage guide
   - Update `raaf/tracing/CLAUDE.md` with OTLP information
   - Add examples in `raaf/tracing/examples/otlp_export.rb`

3. **Tests**
   - RSpec tests for OTelExporter functionality
   - Integration tests with local Jaeger instance
   - Format conversion tests (RAAF → OTLP)
   - Configuration tests (environment variables, programmatic)

## Spec Documentation

- Tasks: @.agent-os/specs/2025-11-12-opentelemetry-protocol-support/tasks.md
- Technical Specification: @.agent-os/specs/2025-11-12-opentelemetry-protocol-support/sub-specs/technical-spec.md
- Database Schema: @.agent-os/specs/2025-11-12-opentelemetry-protocol-support/sub-specs/database-schema.md
- Tests Specification: @.agent-os/specs/2025-11-12-opentelemetry-protocol-support/sub-specs/tests.md
