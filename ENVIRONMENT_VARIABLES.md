# RAAF Environment Variables Reference

This document provides a comprehensive reference for all environment variables used by the Ruby AI Agents Factory (RAAF).

## Core Configuration

### `RAAF_ENVIRONMENT`
- **Function**: Sets the application environment mode
- **Used in**: `core/lib/raaf/configuration.rb`, `tracing/lib/raaf/tracing/trace_provider.rb`
- **What**: Controls environment-specific behavior like console tracing in development vs production logging
- **Why**: Allows different configurations for development (verbose, console output) vs production (structured logging, optimized performance)
- **Format**: String (`development`, `test`, `production`)
- **Default**: `development`
- **Example**: `export RAAF_ENVIRONMENT="production"`

### `RAAF_MAX_TURNS`
- **Function**: Maximum number of conversation turns allowed
- **Used in**: `core/lib/raaf/configuration.rb`, conversation management logic
- **What**: Prevents infinite loops in agent conversations by limiting the number of back-and-forth exchanges
- **Why**: Protects against runaway costs and infinite loops when agents keep calling each other or tools repeatedly
- **Format**: Integer
- **Default**: `100`
- **Example**: `export RAAF_MAX_TURNS="50"`

### `RAAF_DEFAULT_MODEL`
- **Function**: Default AI model to use when none specified
- **Used in**: `core/lib/raaf/configuration.rb`, agent initialization
- **What**: Sets the fallback model when agents are created without explicit model specification
- **Why**: Provides consistent model selection across the application and allows easy model switching via environment
- **Format**: String (model identifier)
- **Default**: `gpt-4o`
- **Example**: `export RAAF_DEFAULT_MODEL="gpt-4o-mini"`

### `RAAF_DEBUG`
- **Function**: Enable debug mode for REPL and development tools
- **Used in**: `core/lib/raaf/configuration.rb`, REPL and debugging utilities
- **What**: Activates additional debugging features like enhanced REPL, verbose error messages, and development helpers
- **Why**: Provides developers with better debugging experience during development without affecting production performance
- **Format**: Boolean (`true`, `false`)
- **Default**: `false`
- **Example**: `export RAAF_DEBUG="true"`

### `RAAF_CONTEXT_MANAGEMENT`
- **Function**: Enable automatic context management for conversations
- **Used in**: `core/lib/raaf/runner.rb`, context management system
- **What**: Automatically manages conversation context, including token limits, message pruning, and summarization
- **Why**: Prevents token limit exceeded errors and manages memory usage in long conversations without manual intervention
- **Format**: Boolean (`true`, `false`)
- **Default**: `false`
- **Example**: `export RAAF_CONTEXT_MANAGEMENT="true"`

## Logging Configuration

### `RAAF_LOG_LEVEL`
- **Function**: Sets the logging level
- **Used in**: `core/lib/raaf/logging.rb`, all logging throughout the system
- **What**: Controls which log messages are displayed based on severity (debug shows everything, fatal shows only critical errors)
- **Why**: Allows fine-tuning log verbosity for debugging (debug) vs production efficiency (warn/error)
- **Format**: String (`debug`, `info`, `warn`, `error`, `fatal`)
- **Default**: `info`
- **Example**: `export RAAF_LOG_LEVEL="debug"`

### `RAAF_LOG_FORMAT`
- **Function**: Output format for log messages
- **Used in**: `core/lib/raaf/logging.rb`, log output formatting
- **What**: Determines whether logs are human-readable text or structured JSON
- **Why**: JSON format is better for log aggregation tools (ELK, Splunk), text format is better for development console viewing
- **Format**: String (`text`, `json`)
- **Default**: `text`
- **Example**: `export RAAF_LOG_FORMAT="json"`

### `RAAF_LOG_OUTPUT`
- **Function**: Where to send log output
- **Used in**: `core/lib/raaf/logging.rb`, log destination routing
- **What**: Directs log messages to console (stdout), file, Rails logger, or automatically detects best option
- **Why**: Provides flexibility for different deployment scenarios (development console, production files, Rails integration)
- **Format**: String (`console`, `file`, `rails`, `auto`)
- **Default**: `auto`
- **Example**: `export RAAF_LOG_OUTPUT="file"`

