# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-11-06-raaf-eval-web-ui/spec.md

> Created: 2025-11-06
> Version: 1.0.0

## Test Coverage

### Unit Tests

**Eval::SpansController**
- Index action lists spans with filters
- Index action applies agent filter
- Index action applies model filter
- Index action applies date range filter
- Index action applies status filter
- Index action paginates results (25/50/100 per page)
- Show action displays span details
- Show action loads associated data (tool calls, handoffs)
- Search action returns matching spans (AJAX)
- Filter action applies filters and returns results (AJAX)
- Handles missing spans gracefully
- Respects user permissions for span access

**Eval::EvaluationsController**
- New action displays evaluation setup form
- New action pre-loads span data
- Create action validates configuration
- Create action creates evaluation record
- Execute action starts async evaluation
- Execute action returns Turbo Stream response
- Status action returns evaluation progress
- Status action updates progress via Turbo Stream
- Results action displays comparison view
- Results action loads baseline and new results
- Show action displays saved evaluation session
- Destroy action deletes evaluation session
- Handles evaluation failures gracefully
- Rate limits concurrent evaluations per user

**Eval::SessionsController**
- Index action lists user's saved sessions
- Index action filters by session type
- Show action loads session with full context
- Show action restores evaluation state
- Create action saves evaluation as named session
- Update action modifies session name/metadata
- Destroy action deletes session and associated data
- Handles session conflicts gracefully

**Components::Eval::SpanBrowser**
- Renders filterable table with correct columns
- Renders filter dropdowns with options
- Renders search bar with debounce
- Renders pagination controls
- Renders row selection checkboxes
- Renders expandable row details
- Renders loading states during AJAX
- Renders empty state with helpful message
- Applies correct CSS classes from raaf-rails
- Handles large datasets efficiently

**Components::Eval::SpanDetail**
- Renders three-section layout (input, output, metadata)
- Renders syntax-highlighted JSON
- Renders expandable tool calls
- Renders expandable handoffs
- Renders timeline for multi-turn conversations
- Renders token and cost breakdown
- Renders copy-to-clipboard buttons
- Handles missing data gracefully
- Applies correct styling from raaf-rails

**Components::Eval::PromptEditor**
- Renders split-pane layout (original vs modified)
- Renders Monaco Editor container
- Renders estimated token count
- Renders character count
- Renders validation indicators
- Renders diff view toggle
- Handles editor state changes
- Preserves editor content on refresh
- Applies correct styling

**Components::Eval::SettingsForm**
- Renders model/provider dropdown
- Renders temperature slider with numeric input
- Renders max tokens input with validation
- Renders top_p slider
- Renders frequency penalty slider
- Renders presence penalty slider
- Renders advanced settings collapsible
- Renders reset to baseline button
- Validates parameter ranges
- Shows error messages for invalid inputs
- Applies correct form styling

**Components::Eval::ExecutionProgress**
- Renders progress bar with percentage
- Renders status messages
- Renders estimated time remaining
- Renders cancel button
- Renders error display on failure
- Updates via Turbo Stream
- Handles progress completion
- Handles cancellation

**Components::Eval::ResultsComparison**
- Renders three-column layout
- Renders baseline output (read-only)
- Renders new output with highlights
- Renders metrics panel (fixed)
- Renders diff highlighting (additions green, deletions red)
- Renders line-by-line vs unified diff toggle
- Renders expandable sections
- Renders delta indicators (↑↓)
- Applies color coding to metrics
- Handles large outputs efficiently

**Components::Eval::MetricsPanel**
- Renders token usage comparison
- Renders latency comparison
- Renders quality metrics
- Renders regression indicators
- Renders statistical significance badges
- Renders expandable detailed metrics
- Renders export metrics button
- Calculates deltas correctly
- Displays cost differences

**Components::Eval::ConfigurationComparison**
- Renders tabbed interface for configurations
- Renders side-by-side comparison grid
- Highlights configuration differences
- Allows selecting configurations to compare
- Shows visual indicators for best/worst
- Handles multiple configurations efficiently

### Integration Tests

**Span Browsing Flow**
- User visits /eval
- Sees table of recent spans
- Applies agent filter
- Applies date range filter
- Searches for specific span
- Clicks span to view details
- Sees full span information
- Clicks "Evaluate This Span"
- Redirected to evaluation setup

