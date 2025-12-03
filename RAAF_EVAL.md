# RAAF Eval - AI Agent Evaluation Framework

> **Status**: Production Ready (Phase 1-3 Complete)
> **Version**: 1.0.0
> **Last Updated**: 2025-01-12

## Overview

RAAF Eval is a comprehensive AI agent evaluation and testing framework for Ruby AI Agents Factory (RAAF). It enables systematic testing and validation of agent behavior when changing LLMs, parameters, or prompts through two complementary interfaces:

- **raaf-eval** - Core evaluation engine with RSpec integration for automated testing
- **raaf-eval-ui** - Interactive web UI for exploratory evaluation and optimization

## Quick Links

### Getting Started
- **[Installation & Quick Start](eval/README.md)** - Get up and running in 5 minutes
- **[Comprehensive Tutorial](eval/GETTING_STARTED.md)** - Step-by-step guide with examples
- **[RSpec Integration Guide](eval/RSPEC_INTEGRATION.md)** - Write evaluation tests

### Core Documentation
- **[Architecture Overview](eval/ARCHITECTURE.md)** - System design and components
- **[API Reference](eval/API.md)** - Complete API documentation
- **[Metrics System](eval/METRICS.md)** - Understanding evaluation metrics
- **[Performance Benchmarks](eval/PERFORMANCE.md)** - Performance characteristics
- **[Statistical LLM Judge Guide](eval/docs/LLM_JUDGE_GUIDE.md)** - Bias-corrected LLM-as-a-Judge evaluation

### UI Documentation
- **[UI Installation](eval-ui/README.md)** - Setting up the web interface
- **[Integration Guide](eval-ui/INTEGRATION_GUIDE.md)** - Integrating with RAAF ecosystem
- **[Contributing](eval-ui/CONTRIBUTING.md)** - Development guidelines

### Technical Reference
- **[Database Schema](eval/MIGRATIONS.md)** - Database structure and migrations

## What Can You Do?

### 1. Automated Testing (raaf-eval)

Write RSpec tests to validate agent behavior across configurations:

```ruby
RSpec.describe "GPT-4 vs Claude comparison" do
  it "maintains quality when switching models" do
    # Find baseline span from production
    baseline = find_span(agent: "CustomerSupportAgent", status: "completed")

    # Evaluate with Claude instead of GPT-4
    result = evaluate_span(baseline) do |config|
      config.model = "claude-3-5-sonnet-20241022"
      config.provider = "anthropic"
    end

    # Assert quality maintained
    expect(result).to maintain_semantic_similarity(threshold: 0.85)
    expect(result).not_to regress_from_baseline
  end
end
```

**40+ RSpec matchers available** for performance, quality, regression, safety, and more.

### 2. Interactive Optimization (raaf-eval-ui)

Use the web UI for exploratory testing:

1. **Browse Spans** - Filter production traces by agent, model, status
2. **Edit Prompts** - Monaco Editor with syntax highlighting and diff view
3. **Modify Settings** - Adjust model, temperature, max_tokens
4. **Run Evaluations** - Real-time execution with progress updates
5. **Compare Results** - Side-by-side diff with metrics and deltas
6. **Save Sessions** - Resume evaluation experiments

## Key Features

### Core Capabilities
- ✅ **Span Serialization** - Capture production agent executions
- ✅ **Configuration Override** - Test model, parameter, prompt changes
- ✅ **Baseline Comparison** - Automatic regression detection
- ✅ **Comprehensive Metrics** - Token usage, latency, quality, safety

### RSpec Integration (Phase 2)
- ✅ **8 Matcher Categories** - Performance, quality, regression, statistical, safety, structural, LLM, custom
- ✅ **40+ Built-in Matchers** - Complete testing vocabulary
- ✅ **Fluent DSL** - Clean, readable test syntax
- ✅ **CI/CD Ready** - Run in automated pipelines

### Web UI (Phase 3)
- ✅ **Span Browser** - Filter, search, paginate production spans
- ✅ **Prompt Editor** - Monaco Editor with diff view
- ✅ **Settings Form** - AI configuration interface
- ✅ **Real-time Progress** - Turbo Streams updates
- ✅ **Results Comparison** - Side-by-side metrics
- ✅ **Session Management** - Save and resume experiments

