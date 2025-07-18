# Core Examples

This directory contains examples demonstrating the core functionality of RAAF (Ruby AI Agents Factory).

## Example Status

✅ = Working example  
⚠️ = Partial functionality (some features may require external setup)  
❌ = Requires missing library functionality  
📋 = Design documentation (shows planned API for unimplemented features)

## Core Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `basic_example.rb` | ✅ | Basic agent creation, tools, and conversations | Fully working |
| `multi_agent_example.rb` | ✅ | Multi-agent collaboration with handoffs | Fully working |
| `structured_output_example.rb` | ✅ | Universal structured output with JSON schemas | Fully working |
| `handoff_objects_example.rb` | ✅ | Advanced handoff patterns | Fully working |
| `dynamic_prompts_example.rb` | ✅ | Dynamic prompt generation | Fully working |
| `lifecycle_hooks_example.rb` | ✅ | Agent lifecycle hooks | Fixed - hooks now work properly after integration fixes |
| `response_format_example.rb` | ✅ | Response formatting | Fully working (universal structured output) |
| `message_flow_example.rb` | ⚠️ | Message flow control | Should work with basic setup |
| `output_type_validation_example.rb` | ⚠️ | Output validation | Should work with schemas |
| `data_pipeline_example.rb` | ⚠️ | Data pipeline patterns | May require additional tools |
| `multi_modal_example.rb` | ❌ | Image/audio processing | Requires multimodal API access |

## Advanced Features

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `configuration_example.rb` | ✅ | Configuration management | Fully working |
| `token_estimation_example.rb` | ✅ | Token usage estimation | Fully working |
| `usage_tracking_example.rb` | ✅ | Usage tracking and monitoring | Fully working |
| `retry_logic_example.rb` | ✅ | Retry and error handling | Fully working |
| `extension_system_example.rb` | ✅ | Extension and plugin system | Fully working |
| `voice_workflow_example.rb` | ✅ | Voice interaction workflows | Fully working |

## Showcase Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `complete_features_showcase.rb` | 📋 | Comprehensive feature demo (DESIGN DOC) | 750+ lines of planned features - implementation specification |
| `comprehensive_examples.rb` | ⚠️ | Extended examples | Mixed functionality |
| `advanced_features_example.rb` | 📋 | Advanced features demo (DESIGN DOC) | Shows planned API design - ~30% implemented, 70% planned |
| `python_parity_features_example.rb` | 📋 | Python SDK parity demo (DESIGN DOC) | Shows planned parity features - ~20% parity achieved |

## Data Processing

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `batch_processing_example.rb` | 📋 | Batch processing workflows (DESIGN DOC) | Shows planned BatchProcessor API - implementation roadmap |
| `working_batch_processing_example.rb` | ✅ | Working batch processing demo | Functional implementation |

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

### Running Working Examples

```bash
# Basic functionality
ruby core/examples/basic_example.rb

# Multi-agent collaboration
ruby core/examples/multi_agent_example.rb

# Structured output
ruby core/examples/structured_output_example.rb

# Advanced handoffs
ruby core/examples/handoff_objects_example.rb

# Configuration
ruby core/examples/configuration_example.rb

# Usage tracking
ruby core/examples/usage_tracking_example.rb

# Fixed examples - now working
ruby core/examples/lifecycle_hooks_example.rb    # Agent lifecycle hooks
```

### Design Documentation Examples

Examples marked with 📋 are **design documentation** that show planned APIs for unimplemented features. They include clear warnings and serve as:
- Implementation roadmaps for developers
- API specifications for future features  
- Educational resources about planned capabilities

These examples include comprehensive error handling and redirect users to working alternatives where available.

## Notes

- Examples are kept for API design reference even if not fully functional
- Working examples have been tested with the current library version
- Some examples require external services or additional setup
- Check individual example files for detailed comments and requirements