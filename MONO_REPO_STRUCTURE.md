# Ruby AI Agents Factory - Mono-repo Structure

This repository contains the Ruby AI Agents Factory (RAAF) organized as a mono-repo with multiple independent gems. This structure allows for modular adoption and clear separation of concerns.

## 📦 Available Gems

### Core Foundation
- **[raaf-core](gems/raaf-core/)** - Essential agent runtime + default OpenAI provider
- **[raaf-dsl](gems/raaf-dsl/)** - Declarative configuration DSL
- **[raaf-providers](gems/raaf-providers/)** - Additional LLM providers (Anthropic, Cohere, etc.)

### Tools & Extensions
- **[raaf-tools](gems/raaf-tools/)** - Basic tool framework (web search, file search)
- **[raaf-tools-advanced](gems/raaf-tools-advanced/)** - Enterprise tools (computer, document, code interpreter)
- **[raaf-extensions](gems/raaf-extensions/)** - Plugin architecture and extension system

### Safety & Compliance
- **[raaf-guardrails](gems/raaf-guardrails/)** - Safety validation and filtering
- **[raaf-compliance](gems/raaf-compliance/)** - Enterprise compliance (GDPR, HIPAA, SOX)

### Memory & Context
- **[raaf-memory](gems/raaf-memory/)** - Memory management and vector search

### Advanced Processing
- **[raaf-multimodal](gems/raaf-multimodal/)** - Vision, audio, and document processing
- **[raaf-voice](gems/raaf-voice/)** - Voice interaction pipeline
- **[raaf-data-pipeline](gems/raaf-data-pipeline/)** - Data processing workflows

### Integration & Protocols
- **[raaf-mcp](gems/raaf-mcp/)** - Model Context Protocol integration
- **[raaf-handoffs](gems/raaf-handoffs/)** - Advanced agent handoff patterns

### Development & Operations
- **[raaf-streaming](gems/raaf-streaming/)** - Real-time streaming and async
- **[raaf-tracing](gems/raaf-tracing/)** - Monitoring and observability
- **[raaf-debug](gems/raaf-debug/)** - Development tools and REPL
- **[raaf-visualization](gems/raaf-visualization/)** - Visual analysis and reporting
- **[raaf-rails](gems/raaf-rails/)** - Rails integration with web UI

### Utilities
- **[raaf-testing](gems/raaf-testing/)** - Testing utilities and RSpec matchers
- **[raaf-prompts](gems/raaf-prompts/)** - Prompt management and templating

## 🚀 Quick Start

### Minimal Setup
```ruby
# Gemfile
gem 'raaf-core'

# Usage
require 'raaf-core'
agent = RubyAIAgentsFactory::Agent.new(
  name: "Assistant",
  instructions: "You are helpful",
  model: "gpt-4o"
)
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("Hello!")
```

### Full-Featured Setup
```ruby
# Gemfile
gem 'raaf-core'
gem 'raaf-dsl'
gem 'raaf-tools'
gem 'raaf-guardrails'
gem 'raaf-memory'
gem 'raaf-tracing'
```

### Enterprise Setup
```ruby
# Gemfile
gem 'raaf-core'
gem 'raaf-dsl'
gem 'raaf-providers'
gem 'raaf-tools-advanced'
gem 'raaf-guardrails'
gem 'raaf-compliance'
gem 'raaf-memory'
gem 'raaf-tracing'
gem 'raaf-rails'
```

## 🏗️ Architecture

### Dependency Graph
```
raaf-core (foundation)
├── raaf-dsl
├── raaf-providers
├── raaf-tools
│   └── raaf-tools-advanced
├── raaf-guardrails
│   └── raaf-compliance
├── raaf-memory
├── raaf-multimodal
│   └── raaf-voice
├── raaf-streaming
├── raaf-tracing
│   ├── raaf-debug
│   ├── raaf-visualization
│   └── raaf-rails
└── raaf-testing
```

### Design Principles
1. **Modular** - Use only what you need
2. **Layered** - Clear dependency hierarchy
3. **Extensible** - Plugin architecture
4. **Compatible** - Maintains API consistency
5. **Enterprise-ready** - Production-grade features

## 🔧 Development

### Building All Gems
```bash
# Build all gems
rake build:all

# Build specific gem
rake build:core
rake build:tools
```

### Testing
```bash
# Test all gems
rake test:all

# Test specific gem
rake test:core
rake test:tools
```

### Publishing
```bash
# Publish all gems
rake publish:all

# Publish specific gem
rake publish:core
```

## 📚 Documentation

Each gem has its own README with detailed usage instructions:
- Core documentation: [gems/raaf-core/README.md](gems/raaf-core/README.md)
- Tools documentation: [gems/raaf-tools/README.md](gems/raaf-tools/README.md)
- And so on...

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make changes to the appropriate gem(s)
4. Add tests for your changes
5. Ensure all tests pass (`rake test:all`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## 📄 License

Each gem is available as open source under the terms of the [MIT License](LICENSE).

## 🔗 Links

- **Main Repository**: https://github.com/raaf-ai/ruby-ai-agents-factory
- **Documentation**: https://docs.raaf.ai
- **Issues**: https://github.com/raaf-ai/ruby-ai-agents-factory/issues
- **Discussions**: https://github.com/raaf-ai/ruby-ai-agents-factory/discussions