### Statistical LLM Judge (NEW)
Based on [Lee et al. "How to Correctly Report LLM-as-a-Judge Evaluations"](https://arxiv.org/abs/2511.21140):
- ✅ **Bias-Corrected Accuracy** - Corrects for judge sensitivity/specificity
- ✅ **Calibration Support** - Ground-truth labeled calibration sets
- ✅ **Confidence Intervals** - Accounts for test and calibration uncertainty
- ✅ **Multi-Judge Consensus** - Aggregate multiple models for reliability
- ✅ **Bias Mitigation** - Position, length, and format bias detection
- ✅ **RSpec Matchers** - `have_bias_corrected_accuracy`, `satisfy_judge_consensus`, etc.

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────┐
│                    RAAF Eval System                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Production Spans → Serialization → Evaluation Engine   │
│                                            ↓             │
│                                       Metrics System     │
│                                            ↓             │
│                                    Result Storage        │
│                                                          │
│  Interfaces:                                            │
│  • RSpec Matchers (automated testing)                   │
│  • Web UI (interactive experimentation)                 │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Two-Gem Architecture

**raaf-eval** (Core Engine):
- Span serialization and deserialization
- Evaluation execution engine
- Metrics calculation (quantitative, qualitative, statistical)
- RSpec integration and matchers
- Database models and persistence

**raaf-eval-ui** (Web Interface):
- Rails engine with Phlex components
- Span browser with filtering
- Prompt editor with Monaco
- Real-time execution tracking
- Results visualization
- Session persistence

See **[Architecture Details](eval/ARCHITECTURE.md)** for complete system design.

## Installation

### Core Evaluation Engine

```ruby
# Gemfile
gem 'raaf-eval'
```

```bash
bundle install
cd eval
bundle exec rake db:migrate
```

### Web UI (Optional)

```ruby
# Gemfile
gem 'raaf-eval-ui'
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount RAAF::Eval::UI::Engine, at: "/eval"
end
```

See **[Installation Guide](eval/README.md)** for detailed setup.

## Usage Examples

### Quick Evaluation

```ruby
require 'raaf/eval'

# Get baseline span from production
baseline_span = RAAF::Eval::SpanAccessor.new.find_by_id("span_123")

# Create evaluation with configuration changes
engine = RAAF::Eval::EvaluationEngine.new
run = engine.create_run(
  name: "Model Comparison",
  baseline_span: RAAF::Eval::SpanSerializer.serialize(baseline_span),
  configurations: [
    { name: "GPT-4", changes: { model: "gpt-4o" } },
    { name: "Claude", changes: { model: "claude-3-5-sonnet-20241022", provider: "anthropic" } }
  ]
)

# Execute and view results
results = engine.execute_run(run)
results.each do |result|
  puts "#{result.configuration.name}: #{result.token_metrics[:total_tokens]} tokens"
end
```

### RSpec Testing

```ruby
RSpec.describe "Agent quality validation" do
  it "maintains output quality across prompt changes" do
    baseline = latest_span_for("ResearchAgent")

    result = evaluate_span(baseline) do |config|
      config.instructions = "Enhanced instructions with more context..."
    end

    expect(result).to maintain_semantic_similarity(threshold: 0.9)
    expect(result).to have_no_safety_violations
    expect(result).to pass_llm_judge(criteria: "accuracy and completeness")
  end
end
```

See **[Getting Started Guide](eval/GETTING_STARTED.md)** for comprehensive examples.

## Metrics System

RAAF Eval provides four categories of metrics:

### 1. Quantitative Metrics
- **Token Usage** - Input, output, total tokens with cost calculation
- **Latency** - Request, processing, total time
- **Accuracy** - Exact match, containment, structural validation
- **Length** - Character and word counts with deltas

### 2. Qualitative Metrics (AI-Powered)
- **Semantic Similarity** - Cosine similarity via embeddings
- **Bias Detection** - Protected attribute mentions
- **Hallucination Detection** - Unsupported claim identification
- **Tone Analysis** - Sentiment and formality assessment

### 3. Statistical Metrics
- **Confidence Intervals** - 95% confidence bounds
- **Statistical Significance** - p-values and significance tests
- **Effect Size** - Cohen's d for practical significance

### 4. Custom Metrics
- **Domain-Specific KPIs** - Define your own metrics
- **Business Logic Validation** - Custom assertion logic

See **[Metrics Documentation](eval/METRICS.md)** for complete reference.

## RSpec Matchers Reference

### Performance Matchers
- `complete_within(ms)` - Execution time limit
- `use_fewer_tokens_than(baseline)` - Token efficiency
- `reduce_tokens_by_at_least(percent)` - Token reduction
- `have_latency_under(ms)` - Response time

### Quality Matchers
- `maintain_semantic_similarity(threshold)` - Meaning preservation
- `have_output_length_within(range)` - Length constraints
- `match_baseline_structure` - Structural consistency
- `pass_llm_judge(criteria)` - AI quality assessment

### Regression Matchers
- `not_regress_from_baseline` - Overall quality check
- `maintain_baseline_quality` - Quality preservation
- `improve_over_baseline` - Quality improvement

### Safety Matchers
- `have_no_safety_violations` - Content safety
- `detect_no_bias` - Bias detection
- `detect_no_hallucinations` - Factual accuracy

**[Complete Matcher Reference](eval/RSPEC_INTEGRATION.md#available-matchers)**

## Integration with RAAF Ecosystem

### Current Integration

RAAF Eval integrates with:
- **raaf-core** - Agent execution and tracing
- **raaf-tracing** - Span data access
- **raaf-providers** - Multi-provider support

### Future Integration (Phase 4.5)

When RAAF tracing dashboard UI exists:
- **"Evaluate This Span"** buttons in trace views
- **"View Original Trace"** links in eval results
- **Unified navigation** between monitoring and evaluation
- **Shared authentication** and authorization

See **[Integration Guide](eval-ui/INTEGRATION_GUIDE.md)** for patterns and recommendations.

## Performance

RAAF Eval is designed for production use:

- **Serialization**: < 10ms per span
- **Evaluation**: ~100-500ms per execution (depends on LLM)
- **Metrics**: < 5ms quantitative, ~200ms qualitative
- **Database**: < 50ms query time for 10,000+ records
- **UI**: < 100ms page load, < 50ms component render

See **[Performance Benchmarks](eval/PERFORMANCE.md)** for detailed analysis.

## Development Status

### Phase 1: Foundation (✅ Complete)
- Database schema and migrations
- Span serialization and deserialization
- Evaluation execution engine
- Basic metrics system

### Phase 2: RSpec Integration (✅ Complete)
- 40+ RSpec matchers across 8 categories
- Fluent evaluation DSL
- Helper methods and test utilities
- CI/CD integration support

### Phase 3: Web UI (✅ Complete)
- Span browser with filtering
- Prompt editor with Monaco
- Settings configuration form
- Real-time execution tracking
- Results comparison view
- Session management

### Phase 4: Metrics & Active Record (Planned)
- Active Record model linking
- Historical performance tracking
- Baseline management
- Automated regression detection

### Phase 4.5: Tracing Integration (Future)
- Deep integration with tracing dashboard
- Cross-navigation between systems
- Unified RAAF platform experience

See **[Product Roadmap](.agent-os/product/roadmap.md)** for complete timeline.

## Contributing

We welcome contributions! See:
- **[Contributing Guide](eval-ui/CONTRIBUTING.md)** - Development setup and guidelines
- **[Architecture Documentation](eval/ARCHITECTURE.md)** - System design
- **[GitHub Issues](https://github.com/raaf-ai/ruby-ai-agents-factory/issues)** - Bug reports and features

## License

MIT License - see LICENSE file for details.

## Documentation Map

### For Users
1. Start: **[README](eval/README.md)** - Quick start
2. Learn: **[Getting Started](eval/GETTING_STARTED.md)** - Tutorial
3. Test: **[RSpec Integration](eval/RSPEC_INTEGRATION.md)** - Writing tests
4. UI: **[UI Setup](eval-ui/README.md)** - Web interface

### For Developers
1. **[Architecture](eval/ARCHITECTURE.md)** - System design
2. **[API Reference](eval/API.md)** - Complete API
3. **[Metrics](eval/METRICS.md)** - Metrics system
4. **[Performance](eval/PERFORMANCE.md)** - Benchmarks

### For Integrators
1. **[Integration Guide](eval-ui/INTEGRATION_GUIDE.md)** - RAAF ecosystem integration
2. **[Migrations](eval/MIGRATIONS.md)** - Database schema
3. **[Contributing](eval-ui/CONTRIBUTING.md)** - Development guide

---

**Questions?** Open an issue on [GitHub](https://github.com/raaf-ai/ruby-ai-agents-factory/issues) or check existing documentation.