### `RAAF_LOG_FILE`
- **Function**: Path to log file when using file output
- **Used in**: `core/lib/raaf/logging.rb`, file logger configuration
- **What**: Specifies the file path where logs should be written when `RAAF_LOG_OUTPUT=file`
- **Why**: Allows customization of log file location for different deployment environments and log rotation strategies
- **Format**: File path
- **Default**: `log/raaf.log`
- **Example**: `export RAAF_LOG_FILE="/var/log/raaf.log"`

### `RAAF_DEBUG_CATEGORIES`
- **Function**: Enable specific debug categories
- **Used in**: `core/lib/raaf/logging.rb`, debug logging throughout the system
- **What**: Fine-grained control over which types of debug messages are shown (API calls, tracing, tool execution, etc.)
- **Why**: Reduces log noise by showing only relevant debug information for the specific area you're debugging
- **Format**: Comma-separated strings or keywords
- **Options**: `api`, `tracing`, `tools`, `handoff`, `context`, `http`, `general`, `all`, `none`
- **Default**: `all`
- **Example**: `export RAAF_DEBUG_CATEGORIES="api,tracing"`

## API Keys & Provider Configuration

### `OPENAI_API_KEY` ⭐ Required
- **Function**: OpenAI API authentication key
- **Used in**: All providers, `core/lib/raaf/models/responses_provider.rb`, `core/lib/raaf/models/openai_provider.rb`
- **What**: Authenticates with OpenAI's API for accessing GPT models and other OpenAI services
- **Why**: Required for all OpenAI model calls, also enables OpenAI tracing dashboard integration
- **Format**: String (API key starting with 'sk-')
- **Default**: None (required)
- **Example**: `export OPENAI_API_KEY="sk-..."`

### `OPENAI_API_BASE`
- **Function**: Custom OpenAI API base URL
- **Format**: URL
- **Default**: `https://api.openai.com/v1`
- **Example**: `export OPENAI_API_BASE="https://custom-api.example.com/v1"`

### `OPENAI_ORGANIZATION`
- **Function**: OpenAI organization ID for billing
- **Format**: String (org ID)
- **Default**: None
- **Example**: `export OPENAI_ORGANIZATION="org-..."`

### `ANTHROPIC_API_KEY`
- **Function**: Anthropic Claude API key
- **Used in**: `providers/lib/raaf/models/anthropic_provider.rb`, multi-provider configurations
- **What**: Enables access to Anthropic's Claude models (Claude 3, Claude 3.5 Sonnet, etc.)
- **Why**: Provides alternative to OpenAI models with different capabilities, pricing, and performance characteristics
- **Format**: String (API key starting with 'sk-ant-')
- **Default**: None
- **Example**: `export ANTHROPIC_API_KEY="sk-ant-..."`

### `COHERE_API_KEY`
- **Function**: Cohere API key
- **Format**: String (API key)
- **Default**: None
- **Example**: `export COHERE_API_KEY="co-..."`

### `GROQ_API_KEY`
- **Function**: Groq API key for fast inference
- **Format**: String (API key)
- **Default**: None
- **Example**: `export GROQ_API_KEY="gsk_..."`

### `TOGETHER_API_KEY`
- **Function**: Together AI API key
- **Format**: String (API key)
- **Default**: None
- **Example**: `export TOGETHER_API_KEY="..."`

### `GEMINI_API_KEY`
- **Function**: Google Gemini API key
- **Format**: String (API key)
- **Default**: None
- **Example**: `export GEMINI_API_KEY="AI..."`

### `RAAF_DEFAULT_PROVIDER`
- **Function**: Default provider when multiple are available
- **Format**: String (`openai`, `anthropic`, `cohere`, `groq`, etc.)
- **Default**: `openai`
- **Example**: `export RAAF_DEFAULT_PROVIDER="anthropic"`

### `RAAF_PROVIDER_TIMEOUT`
- **Function**: API request timeout in seconds
- **Format**: Integer
- **Default**: `30`
- **Example**: `export RAAF_PROVIDER_TIMEOUT="60"`

### `RAAF_PROVIDER_RETRIES`
- **Function**: Number of retry attempts for failed API calls
- **Format**: Integer
- **Default**: `3`
- **Example**: `export RAAF_PROVIDER_RETRIES="5"`

