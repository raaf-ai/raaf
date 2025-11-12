# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-11-12-opentelemetry-protocol-support/spec.md

> Created: 2025-11-12
> Version: 1.0.0

## Test Coverage

### Unit Tests

**RAAF::Tracing::OTelExporter**
- Initialize with valid endpoint and configuration
- Initialize with default configuration from environment variables
- Export single span successfully
- Export batch of spans successfully
- Handle export failures gracefully with retries
- Respect batch size configuration
- Respect timeout configuration
- Shutdown cleanly without losing queued spans
- Handle invalid endpoint gracefully
- Handle network errors with exponential backoff

**RAAF::Tracing::OTelFormatter**
- Convert RAAF span to OTLP ResourceSpans format
- Map RAAF span_id to OTLP span_id (8-byte encoding)
- Map RAAF trace_id to OTLP trace_id (16-byte encoding)
- Map RAAF attributes to OpenTelemetry semantic conventions
- Map gen_ai.system from RAAF provider attribute
- Map gen_ai.request.model from RAAF model attribute
- Map gen_ai.request.temperature from RAAF temperature attribute
- Map gen_ai.usage.prompt_tokens from RAAF token usage
- Map gen_ai.usage.completion_tokens from RAAF token usage
- Preserve RAAF-specific attributes with raaf.* prefix
- Convert RAAF events to OTLP span events
- Convert RAAF status to OTLP status
- Handle nil/missing parent_id correctly
- Convert timestamps to nanoseconds since Unix epoch
- Map RAAF span_kind to OTLP SpanKind enum
- Handle nested attributes correctly
- Handle array attributes correctly
- Handle nil values in attributes

**RAAF::Tracing::OTelConfig**
- Load configuration from environment variables
- Parse OTEL_EXPORTER_OTLP_ENDPOINT
- Parse OTEL_EXPORTER_OTLP_PROTOCOL (http vs grpc)
- Parse OTEL_EXPORTER_OTLP_HEADERS (comma-separated key=value)
- Parse RAAF_OTLP_BATCH_SIZE with default fallback
- Parse RAAF_OTLP_TIMEOUT with default fallback
- Validate endpoint URL format
- Validate protocol value (http or grpc only)
- Merge programmatic config with environment variables
- Programmatic config overrides environment variables

### Integration Tests

**End-to-End OTLP Export**
- Create RAAF agent with OTLP exporter enabled
- Execute agent and generate spans
- Verify spans exported to OTLP endpoint
- Verify spans contain correct OTLP format
- Verify spans contain AI semantic conventions
- Verify batch export with multiple spans
- Verify concurrent span export from multiple agents

**Jaeger Backend Integration**
- Start local Jaeger instance (via Docker)
- Configure RAAF to export to Jaeger OTLP endpoint
- Execute RAAF agent with tool calls and handoffs
- Query Jaeger API for exported traces
- Verify trace structure in Jaeger (parent-child relationships)
- Verify span attributes visible in Jaeger UI
- Verify events visible in Jaeger UI

**Grafana Tempo Integration**
- Start local Tempo instance (via Docker)
- Configure RAAF to export to Tempo OTLP endpoint
- Execute RAAF agent with complex workflow
- Query Tempo API for exported traces
- Verify trace data matches RAAF execution

**Multi-Processor Integration**
- Configure RAAF with Console, OpenAI, and OTLP processors
- Execute agent and generate spans
- Verify all three processors receive spans
- Verify OTLP export doesn't interfere with other processors
- Verify performance impact is minimal (< 5ms added latency)

**Error Handling Integration**
- Configure OTLP exporter with unreachable endpoint
- Execute agent and verify span processing continues
- Verify retry logic activates (3 retries with backoff)
- Verify errors logged appropriately
- Verify circuit breaker triggers after persistent failures
- Verify normal operation resumes when endpoint recovers

### Performance Tests

**Latency Benchmarks**
- Measure OTLP export latency for single span (target: < 5ms)
- Measure OTLP export latency for batch of 100 spans (target: < 50ms)
- Measure impact on agent execution time (target: < 1% overhead)
- Measure memory usage with OTLP export enabled (target: linear scaling)

**Throughput Benchmarks**
- Export 1,000 spans/second sustained throughput
- Export 10,000 spans with batching enabled
- Verify no span loss during high-volume export
- Measure CPU usage during sustained export

**Stress Tests**
- Export 100,000 spans continuously
- Verify memory doesn't grow unbounded
- Verify export queue doesn't grow unbounded
- Recover gracefully from network interruptions

### Compatibility Tests

**OpenAI Provider Compatibility**
- Export spans from OpenAI provider (gpt-4o, gpt-4, gpt-3.5-turbo)
- Verify gen_ai.system = "openai"
- Verify model names mapped correctly

**Anthropic Provider Compatibility**
- Export spans from Anthropic provider (claude-3-5-sonnet, claude-3-opus)
- Verify gen_ai.system = "anthropic"
- Verify model names mapped correctly

**Gemini Provider Compatibility**
- Export spans from Gemini provider (gemini-2.0-flash-exp)
- Verify gen_ai.system = "gemini"
- Verify model names mapped correctly

**Multi-Provider Workflow**
- Execute agent workflow with multiple providers
- Verify all spans exported with correct provider attribution
- Verify trace continuity across provider boundaries

**Tool Call Tracing**
- Export spans with tool calls
- Verify tool spans as children of agent spans
- Verify tool attributes preserved in OTLP format

**Handoff Tracing**
- Export spans with agent handoffs
- Verify handoff spans maintain trace continuity
- Verify parent-child relationships correct

### Regression Tests

