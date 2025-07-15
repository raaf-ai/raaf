# RAAF Tools Advanced

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/Version-0.1.0-blue.svg)](https://rubygems.org/gems/raaf-tools-advanced)
[![Ruby](https://img.shields.io/badge/Ruby-3.0%2B-red.svg)](https://www.ruby-lang.org/)

Advanced enterprise-grade tools for Ruby AI Agents Factory (RAAF). This gem provides sophisticated AI agent capabilities including computer control, code interpretation, document processing, database operations, and enterprise system integrations.

> 🛡️ **Security First**: All tools run in secure, isolated environments with comprehensive sandbox protection and enterprise-grade security controls.

## 🌟 Features

### Core Advanced Tools
- **🖥️ Computer Control** - Desktop automation, browser control, and UI interaction
- **🐍 Code Interpretation** - Safe execution of Python, Ruby, JavaScript, and more
- **📄 Document Processing** - PDF, DOCX, Excel, PowerPoint processing and generation
- **🗄️ Database Operations** - Secure database queries and data manipulation
- **☁️ Cloud Storage** - AWS S3, Google Cloud Storage, Azure Blob integration
- **🔌 API Client Generation** - Dynamic REST API client creation and management

### Enterprise Integrations
- **🏢 Salesforce** - CRM operations, SOQL queries, record management
- **🏭 SAP** - ERP integration, BAPI calls, table operations
- **📊 Microsoft Graph** - Office 365, Teams, OneDrive integration
- **🔒 Security Scanning** - Vulnerability detection and compliance checking
- **📋 Workflow Automation** - Complex business process automation

### Security & Compliance
- **🛡️ Sandbox Isolation** - Complete process and network isolation
- **🔐 Resource Limits** - Memory, CPU, and time constraints
- **🔍 Security Scanning** - Real-time threat detection
- **📊 Audit Logging** - Comprehensive security event tracking
- **⚡ Circuit Breakers** - Automatic failure protection

## 📦 Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-tools-advanced'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install raaf-tools-advanced
```

## 🚀 Quick Start

### Computer Control

```ruby
require 'raaf-tools-advanced'

# Create computer control tool
computer = RubyAIAgentsFactory::Tools::Advanced::ComputerTool.new(
  display: ":0",
  browser: "chrome",
  sandbox: true,
  allowed_actions: [:screenshot, :click, :type, :scroll]
)

# Create agent with computer control
agent = RubyAIAgentsFactory::Agent.new(
  name: "AutomationAgent",
  instructions: "You can control the computer to help automate tasks. Always explain what you're doing and ask for confirmation before taking actions.",
  model: "gpt-4o"
)

agent.add_tool(computer)

# Run with computer control
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("Take a screenshot of the desktop and describe what you see")
```

### Code Interpretation

```ruby
require 'raaf-tools-advanced'

# Create code interpreter with security constraints
code_interpreter = RubyAIAgentsFactory::Tools::Advanced::CodeInterpreter.new(
  languages: [:python, :ruby, :javascript],
  sandbox: true,
  timeout: 60,
  memory_limit: "512MB"
)

# Create coding agent
agent = RubyAIAgentsFactory::Agent.new(
  name: "CodeAgent",
  instructions: "You can execute code to solve problems and analyze data. Always explain your approach and ensure code is safe.",
  model: "gpt-4o"
)

agent.add_tool(code_interpreter)

# Execute code through agent
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("Calculate the first 10 Fibonacci numbers using Python")
```

### Document Processing

```ruby
require 'raaf-tools-advanced'

# Create document processor
doc_processor = RubyAIAgentsFactory::Tools::Advanced::DocumentProcessor.new(
  supported_formats: [:pdf, :docx, :xlsx, :pptx],
  max_file_size: 50 * 1024 * 1024,  # 50MB
  extract_images: true,
  extract_tables: true
)

# Create document agent
agent = RubyAIAgentsFactory::Agent.new(
  name: "DocumentAgent",
  instructions: "You can process and analyze documents. Extract key information and provide summaries.",
  model: "gpt-4o"
)

agent.add_tool(doc_processor)

# Process documents
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("Extract all text and tables from /path/to/document.pdf")
```

### Database Operations

```ruby
require 'raaf-tools-advanced'

# Create database tool with read-only access
database = RubyAIAgentsFactory::Tools::Advanced::DatabaseTool.new(
  connection_string: "postgres://user:pass@localhost/db",
  read_only: true,
  timeout: 30,
  max_results: 1000
)

# Create database agent
agent = RubyAIAgentsFactory::Agent.new(
  name: "DatabaseAgent",
  instructions: "You can query databases to find information. Always use safe queries and respect data privacy.",
  model: "gpt-4o"
)

agent.add_tool(database)

# Query database
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("Find all users created in the last 30 days")
```

## 🔧 Configuration

### Global Configuration

```ruby
RubyAIAgentsFactory::Tools::Advanced.configure do |config|
  # Computer control settings
  config.computer_control.enabled = true
  config.computer_control.browser = "chrome"
  config.computer_control.timeout = 30
  config.computer_control.sandbox = true

  # Code interpreter settings
  config.code_interpreter.enabled = true
  config.code_interpreter.sandbox = true
  config.code_interpreter.timeout = 60
  config.code_interpreter.memory_limit = "512MB"
  config.code_interpreter.languages = [:python, :ruby, :javascript]

  # Document processor settings
  config.document_processor.enabled = true
  config.document_processor.max_file_size = 50 * 1024 * 1024
  config.document_processor.supported_formats = [:pdf, :docx, :xlsx, :pptx]
  config.document_processor.extract_images = true

  # Database settings
  config.database.enabled = true
  config.database.read_only = true
  config.database.timeout = 30
  config.database.max_results = 1000

  # Security settings
  config.security.sandbox_all = true
  config.security.network_isolation = true
  config.security.file_system_isolation = true
  config.security.resource_limits = true
end
```

### Environment Variables

```bash
# Computer control
export DISPLAY=":0"
export RAAF_COMPUTER_BROWSER="chrome"
export RAAF_COMPUTER_TIMEOUT="30"
export RAAF_COMPUTER_SANDBOX="true"

# Code interpreter
export RAAF_CODE_SANDBOX="true"
export RAAF_CODE_TIMEOUT="60"
export RAAF_CODE_MEMORY_LIMIT="512MB"
export RAAF_CODE_LANGUAGES="python,ruby,javascript"

# Document processor
export RAAF_DOC_MAX_SIZE="52428800"  # 50MB
export RAAF_DOC_EXTRACT_IMAGES="true"
export RAAF_DOC_EXTRACT_TABLES="true"

# Database
export RAAF_DB_READ_ONLY="true"
export RAAF_DB_TIMEOUT="30"
export RAAF_DB_MAX_RESULTS="1000"

# Security
export RAAF_SANDBOX_ALL="true"
export RAAF_NETWORK_ISOLATION="true"
export RAAF_FILE_SYSTEM_ISOLATION="true"
```

## 🛠️ Advanced Tools

### Computer Tool

Control desktop applications and web browsers:

```ruby
computer = RubyAIAgentsFactory::Tools::Advanced::ComputerTool.new(
  display: ":0",
  browser: "chrome",
  headless: false,
  sandbox: true,
  allowed_actions: [:screenshot, :click, :type, :scroll, :navigate]
)

# Available actions:
# - screenshot: Take desktop or window screenshots
# - click: Click at coordinates or on elements
# - type: Type text input
# - scroll: Scroll pages or elements
# - navigate: Navigate to URLs
# - wait: Wait for elements to appear
# - key: Press individual keys
# - move: Move mouse cursor
```

### Code Interpreter

Execute code in multiple languages safely:

```ruby
code_interpreter = RubyAIAgentsFactory::Tools::Advanced::CodeInterpreter.new(
  languages: [:python, :ruby, :javascript, :bash, :sql],
  sandbox: true,
  timeout: 60,
  memory_limit: "512MB",
  disk_limit: "1GB"
)

# Supported languages:
# - Python: Data analysis, machine learning, scientific computing
# - Ruby: Web scraping, automation, text processing
# - JavaScript: Web development, API calls, JSON processing
# - Bash: System administration, file operations
# - SQL: Database queries and analysis
```

### Document Processor

Process various document formats:

```ruby
doc_processor = RubyAIAgentsFactory::Tools::Advanced::DocumentProcessor.new(
  supported_formats: [:pdf, :docx, :xlsx, :pptx, :txt, :md, :html],
  max_file_size: 50 * 1024 * 1024,
  extract_images: true,
  extract_tables: true,
  extract_metadata: true
)

# Available operations:
# - extract_text: Extract text content
# - extract_images: Extract embedded images
# - extract_tables: Extract table data as CSV/JSON
# - extract_metadata: Get document metadata
# - convert_format: Convert between formats
# - generate_summary: AI-powered document summary
```

### Database Tool

Query and manipulate databases securely:

```ruby
database = RubyAIAgentsFactory::Tools::Advanced::DatabaseTool.new(
  connection_string: "postgres://user:pass@localhost/db",
  read_only: true,
  timeout: 30,
  max_results: 1000,
  allowed_tables: ["users", "orders", "products"]
)

# Available operations:
# - query: Execute SELECT queries
# - insert: Insert data (if not read-only)
# - update: Update data (if not read-only)
# - delete: Delete data (if not read-only)
# - schema: Get table schema information
# - tables: List available tables
# - explain: Get query execution plan
```

### Cloud Storage Tool

Integrate with cloud storage providers:

```ruby
cloud_storage = RubyAIAgentsFactory::Tools::Advanced::CloudStorageTool.new(
  provider: :s3,
  credentials: {
    access_key_id: "your-access-key",
    secret_access_key: "your-secret-key",
    region: "us-east-1"
  },
  bucket: "your-bucket",
  timeout: 60
)

# Supported providers: :s3, :gcs, :azure
# Available operations:
# - upload: Upload files to cloud storage
# - download: Download files from cloud storage
# - list: List files in bucket/container
# - delete: Delete files from cloud storage
# - generate_url: Generate signed URLs
# - copy: Copy files between locations
```

### API Client Tool

Create and use REST API clients dynamically:

```ruby
api_client = RubyAIAgentsFactory::Tools::Advanced::ApiClientTool.new(
  base_url: "https://api.example.com",
  authentication: {
    type: :bearer,
    token: "your-api-token"
  },
  timeout: 30,
  retry_count: 3
)

# Available operations:
# - get: HTTP GET requests
# - post: HTTP POST requests
# - put: HTTP PUT requests
# - delete: HTTP DELETE requests
# - patch: HTTP PATCH requests
# - head: HTTP HEAD requests
# - options: HTTP OPTIONS requests
```

## 🏢 Enterprise Integrations

### Salesforce Integration

```ruby
salesforce = RubyAIAgentsFactory::Tools::Advanced::EnterpriseIntegrations::SalesforceTool.new(
  client_id: "your-client-id",
  client_secret: "your-client-secret",
  username: "your-username",
  password: "your-password",
  security_token: "your-security-token",
  sandbox: true,
  api_version: "58.0"
)

# Available operations:
# - query: Execute SOQL queries
# - create: Create records
# - update: Update records
# - delete: Delete records
# - upsert: Upsert records
# - describe: Get object metadata
# - search: Execute SOSL searches
```

### SAP Integration

```ruby
sap = RubyAIAgentsFactory::Tools::Advanced::EnterpriseIntegrations::SAPTool.new(
  host: "sap-server.company.com",
  username: "your-username",
  password: "your-password",
  client: "100",
  language: "EN",
  system_number: "00"
)

# Available operations:
# - call_function: Call SAP function modules
# - read_table: Read SAP table data
# - execute_bapi: Execute BAPI functions
# - get_structure: Get table/structure definitions
# - call_transaction: Execute SAP transactions
```

### Microsoft Graph Integration

```ruby
graph = RubyAIAgentsFactory::Tools::Advanced::EnterpriseIntegrations::GraphTool.new(
  tenant_id: "your-tenant-id",
  client_id: "your-client-id",
  client_secret: "your-client-secret",
  scopes: ["https://graph.microsoft.com/.default"]
)

# Available operations:
# - get_users: Get user information
# - send_email: Send emails via Outlook
# - get_calendar: Get calendar events
# - create_event: Create calendar events
# - upload_file: Upload files to OneDrive
# - create_team: Create Microsoft Teams
# - get_messages: Get email messages
```

## 🛡️ Security Features

### Sandbox Isolation

All tools run in secure sandbox environments:

```ruby
# Enable comprehensive sandboxing
RubyAIAgentsFactory::Tools::Advanced.configure do |config|
  config.security.sandbox_all = true
  config.security.network_isolation = true
  config.security.file_system_isolation = true
  config.security.process_isolation = true
end

# Tools automatically run with:
# - Limited file system access
# - Network request filtering
# - Resource limits (memory, CPU, time)
# - Process isolation
# - Input/output sanitization
```

### Resource Limits

Configure resource constraints for tools:

```ruby
RubyAIAgentsFactory::Tools::Advanced.configure do |config|
  # Code interpreter limits
  config.code_interpreter.timeout = 60
  config.code_interpreter.memory_limit = "512MB"
  config.code_interpreter.disk_limit = "1GB"
  config.code_interpreter.cpu_limit = "2"

  # Document processor limits
  config.document_processor.max_file_size = 50 * 1024 * 1024
  config.document_processor.max_pages = 1000
  config.document_processor.timeout = 120

  # Database limits
  config.database.max_results = 1000
  config.database.query_timeout = 30
  config.database.connection_timeout = 10
end
```

### Access Control

Control which tools are available:

```ruby
# Disable dangerous tools
RubyAIAgentsFactory::Tools::Advanced.disable!(:computer_control)

# Enable specific tools
RubyAIAgentsFactory::Tools::Advanced.enable!(:document_processor)
RubyAIAgentsFactory::Tools::Advanced.enable!(:code_interpreter)

# Check if tool is enabled
if RubyAIAgentsFactory::Tools::Advanced.enabled?(:computer_control)
  # Tool is available
  computer = RubyAIAgentsFactory::Tools::Advanced.create_computer_tool
end

# Get security status
security_status = RubyAIAgentsFactory::Tools::Advanced.validate_security!
```

## 🔄 RAAF Ecosystem Integration

### Core Integration

```ruby
# Works seamlessly with RAAF Core
require 'raaf-core'
require 'raaf-tools-advanced'

agent = RubyAIAgentsFactory::Agent.new(
  name: "AdvancedAgent",
  instructions: "You have access to advanced enterprise tools"
)

# Add multiple advanced tools
agent.add_tool(RubyAIAgentsFactory::Tools::Advanced.create_code_interpreter)
agent.add_tool(RubyAIAgentsFactory::Tools::Advanced.create_document_processor)
agent.add_tool(RubyAIAgentsFactory::Tools::Advanced.create_database_tool)
```

### Memory Integration

```ruby
# Combine with RAAF Memory for persistent context
require 'raaf-memory'
require 'raaf-tools-advanced'

memory_manager = RubyAIAgentsFactory::Memory::MemoryManager.new
agent = RubyAIAgentsFactory::Agent.new(
  name: "MemoryAdvancedAgent",
  instructions: "You have advanced tools and memory"
)

agent.add_tool(RubyAIAgentsFactory::Tools::Advanced.create_code_interpreter)
runner = RubyAIAgentsFactory::Runner.new(agent: agent, memory: memory_manager)
```

### Tracing Integration

```ruby
# Monitor advanced tool usage with RAAF Tracing
require 'raaf-tracing'
require 'raaf-tools-advanced'

tracer = RubyAIAgentsFactory::Tracing::SpanTracer.new
tracer.add_processor(RubyAIAgentsFactory::Tracing::OpenAIProcessor.new)

agent = RubyAIAgentsFactory::Agent.new(name: "TracedAdvancedAgent")
agent.add_tool(RubyAIAgentsFactory::Tools::Advanced.create_computer_tool)

runner = RubyAIAgentsFactory::Runner.new(agent: agent, tracer: tracer)
```

### Guardrails Integration

```ruby
# Secure advanced tools with RAAF Guardrails
require 'raaf-guardrails'
require 'raaf-tools-advanced'

# Security guardrails for advanced tools
security_guard = RubyAIAgentsFactory::Guardrails::SecurityGuardrail.new
pii_guard = RubyAIAgentsFactory::Guardrails::PIIDetector.new

agent = RubyAIAgentsFactory::Agent.new(name: "SecureAdvancedAgent")
agent.add_tool(RubyAIAgentsFactory::Tools::Advanced.create_code_interpreter)

runner = RubyAIAgentsFactory::Runner.new(
  agent: agent,
  input_guardrails: [security_guard, pii_guard]
)
```

## 🏗️ Architecture

### Tool Hierarchy

```
RubyAIAgentsFactory::Tools::Advanced
├── ComputerTool          # Desktop automation
├── CodeInterpreter       # Code execution
├── DocumentProcessor     # Document handling
├── DatabaseTool          # Database operations
├── CloudStorageTool      # Cloud storage
├── ApiClientTool         # API interactions
├── WorkflowTool          # Process automation
├── DataAnalyticsTool     # Data analysis
└── EnterpriseIntegrations/
    ├── SalesforceTool    # Salesforce CRM
    ├── SAPTool           # SAP ERP
    ├── GraphTool         # Microsoft Graph
    └── CustomTool        # Custom integrations
```

### Security Architecture

```
Security Layer
├── Sandbox Isolation
│   ├── Process Isolation
│   ├── Network Isolation
│   └── File System Isolation
├── Resource Management
│   ├── CPU Limits
│   ├── Memory Limits
│   └── Time Limits
├── Access Control
│   ├── Tool Permissions
│   ├── API Access
│   └── Data Access
└── Audit & Monitoring
    ├── Security Events
    ├── Resource Usage
    └── Performance Metrics
```

## 📊 Performance Considerations

### Resource Management

- **Memory**: Set appropriate limits for code execution and document processing
- **CPU**: Use timeouts to prevent long-running operations
- **Disk**: Limit file sizes and temporary storage usage
- **Network**: Implement connection pooling and request throttling

### Caching Strategies

```ruby
# Cache document processing results
RubyAIAgentsFactory::Tools::Advanced.configure do |config|
  config.document_processor.cache_results = true
  config.document_processor.cache_ttl = 3600  # 1 hour
end

# Cache API responses
RubyAIAgentsFactory::Tools::Advanced.configure do |config|
  config.api_client.cache_responses = true
  config.api_client.cache_store = :redis
end
```

### Scaling Recommendations

- **Horizontal Scaling**: Run tools in separate processes or containers
- **Queue Processing**: Use message queues for asynchronous tool execution
- **Load Balancing**: Distribute tool execution across multiple instances
- **Circuit Breakers**: Implement failure protection for external services

## 🔧 Development

### Setup

```bash
git clone https://github.com/raaf-ai/ruby-ai-agents-factory
cd ruby-ai-agents-factory/tools-advanced
bundle install
```

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test suites
bundle exec rspec spec/computer_tool_spec.rb
bundle exec rspec spec/code_interpreter_spec.rb
bundle exec rspec spec/document_processor_spec.rb
```

### Adding New Tools

1. **Create Tool Class**:
   ```ruby
   # lib/raaf/tools/advanced/my_tool.rb
   class MyTool < RubyAIAgentsFactory::FunctionTool
     def initialize(**options)
       super(
         method(:execute_action),
         name: "my_tool",
         description: "Description of my tool"
       )
       @options = options
     end

     private

     def execute_action(action:, **params)
       # Tool implementation
       validate_security!(params)
       perform_action(action, params)
     end

     def validate_security!(params)
       # Security validation
       raise SecurityError if dangerous_params?(params)
     end
   end
   ```

2. **Add Security Features**:
   - Implement sandbox isolation
   - Add resource limits
   - Validate inputs
   - Log security events

3. **Write Tests**:
   ```ruby
   # spec/my_tool_spec.rb
   RSpec.describe MyTool do
     it "executes actions safely" do
       tool = MyTool.new
       result = tool.call(action: "safe_action")
       expect(result).to be_successful
     end

     it "blocks dangerous actions" do
       tool = MyTool.new
       expect {
         tool.call(action: "dangerous_action")
       }.to raise_error(SecurityError)
     end
   end
   ```

4. **Update Documentation**:
   - Add tool to README
   - Create usage examples
   - Document security considerations

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with comprehensive tests
4. Ensure all security checks pass
5. Add documentation for new features
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Contributing Guidelines

- **Security First**: All new tools must implement sandbox isolation
- **Test Coverage**: Maintain >95% test coverage
- **Documentation**: Document all public APIs and usage examples
- **Performance**: Include performance benchmarks for new tools
- **Compatibility**: Ensure compatibility with all RAAF gems

## 📄 License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## 🙏 Acknowledgments

- Built on the OpenAI Agents architecture
- Inspired by enterprise automation needs
- Developed with security and reliability in mind
- Community-driven feature development

---

> 🤖 **AI-Powered Development**: This gem was developed using AI assistance, showcasing the power of AI-human collaboration in creating sophisticated software tools.

For more information about the Ruby AI Agents Factory ecosystem, visit our [main repository](https://github.com/raaf-ai/ruby-ai-agents-factory).