# Memory Examples

This directory contains examples demonstrating memory management capabilities for RAAF (Ruby AI Agents Factory).

## Example Status

✅ = Working example  
⚠️ = Partial functionality (some features may require external setup)  
❌ = Requires missing library functionality  
📋 = Design documentation (shows planned API for unimplemented features)

## Memory System Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `memory_agent_simple.rb` | ✅ | Memory system components demo | Shows how memory stores work independently |
| `context_management_example.rb` | ✅ | Context management strategies | Fully working (runs 20 API calls) |
| `memory_agent_example.rb` | 📋 | Agent memory integration (DESIGN DOC) | Shows planned memory API - redirects to working memory_agent_simple.rb |
| `vector_store_example.rb` | ❌ | Vector database integration | Requires vector DB setup |
| `semantic_search_example.rb` | ❌ | Semantic search capabilities | Requires embeddings and vector store |

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

3. For vector store examples (when implemented):
   ```bash
   # Vector database setup will be required
   # Instructions will be provided when implemented
   ```

### Running Working Examples

```bash
# Basic memory components
ruby memory/examples/memory_agent_simple.rb

# Context management
ruby memory/examples/context_management_example.rb
```

## Memory System Components

### Memory Stores
- **InMemoryStore**: Fast, temporary storage for session data
- **FileStore**: Persistent storage using local files
- **VectorStore**: Semantic search capabilities (planned)

### Context Management
- **Automatic context pruning**: Manages conversation length
- **Important message preservation**: Keeps critical information
- **Semantic relevance**: Maintains context coherence

### Memory Features
- **Session persistence**: Remembers across conversations
- **Selective retention**: Keeps important information
- **Context-aware retrieval**: Finds relevant past interactions
- **Memory consolidation**: Optimizes storage over time

## Design Documentation

The `memory_agent_example.rb` file serves as design documentation showing the planned integration between agents and memory systems. It demonstrates:

- Seamless memory integration with agents
- Automatic context management
- Persistent conversation history
- Intelligent memory retrieval

This example redirects to `memory_agent_simple.rb` which shows the current working implementation of memory components.

## Notes

- Memory system is actively being developed
- Working examples demonstrate current capabilities
- Vector store integration is planned for future releases
- Check individual example files for detailed comments and requirements