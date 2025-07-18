# RAAF (Ruby AI Agents Factory) Examples

This directory serves as the main entry point for all examples across the RAAF (Ruby AI Agents Factory) ecosystem. Examples have been organized into their respective sub-gem directories to better reflect the modular architecture.

## Sub-Gem Examples

Each sub-gem contains its own examples directory with comprehensive documentation:

### 🧠 [Core Examples](../core/examples/)
Essential functionality including basic agents, multi-agent collaboration, structured output, and handoffs.

### 🔌 [Provider Examples](../providers/examples/)
AI provider integrations including OpenAI, Anthropic, Cohere, Groq, Ollama, and Together AI.

### 💾 [Memory Examples](../memory/examples/)
Memory management, context handling, vector stores, and semantic search capabilities.

### 📊 [Tracing Examples](../tracing/examples/)
Distributed tracing, monitoring, alerting, and performance analytics.

### 🛡️ [Guardrails Examples](../guardrails/examples/)
Safety features, compliance tools, PII detection, and security scanning.

### 🔧 [Basic Tools Examples](../tools-basic/examples/)
Simple tool creation, context management, and function wrapping.

### ⚙️ [Advanced Tools Examples](../tools-advanced/examples/)
Complex integrations including code execution, web search, and enterprise tools.

### 🌊 [Streaming Examples](../streaming/examples/)
Real-time streaming, asynchronous operations, and concurrent processing.

### 🐛 [Debug Examples](../debug/examples/)
Debugging tools, interactive REPL, and development utilities.

### 📈 [Analytics Examples](../analytics/examples/)
AI-powered analytics, natural language queries, and data visualization.

### 📝 [Logging Examples](../logging/examples/)
Unified logging system, Rails integration, and structured logging.

### 🚄 [Rails Examples](../rails/examples/)
Ruby on Rails integration, controllers, models, and frontend components.

### 📊 [Visualization Examples](../visualization/examples/)
Workflow diagrams, performance charts, and interactive dashboards.

## Quick Start

### Prerequisites

1. Set your OpenAI API key:
   ```bash
   export OPENAI_API_KEY="your-api-key"
   ```

2. Install required gems:
   ```bash
   bundle install
   ```

### Running Examples

Navigate to any sub-gem's examples directory and run the examples:

```bash
# Core functionality
ruby core/examples/basic_example.rb

# Multi-agent collaboration  
ruby core/examples/multi_agent_example.rb

# Provider integration
ruby providers/examples/multi_provider_example.rb

# Memory and context
ruby memory/examples/memory_agent_simple.rb

# Tracing and monitoring
ruby tracing/examples/tracing_example.rb

# Streaming responses
ruby streaming/examples/streaming_example.rb
```

## Example Categories

### ✅ Production Ready
Examples marked as working are production-ready and fully tested.

### ⚠️ Requires Setup  
Examples that need external services or additional configuration.

### ❌ Planned Features
Examples showing future functionality - currently design specifications.

### 📋 Design Documentation
Comprehensive API specifications for planned features.

## Getting Help

Each sub-gem's examples directory contains:
- **README.md**: Detailed documentation and setup instructions
- **Working examples**: Fully functional code you can run immediately
- **Configuration guides**: How to set up external services
- **Usage patterns**: Best practices and common scenarios

## Architecture Benefits

This modular organization provides:
- **Clear separation**: Each gem focuses on specific functionality
- **Independent development**: Work on features in isolation
- **Easier maintenance**: Find and update examples efficiently
- **Better documentation**: Focused docs for each component

## Contributing

To contribute examples:

1. **Choose the right sub-gem**: Place examples in the appropriate directory
2. **Follow conventions**: Use existing examples as templates
3. **Update documentation**: Add your example to the sub-gem's README
4. **Test thoroughly**: Ensure examples work as documented

## Notes

- All working examples have been tested with the current library version
- Sub-gem examples can be run independently
- Check individual README files for specific requirements and setup instructions
- Examples demonstrate both basic usage and advanced patterns