# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-08-25-enhanced-agent-tracing-ui/spec.md

> Created: 2025-08-25
> Version: 1.0.0

## Test Coverage

### Unit Tests

**RAAF::Tracing::SpanRecord (Enhanced Model)**
- Validates new JSONB fields (agent_name, prompt_data, input_context, output_context, chat_messages, execution_metadata)
- Tests JSONB field serialization and deserialization
- Tests new query methods and scopes for enhanced data
- Validates data size limits and sanitization
- Tests new helper methods for extracting agent-specific information

**RAAF::Tracing::EnhancedSpanProcessor**
- Tests extraction of agent names from span attributes
- Tests prompt data extraction and formatting
- Tests input/output context capture and validation
- Tests chat message array construction
- Tests execution metadata compilation
- Tests error handling for malformed data

**Enhanced Helper Methods**
- Tests duration_display formatting for various time ranges
- Tests data_size calculations for different payload sizes  
- Tests JSON formatting and syntax highlighting helpers
- Tests time zone handling for timestamp displays

### Integration Tests

**Enhanced Traces Controller**
- Tests index action with filtering by agent name, date range, and workflow
- Tests search functionality across JSON fields
- Tests pagination with large datasets
- Tests JSON API responses for programmatic access
- Tests show action with complete span details including enhanced data
- Tests error handling for missing traces and malformed parameters

**JSON Data Controller**
- Tests dynamic JSON field loading for large payloads
- Tests field-specific data retrieval (prompt_data, input_context, etc.)
- Tests JSON formatting and syntax highlighting
- Tests error handling for invalid span IDs and missing fields
- Tests response caching for improved performance

**Database Migration Integration**
- Tests migration up/down functionality
- Tests index creation and performance impact
- Tests data preservation during schema changes
- Tests rollback scenarios and data recovery

### Feature Tests

**Complete Agent Tracing Workflow**
- User visits enhanced traces dashboard
- User filters traces by agent name and sees relevant results
- User clicks on trace to view detailed agent execution flow
- User expands JSON sections to inspect input/output context
- User copies JSON data to clipboard
- User navigates between different agent executions within same trace

**Interactive JSON Viewer**
- User expands/collapses individual JSON sections
- User uses "Expand All" and "Collapse All" controls
- User searches within large JSON structures
- User copies specific JSON sections
- JSON syntax highlighting displays correctly
- Responsive design works on mobile devices

**Search and Filtering**
- User searches across all enhanced fields using text input
- User filters by date range and sees chronologically filtered results
- User combines multiple filters (agent + date + workflow)
- User exports filtered results
- Search results highlight matching content
- Pagination works correctly with filtered results

### JavaScript/Stimulus Tests

**JSON Viewer Controller**
- Tests toggle functionality for expand/collapse
- Tests expandAll() and collapseAll() methods
- Tests lazy loading of large JSON data
- Tests copy-to-clipboard functionality
- Tests keyboard navigation and accessibility
- Tests error handling for failed AJAX requests

**Search Controller**
- Tests real-time search with debouncing
- Tests filter form submission and URL parameter handling
- Tests results updating without page refresh
- Tests search history and browser back/forward navigation

### Performance Tests

**Database Query Performance**
- Tests JSONB index usage for filtering operations
- Tests pagination performance with large datasets (>100k records)
- Tests complex queries combining multiple JSON fields
- Tests query performance with different data payload sizes
- Benchmarks index-only scans vs full table scans

**Frontend Performance**
- Tests JavaScript performance with large JSON structures (>1MB)
- Tests rendering performance with many expandable sections (>100)
- Tests memory usage during prolonged browsing sessions
- Tests browser compatibility across major browsers

**UI Responsiveness**
- Tests page load times for dashboard with various data volumes
- Tests JSON expansion/collapse response times
- Tests search response times with different query complexities
- Tests mobile device performance and touch interactions

### Security Tests

**Input Validation and Sanitization**
- Tests XSS prevention in JSON display components
- Tests SQL injection protection in search parameters
- Tests CSRF protection on all forms
- Tests parameter validation for malicious payloads
- Tests access control for sensitive tracing data

**Data Privacy**
- Tests PII redaction in captured context data
- Tests data anonymization for demo/testing environments
- Tests access logging for audit trails
- Tests data retention policy enforcement

### Mocking Requirements

**External API Calls**
- Mock OpenAI API responses for agent execution testing
- Mock large JSON payloads for performance testing
- Use VCR cassettes for consistent test data across runs

**Database Operations**
- Mock expensive JSONB operations in unit tests
- Use database transactions for test isolation
- Mock migration operations for faster test suite execution

**File System Operations**
- Mock JSON export functionality
- Mock file uploads for bulk data import testing

### Test Data Factories

