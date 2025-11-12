# Spec Tasks

These are the tasks to be completed for the spec detailed in @.agent-os/specs/2025-11-12-opentelemetry-protocol-support/spec.md

> Created: 2025-11-12
> Status: Ready for Implementation

## Tasks

- [ ] 1. Setup and Dependencies
  - [ ] 1.1 Add opentelemetry-sdk and opentelemetry-exporter-otlp to raaf-tracing gemspec
  - [ ] 1.2 Add opentelemetry-semantic_conventions gem (optional, for AI attribute constants)
  - [ ] 1.3 Update raaf-tracing README with OTLP support information
  - [ ] 1.4 Create OPENTELEMETRY.md documentation file in raaf/tracing/

- [ ] 2. Implement OTelFormatter
  - [ ] 2.1 Create RAAF::Tracing::OTelFormatter class
  - [ ] 2.2 Implement to_otlp_span method (RAAF span → OTLP ResourceSpans)
  - [ ] 2.3 Implement build_resource method (service metadata)
  - [ ] 2.4 Implement build_scope method (instrumentation scope)
  - [ ] 2.5 Implement build_span method (core span data conversion)
  - [ ] 2.6 Implement build_attributes method (map RAAF → OTel semantic conventions)
  - [ ] 2.7 Implement gen_ai.* attribute mapping (system, model, temperature, tokens)
  - [ ] 2.8 Implement raaf.* custom attribute preservation
  - [ ] 2.9 Implement build_events method (RAAF events → OTLP events)
  - [ ] 2.10 Implement build_status method (RAAF status → OTLP status)
  - [ ] 2.11 Implement time_to_nano conversion (Time → nanoseconds since epoch)
  - [ ] 2.12 Implement encode_span_id method (RAAF ID → 8-byte OTLP format)
  - [ ] 2.13 Implement encode_trace_id method (RAAF ID → 16-byte OTLP format)
  - [ ] 2.14 Implement map_span_kind method (RAAF span_kind → OTLP SpanKind enum)
  - [ ] 2.15 Write unit tests for OTelFormatter (95%+ coverage)

- [ ] 3. Implement OTelConfig
  - [ ] 3.1 Create RAAF::Tracing::OTelConfig class
  - [ ] 3.2 Implement environment variable parsing (OTEL_EXPORTER_OTLP_ENDPOINT)
  - [ ] 3.3 Implement protocol parsing (OTEL_EXPORTER_OTLP_PROTOCOL)
  - [ ] 3.4 Implement headers parsing (OTEL_EXPORTER_OTLP_HEADERS)
  - [ ] 3.5 Implement batch size configuration (RAAF_OTLP_BATCH_SIZE)
  - [ ] 3.6 Implement timeout configuration (RAAF_OTLP_TIMEOUT)
  - [ ] 3.7 Implement configuration validation (endpoint URL, protocol enum)
  - [ ] 3.8 Implement configuration merging (env vars + programmatic config)
  - [ ] 3.9 Write unit tests for OTelConfig (95%+ coverage)

- [ ] 4. Implement OTelExporter
  - [ ] 4.1 Create RAAF::Tracing::OTelExporter class inheriting from BaseProcessor
  - [ ] 4.2 Implement initialize method (create OTel exporter instance)
  - [ ] 4.3 Implement process_span method (format and export single span)
  - [ ] 4.4 Implement batch export logic (collect spans until batch size reached)
  - [ ] 4.5 Implement async export (background thread for network calls)
  - [ ] 4.6 Implement retry logic with exponential backoff (3 retries max)
  - [ ] 4.7 Implement timeout handling (configurable timeout)
  - [ ] 4.8 Implement error logging (export failures, network errors)
  - [ ] 4.9 Implement circuit breaker pattern (disable after persistent failures)
  - [ ] 4.10 Implement shutdown method (flush queued spans, close exporter)
  - [ ] 4.11 Write unit tests for OTelExporter (95%+ coverage)

