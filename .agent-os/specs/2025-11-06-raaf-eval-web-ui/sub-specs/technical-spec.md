# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-11-06-raaf-eval-web-ui/spec.md

> Created: 2025-11-06
> Version: 1.0.0

## Technical Requirements

### Rails Engine Architecture

**Structure:** Standalone Rails engine gem (`raaf-eval-ui`) in RAAF mono-repo

**Key Features:**
- Mountable Rails engine for maximum portability
- Can be used with or without raaf-rails
- Isolated namespace to prevent conflicts
- Configurable authentication and authorization
- Self-contained assets, views, and JavaScript
- Phlex components for consistent UI

**Engine Setup:**

```ruby
# lib/raaf/eval/ui/engine.rb
module RAAF
  module Eval
    module UI
      class Engine < ::Rails::Engine
        isolate_namespace RAAF::Eval::UI

        # Load Phlex for components
        config.autoload_paths << root.join('app/components')

        # Add engine's JavaScript controllers to Stimulus
        config.importmap.paths << root.join('config/importmap.rb')

        # Ensure migrations are available
        initializer "raaf-eval-ui.migrations" do |app|
          config.paths["db/migrate"].expanded.each do |expanded_path|
            app.config.paths["db/migrate"] << expanded_path
          end
        end

        # Configure authentication (default: Devise)
        config.authentication_method = :authenticate_user!
        config.current_user_method = :current_user
      end
    end
  end
end
```

**Mounting in Host Application:**

```ruby
# config/routes.rb (in host Rails app)
Rails.application.routes.draw do
  # Mount engine at /eval path
  mount RAAF::Eval::UI::Engine, at: "/eval"
end
```

**Configuration:**

```ruby
# config/initializers/raaf_eval_ui.rb (in host app)
RAAF::Eval::UI.configure do |config|
  # Authentication method (method name on controller)
  config.authentication_method = :authenticate_user!

  # Current user method (method name on controller)
  config.current_user_method = :current_user

  # Authorization callback (optional)
  config.authorize_span_access = ->(user, span) {
    # Custom logic to check if user can access span
    user.admin? || span.user_id == user.id || user.team_ids.include?(span.team_id)
  }

  # Layout to use (optional, defaults to engine's layout)
  config.layout = "application"  # Use host app's layout

  # Whether to inherit host app's assets
  config.inherit_assets = true
end
```

### Engine Route Structure

```ruby
# config/routes.rb (inside raaf-eval-ui engine)
RAAF::Eval::UI::Engine.routes.draw do
  resources :spans, only: [:index, :show] do
    collection do
      get :search
      get :filter
    end
  end

  resources :evaluations, only: [:new, :create, :show, :destroy] do
    member do
      post :execute
      get :status
      get :results
    end
  end

  resources :sessions, only: [:index, :show, :create, :update, :destroy]

  root to: 'spans#index'
end

# Routes are accessible at:
# - /eval (when mounted at root)
# - /eval/spans
# - /eval/evaluations
# - /eval/sessions
```

### Controller Architecture

All controllers inherit from `RAAF::Eval::UI::ApplicationController` which provides:
- Authentication via configurable method
- Authorization via configurable callback
- Layout configuration
- Error handling

**RAAF::Eval::UI::SpansController**
- `index` - List spans with filters (agent, model, date range, status)
- `show` - Display span details with full context
- `search` - AJAX endpoint for typeahead search
- `filter` - AJAX endpoint for filter application
- Uses Phase 1 models (`RAAF::Eval::Models::EvaluationSpan`)

**RAAF::Eval::UI::EvaluationsController**
- `new` - Setup new evaluation from span
- `create` - Create evaluation configuration
- `execute` - Start async evaluation execution (via background job)
- `status` - Poll evaluation progress (returns Turbo Stream or JSON)
- `results` - Display evaluation results with comparison
- `show` - Display saved evaluation session
- `destroy` - Delete evaluation session
- Integrates with Phase 1 `RAAF::Eval::EvaluationEngine`

**RAAF::Eval::UI::SessionsController**
- `index` - List saved evaluation sessions
- `show` - Load session with full context
- `create` - Save current evaluation as session
- `update` - Update session name/metadata
- `destroy` - Delete session
- Uses engine's session models

**ApplicationController Base:**

