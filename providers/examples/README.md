# Provider Examples

This directory contains examples demonstrating various AI provider integrations for RAAF (Ruby AI Agents Factory).

## Example Status

✅ = Working example  
⚠️ = Partial functionality (some features may require external setup)  
❌ = Requires missing library functionality  

## Provider Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `multi_provider_example.rb` | ✅ | Multiple AI providers | Working (OpenAI only, others need API keys) |
| `cohere_provider_example.rb` | ✅ | Cohere integration | Working (requires Cohere API key) |
| `anthropic_provider_example.rb` | ✅ | Anthropic integration | Working (requires Anthropic API key) |
| `groq_provider_example.rb` | ✅ | Groq integration | Working (requires Groq API key) |
| `ollama_provider_example.rb` | ✅ | Ollama local models | Working (requires Ollama setup) |
| `together_provider_example.rb` | ✅ | Together AI integration | Working (requires Together API key) |
| `retryable_provider_example.rb` | ✅ | Provider retry logic | Working (demonstrates error handling) |
| `litellm_example.rb` | ⚠️ | LiteLLM integration | Requires LiteLLM setup |

## Running Examples

### Prerequisites

1. Set your OpenAI API key (always required):
   ```bash
   export OPENAI_API_KEY="your-openai-key"
   ```

2. For specific providers, set additional API keys:
   ```bash
   export ANTHROPIC_API_KEY="your-anthropic-key"
   export COHERE_API_KEY="your-cohere-key"
   export GROQ_API_KEY="your-groq-key"
   export TOGETHER_API_KEY="your-together-key"
   ```

3. For Ollama (local models):
   ```bash
   # Install and start Ollama
   ollama pull llama2
   ollama serve
   ```

4. Install required gems:
   ```bash
   bundle install
   ```

### Running Provider Examples

```bash
# Multi-provider demo (OpenAI fallback)
ruby providers/examples/multi_provider_example.rb

# Specific providers (require API keys)
ruby providers/examples/cohere_provider_example.rb
ruby providers/examples/anthropic_provider_example.rb
ruby providers/examples/groq_provider_example.rb

# Local models
ruby providers/examples/ollama_provider_example.rb

# Error handling and retries
ruby providers/examples/retryable_provider_example.rb
```

## Provider Configuration

### OpenAI (Default)
- **Required**: `OPENAI_API_KEY`
- **Models**: `gpt-4o`, `gpt-4`, `gpt-3.5-turbo`
- **Features**: Full feature support

### Anthropic
- **Required**: `ANTHROPIC_API_KEY`
- **Models**: `claude-3-opus`, `claude-3-sonnet`, `claude-3-haiku`
- **Features**: Text generation, function calling

### Cohere
- **Required**: `COHERE_API_KEY`
- **Models**: `command`, `command-nightly`
- **Features**: Text generation, basic function calling

### Groq
- **Required**: `GROQ_API_KEY`
- **Models**: `mixtral-8x7b-32768`, `llama2-70b-4096`
- **Features**: Fast inference, text generation

### Ollama (Local)
- **Required**: Ollama installation and running service
- **Models**: Any Ollama-compatible model (`llama2`, `mistral`, etc.)
- **Features**: Local inference, privacy-focused

### Together AI
- **Required**: `TOGETHER_API_KEY`
- **Models**: Various open-source models
- **Features**: Affordable inference, multiple models

## Notes

- All examples fall back to OpenAI if the specific provider is not configured
- Provider-specific features may vary based on the underlying API capabilities
- Some providers may have rate limits or usage restrictions
- Check individual example files for provider-specific configuration options