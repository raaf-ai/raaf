# RAAF Eval UI - Interactive Evaluation Interface

> Web UI for RAAF Eval providing visual interface for agent evaluation and optimization

**Part of RAAF Eval** - See **[Master Documentation](../RAAF_EVAL.md)** for complete feature overview and architecture.

## Overview

RAAF Eval UI is a Rails engine that provides an interactive web interface for the RAAF Eval evaluation framework. Use it for exploratory testing, prompt optimization, and visual comparison of evaluation results.

**For programmatic testing**, use the **[core evaluation engine](../eval/README.md)** with **[RSpec integration](../eval/RSPEC_INTEGRATION.md)**.

## Features

- **Span Browser**: Filter, search, and browse production agent execution spans
- **Prompt Editor**: Monaco Editor integration with syntax highlighting and diff view
- **AI Settings Form**: Configure model, temperature, and other LLM parameters
- **Real-time Execution**: Live progress updates via Turbo Streams
- **Results Comparison**: Side-by-side diff view with metrics and delta indicators
- **Session Management**: Save and resume evaluation sessions

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-eval-ui'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install raaf-eval-ui
```

## Usage

### Mount the Engine

In your Rails application's `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  mount RAAF::Eval::UI::Engine, at: "/eval"
end
```

### Run Migrations

Copy and run the migrations:

```bash
$ rails raaf_eval_ui:install:migrations
$ rails db:migrate
```

### Configure Authentication

Create an initializer at `config/initializers/raaf_eval_ui.rb`:

```ruby
RAAF::Eval::UI.configure do |config|
  # Authentication method to call before all actions
  config.authentication_method = :authenticate_user!

  # Method to get current user
  config.current_user_method = :current_user

  # Optional: Authorization callback for span access
  config.authorize_span_access = ->(user, span) {
    user.admin? || span.user_id == user.id
  }

  # Optional: Use host app's layout instead of engine's
  config.layout = "application"

  # Optional: Inherit host app's assets
  config.inherit_assets = true
end
```

### Access the UI

Navigate to `/eval` in your Rails application to access the evaluation interface.

## Configuration Options

### Authentication

The engine is designed to work with any authentication system (Devise, Sorcery, custom):

```ruby
# For Devise
config.authentication_method = :authenticate_user!
config.current_user_method = :current_user

# For Sorcery
config.authentication_method = :require_login
config.current_user_method = :current_user

# For custom authentication
config.authentication_method = :authenticate_admin!
config.current_user_method = :current_admin
```

### Authorization

Control who can access specific spans:

```ruby
config.authorize_span_access = ->(user, span) {
  # Example: Users can only access their own spans or public spans
  user.admin? || span.user_id == user.id || span.public?
}
```

### Layout

Use your application's layout:

```ruby
config.layout = "application"  # or "admin", "dashboard", etc.
```

### Assets

Inherit CSS and JavaScript from your host application:

```ruby
config.inherit_assets = true
```

## Components

### SpanBrowser

Browse and filter production spans:

```ruby
render RAAF::Eval::UI::SpanBrowser.new(
  spans: @spans,
  filters: { agent_name: "MyAgent", status: "completed" }
)
```

### PromptEditor

Edit prompts with Monaco Editor:

```ruby
render RAAF::Eval::UI::PromptEditor.new(
  original: baseline_prompt,
  current: modified_prompt,
  language: "markdown"
)
```

### SettingsForm

Configure AI model settings:

```ruby
render RAAF::Eval::UI::SettingsForm.new(
  configuration: { model: "gpt-4", temperature: 0.7 },
  baseline: { model: "gpt-3.5-turbo", temperature: 1.0 }
)
```

### ExecutionProgress

Show evaluation progress:

```ruby
render RAAF::Eval::UI::ExecutionProgress.new(session: @session)
```

### ResultsComparison

Compare baseline and new results:

```ruby
render RAAF::Eval::UI::ResultsComparison.new(
  baseline: baseline_result,
  result: new_result
)
```

### MetricsPanel

Display detailed metrics:

```ruby
render RAAF::Eval::UI::MetricsPanel.new(
  baseline_metrics: baseline_metrics,
  result_metrics: result_metrics
)
```

## Integration with Phase 1 (raaf-eval)

This UI engine integrates with the Phase 1 `raaf-eval` gem for core evaluation functionality:

```ruby
# In your evaluation execution job
def execute_configuration(baseline_span, configuration)
  engine = ::RAAF::Eval::EvaluationEngine.new

  result = engine.execute(
    baseline_span: baseline_span,
    configuration: configuration
  )

  result