```ruby
# app/controllers/raaf/eval/ui/application_controller.rb
module RAAF
  module Eval
    module UI
      class ApplicationController < ActionController::Base
        # Use engine layout by default (can be overridden via config)
        layout -> { RAAF::Eval::UI.configuration.layout || "raaf/eval/ui/application" }

        # Apply authentication before all actions
        before_action :authenticate_user_from_config!

        # Helper methods available to all controllers
        helper_method :current_user

        private

        def authenticate_user_from_config!
          method_name = RAAF::Eval::UI.configuration.authentication_method
          send(method_name) if respond_to?(method_name, true)
        end

        def current_user
          method_name = RAAF::Eval::UI.configuration.current_user_method
          send(method_name) if respond_to?(method_name, true)
        end

        def authorize_span_access!(span)
          callback = RAAF::Eval::UI.configuration.authorize_span_access
          return true unless callback

          unless callback.call(current_user, span)
            redirect_to root_path, alert: "You don't have permission to access this span"
          end
        end
      end
    end
  end
end
```

### Engine Gem Structure

```
raaf-eval-ui/
├── app/
│   ├── assets/
│   │   ├── config/
│   │   │   └── raaf_eval_ui_manifest.js
│   │   ├── images/raaf/eval/ui/
│   │   ├── stylesheets/raaf/eval/ui/
│   │   │   └── application.css
│   │   └── javascript/raaf/eval/ui/
│   │       └── application.js
│   ├── components/raaf/eval/ui/
│   │   ├── span_browser.rb
│   │   ├── span_detail.rb
│   │   ├── prompt_editor.rb
│   │   ├── settings_form.rb
│   │   ├── execution_progress.rb
│   │   ├── results_comparison.rb
│   │   ├── metrics_panel.rb
│   │   └── configuration_comparison.rb
│   ├── controllers/raaf/eval/ui/
│   │   ├── application_controller.rb
│   │   ├── spans_controller.rb
│   │   ├── evaluations_controller.rb
│   │   └── sessions_controller.rb
│   ├── jobs/raaf/eval/ui/
│   │   └── evaluation_execution_job.rb
│   ├── models/raaf/eval/ui/
│   │   ├── session.rb
│   │   ├── session_configuration.rb
│   │   └── session_result.rb
│   └── views/raaf/eval/ui/
│       └── layouts/
│           └── application.html.erb
├── config/
│   ├── importmap.rb
│   └── routes.rb
├── db/
│   └── migrate/
│       ├── 001_create_eval_sessions.rb
│       ├── 002_create_eval_session_configurations.rb
│       └── 003_create_eval_session_results.rb
├── lib/
│   ├── raaf/
│   │   └── eval/
│   │       └── ui/
│   │           ├── configuration.rb
│   │           ├── engine.rb
│   │           └── version.rb
│   ├── raaf-eval-ui.rb
│   └── tasks/
│       └── raaf_eval_ui_tasks.rake
├── spec/
├── raaf-eval-ui.gemspec
└── README.md
```

**Gemspec:**

```ruby
# raaf-eval-ui.gemspec
Gem::Specification.new do |spec|
  spec.name        = "raaf-eval-ui"
  spec.version     = RAAF::Eval::UI::VERSION
  spec.authors     = ["RAAF Team"]
  spec.email       = ["team@raaf.dev"]
  spec.summary     = "Web UI for RAAF Eval interactive evaluation"
  spec.description = "Standalone Rails engine providing web interface for RAAF evaluation system"
  spec.license     = "MIT"

  spec.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  # Core dependencies
  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "raaf-eval", "~> 0.1.0"  # Phase 1 foundation
  spec.add_dependency "phlex-rails", "~> 1.0"

  # UI dependencies
  spec.add_dependency "turbo-rails", "~> 1.4"
  spec.add_dependency "stimulus-rails", "~> 1.2"
  spec.add_dependency "importmap-rails", "~> 1.2"
  spec.add_dependency "tailwindcss-rails", "~> 2.0"

  # Diff generation
  spec.add_dependency "diff-lcs", "~> 1.5"
  spec.add_dependency "diffy", "~> 3.4"

  # Development dependencies
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "capybara", "~> 3.0"
  spec.add_development_dependency "selenium-webdriver", "~> 4.0"
end
```

### Phlex Component Requirements

All UI components use Phlex and are namespaced under `RAAF::Eval::UI::Components::`.

**RAAF::Eval::UI::Components::SpanBrowser**
- Filterable table with sortable columns
- Pagination (25/50/100 per page)
- Search bar with debounced AJAX
- Filter dropdowns (agent, model, status, date range)
- Row selection for evaluation
- Expandable row details
- Loading states and skeleton UI

**RAAF::Eval::UI::Components::SpanDetail**
- Three-section layout: input, output, metadata
- Syntax-highlighted JSON/text display
- Expandable tool calls and handoffs
- Copy-to-clipboard buttons
- Timeline visualization for multi-turn conversations
- Token and cost breakdown