**SpanRecord Factory with Enhanced Data**
```ruby
FactoryBot.define do
  factory :enhanced_span, class: 'RAAF::Tracing::SpanRecord' do
    span_id { "span_#{SecureRandom.hex(12)}" }
    trace_id { "trace_#{SecureRandom.alphanumeric(32)}" }
    name { "test_operation" }
    kind { "agent" }
    agent_name { "TestAgent" }
    start_time { 1.hour.ago }
    end_time { 30.minutes.ago }
    duration_ms { 1_800_000 }
    status { "ok" }
    
    prompt_data do
      {
        text: "Analyze the provided data for insights",
        template: "Analyze the #{data_type} data for #{analysis_focus}",
        variables: { data_type: "customer", analysis_focus: "insights" },
        model: "gpt-4o",
        temperature: 0.7
      }
    end
    
    input_context do
      {
        data: { records: (1..10).map { |i| { id: i, value: "record_#{i}" } } },
        schema: { records: "array" },
        validation_results: [{ field: "records", status: "valid" }]
      }
    end
    
    output_context do
      {
        data: { insights: ["Insight 1", "Insight 2"], confidence: 0.87 },
        schema: { insights: "array", confidence: "float" },
        transformations: [{ step: "analysis", duration_ms: 1250 }]
      }
    end
    
    chat_messages do
      [
        { role: "system", content: "You are a helpful analyst", timestamp: 2.hours.ago.iso8601 },
        { role: "user", content: "Analyze this data", timestamp: 1.hour.ago.iso8601 },
        { role: "assistant", content: "Here are the insights...", timestamp: 30.minutes.ago.iso8601 }
      ]
    end
    
    execution_metadata do
      {
        agent_class: "TestAgent",
        start_time: start_time.iso8601,
        end_time: end_time.iso8601,
        tools_used: ["data_analyzer"],
        memory_usage_mb: 45.2
      }
    end
    
    trait :with_large_payload do
      input_context do
        {
          data: { large_array: (1..1000).to_a },
          schema: { large_array: "array" }
        }
      end
    end
    
    trait :with_error do
      status { "error" }
      execution_metadata do
        {
          agent_class: "TestAgent",
          error_info: {
            type: "RuntimeError",
            message: "Test error",
            stacktrace: "line 1\nline 2"
          }
        }
      end
    end
  end
end
```

**TraceRecord Factory for Testing**
```ruby
FactoryBot.define do
  factory :enhanced_trace, class: 'RAAF::Tracing::TraceRecord' do
    trace_id { "trace_#{SecureRandom.alphanumeric(32)}" }
    workflow_name { "Test Workflow" }
    status { "completed" }
    started_at { 2.hours.ago }
    ended_at { 1.hour.ago }
    
    trait :with_multiple_agents do
      after(:create) do |trace|
        create_list(:enhanced_span, 3, trace_id: trace.trace_id, 
                   agent_name: "Agent#{rand(1..3)}")
      end
    end
    
    trait :long_running do
      started_at { 24.hours.ago }
      ended_at { 23.hours.ago }
    end
  end
end
```

### Test Configuration

**RSpec Configuration for Enhanced Features**
```ruby
# spec/rails_helper.rb additions
RSpec.configure do |config|
  # Database cleaner for JSONB fields
  config.before(:each, type: :feature) do
    DatabaseCleaner.strategy = :truncation
  end
  
  # Shared examples for JSON field testing
  config.include_context "json_field_validation", type: :model
  config.include JSONTestHelpers, type: :controller
end
```

**Shared Examples for JSON Validation**
```ruby
# spec/support/shared_examples/json_field_validation.rb
RSpec.shared_examples "json_field_validation" do |field_name|
  it "accepts valid JSON for #{field_name}" do
    subject.send("#{field_name}=", { key: "value" })
    expect(subject).to be_valid
  end
  
  it "handles nil values for #{field_name}" do
    subject.send("#{field_name}=", nil)
    expect(subject).to be_valid
  end
  
  it "serializes and deserializes #{field_name} correctly" do
    data = { nested: { array: [1, 2, 3] } }
    subject.send("#{field_name}=", data)
    subject.save!
    subject.reload
    expect(subject.send(field_name)).to eq(data.stringify_keys)
  end
end
```

### Continuous Integration Test Pipeline

**Test Stages**
1. **Unit Tests**: Fast model and helper tests (< 30 seconds)
2. **Integration Tests**: Controller and API tests (< 2 minutes)  
3. **Feature Tests**: Full browser tests with Capybara (< 5 minutes)
4. **Performance Tests**: Database and frontend benchmarks (< 3 minutes)
5. **Security Tests**: Vulnerability scanning (< 1 minute)

**Browser Test Matrix**
- Chrome (latest)
- Firefox (latest)
- Safari (latest)
- Mobile browsers (iOS Safari, Chrome Mobile)

**Database Test Matrix**
- PostgreSQL 14+ (primary)
- PostgreSQL 13 (compatibility)
- Different data volumes (1K, 10K, 100K records)

### Test Metrics and Coverage Goals

**Coverage Targets**
- Unit Tests: 95% line coverage
- Integration Tests: 90% path coverage  
- Feature Tests: 100% user story coverage
- JavaScript Tests: 85% statement coverage

**Performance Benchmarks**
- Dashboard page load: < 2 seconds
- JSON expansion: < 200ms
- Search results: < 1 second
- Database queries: < 100ms (95th percentile)