## Tracing & Monitoring

### `RAAF_DISABLE_TRACING`
- **Function**: Completely disable all tracing functionality
- **Used in**: `core/lib/raaf/runner.rb`, `tracing/lib/raaf/tracing/trace_provider.rb`
- **What**: Turns off all span creation, trace collection, and trace export to improve performance
- **Why**: Useful for high-performance production environments where tracing overhead is not desired, or during testing
- **Format**: Boolean (`true`, `false`)
- **Default**: `false`
- **Example**: `export RAAF_DISABLE_TRACING="true"`

### `RAAF_TRACE_CONSOLE`
- **Function**: Enable console output for traces
- **Used in**: `tracing/lib/raaf/tracing/trace_provider.rb`, console span processor
- **What**: Prints trace spans to console/stdout for real-time debugging
- **Why**: Helpful for development debugging to see trace data immediately without needing external tools
- **Format**: Boolean (`true`, `false`)
- **Default**: `false` (auto-enabled in development environment)
- **Example**: `export RAAF_TRACE_CONSOLE="true"`

### `RAAF_TRACE_BATCH_SIZE`
- **Function**: Number of spans to batch before sending to OpenAI
- **Used in**: `tracing/lib/raaf/tracing/trace_provider.rb`, OpenAI trace export
- **What**: Groups multiple trace spans together before sending to OpenAI's trace dashboard
- **Why**: Reduces API calls and improves performance by sending traces in batches rather than individually
- **Format**: Integer
- **Default**: `10`
- **Example**: `export RAAF_TRACE_BATCH_SIZE="50"`

### `RAAF_TRACE_FLUSH_INTERVAL`
- **Function**: Interval in seconds to flush trace batches
- **Used in**: `tracing/lib/raaf/tracing/trace_provider.rb`, batch processor timing
- **What**: Maximum time to wait before sending incomplete batches to ensure traces aren't delayed too long
- **Why**: Balances between batching efficiency and real-time trace visibility in monitoring dashboards
- **Format**: Float
- **Default**: `2.0`
- **Example**: `export RAAF_TRACE_FLUSH_INTERVAL="5.0"`

## Memory & Storage

### `RAAF_MEMORY_ENCRYPTION_KEY`
- **Function**: Encryption key for memory storage
- **Format**: String (encryption key)
- **Default**: None
- **Example**: `export RAAF_MEMORY_ENCRYPTION_KEY="your-32-char-key"`

### `RAAF_MEMORY_STORAGE_PATH`
- **Function**: Directory path for memory file storage
- **Format**: Directory path
- **Default**: Current directory
- **Example**: `export RAAF_MEMORY_STORAGE_PATH="/var/lib/raaf/memory"`

### `RAAF_MEMORY_MAX_TOKENS`
- **Function**: Maximum tokens to store in memory before summarization
- **Used in**: `memory/` gem, context management system
- **What**: Threshold for triggering automatic summarization or pruning of conversation history
- **Why**: Prevents token limit errors and controls memory usage in long conversations while preserving important context
- **Format**: Integer
- **Default**: `4000`
- **Example**: `export RAAF_MEMORY_MAX_TOKENS="8000"`

## Tools Configuration

### `RAAF_WORKSPACE`
- **Function**: Base directory for tool workspaces (code execution, file operations)
- **Used in**: `tools/lib/raaf/code_interpreter_tool.rb`, `tools/lib/raaf/tools/code_interpreter_tool.rb`
- **What**: Directory where tools create temporary workspaces for code execution, file manipulation, and other operations
- **Why**: Provides isolated, controlled environment for potentially unsafe operations and allows cleanup of temporary files
- **Format**: Directory path
- **Default**: `/tmp/raaf_workspaces`
- **Example**: `export RAAF_WORKSPACE="/opt/raaf/workspaces"`

### `RAAF_TOOLS_SANDBOX`
- **Function**: Enable sandbox mode for tool execution
- **Used in**: Tool execution security layer, code interpreter tools
- **What**: Restricts tool execution to isolated environments with limited system access
- **Why**: Critical security feature preventing tools from accessing sensitive system resources or performing destructive operations
- **Format**: Boolean (`true`, `false`)
- **Default**: `true`
- **Example**: `export RAAF_TOOLS_SANDBOX="false"` (⚠️ Use with caution)