**RAAF::Eval::UI::Components::PromptEditor**
- Split-pane layout: original (left) vs modified (right)
- Monaco Editor integration with:
  - Syntax highlighting (Markdown/Plain Text)
  - Line numbers and minimap
  - Search and replace
  - Diff view option
  - Validation indicators
- Estimated token count display
- Character count and warnings

**RAAF::Eval::UI::Components::SettingsForm**
- Model/provider dropdown (grouped by provider)
- Parameter inputs with validation:
  - Temperature: slider (0.0-2.0) with numeric input
  - Max tokens: numeric input with model limits
  - Top P: slider (0.0-1.0)
  - Frequency penalty: slider (-2.0-2.0)
  - Presence penalty: slider (-2.0-2.0)
- Advanced settings collapsible section
- Real-time validation with error messages
- Reset to baseline button

**RAAF::Eval::UI::Components::ExecutionProgress**
- Progress bar with percentage
- Status messages (initializing, executing, calculating metrics, etc.)
- Estimated time remaining
- Cancel button
- Error display if execution fails
- Turbo Stream updates for real-time progress

**RAAF::Eval::UI::Components::ResultsComparison**
- Three-column layout:
  - Baseline output (left, read-only)
  - New output (middle, highlighted)
  - Metrics panel (right, fixed)
- Diff highlighting:
  - Additions: green background
  - Deletions: red background with strikethrough
  - Modifications: yellow background
- Line-by-line diff or unified diff toggle
- Expandable sections: messages, tool calls, metadata
- Metrics with delta indicators (↑↓) and color coding

**RAAF::Eval::UI::Components::MetricsPanel**
- Token usage comparison (total, input, output, cost)
- Latency comparison (total time, TTFT)
- Quality metrics (semantic similarity, coherence)
- Regression indicators (⚠️ warnings if detected)
- Statistical significance badges
- Expandable detailed metrics
- Export metrics button (JSON/CSV)

**RAAF::Eval::UI::Components::ConfigurationComparison**
- Tabbed interface for multiple configurations
- Side-by-side comparison grid
- Highlight differences in configuration
- Select configurations to compare
- Visual indicators for best/worst performers

### Monaco Editor Integration

**Technical Approach:**
- Use `@monaco-editor/react` via importmap
- Lazy load Monaco only when editor opens (reduce initial bundle)
- Custom theme matching raaf-rails design
- Save/restore editor state in session storage
- Keyboard shortcuts (Cmd+S save, Cmd+Enter run)

**Configuration:**
```javascript
// app/assets/javascript/raaf/eval/ui/controllers/monaco_editor_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor", "content", "validation"]
  static values = {
    language: { type: String, default: "markdown" },
    readonly: { type: Boolean, default: false },
    originalContent: String
  }

  connect() {
    this.loadMonaco().then(() => this.initializeEditor())
  }

  async loadMonaco() {
    if (window.monaco) return
    const script = document.createElement('script')
    script.src = 'https://cdn.jsdelivr.net/npm/monaco-editor@latest/min/vs/loader.js'
    document.head.appendChild(script)
    // Load Monaco
  }

  initializeEditor() {
    this.editor = monaco.editor.create(this.editorTarget, {
      value: this.contentTarget.value,
      language: this.languageValue,
      theme: 'raaf-eval-dark',
      readOnly: this.readonlyValue,
      minimap: { enabled: true },
      lineNumbers: 'on',
      automaticLayout: true
    })

    // Sync content back to form
    this.editor.onDidChangeModelContent(() => {
      this.contentTarget.value = this.editor.getValue()
      this.validateContent()
    })
  }

  validateContent() {
    // Custom validation logic
  }

  showDiff() {
    // Switch to diff editor mode
  }
}

// Register controller with Stimulus
// Automatically registered via importmap in engine
```

### Turbo Streams for Real-Time Updates

**Evaluation Execution Progress:**

```ruby
# app/controllers/raaf/eval/ui/evaluations_controller.rb
module RAAF
  module Eval
    module UI
      class EvaluationsController < ApplicationController
        def status
          evaluation = find_evaluation(params[:id])

          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.replace(
                "evaluation_progress",
                partial: "raaf/eval/ui/evaluations/progress",
                locals: { evaluation: evaluation }
              )
            end
            format.json { render json: evaluation.status }
          end
        end
      end
    end
  end
end
```

**Progress Polling:**

