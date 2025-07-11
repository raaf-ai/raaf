# OpenAI Agents Ruby Examples

This directory contains example scripts demonstrating various features of the OpenAI Agents Ruby library.

## Example Status

✅ = Working example  
⚠️ = Partial functionality (some features may require external setup)  
❌ = Requires missing library functionality  
📋 = Design documentation (shows planned API for unimplemented features)

### Core Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `basic_example.rb` | ✅ | Basic agent creation, tools, and conversations | Fully working |
| `multi_agent_example.rb` | ✅ | Multi-agent collaboration with handoffs | Fully working |
| `structured_output_example.rb` | ✅ | Universal structured output with JSON schemas | Fully working |
| `tracing_example.rb` | ✅ | Distributed tracing and monitoring | Fully working |
| `guardrails_example.rb` | ✅ | Input/output guardrails and safety | Fully working |
| `tool_context_example.rb` | ✅ | Tool context management | Fully working |
| `tool_context_simple.rb` | ✅ | Simplified tool context demo | Alternative implementation |

### Memory System

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `memory_agent_example.rb` | 📋 | Agent memory integration (DESIGN DOC) | Shows planned memory API - redirects to working memory_agent_simple.rb |
| `memory_agent_simple.rb` | ✅ | Memory system components demo | Shows how memory stores work independently |

### Advanced Features

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `async_example.rb` | ✅ | Concurrent agent operations | Fixed - now shows proper concurrent patterns using threads |
| `context_management_example.rb` | ✅ | Context management strategies | Fully working (runs 20 API calls) |
| `handoff_objects_example.rb` | ✅ | Advanced handoff patterns | Fully working |
| `dynamic_prompts_example.rb` | ✅ | Dynamic prompt generation | Fully working |
| `lifecycle_hooks_example.rb` | ✅ | Agent lifecycle hooks | Fixed - hooks now work properly after integration fixes |

### Provider Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `multi_provider_example.rb` | ✅ | Multiple AI providers | Working (OpenAI only, others need API keys) |
| `cohere_provider_example.rb` | ✅ | Cohere integration | Working (requires Cohere API key) |
| `litellm_example.rb` | ⚠️ | LiteLLM integration | Requires LiteLLM setup |
| `response_format_example.rb` | ✅ | Response formatting | Fully working (universal structured output) |

### Enterprise Features

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `compliance_example.rb` | ⚠️ | Compliance and audit features | Requires compliance module setup |
| `security_scanning_example.rb` | ⚠️ | Security scanning integration | Requires security tools |
| `pii_guardrail_example.rb` | ⚠️ | PII detection guardrails | Requires PII detection setup |
| `tripwire_guardrail_example.rb` | ⚠️ | Tripwire rules | Requires guardrail configuration |

### Integration Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `confluence_tool_example.rb` | ❌ | Confluence integration | Requires Confluence API setup |
| `mcp_integration_example.rb` | ❌ | Model Context Protocol | MCP server required |
| `vector_store_example.rb` | ❌ | Vector database integration | Requires vector DB setup |
| `semantic_search_example.rb` | ❌ | Semantic search capabilities | Requires embeddings and vector store |

### Data Processing

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `batch_processing_example.rb` | 📋 | Batch processing workflows (DESIGN DOC) | Shows planned BatchProcessor API - implementation roadmap |
| `data_pipeline_example.rb` | ⚠️ | Data pipeline patterns | May require additional tools |
| `output_type_validation_example.rb` | ⚠️ | Output validation | Should work with schemas |

### UI/Multimodal

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `multi_modal_example.rb` | ❌ | Image/audio processing | Requires multimodal API access |
| `message_flow_example.rb` | ⚠️ | Message flow control | Should work with basic setup |

### Showcase Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `complete_features_showcase.rb` | 📋 | Comprehensive feature demo (DESIGN DOC) | 750+ lines of planned features - implementation specification |
| `comprehensive_examples.rb` | ⚠️ | Extended examples | Mixed functionality |
| `advanced_features_example.rb` | 📋 | Advanced features demo (DESIGN DOC) | Shows planned API design - ~30% implemented, 70% planned |
| `python_parity_features_example.rb` | 📋 | Python SDK parity demo (DESIGN DOC) | Shows planned parity features - ~20% parity achieved |

## Running Examples

### Prerequisites

1. Set your OpenAI API key:
   ```bash
   export OPENAI_API_KEY="your-api-key"
   ```

2. Install required gems:
   ```bash
   bundle install
   ```

3. For specific examples, you may need additional API keys:
   ```bash
   export ANTHROPIC_API_KEY="your-anthropic-key"
   export COHERE_API_KEY="your-cohere-key"
   ```

### Running Working Examples

```bash
# Basic functionality
ruby examples/basic_example.rb

# Multi-agent collaboration
ruby examples/multi_agent_example.rb

# Structured output
ruby examples/structured_output_example.rb

# Tracing
ruby examples/tracing_example.rb

# Guardrails
ruby examples/guardrails_example.rb

# Fixed examples - now working
ruby examples/async_example.rb              # Concurrent agent execution
ruby examples/lifecycle_hooks_example.rb    # Agent lifecycle hooks
```

### Design Documentation Examples

Examples marked with 📋 are **design documentation** that show planned APIs for unimplemented features. They include clear warnings and serve as:
- Implementation roadmaps for developers
- API specifications for future features  
- Educational resources about planned capabilities

These examples include comprehensive error handling and redirect users to working alternatives where available.

### Examples with Missing Functionality

For examples marked with ❌, the required library functionality is not yet implemented. These typically require external services or dependencies.

**Note**: Examples marked with 📋 (design docs) will show warnings and demonstrate planned APIs, while ❌ examples require actual missing functionality to work.

## Contributing

If you'd like to help implement missing functionality or improve examples:

1. Check the example status above
2. Review the intended API in non-working examples
3. Submit a PR with implementation or improvements

## Notes

- Examples are kept for API design reference even if not fully functional
- Working examples have been tested with the current library version
- Some examples require external services or additional setup
- Check individual example files for detailed comments and requirements