### `RAAF_TOOLS_TIMEOUT`
- **Function**: Tool execution timeout in seconds
- **Format**: Integer
- **Default**: `30`
- **Example**: `export RAAF_TOOLS_TIMEOUT="60"`

### `RAAF_TOOLS_LOG_LEVEL`
- **Function**: Logging level for tool operations
- **Format**: String (same as `RAAF_LOG_LEVEL`)
- **Default**: Inherits from `RAAF_LOG_LEVEL`
- **Example**: `export RAAF_TOOLS_LOG_LEVEL="debug"`

### `TAVILY_API_KEY`
- **Function**: Tavily web search API key (used by web search tool)
- **Used in**: `tools/lib/raaf/tools/web_search_tool.rb`, `dsl/lib/raaf/dsl/tools/web_search.rb`
- **What**: Enables agents to search the web and retrieve current information from the internet
- **Why**: Critical for agents that need real-time information, news, or data not in their training data
- **Format**: String (API key starting with 'tvly-')
- **Default**: None
- **Example**: `export TAVILY_API_KEY="tvly-..."`

### `PINECONE_API_KEY`
- **Function**: Pinecone vector database API key
- **Format**: String (API key)
- **Default**: None
- **Example**: `export PINECONE_API_KEY="..."`

## Guardrails & Security

### `RAAF_GUARDRAILS_ENABLED`
- **Function**: Enable security and safety guardrails
- **Used in**: `guardrails/` gem, input/output filtering system
- **What**: Activates PII detection, toxicity filtering, security scanning, and other safety measures
- **Why**: Essential for production deployments to prevent data leaks, harmful content, and security vulnerabilities
- **Format**: Boolean (`true`, `false`)
- **Default**: `true`
- **Example**: `export RAAF_GUARDRAILS_ENABLED="false"` (⚠️ Not recommended for production)

### `RAAF_PII_DETECTION`
- **Function**: PII detection sensitivity level
- **Format**: String (`strict`, `moderate`, `relaxed`)
- **Default**: `moderate`
- **Example**: `export RAAF_PII_DETECTION="strict"`

### `RAAF_TOXICITY_THRESHOLD`
- **Function**: Threshold for toxicity detection (0.0-1.0)
- **Format**: Float
- **Default**: `0.7`
- **Example**: `export RAAF_TOXICITY_THRESHOLD="0.5"`

### `RAAF_SECURITY_ALERTS_WEBHOOK`
- **Function**: Webhook URL for security alerts
- **Format**: URL
- **Default**: None
- **Example**: `export RAAF_SECURITY_ALERTS_WEBHOOK="https://alerts.example.com/webhook"`

## Rails Integration

### `RAAF_DASHBOARD_ENABLED`
- **Function**: Enable Rails dashboard interface
- **Format**: Boolean (`true`, `false`)
- **Default**: `true`
- **Example**: `export RAAF_DASHBOARD_ENABLED="false"`

### `RAAF_STORE_TRACES`
- **Function**: Store traces in Rails database
- **Format**: Boolean (`true`, `false`)
- **Default**: `true`
- **Example**: `export RAAF_STORE_TRACES="false"`

### `RAAF_RETENTION_DAYS`
- **Function**: Number of days to retain traces in database
- **Format**: Integer
- **Default**: `30`
- **Example**: `export RAAF_RETENTION_DAYS="90"`

## DSL Configuration

### `RAAF_DEBUG_TOOLS`
- **Function**: Enable debugging tools for DSL development
- **Format**: Boolean (`true`, `false`)
- **Default**: `false`
- **Example**: `export RAAF_DEBUG_TOOLS="true"`

## External Services

### `REDIS_URL`
- **Function**: Redis connection URL for streaming and caching
- **Format**: Redis URL
- **Default**: `redis://localhost:6379`
- **Example**: `export REDIS_URL="redis://user:pass@host:port/db"`

## Quick Setup Examples

### Basic Development Setup
**Use case**: Local development with verbose logging and debugging
```bash
export OPENAI_API_KEY="sk-your-openai-key"          # Required for OpenAI models
export RAAF_LOG_LEVEL="debug"                        # Show all log messages
export RAAF_DEBUG_CATEGORIES="api,tracing"           # Debug API calls and tracing
export RAAF_ENVIRONMENT="development"                # Enable dev-specific features
export RAAF_TRACE_CONSOLE="true"                     # Show traces in console
```