```javascript
// app/assets/javascript/raaf/eval/ui/controllers/evaluation_progress_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 1000 } }

  connect() {
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    this.pollInterval = setInterval(() => {
      fetch(this.urlValue, { headers: { "Accept": "text/vnd.turbo-stream.html" } })
        .then(response => response.text())
        .then(html => Turbo.renderStreamMessage(html))
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
    }
  }
}
```

### Async Evaluation Execution

**Background Job Pattern:**

```ruby
# app/jobs/raaf/eval/ui/evaluation_execution_job.rb
module RAAF
  module Eval
    module UI
      class EvaluationExecutionJob < ApplicationJob
        queue_as :raaf_evaluations

        def perform(evaluation_id)
          evaluation = Session.find(evaluation_id)
          evaluation.update(status: 'running')

          # Execute using Phase 1 engine
          engine = ::RAAF::Eval::EvaluationEngine.new
          result = engine.execute(
            baseline_span: evaluation.baseline_span,
            configuration: evaluation.configuration
          )

          evaluation.update(
            status: 'completed',
            result_data: result,
            completed_at: Time.current
          )

        rescue StandardError => e
          evaluation.update(
            status: 'failed',
            error_message: e.message,
            error_backtrace: e.backtrace.join("\n")
          )
        end
      end
    end
  end
end
```

### Session Persistence

**Session Model:**

```ruby
# app/models/raaf/eval/ui/session.rb
module RAAF
  module Eval
    module UI
      class Session < ApplicationRecord
        self.table_name = 'raaf_eval_ui_sessions'

        belongs_to :user, optional: true, class_name: '::User'
        belongs_to :baseline_span, class_name: '::RAAF::Eval::Models::EvaluationSpan'

        has_many :configurations, class_name: 'SessionConfiguration', dependent: :destroy
        has_many :results, class_name: 'SessionResult', dependent: :destroy

        validates :name, presence: true, length: { maximum: 255 }
        validates :session_type, inclusion: { in: %w[draft saved archived] }

        scope :recent, -> { order(updated_at: :desc).limit(10) }
        scope :saved, -> { where(session_type: 'saved') }
      end
    end
  end
end
```

**Session Storage Schema:**

```ruby
# db/migrate/001_create_raaf_eval_ui_sessions.rb
class CreateRaafEvalUiSessions < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_eval_ui_sessions do |t|
      t.references :user, foreign_key: true
      t.references :baseline_span, foreign_key: { to_table: :raaf_eval_spans }
      t.string :name, null: false
      t.text :description
      t.string :session_type, null: false, default: 'draft'
      t.jsonb :metadata, default: {}
      t.timestamps

      t.index [:user_id, :session_type]
      t.index :created_at
    end

    create_table :raaf_eval_ui_session_configurations do |t|
      t.references :raaf_eval_ui_session, null: false, foreign_key: true
      t.string :name, null: false
      t.jsonb :configuration, null: false
      t.integer :display_order, default: 0
      t.timestamps

      t.index [:raaf_eval_ui_session_id, :display_order]
    end

    create_table :raaf_eval_ui_session_results do |t|
      t.references :raaf_eval_ui_session, null: false, foreign_key: true
      t.references :raaf_eval_ui_session_configuration, null: false, foreign_key: true
      t.references :raaf_eval_result, foreign_key: { to_table: :raaf_eval_results }
      t.string :status, null: false, default: 'pending'
      t.timestamps

      t.index [:raaf_eval_ui_session_id, :status]
    end
  end
end
```

## Approach Options

### Option A: Direct Integration with raaf-rails (Not Selected)

Integrate UI directly into raaf-rails gem as additional controllers and views.

**Pros:**
- Simpler initial setup
- Tight integration with raaf-rails
- Share authentication and layout immediately

**Cons:**
- Couples UI tightly to raaf-rails
- Can't be used independently
- Harder to version separately
- Pollutes raaf-rails with UI-specific code

### Option B: Standalone Rails Engine (Selected)

Create standalone Rails engine (`raaf-eval-ui`) that can be mounted in any Rails app.

**Pros:**
- Maximum portability and reusability
- Can be used with or without raaf-rails
- Clean separation of concerns
- Independent versioning
- Configurable authentication/authorization
- Isolated namespace prevents conflicts
- Can be tested independently

**Cons:**
- Slightly more complex initial setup
- Requires configuration in host app
- Need to maintain engine structure

**Rationale:** The engine approach provides maximum flexibility and portability. Users can mount the UI in raaf-rails, standalone Rails apps, or any other Rails application. The configuration system allows adapting to different authentication schemes and layouts.

### Option C: Full SPA with React (Not Selected)

Build entire UI as React SPA communicating with JSON API.