**Backward Compatibility**
- Verify existing Console processor still works with OTLP enabled
- Verify existing OpenAI processor still works with OTLP enabled
- Verify raaf-eval can still query local spans with OTLP enabled
- Verify no changes to existing RAAF span format
- Verify no breaking changes to processor API

**Configuration Compatibility**
- Verify OTLP export can be disabled via environment variable
- Verify graceful degradation if OTLP endpoint unavailable
- Verify no errors if opentelemetry-exporter-otlp gem not installed

## Mocking Requirements

### Mock OTLP Endpoint

```ruby
# spec/support/mock_otlp_endpoint.rb
class MockOTLPEndpoint
  attr_reader :received_spans, :request_count

  def initialize(port: 4318)
    @port = port
    @received_spans = []
    @request_count = 0
    start_server
  end

  def start_server
    @server = WEBrick::HTTPServer.new(Port: @port, Logger: WEBrick::Log.new("/dev/null"))
    @server.mount_proc('/v1/traces') do |req, res|
      @request_count += 1
      payload = decode_otlp_payload(req.body)
      @received_spans.concat(extract_spans(payload))
      res.status = 200
      res.body = '{}'
    end
    Thread.new { @server.start }
  end

  def stop
    @server.shutdown if @server
  end

  def reset
    @received_spans = []
    @request_count = 0
  end

  private

  def decode_otlp_payload(body)
    # Decode Protobuf or JSON payload depending on content-type
    JSON.parse(body)
  end

  def extract_spans(payload)
    # Extract spans from OTLP ResourceSpans structure
    payload.dig('resourceSpans', 0, 'scopeSpans', 0, 'spans') || []
  end
end

# Usage in tests
RSpec.describe RAAF::Tracing::OTelExporter do
  let(:mock_endpoint) { MockOTLPEndpoint.new }
  after { mock_endpoint.stop }

  it 'exports spans to OTLP endpoint' do
    exporter = RAAF::Tracing::OTelExporter.new(
      endpoint: "http://localhost:4318/v1/traces"
    )

    span = create_raaf_span(name: "test_span")
    exporter.process_span(span)

    expect(mock_endpoint.received_spans).to have(1).item
    expect(mock_endpoint.received_spans.first['name']).to eq('test_span')
  end
end
```

### Mock OpenTelemetry Exporter

```ruby
# spec/support/mock_otel_exporter.rb
class MockOTelExporter
  attr_reader :exported_spans, :export_calls

  def initialize
    @exported_spans = []
    @export_calls = 0
  end

  def export(spans)
    @export_calls += 1
    @exported_spans.concat(spans)
    OpenTelemetry::SDK::Trace::Export::SUCCESS
  end

  def shutdown
    OpenTelemetry::SDK::Trace::Export::SUCCESS
  end

  def reset
    @exported_spans = []
    @export_calls = 0
  end
end

# Usage in tests
RSpec.describe RAAF::Tracing::OTelFormatter do
  let(:mock_exporter) { MockOTelExporter.new }

  it 'formats RAAF span to OTLP format' do
    formatter = RAAF::Tracing::OTelFormatter.new
    raaf_span = create_raaf_span(
      name: "agent_span",
      attributes: { model: "gpt-4o", temperature: 0.7 }
    )

    otlp_span = formatter.to_otlp_span(raaf_span)

    expect(otlp_span[:name]).to eq('agent_span')
    expect(otlp_span[:attributes]).to include(
      { key: 'gen_ai.request.model', value: { string_value: 'gpt-4o' } }
    )
  end
end
```

### Docker Compose for Integration Tests

```yaml
# spec/support/docker-compose.yml
version: '3.8'

services:
  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "4317:4317"  # OTLP gRPC
      - "4318:4318"  # OTLP HTTP
      - "16686:16686"  # Jaeger UI
    environment:
      - COLLECTOR_OTLP_ENABLED=true

  tempo:
    image: grafana/tempo:latest
    command: ["-config.file=/etc/tempo.yaml"]
    ports:
      - "4319:4318"  # OTLP HTTP (different port to avoid conflict)
    volumes:
      - ./tempo-config.yaml:/etc/tempo.yaml

  otel-collector:
    image: otel/opentelemetry-collector:latest
    command: ["--config=/etc/otel-collector-config.yaml"]
    ports:
      - "4320:4318"  # OTLP HTTP
    volumes:
      - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml
```

## Test Execution Strategy

### Local Development
```bash
# Run unit tests only (fast feedback)
cd raaf/tracing
bundle exec rspec spec/unit/

# Run integration tests (requires Docker)
docker-compose -f spec/support/docker-compose.yml up -d
bundle exec rspec spec/integration/
docker-compose -f spec/support/docker-compose.yml down

# Run all tests
bundle exec rspec
```

### CI/CD Pipeline
```yaml
# .github/workflows/test_otlp.yml
name: OTLP Integration Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      jaeger:
        image: jaegertracing/all-in-one:latest
        ports:
          - 4318:4318
        env:
          COLLECTOR_OTLP_ENABLED: true

    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.3
          bundler-cache: true
      - name: Run unit tests
        run: bundle exec rspec spec/unit/
      - name: Run integration tests
        run: bundle exec rspec spec/integration/
        env:
          OTEL_EXPORTER_OTLP_ENDPOINT: http://localhost:4318/v1/traces
```

## Coverage Goals

- **Unit Tests:** 95%+ code coverage for OTelExporter, OTelFormatter, OTelConfig
- **Integration Tests:** 100% coverage of happy path workflows with Jaeger/Tempo
- **Error Handling:** 100% coverage of failure scenarios and retry logic
- **Performance:** All benchmarks pass with < 5ms latency target
- **Compatibility:** All RAAF providers tested with OTLP export
