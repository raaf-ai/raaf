# Technical Stack

> Last Updated: 2025-11-06
> Version: 1.0.0

## Application Framework

- **Language:** Ruby 3.3+
- **Architecture:** Gem within RAAF mono-repo structure
- **Gem Name:** raaf-eval
- **Minimum Ruby Version:** 3.3.0

## Web Framework

- **Framework:** Ruby on Rails 7.0+
- **UI Library:** Phlex for component-based views
- **JavaScript:** Stimulus Rails (~> 1.0) for interactivity
- **Reactivity:** Turbo Rails (~> 1.0) for dynamic updates
- **CSS Framework:** Tailwind CSS (inherited from RAAF Rails integration)

## Database

- **Primary:** PostgreSQL with pgvector extension
- **ORM:** Active Record
- **Migrations:** Rails migrations
- **Schema:** Evaluation runs, span snapshots, results, and configuration tracking

## Testing Framework

- **Framework:** RSpec (~> 3.0)
- **Rails Testing:** RSpec Rails (~> 6.0)
- **Integration:** Native RSpec integration for running evals as tests
- **Test Data:** Factory Bot (~> 6.2) for generating test scenarios

## RAAF Integration

- **Core Dependency:** raaf-core (tracing, agents, spans)
- **Tracing Integration:** raaf-tracing (span data access)
- **Provider Support:** All RAAF providers (OpenAI, Anthropic, Groq, Gemini, Perplexity, etc.)
- **Rails Integration:** raaf-rails (UI dashboard and routes)

## API & HTTP

- **HTTP Client:** Faraday (~> 2.7) for external API calls
- **API Design:** RESTful Rails controllers with JSON responses
- **Authentication:** Inherits from RAAF Rails authentication system

## UI Components

- **Component Library:** Phlex-based components
- **Forms:** Rails form helpers with Phlex DSL
- **Data Tables:** Server-side pagination and filtering
- **Code Editor:** Monaco Editor or CodeMirror for prompt editing
- **Diff Viewer:** Syntax-highlighted diff display for prompt comparison

## Development Tools

- **Linting:** RuboCop (~> 1.21)
- **Documentation:** YARD (~> 0.9)
- **Debugging:** Pry (~> 0.14) with Pry Byebug
- **Code Quality:** SimpleCov (~> 0.21) for coverage

## Infrastructure

- **Build Tool:** Rake (~> 13.0)
- **Dependency Manager:** Bundler (~> 2.0)
- **Package Distribution:** RubyGems (as part of RAAF mono-repo)
- **CI/CD:** GitHub Actions (integrated with RAAF CI pipeline)

## Storage & Caching

- **Span Storage:** PostgreSQL JSONB columns for span data snapshots
- **Result Caching:** Rails cache for computed metrics
- **File Storage:** Local file system or Rails Active Storage (for exports)

## Security

- **Authentication:** Inherits from RAAF Rails authentication
- **Authorization:** Role-based access control for evaluation management
- **PII Handling:** Leverages RAAF's built-in PII detection and redaction
- **Audit Logging:** Track all configuration changes and evaluation runs

## Deployment

- **Application Hosting:** Deployed as part of RAAF Rails application
- **Database Hosting:** PostgreSQL (same as RAAF)
- **Asset Pipeline:** Propshaft or Sprockets (Rails default)
- **Code Repository:** GitHub (RAAF mono-repo)
