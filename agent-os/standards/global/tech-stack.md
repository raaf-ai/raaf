# Tech Stack

> Version: 1.0.0
> Last Updated: 2025-01-22

## Context

This file is part of the Agent OS standards system. These global tech stack defaults are referenced by all product codebases when initializing new projects. Individual projects may override these choices in their `.agent-os/product/tech-stack.md` file.

## Core Technologies

### Application Framework
- **Language:** Ruby 3.3+
- **Architecture:** Modular gem-based mono-repo
- **Minimum Ruby Version:** 3.0.0 (3.3.0+ for core modules)

### AI/LLM Integration
- **Primary Provider:** OpenAI (~> 7.0)
- **Additional Providers:** 
  - Anthropic (~> 0.3)
  - Google Cloud AI Platform (~> 1.0)
  - AWS SDK Bedrock (~> 1.0)
  - Azure OpenAI (~> 0.1)

### Database
- **Primary:** PostgreSQL with pgvector extension
- **ORM:** Active Record (when using Rails integration)
- **Additional Storage:** In-memory and file-based options

## Web Framework (Optional)

### Rails Integration
- **Framework:** Ruby on Rails 7.0+
- **JavaScript:** Stimulus Rails (~> 1.0) **MANDATORY** - No vanilla JavaScript
- **Reactivity:** Turbo Rails (~> 1.0)
- **JavaScript Philosophy:**
  - Use Stimulus controllers exclusively
  - Abstract common behaviors into reusable controllers
  - Promote controller composition and inheritance
  - Never write inline JavaScript or vanilla JS

### HTTP & Networking
- **HTTP Client:** Faraday (~> 2.7)
- **Alternative:** HTTParty (~> 0.21)
- **Async Support:** Async (~> 2.0)

## Testing & Quality

### Testing Framework
- **Framework:** RSpec (~> 3.0)
- **Rails Testing:** RSpec Rails (~> 6.0)
- **Integration Testing:** Capybara (~> 3.0)
- **Browser Automation:** Selenium WebDriver (~> 4.0)

### Code Quality
- **Linting:** RuboCop (~> 1.21)
- **Documentation:** YARD (~> 0.9)
- **Coverage:** SimpleCov (~> 0.21)

### Development Tools
- **Debugging:** Pry (~> 0.14) with Pry Byebug
- **HTTP Mocking:** WebMock (~> 3.18) with VCR (~> 6.1)
- **Test Data:** Factory Bot (~> 6.2)

## Infrastructure

### Build & Dependency Management
- **Build Tool:** Rake (~> 13.0)
- **Dependency Manager:** Bundler (~> 2.0)
- **Package Distribution:** RubyGems

### CI/CD Pipeline
- **Platform:** GitHub Actions
- **Ruby Versions Tested:** 3.2, 3.3, 3.4, ruby-head
- **Container Support:** Docker

### Documentation
- **Documentation Site:** Jekyll with GitHub Pages
- **Markdown Processing:** Redcarpet (~> 3.6.1)
- **Syntax Highlighting:** Rouge

## Security & Compliance

### Security Features
- **PII Detection:** Built-in redaction capabilities
- **Security Filtering:** Tripwire rules and content filtering
- **Compliance:** GDPR/SOC2/HIPAA tracking support
- **Audit Logging:** With integrity hashing

## External Integrations

### Tool Integration
- **Protocol:** Model Context Protocol (MCP)
- **External Tools:** 
  - Confluence integration
  - Local shell execution
  - Computer control capabilities
- **Communication:** Speech-to-text and text-to-speech pipelines

---

*Customize this file with your organization's preferred tech stack. These defaults are used when initializing new projects with Agent OS.*