end
```

## Background Jobs

The engine uses ActiveJob for async evaluation execution. Ensure you have a job processor configured:

```ruby
# config/application.rb
config.active_job.queue_adapter = :sidekiq  # or :delayed_job, :resque, etc.
```

## Browser Support

- Chrome 100+
- Firefox 100+
- Safari 15+
- Edge 100+

## Development

To work on the engine locally:

```bash
$ bundle install
$ cd spec/dummy
$ rails db:migrate
$ rails server
```

Visit `http://localhost:3000/eval` to see the engine in action.

## Testing

Run the test suite:

```bash
$ bundle exec rspec
```

Run system tests (requires Chrome/Firefox):

```bash
$ bundle exec rspec spec/system
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/raaf-ai/ruby-ai-agents-factory.

## Integration with RAAF Ecosystem

### Relationship to RAAF Tracing

RAAF Eval UI works alongside RAAF's tracing infrastructure but serves a different purpose:

- **RAAF Tracing**: Read-only view of production traces for monitoring and debugging
- **RAAF Eval UI**: Interactive experimentation with agent behavior for testing and optimization

Both systems use the same span data, but Eval UI adds the ability to modify configurations and re-run evaluations. For complete details on how these systems integrate, see [INTEGRATION_GUIDE.md](./INTEGRATION_GUIDE.md).

### Cross-Linking

When a tracing dashboard exists, you can add evaluation actions to trace views:

```ruby
# In tracing dashboard span detail view
link_to "🔬 Evaluate This Span",
        eval_evaluation_path(span_id: @span.id),
        class: "btn btn-primary"
```

### Unified Platform

For a complete RAAF platform experience, consider mounting both engines under a unified namespace:

```ruby
Rails.application.routes.draw do
  # Unified RAAF platform
  namespace :raaf do
    mount RAAF::Tracing::UI::Engine, at: "/monitoring"  # Future
    mount RAAF::Eval::UI::Engine, at: "/eval"
  end
end
```

See [INTEGRATION_GUIDE.md](./INTEGRATION_GUIDE.md) for detailed integration patterns and best practices.

## Quick Links

| Task | Documentation |
|------|---------------|
| **Complete Overview** | [RAAF Eval Master Docs](../RAAF_EVAL.md) |
| Core Engine Setup | [Core Eval README](../eval/README.md) |
| Tutorial & Examples | [Getting Started Guide](../eval/GETTING_STARTED.md) |
| Write RSpec Tests | [RSpec Integration](../eval/RSPEC_INTEGRATION.md) |
| Ecosystem Integration | [Integration Guide](./INTEGRATION_GUIDE.md) |
| Development Setup | [Contributing Guide](./CONTRIBUTING.md) |

## Documentation Structure

### RAAF Eval System
- **[RAAF_EVAL.md](../RAAF_EVAL.md)** - Master documentation with complete feature overview
- **[eval/README.md](../eval/README.md)** - Core evaluation engine quick start
- **[eval/GETTING_STARTED.md](../eval/GETTING_STARTED.md)** - Comprehensive tutorial
- **[eval/RSPEC_INTEGRATION.md](../eval/RSPEC_INTEGRATION.md)** - RSpec testing guide

### UI-Specific Documentation
- **[README.md](./README.md)** - This file (UI installation and configuration)
- **[INTEGRATION_GUIDE.md](./INTEGRATION_GUIDE.md)** - RAAF ecosystem integration patterns
- **[CONTRIBUTING.md](./CONTRIBUTING.md)** - Development guidelines

### Technical Reference
- **[eval/ARCHITECTURE.md](../eval/ARCHITECTURE.md)** - System architecture
- **[eval/API.md](../eval/API.md)** - API reference
- **[eval/METRICS.md](../eval/METRICS.md)** - Metrics system
- **[eval/PERFORMANCE.md](../eval/PERFORMANCE.md)** - Performance benchmarks

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

---

**Getting Started?** Read the **[Complete Tutorial](../eval/GETTING_STARTED.md)** or **[Master Documentation](../RAAF_EVAL.md)**.