**Evaluation Setup Flow**
- User selects span for evaluation
- Sees evaluation editor with three panes
- Original configuration loaded (read-only)
- New configuration editable
- Modifies prompt in Monaco Editor
- Changes temperature slider
- Changes model dropdown
- Sees token count estimate update
- Clicks "Run Evaluation"
- Evaluation starts with progress indicator

**Evaluation Execution Flow**
- Evaluation executes in background
- Progress bar updates via Turbo Stream
- Status messages update (initializing, executing, calculating)
- Estimated time remaining displayed
- Evaluation completes successfully
- Redirected to results page
- Sees side-by-side comparison
- Sees metrics with deltas
- Can save evaluation as session

**Session Management Flow**
- User saves evaluation as session
- Enters session name
- Session saved to database
- User navigates to sessions list
- Sees saved session
- Clicks to load session
- Evaluation state restored
- Can delete session

**Real-Time Updates Flow**
- User starts evaluation
- Progress updates every 1 second via Turbo Stream
- Status messages change in real-time
- Progress bar percentage increases
- Completion triggers page transition
- Polling stops automatically

### Feature Tests

**Browse and Filter Production Spans**
- Given production spans exist in database
- When user visits /eval
- And applies filters for agent, model, date range
- Then sees matching spans in table
- And can select span for evaluation

**Edit Prompts in Monaco Editor**
- Given user has selected span for evaluation
- When user opens prompt editor
- And modifies prompt text
- And changes model settings
- Then sees validation indicators
- And token count updates
- And can save changes

**View Side-by-Side Results with Diff**
- Given evaluation has completed
- When user views results page
- Then sees baseline and new output side-by-side
- And differences highlighted with colors
- And metrics comparison displayed
- And can expand/collapse sections

**Save and Load Evaluation Sessions**
- Given user has run evaluation
- When user saves evaluation as session
- And navigates away
- And returns to sessions list
- Then can load saved session
- And evaluation state restored completely

### JavaScript Tests

**Monaco Editor Controller (Stimulus)**
- Initializes Monaco Editor on connect
- Loads editor with initial content
- Syncs content back to form field
- Validates content on change
- Shows diff mode when toggled
- Saves editor state to sessionStorage
- Restores editor state on page load
- Handles keyboard shortcuts (Cmd+S, Cmd+Enter)
- Cleans up editor on disconnect

**Evaluation Progress Controller (Stimulus)**
- Starts polling on connect
- Fetches status updates every 1 second
- Renders Turbo Stream updates
- Stops polling when evaluation complete
- Stops polling when user cancels
- Handles network errors gracefully
- Cleans up interval on disconnect

**Form Validation Controller (Stimulus)**
- Validates temperature range (0.0-2.0)
- Validates max tokens (positive integer)
- Validates top_p range (0.0-1.0)
- Validates penalty ranges (-2.0-2.0)
- Shows error messages for invalid inputs
- Disables submit with invalid inputs
- Clears errors when inputs corrected

### Performance Tests

**Span Browser Table Rendering**
- Renders 100 spans in < 500ms
- Pagination loads new page in < 200ms
- Filter application returns results in < 300ms
- Search typeahead responds in < 100ms
- Expandable rows expand in < 50ms

**Monaco Editor Initialization**
- Lazy loads Monaco in < 1s
- Initializes editor in < 500ms
- First edit registers in < 100ms
- Diff calculation completes in < 200ms
- Large files (10k lines) load in < 2s

**Diff Rendering Performance**
- Renders diffs up to 1000 lines in < 500ms
- Line-by-line toggle switches in < 100ms
- Expandable sections toggle in < 50ms
- Large diffs (5000+ lines) paginate properly

**Real-Time Update Performance**
- Turbo Stream update applies in < 100ms
- Polling interval maintains 1s consistently
- Progress updates don't block UI
- Multiple concurrent evaluations supported

### Browser Compatibility Tests

**Chrome 100+**
- All features work correctly
- Monaco Editor renders properly
- Turbo Streams update correctly
- Keyboard shortcuts work

**Firefox 100+**
- All features work correctly
- Monaco Editor renders properly
- Turbo Streams update correctly
- Minor CSS adjustments if needed

**Safari 15+**
- Core features work correctly
- Monaco Editor renders properly
- Turbo Streams update correctly
- Polyfills for missing features

**Edge 100+**
- All features work correctly
- Monaco Editor renders properly
- Turbo Streams update correctly

### Accessibility Tests

**Keyboard Navigation**
- Tab through all interactive elements
- Focus indicators visible
- Keyboard shortcuts work (/, Cmd+Enter, Cmd+S, Esc)
- Modal focus management works
- Screen reader friendly labels