### Production Setup
**Use case**: Production deployment with optimized logging and monitoring
```bash
export OPENAI_API_KEY="sk-your-production-key"       # Production API key
export RAAF_LOG_LEVEL="info"                         # Production-appropriate logging
export RAAF_LOG_FORMAT="json"                        # Structured logs for aggregation
export RAAF_LOG_OUTPUT="file"                        # Write to log files
export RAAF_LOG_FILE="/var/log/raaf/app.log"        # Custom log location
export RAAF_ENVIRONMENT="production"                 # Production optimizations
export RAAF_DISABLE_TRACING="false"                  # Keep tracing for monitoring
export RAAF_TRACE_BATCH_SIZE="100"                   # Larger batches for efficiency
export RAAF_TRACE_FLUSH_INTERVAL="10.0"             # Less frequent flushes
```

### Multi-Provider Setup
**Use case**: Using multiple AI providers for different tasks or redundancy
```bash
export OPENAI_API_KEY="sk-openai-key"                # Primary provider
export ANTHROPIC_API_KEY="sk-ant-anthropic-key"     # Alternative for reasoning tasks
export GROQ_API_KEY="gsk-groq-key"                   # Fast inference provider
export COHERE_API_KEY="co-cohere-key"                # Specialized use cases
export RAAF_DEFAULT_PROVIDER="openai"                # Fallback provider
export RAAF_PROVIDER_TIMEOUT="60"                    # Longer timeout for multiple providers
export RAAF_PROVIDER_RETRIES="5"                     # More retries for reliability
```

### Tool-Heavy Setup
**Use case**: Agents that need web search, vector databases, and code execution
```bash
export OPENAI_API_KEY="sk-your-key"                  # Core AI functionality
export TAVILY_API_KEY="tvly-search-key"             # Web search capability
export PINECONE_API_KEY="pinecone-key"              # Vector database access
export RAAF_WORKSPACE="/opt/raaf/workspaces"        # Secure workspace location
export RAAF_TOOLS_TIMEOUT="60"                       # Longer timeout for complex tools
export RAAF_TOOLS_SANDBOX="true"                     # Security for code execution
export RAAF_GUARDRAILS_ENABLED="true"               # Safety filters
```

### Memory & Context Management Setup
**Use case**: Long conversations with intelligent context management
```bash
export OPENAI_API_KEY="sk-your-key"                  # Required
export RAAF_CONTEXT_MANAGEMENT="true"                # Auto-manage conversation length
export RAAF_MEMORY_MAX_TOKENS="8000"                # Higher token limit
export RAAF_MEMORY_STORAGE_PATH="/var/lib/raaf"     # Persistent memory storage
export RAAF_MEMORY_ENCRYPTION_KEY="your-32-char-key" # Encrypt stored memories
```

### High-Security Production Setup
**Use case**: Production with maximum security and compliance
```bash
export OPENAI_API_KEY="sk-your-key"                  # Required
export RAAF_ENVIRONMENT="production"                 # Production mode
export RAAF_GUARDRAILS_ENABLED="true"               # Enable all safety features
export RAAF_PII_DETECTION="strict"                   # Strict PII filtering
export RAAF_TOXICITY_THRESHOLD="0.5"                # Low toxicity tolerance
export RAAF_TOOLS_SANDBOX="true"                     # Mandatory sandboxing
export RAAF_SECURITY_ALERTS_WEBHOOK="https://alerts.company.com/webhook"
export RAAF_LOG_FORMAT="json"                        # Audit-friendly logging
export RAAF_STORE_TRACES="true"                      # Store for compliance
export RAAF_RETENTION_DAYS="90"                      # Extended retention
```

## Notes

- ⭐ **Required**: Variables marked as required must be set for basic functionality
- **Boolean Values**: Use `"true"` or `"false"` as strings
- **File Paths**: Use absolute paths for reliability in production
- **API Keys**: Keep API keys secure and never commit them to version control
- **Development vs Production**: Some variables have different recommended values for different environments

For gem-specific configuration details, see the individual `CLAUDE.md` files in each gem directory.