- [ ] 5. Integration Testing
  - [ ] 5.1 Create Docker Compose file for test backends (Jaeger, Tempo)
  - [ ] 5.2 Create MockOTLPEndpoint test helper
  - [ ] 5.3 Write Jaeger integration tests (export + query verification)
  - [ ] 5.4 Write Tempo integration tests (export + query verification)
  - [ ] 5.5 Write multi-processor integration tests (Console + OpenAI + OTLP)
  - [ ] 5.6 Write error handling integration tests (unreachable endpoint, retries)
  - [ ] 5.7 Write end-to-end workflow test (agent execution → OTLP export → backend query)
  - [ ] 5.8 Verify all integration tests pass

- [ ] 6. Compatibility Testing
  - [ ] 6.1 Test OpenAI provider compatibility (gpt-4o, gpt-4, gpt-3.5-turbo)
  - [ ] 6.2 Test Anthropic provider compatibility (claude-3-5-sonnet, claude-3-opus)
  - [ ] 6.3 Test Gemini provider compatibility (gemini-2.0-flash-exp)
  - [ ] 6.4 Test Perplexity provider compatibility (sonar-pro)
  - [ ] 6.5 Test multi-provider workflow (spans from different providers in same trace)
  - [ ] 6.6 Test tool call tracing (tool spans exported correctly)
  - [ ] 6.7 Test handoff tracing (handoff spans maintain trace continuity)
  - [ ] 6.8 Verify all compatibility tests pass

- [ ] 7. Performance Testing
  - [ ] 7.1 Write latency benchmarks (single span export < 5ms)
  - [ ] 7.2 Write batch latency benchmarks (100 spans < 50ms)
  - [ ] 7.3 Write throughput benchmarks (1000 spans/second sustained)
  - [ ] 7.4 Write memory usage tests (linear scaling with batch size)
  - [ ] 7.5 Write stress tests (100,000 spans continuous export)
  - [ ] 7.6 Verify all performance benchmarks pass

- [ ] 8. Documentation
  - [ ] 8.1 Write OPENTELEMETRY.md setup guide
  - [ ] 8.2 Document Jaeger setup example (Docker Compose)
  - [ ] 8.3 Document Grafana Tempo setup example
  - [ ] 8.4 Document environment variable configuration
  - [ ] 8.5 Document programmatic configuration examples
  - [ ] 8.6 Document AI semantic conventions mapping
  - [ ] 8.7 Update raaf/tracing/CLAUDE.md with OTLP information
  - [ ] 8.8 Create example code in examples/otlp_export.rb
  - [ ] 8.9 Add troubleshooting section to OPENTELEMETRY.md

- [ ] 9. Backward Compatibility Verification
  - [ ] 9.1 Verify existing ConsoleProcessor works with OTLP enabled
  - [ ] 9.2 Verify existing OpenAIProcessor works with OTLP enabled
  - [ ] 9.3 Verify raaf-eval can query local spans with OTLP enabled
  - [ ] 9.4 Verify no changes to existing span format
  - [ ] 9.5 Verify no breaking changes to processor API
  - [ ] 9.6 Verify graceful degradation if OTLP disabled
  - [ ] 9.7 Run full raaf-tracing test suite to catch regressions
  - [ ] 9.8 Verify all backward compatibility tests pass

- [ ] 10. CI/CD Integration
  - [ ] 10.1 Create GitHub Actions workflow for OTLP tests
  - [ ] 10.2 Configure Jaeger service in GitHub Actions
  - [ ] 10.3 Add OTLP integration tests to CI pipeline
  - [ ] 10.4 Add performance benchmarks to CI (with thresholds)
  - [ ] 10.5 Add compatibility tests to CI (all providers)
  - [ ] 10.6 Verify all CI tests pass on pull request

- [ ] 11. Release Preparation
  - [ ] 11.1 Update raaf-tracing CHANGELOG.md
  - [ ] 11.2 Update raaf-tracing version number
  - [ ] 11.3 Update main RAAF CLAUDE.md with OTLP information
  - [ ] 11.4 Create example application demonstrating OTLP export
  - [ ] 11.5 Write blog post announcement (optional)
  - [ ] 11.6 Update raaf-tracing README badges (if applicable)