**ARIA Compliance**
- All buttons have aria-label
- Tables have proper headers
- Forms have proper labels
- Loading states announced
- Error states announced

**Color Contrast**
- All text meets WCAG AA standards
- Diff highlights readable
- Metrics color coding accessible
- Dark mode support (if raaf-rails has it)

### Security Tests

**Authentication and Authorization**
- Unauthenticated users redirected to login
- Users can only see their own spans
- Team spans visible to team members
- Admin users can see all spans
- CSRF protection on all forms

**Input Validation and Sanitization**
- User prompts sanitized for display
- Model names validated against whitelist
- Parameter values validated
- No XSS vulnerabilities in displayed content
- No SQL injection in filters

**Rate Limiting**
- Max 5 concurrent evaluations per user
- Evaluation execution rate limited
- API endpoints rate limited
- Handles rate limit gracefully

**PII Protection**
- Phase 1 redaction applied to displayed spans
- Sensitive data not logged
- No PII in error messages
- User data properly isolated

### Edge Cases and Error Handling

**Missing or Invalid Data**
- Handles missing span gracefully
- Handles invalid span_id
- Handles corrupted span data
- Handles missing baseline results
- Handles incomplete evaluations

**Network and API Failures**
- Handles evaluation execution timeout
- Handles API provider failures
- Handles network disconnection during polling
- Retries transient failures
- Shows clear error messages

**Large Datasets**
- Handles spans with 10k+ tokens
- Handles evaluations with many configurations
- Handles long-running evaluations (> 5 minutes)
- Paginates large result sets
- Streams large diffs

**Concurrent Operations**
- Handles multiple users evaluating same span
- Handles concurrent session saves
- Handles race conditions in polling
- Database transactions prevent conflicts

## Test Data Factories

**Factory: evaluation_test_span**
```ruby
FactoryBot.define do
  factory :evaluation_test_span, class: 'RAAF::Eval::Models::EvaluationSpan' do
    span_id { SecureRandom.uuid }
    trace_id { SecureRandom.uuid }
    span_type { "agent" }
    source { "production" }
    span_data do
      {
        agent_name: "TestAgent",
        model: "gpt-4o",
        instructions: "Test instructions",
        input_messages: [
          { role: "user", content: "Test input" }
        ],
        output_messages: [
          { role: "assistant", content: "Test output" }
        ],
        metadata: {
          tokens: { total: 100, input: 50, output: 50 },
          latency_ms: 1000,
          cost: 0.002
        }
      }
    end
  end
end
```

**Factory: evaluation_session**
```ruby
FactoryBot.define do
  factory :evaluation_session, class: 'Eval::Session' do
    name { "Test Evaluation Session" }
    description { "Testing evaluation features" }
    session_type { "saved" }
    association :baseline_span, factory: :evaluation_test_span
    metadata { {} }
  end
end
```

**Factory: evaluation_configuration**
```ruby
FactoryBot.define do
  factory :evaluation_configuration, class: 'Eval::SessionConfiguration' do
    association :eval_session, factory: :evaluation_session
    name { "GPT-4 High Temp" }
    configuration do
      {
        model: "gpt-4o",
        temperature: 0.9,
        max_tokens: 1000
      }
    end
    display_order { 0 }
  end
end
```

## Mocking Requirements

**Phase 1 Evaluation Engine**
- Mock `RAAF::Eval::EvaluationEngine` for fast tests
- Provide fixture evaluation results
- Mock async execution
- Mock metrics calculation

**External Services**
- Mock Monaco Editor CDN requests
- Mock background job execution
- Mock Turbo Stream broadcasts
- Mock Redis for caching (if used)

**Database**
- Use transactional tests for isolation
- Clean database between tests
- Seed minimal test data
- Use in-memory SQLite for fast tests (optional)

## Coverage Goals

- **Unit Test Coverage:** 95%+ for controllers and components
- **Integration Coverage:** All user workflows
- **Feature Coverage:** All 3 user stories
- **JavaScript Coverage:** 90%+ for Stimulus controllers
- **Accessibility Coverage:** WCAG AA compliance
- **Performance:** All targets met under load

## CI/CD Testing Strategy

- Run tests in GitHub Actions
- Test against Rails 7.0, 7.1, 8.0
- Test against Ruby 3.2, 3.3, 3.4
- Test browser compatibility (headless Chrome)
- Generate coverage reports
- Test Monaco Editor integration
- Test Turbo Streams in isolation