**Pros:**
- Rich interactivity
- Smooth user experience
- Independent frontend/backend

**Cons:**
- Breaks from Rails patterns
- Requires separate frontend build pipeline
- More complex authentication
- Doesn't leverage Turbo/Stimulus
- Higher maintenance burden
- No server-side rendering benefits

**Rationale:** A full SPA adds unnecessary complexity. Turbo + Stimulus provides excellent interactivity while maintaining Rails conventions and server-side rendering benefits.

### Option D: ViewComponent instead of Phlex (Not Selected)

Use Rails ViewComponent instead of Phlex for components.

**Pros:**
- More common in Rails community
- More documentation and examples

**Cons:**
- Phlex provides better performance
- Phlex has cleaner Ruby DSL
- Breaking from RAAF patterns (raaf-rails uses Phlex)

**Rationale:** Maintain consistency with raaf-rails Phlex patterns for component architecture.

## External Dependencies

### New Dependencies

**monaco-rails (~> 1.0)** (optional via importmap)
- Purpose: Monaco Editor for code editing
- Justification: Industry-standard code editor, used by VS Code
- License: MIT (compatible)
- Note: Loaded via CDN through importmap, not bundled

**diff-lcs (~> 1.5)**
- Purpose: Generate line-by-line diffs for output comparison
- Justification: Ruby standard for diff generation, efficient
- License: MIT (compatible)

**diffy (~> 3.4)**
- Purpose: Unified and side-by-side diff formatting
- Justification: Clean API for generating HTML diffs
- License: MIT (compatible)

**turbo-rails (~> 1.4)**
- Purpose: Turbo Frames and Streams for interactivity
- Justification: Already in raaf-rails, standard Rails 8 stack
- License: MIT (compatible)
- Note: No new dependency, already available

**stimulus-rails (~> 1.2)**
- Purpose: JavaScript controllers for interactivity
- Justification: Already in raaf-rails, standard Rails 8 stack
- License: MIT (compatible)
- Note: No new dependency, already available

### Optional Dependencies

**chartkick (~> 5.0)** (optional)
- Purpose: Charts for metrics visualization
- Justification: Simple charting with minimal setup
- License: MIT (compatible)
- Note: Optional - for metrics charts in Phase 4

## Performance Considerations

### Span Browser Optimization

- Server-side pagination (25/50/100 per page)
- Eager load associations for list view
- Index on commonly filtered columns (agent_name, created_at, status)
- Use JSONB GIN indexes for metadata filtering
- Limit initial data load, expand on demand
- Cache filter counts for common queries

### Editor Performance

- Lazy load Monaco Editor (only when needed)
- Debounce content change handlers (300ms)
- Store editor state in sessionStorage
- Virtual scrolling for large outputs
- Syntax highlighting on-demand

### Diff Performance

- Generate diffs server-side
- Limit diff display to first 1000 lines (expand on demand)
- Use fragment caching for static portions
- Stream large diffs with Turbo Frames
- Client-side collapse/expand for large sections

### Real-Time Updates

- Poll interval: 1s for active evaluations
- Stop polling when evaluation complete
- Use Turbo Streams to update only changed portions
- WebSocket option for future enhancement

## Security Considerations

- Inherit authentication from raaf-rails
- Authorize span access (user can only see their spans, or team spans)
- Sanitize all user inputs (prompts, settings)
- Validate model names against whitelist
- Rate limit evaluation execution (max 5 concurrent per user)
- Audit log all evaluation executions
- PII detection on displayed content (use Phase 1 redaction)
- CSRF protection on all forms

## UI/UX Requirements

### Design System

- Use Tailwind CSS (inherited from raaf-rails)
- Follow raaf-rails component styling
- Consistent color palette and spacing
- Responsive breakpoints (desktop, tablet, mobile-optional)
- Dark mode support (if raaf-rails has it)

### Accessibility

- Keyboard navigation throughout
- ARIA labels on interactive elements
- Focus management for modals
- Screen reader friendly tables
- Color contrast compliance (WCAG AA)

### Loading States

- Skeleton UI for initial page loads
- Spinner for async operations
- Progress indicators for evaluations
- Empty states with helpful actions
- Error states with retry options

### Keyboard Shortcuts

- `/` - Focus search
- `Cmd+Enter` - Run evaluation
- `Cmd+S` - Save session
- `Esc` - Close modals
- `?` - Show keyboard shortcuts help

## Browser Support

- Chrome 100+ (primary)
- Firefox 100+ (supported)
- Safari 15+ (supported)
- Edge 100+ (supported)
- Mobile browsers (optional, basic support)
