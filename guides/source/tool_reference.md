**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Tool Reference
===================

This is a comprehensive reference for all built-in tools and their configuration options and usage patterns. RAAF provides a rich ecosystem of tools that enable agents to interact with external systems and perform specialized tasks.

After reading this reference, you will know:

* All available built-in tools and their capabilities
* How to configure and use each tool effectively
* Tool parameters, return types, and error handling
* Best practices for tool integration
* How to create custom tools
* Security considerations for tool usage

--------------------------------------------------------------------------------

Tool Categories
---------------

RAAF tools are organized into several categories based on their complexity, security implications, and use cases. This categorization helps you understand the appropriate tool selection for different agent types and deployment scenarios.

- **Core Tools** - Essential tools for web search and file operations
- **Basic Tools** - Mathematical, text processing, and utility functions
- **Advanced Tools** - Code execution, computer control, and enterprise integrations
- **Enterprise Tools** - Business system integrations and specialized workflows
- **Custom Tools** - User-defined tools for specific use cases

**Category selection strategy:** The tool category often determines the appropriate security model and deployment considerations. Core tools are generally safe for most environments, while Advanced tools require careful security review and sandboxing.

Basic tools provide fundamental capabilities that most agents need, making them excellent building blocks for complex behaviors. Enterprise tools bridge the gap between AI capabilities and existing business systems, enabling agents to participate in established workflows.

**Security considerations by category:** Each category has different security implications. Core tools typically interact with external APIs and require API key management. Basic tools are generally safe but may need input validation. Advanced tools require sandboxing and resource limits, while Enterprise tools need authentication and authorization controls.

Understanding these security implications helps you design appropriate deployment architectures and access controls for your AI applications.

**Performance characteristics:** Different tool categories have vastly different performance profiles. Basic tools execute quickly and predictably, while Advanced tools may have significant latency and resource requirements. Enterprise tools often depend on external system performance and network conditions.

Consider these performance characteristics when designing agent workflows. Place performance-critical tools early in workflows and provide fallback options for tools that may fail or be slow.

Core Tools
----------

### WebSearchTool

Real-time web search capabilities through OpenAI's hosted search service. Web search transforms agents from static knowledge repositories into dynamic research assistants capable of finding current information on any topic.

**The knowledge recency problem:** Traditional AI models have knowledge cutoffs that make them unsuitable for queries requiring current information. Web search solves this limitation by providing access to the latest information, breaking news, and evolving situations.

This capability is particularly valuable for agents handling customer inquiries, research tasks, or any scenario where information freshness matters. The search service handles the complexity of web indexing, content extraction, and result ranking.

**Query optimization:** Effective web search depends on query optimization techniques that transform natural language questions into search queries that produce relevant results. The tool automatically applies these optimizations, improving result quality without requiring manual query crafting.

The search service also handles common search challenges like disambiguation, synonym recognition, and context-aware result ranking. These optimizations significantly improve the usefulness of search results for AI agents.

**Result processing:** Raw web search results often contain irrelevant or low-quality content. The tool includes intelligent filtering and summarization capabilities that extract key information while filtering out noise.

This processing is crucial for maintaining conversation flow and avoiding information overload. Instead of presenting users with raw search results, agents can provide synthesized answers based on multiple sources.

```ruby
# Basic usage
web_search_tool = RAAF::Tools::WebSearchTool.new
result = web_search_tool.web_search(query: "latest AI news")

# With configuration
web_search_tool = RAAF::Tools::WebSearchTool.new(
  user_location: "San Francisco, CA",
  search_context_size: "high"
)
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | String | Yes | Search query string |
| `user_location` | String/Hash | No | Location for context-aware results |
| `search_context_size` | String | No | Context size: "low", "medium", "high" |

**Return Format:**

```ruby
{
  results: [
    {
      title: "Article Title",
      url: "https://example.com",
      snippet: "Article description...",
      timestamp: "2024-01-15T10:30:00Z"
    }
  ],
  search_metadata: {
    query: "original query",
    result_count: 10,
    location: "San Francisco, CA"
  }
}
```

**DSL Usage:**

```ruby
class WebSearchAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  uses_tool :web_search,
    user_location: "New York, NY",
    search_context_size: "high"
end
```

### FileSearchTool

Search through files and documents with support for various formats. File search enables agents to work with existing organizational knowledge, documentation, and data files, making them valuable for internal knowledge management and document analysis tasks.

**The organizational knowledge challenge:** Most organizations have vast amounts of knowledge stored in documents, code repositories, and file systems. This knowledge is often difficult to access and search effectively, leading to duplicated effort and missed insights.

File search tools bridge this gap by making organizational knowledge accessible to AI agents. Agents can quickly find relevant information, answer questions based on internal documentation, and help users navigate complex information repositories.

**Format diversity:** Modern organizations use diverse file formats for different purposes. Text files contain documentation, spreadsheets hold data analysis, presentations communicate insights, and code files implement business logic.

The tool's multi-format support ensures that agents can work with your existing information architecture without requiring format conversions or specialized preprocessing.

**Search vs. retrieval:** File search differs from simple file retrieval in its ability to find relevant information within files rather than just locating specific files. This semantic search capability is essential for knowledge work where the relevant information might be scattered across multiple documents.

The tool builds search indexes that enable fast, relevant searches across large document collections. This indexing approach provides much better performance than sequential file scanning while maintaining search accuracy.

**Content extraction:** Different file formats require different extraction techniques. The tool handles format-specific parsing, metadata extraction, and content normalization automatically, presenting a unified search interface regardless of underlying file complexity.

This extraction capability is particularly valuable for complex formats like PDFs with embedded images, Excel files with multiple sheets, or PowerPoint presentations with speaker notes.

```ruby
# Basic file search
file_search_tool = RAAF::Tools::FileSearchTool.new
result = file_search_tool.search_files(
  query: "machine learning",
  directory: "/path/to/documents"
)

# With file type filtering
result = file_search_tool.search_files(
  query: "budget analysis",
  directory: "/path/to/docs",
  file_types: ["pdf", "docx", "xlsx"],
  max_results: 20
)
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | String | Yes | Search terms |
| `directory` | String | Yes | Directory to search |
| `file_types` | Array | No | File extensions to include |
| `max_results` | Integer | No | Maximum results to return (default: 10) |
| `recursive` | Boolean | No | Search subdirectories (default: true) |

**Supported File Types:**

- **Text:** txt, md, csv, json, xml, yaml
- **Documents:** pdf, doc, docx, rtf
- **Spreadsheets:** xls, xlsx, csv
- **Presentations:** ppt, pptx
- **Code:** rb, py, js, java, cpp, etc.

### VectorSearchTool

Semantic search using vector embeddings for intelligent document retrieval. Vector search represents a fundamental advancement in information retrieval, enabling agents to find conceptually related information even when exact keywords don't match.

**Beyond keyword matching:** Traditional search relies on keyword matching, which fails when queries and documents use different terminology for the same concepts. Vector search solves this limitation by understanding semantic relationships between words and concepts.

This semantic understanding enables agents to find relevant information even when queries are phrased differently than source documents. A query about "customer satisfaction" can find documents discussing "user happiness" or "client contentment."

**Embedding models:** Vector search depends on embedding models that convert text into high-dimensional vectors representing semantic meaning. The quality of these embeddings directly impacts search effectiveness.

The tool supports multiple embedding models, allowing you to choose models optimized for your domain or use case. Specialized models for legal documents, medical texts, or technical documentation can provide better results than general-purpose models.

**Similarity thresholds:** Vector search uses similarity scores to rank results, but these scores require careful interpretation. The similarity threshold parameter controls the trade-off between result relevance and recall.

Low thresholds return more results but may include less relevant content. High thresholds ensure relevance but might miss related information. The optimal threshold depends on your specific use case and content characteristics.

**Index management:** Vector search requires building and maintaining search indexes that store document embeddings. The tool handles index creation, updates, and optimization automatically, but understanding index management helps optimize performance.

Large document collections benefit from index optimization strategies like hierarchical clustering or approximate nearest neighbor algorithms. These optimizations maintain search speed while handling millions of documents.

**Hybrid search strategies:** The most effective search implementations combine vector search with traditional keyword search. This hybrid approach leverages the precision of keyword matching for exact terms while using vector search for conceptual relationships.

The tool can implement hybrid search strategies that provide both exact matches and semantically similar results, giving agents comprehensive information retrieval capabilities.

```ruby
# Initialize with embedding model
vector_search_tool = RAAF::Tools::VectorSearchTool.new(
  embedding_model: "text-embedding-3-large",
  index_path: "/path/to/vector/index"
)

# Semantic search
result = vector_search_tool.semantic_search(
  query: "financial risk assessment",
  top_k: 5,
  similarity_threshold: 0.7
)
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | String | Yes | Semantic search query |
| `top_k` | Integer | No | Number of results (default: 10) |
| `similarity_threshold` | Float | No | Minimum similarity score (0.0-1.0) |
| `filters` | Hash | No | Metadata filters |

Basic Tools
-----------

### MathTools

Safe mathematical calculations and statistical operations. Mathematical capabilities transform agents from text processors into analytical tools capable of performing calculations, analyzing data, and solving quantitative problems.

**Calculation safety:** Mathematical operations in AI systems require careful safety considerations. User-provided expressions could contain malicious code or cause performance issues through complex calculations.

The tool implements safe expression evaluation that prevents code execution while supporting standard mathematical operations. This safety approach enables powerful mathematical capabilities without security risks.

**Statistical analysis:** Statistical functions provide agents with data analysis capabilities essential for business intelligence, research, and decision support applications. Basic statistics like mean, median, and standard deviation form the foundation for more complex analyses.

The tool includes common statistical operations while maintaining numerical stability and handling edge cases gracefully. This reliability is crucial for business applications where calculation accuracy directly impacts decision-making.

**Unit conversion:** Unit conversions are surprisingly complex, with multiple conversion systems, regional variations, and precision requirements. The tool provides accurate conversions across common unit systems while handling ambiguous cases appropriately.

This capability is particularly valuable for international applications where users might provide measurements in different unit systems. Agents can seamlessly work with both metric and imperial units without requiring user specification.

**Numerical precision:** Mathematical operations must balance precision with practical usability. The tool handles floating-point arithmetic carefully, providing appropriate precision for different use cases while avoiding common numerical pitfalls.

For business applications, currency calculations require exact decimal arithmetic to avoid rounding errors. Scientific calculations might need different precision requirements based on the domain and application.

```ruby
# Calculator
result = RAAF::Tools::Basic::MathTools.calculate(
  expression: "2 * (3 + 4) / 5"
)
# => { result: 2.8, expression: "2 * (3 + 4) / 5" }

# Statistics
stats = RAAF::Tools::Basic::MathTools.statistics(
  data: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
)
# => { mean: 5.5, median: 5.5, mode: nil, std_dev: 3.03, min: 1, max: 10 }

# Random number generation
random = RAAF::Tools::Basic::MathTools.random_number(
  min: 1,
  max: 100,
  count: 5
)
# => { numbers: [23, 67, 12, 89, 45] }

# Unit conversion
conversion = RAAF::Tools::Basic::MathTools.convert_units(
  value: 100,
  from_unit: "fahrenheit",
  to_unit: "celsius"
)
# => { result: 37.78, from: "100 fahrenheit", to: "37.78 celsius" }
```

**Available Math Functions:**

| Function | Description | Parameters |
|----------|-------------|------------|
| `calculate` | Safe expression evaluation | `expression` (String) |
| `statistics` | Statistical analysis | `data` (Array of Numbers) |
| `random_number` | Random number generation | `min`, `max`, `count` |
| `convert_units` | Unit conversions | `value`, `from_unit`, `to_unit` |
| `solve_equation` | Basic equation solving | `equation` (String) |

### TextTools

Text processing, manipulation, and analysis utilities. Text manipulation forms the foundation of many AI applications, enabling agents to clean, transform, and analyze textual information effectively.

**Text analysis challenges:** Modern applications deal with diverse text sources including user input, documents, social media content, and system logs. Each source has different characteristics, formatting, and quality levels.

The tool provides comprehensive text analysis capabilities that handle these variations gracefully. From basic word counting to advanced readability analysis, these functions enable agents to understand text characteristics and quality.

**Language detection:** Multilingual applications require accurate language detection to provide appropriate responses and processing. The tool uses advanced language detection algorithms that work reliably even with short text fragments.

This capability is essential for global applications where users might communicate in different languages. Agents can adapt their behavior based on detected language, providing more appropriate responses.

**Entity extraction:** Named entity recognition enables agents to identify and extract important information like names, locations, organizations, and dates from unstructured text. This structured extraction transforms free-form text into actionable data.

The tool supports multiple entity types and provides confidence scores for extracted entities. This probabilistic approach enables agents to make informed decisions about entity reliability and importance.

**Text transformation:** Text transformation capabilities enable agents to format text appropriately for different contexts. Case conversion, formatting, and normalization ensure consistent text presentation across applications.

These transformations are particularly important for user-facing applications where text presentation affects user experience. Consistent formatting improves readability and professionalism.

**Summarization strategies:** Text summarization requires sophisticated natural language processing to identify key information while maintaining readability. The tool provides multiple summarization approaches optimized for different content types.

Extractive summarization preserves original wording while reducing length, making it suitable for factual content. Abstractive summarization creates new phrasing that captures essential meaning, better for creative or explanatory content.

```ruby
# Text analysis
analysis = RAAF::Tools::Basic::TextTools.analyze_text(
  text: "This is a sample text for analysis."
)
# => {
#   word_count: 8,
#   character_count: 37,
#   sentence_count: 1,
#   readability_score: 85.2,
#   language: "en"
# }

# Text transformation
transformed = RAAF::Tools::Basic::TextTools.transform_text(
  text: "hello world",
  transformation: "title_case"
)
# => { result: "Hello World", transformation: "title_case" }

# Text extraction
extracted = RAAF::Tools::Basic::TextTools.extract_entities(
  text: "John Smith lives in New York and works at OpenAI.",
  entity_types: ["person", "location", "organization"]
)
# => {
#   entities: [
#     { text: "John Smith", type: "person", confidence: 0.95 },
#     { text: "New York", type: "location", confidence: 0.92 },
#     { text: "OpenAI", type: "organization", confidence: 0.88 }
#   ]
# }

# Text summarization
summary = RAAF::Tools::Basic::TextTools.summarize_text(
  text: "Long article text...",
  max_sentences: 3
)
# => { summary: "Brief summary...", compression_ratio: 0.15 }
```

**Available Text Functions:**

| Function | Description | Parameters |
|----------|-------------|------------|
| `analyze_text` | Text statistics and analysis | `text` |
| `transform_text` | Text transformations | `text`, `transformation` |
| `extract_entities` | Named entity recognition | `text`, `entity_types` |
| `summarize_text` | Text summarization | `text`, `max_sentences` |
| `translate_text` | Language translation | `text`, `target_language` |
| `detect_language` | Language detection | `text` |

Advanced Tools
--------------

### CodeInterpreterTool

Execute and interpret code in a secure sandbox environment. Code execution capabilities transform agents from information processors into computational tools capable of data analysis, algorithm implementation, and complex problem solving.

**The computational gap:** Many problems require computational solutions that go beyond text processing. Data analysis, mathematical modeling, and algorithm implementation need actual code execution rather than just code generation.

Code interpretation bridges this gap by providing agents with actual computational capabilities. Instead of just suggesting code solutions, agents can execute code, verify results, and iterate on solutions.

**Sandbox architecture:** Code execution presents significant security challenges. Malicious or buggy code could damage systems, access unauthorized data, or consume excessive resources.

The tool implements comprehensive sandboxing that isolates code execution from the host system. This isolation includes file system restrictions, network limitations, and resource controls that prevent malicious activity.

**Language ecosystem:** Different programming languages excel at different tasks. Python dominates data science and machine learning, JavaScript handles web technologies, R specializes in statistics, and SQL manages database operations.

The tool supports multiple languages with appropriate library ecosystems. This multi-language support enables agents to choose the right tool for each task rather than forcing everything into a single language.

**Library management:** Pre-installed libraries dramatically expand agent capabilities without requiring custom tool development. The tool includes carefully curated library sets that balance functionality with security and performance.

Library selection reflects real-world usage patterns and common task requirements. Data analysis agents get NumPy, Pandas, and Matplotlib, while web automation agents receive requests and BeautifulSoup.

**Resource controls:** Code execution can consume significant computational resources. The tool implements intelligent resource limiting that prevents runaway processes while allowing legitimate computational tasks.

These controls include memory limits, CPU time restrictions, and file system quotas. The limits are configurable based on agent requirements and system capabilities.

**Result handling:** Code execution produces various types of results including text output, data files, images, and error messages. The tool handles these diverse outputs gracefully, providing structured access to execution results.

This result handling is crucial for maintaining conversation flow. Instead of presenting raw execution output, agents can interpret results and provide meaningful explanations to users.

```ruby
# Initialize with language support
code_tool = RAAF::Tools::CodeInterpreterTool.new(
  supported_languages: ["python", "javascript", "ruby"],
  timeout: 30,
  memory_limit: "512MB"
)

# Execute Python code
result = code_tool.execute_code(
  language: "python",
  code: """
import numpy as np
import matplotlib.pyplot as plt

# Generate data
x = np.linspace(0, 10, 100)
y = np.sin(x)

# Create plot
plt.figure(figsize=(10, 6))
plt.plot(x, y)
plt.title('Sine Wave')
plt.savefig('sine_wave.png')

print(f'Generated plot with {len(x)} data points')
"""
)
# => {
#   output: "Generated plot with 100 data points",
#   files: ["sine_wave.png"],
#   execution_time: 1.23,
#   memory_used: "45MB"
# }
```

**Supported Languages:**

- **Python** - Full scientific computing stack (NumPy, Pandas, Matplotlib, SciPy)
- **JavaScript/Node.js** - ES6+ with popular libraries
- **Ruby** - Full Ruby standard library
- **R** - Statistical computing and graphics
- **SQL** - Database queries (read-only by default)

**Security Features:**

- Sandboxed execution environment
- Resource limits (CPU, memory, time)
- Network access controls
- File system restrictions

### ComputerTool

Control computer interfaces including screen capture, mouse, and keyboard. Computer control capabilities enable agents to interact with applications and systems through their user interfaces, bridging the gap between AI capabilities and existing software.

**UI automation philosophy:** Many business processes require interaction with applications that don't provide programmatic APIs. Computer control enables agents to automate these processes through standard user interface interactions.

This capability is particularly valuable for legacy systems, third-party applications, and workflows that span multiple applications. Agents can perform complex multi-step processes that would otherwise require human intervention.

**Visual understanding:** Computer control relies on visual understanding to interpret screen content and make appropriate decisions. The tool combines screen capture with image analysis to understand application state and user interface elements.

This visual approach enables agents to work with applications dynamically, adapting to interface changes and handling unexpected conditions. Unlike brittle automation scripts, agents can respond to visual cues and adjust their behavior accordingly.

**Interaction patterns:** Effective computer control requires understanding common interaction patterns and user interface conventions. The tool implements intelligent interaction strategies that mirror human behavior patterns.

These patterns include appropriate timing between actions, error detection and recovery, and context-aware decision making. This human-like behavior improves automation reliability and reduces the likelihood of application errors.

**Safety mechanisms:** Computer control presents significant safety risks if not properly controlled. Agents could accidentally modify important data, trigger unintended actions, or interfere with other processes.

The tool implements comprehensive safety mechanisms including action confirmation, restricted operation modes, and emergency stop capabilities. These safety features ensure that automation remains under human control and supervision.

**Performance considerations:** Computer control operations can be slow compared to API-based interactions. Screen captures, image analysis, and UI interaction all introduce latency that affects agent responsiveness.

The tool optimizes performance through intelligent caching, efficient screen capture techniques, and predictive UI analysis. These optimizations minimize latency while maintaining automation reliability.

**Accessibility compliance:** Computer control should respect accessibility features and user preferences. The tool works with screen readers, high-contrast modes, and other accessibility tools to ensure inclusive automation.

This accessibility support is not just about compliance—it often improves automation reliability by providing additional interface information and alternative interaction methods.

```ruby
# Initialize computer tool
computer_tool = RAAF::Tools::ComputerTool.new(
  screen_size: { width: 1920, height: 1080 },
  safety_mode: true
)

# Take screenshot
screenshot = computer_tool.screenshot
# => { image_data: "base64...", timestamp: "2024-01-15T10:30:00Z" }

# Click at coordinates
computer_tool.click(x: 500, y: 300)

# Type text
computer_tool.type(text: "Hello, World!")

# Scroll page
computer_tool.scroll(direction: "down", amount: 3)

# Wait for element
computer_tool.wait_for_element(
  selector: "button[class='submit-btn']",
  timeout: 10
)
```

**Available Actions:**

| Action | Description | Parameters |
|--------|-------------|------------|
| `screenshot` | Capture screen | `region` (optional) |
| `click` | Mouse click | `x`, `y`, `button` |
| `double_click` | Mouse double-click | `x`, `y` |
| `right_click` | Right mouse click | `x`, `y` |
| `drag` | Mouse drag | `from_x`, `from_y`, `to_x`, `to_y` |
| `type` | Type text | `text` |
| `key_press` | Press keys | `keys` |
| `scroll` | Scroll page | `direction`, `amount` |
| `wait_for_element` | Wait for UI element | `selector`, `timeout` |

### DocumentTool

Process and extract information from various document formats.

```ruby
# Initialize document processor
doc_tool = RAAF::Tools::DocumentTool.new(
  ocr_enabled: true,
  extract_tables: true,
  extract_images: true
)

# Process PDF document
result = doc_tool.process_document(
  file_path: "/path/to/document.pdf",
  extract_options: {
    text: true,
    metadata: true,
    tables: true,
    images: false
  }
)
# => {
#   text: "Extracted text content...",
#   metadata: { title: "Document Title", author: "Author", pages: 10 },
#   tables: [...],
#   processing_time: 2.45
# }

# Extract specific sections
sections = doc_tool.extract_sections(
  file_path: "/path/to/document.pdf",
  section_types: ["introduction", "conclusion", "tables"]
)

# Compare documents
comparison = doc_tool.compare_documents(
  file1: "/path/to/doc1.pdf",
  file2: "/path/to/doc2.pdf",
  comparison_type: "semantic"
)
```

**Supported Formats:**

- **PDF** - Text extraction, OCR, table detection
- **Word** - DOC, DOCX with full formatting
- **Excel** - XLS, XLSX with sheet processing
- **PowerPoint** - PPT, PPTX with slide content
- **Images** - PNG, JPG, TIFF with OCR
- **HTML** - Web page content extraction
- **CSV/TSV** - Structured data processing

### LocalShellTool

Execute shell commands in a controlled environment.

```ruby
# Initialize shell tool
shell_tool = RAAF::Tools::LocalShellTool.new(
  allowed_commands: ["ls", "grep", "find", "cat", "head", "tail"],
  working_directory: "/safe/directory",
  timeout: 30
)

# Execute command
result = shell_tool.execute(
  command: "find /safe/directory -name '*.log' | head -10"
)
# => {
#   stdout: "/safe/directory/app.log\n/safe/directory/error.log\n",
#   stderr: "",
#   exit_code: 0,
#   execution_time: 0.15
# }

# Execute with environment variables
result = shell_tool.execute(
  command: "echo $CUSTOM_VAR",
  environment: { "CUSTOM_VAR" => "Hello World" }
)
```

**Security Features:**

- Command whitelist/blacklist
- Working directory restrictions
- Environment variable controls
- Resource limits
- Audit logging

Enterprise Tools
----------------

### ConfluenceTool

Integrate with Atlassian Confluence for knowledge management.

```ruby
# Initialize with Confluence credentials
confluence_tool = RAAF::Tools::ConfluenceTool.new(
  base_url: "https://company.atlassian.net/wiki",
  username: "user@company.com",
  api_token: ENV['CONFLUENCE_API_TOKEN']
)

# Search pages
pages = confluence_tool.search_pages(
  query: "API documentation",
  space_keys: ["TECH", "DEV"],
  max_results: 10
)

# Get page content
content = confluence_tool.get_page(
  page_id: "123456789",
  expand: ["body.storage", "metadata"]
)

# Create new page
new_page = confluence_tool.create_page(
  space_key: "TECH",
  title: "New Documentation Page",
  content: "<p>Page content in Confluence storage format</p>",
  parent_id: "987654321"
)

# Update existing page
confluence_tool.update_page(
  page_id: "123456789",
  title: "Updated Title",
  content: "<p>Updated content</p>",
  version_number: 2
)
```

**Available Operations:**

| Operation | Description | Parameters |
|-----------|-------------|------------|
| `search_pages` | Search Confluence pages | `query`, `space_keys`, `max_results` |
| `get_page` | Get page by ID | `page_id`, `expand` |
| `create_page` | Create new page | `space_key`, `title`, `content`, `parent_id` |
| `update_page` | Update existing page | `page_id`, `title`, `content`, `version_number` |
| `delete_page` | Delete page | `page_id` |
| `get_spaces` | List available spaces | `limit` |
| `upload_attachment` | Upload file attachment | `page_id`, `file_path` |

### MCPTool

Integration with Model Context Protocol (MCP) servers.

```ruby
# Connect to MCP server
mcp_tool = RAAF::Tools::MCPTool.new(
  server_url: "http://localhost:8080",
  protocol_version: "1.0"
)

# List available tools
tools = mcp_tool.list_tools
# => [
#   { name: "database_query", description: "Query database" },
#   { name: "send_email", description: "Send email" }
# ]

# Execute MCP tool
result = mcp_tool.execute_tool(
  tool_name: "database_query",
  parameters: {
    query: "SELECT * FROM users WHERE active = true",
    database: "production"
  }
)

# Get server capabilities
capabilities = mcp_tool.get_capabilities
```

Tool Configuration Patterns
----------------------------

Tool configuration patterns provide proven approaches for managing tool behavior across different environments, agents, and use cases. These patterns encode best practices learned from production deployments and help avoid common configuration pitfalls.

**Configuration philosophy:** Effective tool configuration balances flexibility with safety. Tools must be configurable enough to handle diverse use cases while maintaining security and reliability constraints.

The pattern-based approach provides structured ways to think about configuration that scale from simple development scenarios to complex production deployments with multiple environments and security requirements.

**Layered configuration:** Configuration patterns often use layered approaches where general settings provide defaults, environment-specific settings override as needed, and agent-specific settings provide final customization.

This layered approach prevents configuration duplication while enabling appropriate customization at each level. It also makes configuration changes more predictable and testable.

### Environment-Based Configuration

```ruby
# config/initializers/raaf_tools.rb
RAAF::Tools.configure do |config|
  case Rails.env
  when 'development'
    config.code_interpreter_enabled = true
    config.shell_commands_allowed = ["ls", "grep", "find"]
    config.computer_tool_enabled = false
    
  when 'test'
    config.code_interpreter_enabled = false
    config.shell_commands_allowed = []
    config.computer_tool_enabled = false
    config.mock_external_tools = true
    
  when 'production'
    config.code_interpreter_enabled = true
    config.shell_commands_allowed = ["ls", "grep", "find", "head", "tail"]
    config.computer_tool_enabled = false
    config.audit_tool_usage = true
  end
  
  # Global settings
  config.tool_timeout = 30
  config.max_tool_output_size = 10.megabytes
  config.enable_tool_caching = true
end
```

### Agent-Specific Tool Selection

```ruby
# Customer support agent with limited tools
class CustomerSupportAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  uses_tool :web_search, search_context_size: "medium"
  uses_tool :file_search, directory: "/kb/support_docs"
  uses_tool :text_tools, functions: ["analyze_text", "summarize_text"]
end

# Data analyst agent with advanced tools
class DataAnalystAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  uses_tool :code_interpreter, languages: ["python", "r"]
  uses_tool :file_search, file_types: ["csv", "xlsx", "json"]
  uses_tool :math_tools
  uses_tool :document_tool, extract_tables: true
end

# DevOps agent with system access
class DevOpsAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  uses_tool :shell_tool, 
    allowed_commands: ["kubectl", "docker", "aws", "terraform"],
    working_directory: "/ops"
  uses_tool :file_search, directory: "/ops/configs"
  uses_tool :web_search
end
```

**Role-based tool selection:** Different agent roles require different tool capabilities. Customer support agents need information retrieval and communication tools, while data analysts require computational and visualization capabilities.

This role-based approach ensures that agents have appropriate tools for their intended functions while avoiding unnecessary complexity or security risks. It also makes agent behavior more predictable and easier to debug.

**Security through restriction:** Agent-specific tool selection implements security through the principle of least privilege. Each agent receives only the tools necessary for its role, reducing the potential impact of security breaches or agent misbehavior.

This restrictive approach is particularly important for agents that handle sensitive data or have access to critical systems. By limiting tool access, you reduce the attack surface and potential for accidental damage.

**Performance optimization:** Tool selection affects agent performance significantly. Agents with many tools face longer decision times and increased token usage for tool descriptions. Focused tool sets improve response times and reduce computational overhead.

The performance impact is particularly noticeable in high-frequency applications where agents need to respond quickly to user queries. Careful tool selection can dramatically improve user experience.

**Maintenance benefits:** Role-specific tool configurations make system maintenance easier. Changes to tool behavior or security policies can be applied to specific agent types without affecting the entire system.

This targeted approach reduces the risk of unintended consequences and makes it easier to test changes before deployment. It also enables gradual rollouts of new tool capabilities.

Creating Custom Tools
---------------------

Custom tools enable organizations to extend RAAF with domain-specific capabilities that aren't available in the built-in tool set. Creating effective custom tools requires understanding both the technical integration requirements and the design principles that make tools useful for AI agents.

**When to create custom tools:** Custom tools are appropriate when your use case requires capabilities that can't be achieved through existing tools or when you need to integrate with proprietary systems and APIs.

The decision to create custom tools should consider maintenance overhead, testing requirements, and the complexity of the integration. Sometimes combining existing tools provides a better solution than creating new ones.

**Tool design principles:** Effective custom tools follow several key design principles. They should be focused on a single responsibility, provide clear and consistent interfaces, handle errors gracefully, and include appropriate documentation.

These principles ensure that AI models can use tools effectively and that human developers can understand and maintain the tools over time.

**Integration patterns:** Custom tools integrate with RAAF through established patterns that handle parameter validation, error handling, and result formatting. Understanding these patterns is crucial for creating tools that work reliably with AI agents.

The integration patterns also provide hooks for logging, monitoring, and debugging that are essential for production deployments.

### Basic Custom Tool

```ruby
# lib/my_app/tools/custom_calculator.rb
module MyApp
  module Tools
    class CustomCalculator < RAAF::FunctionTool
      def initialize
        super(
          method(:calculate_tax),
          name: "calculate_tax",
          description: "Calculate tax for given income and location",
          parameters: {
            type: "object",
            properties: {
              income: {
                type: "number",
                description: "Annual income"
              },
              location: {
                type: "string",
                description: "State or country"
              },
              filing_status: {
                type: "string",
                enum: ["single", "married", "head_of_household"],
                description: "Tax filing status"
              }
            },
            required: ["income", "location"]
          }
        )
      end
      
      private
      
      def calculate_tax(income:, location:, filing_status: "single")
        # Tax calculation logic
        tax_rate = get_tax_rate(location, filing_status)
        tax_amount = income * tax_rate
        
        {
          income: income,
          location: location,
          filing_status: filing_status,
          tax_rate: tax_rate,
          tax_amount: tax_amount,
          after_tax_income: income - tax_amount
        }
      end
      
      def get_tax_rate(location, filing_status)
        # Simplified tax rate lookup
        rates = {
          "CA" => { "single" => 0.13, "married" => 0.12 },
          "NY" => { "single" => 0.12, "married" => 0.11 },
          "TX" => { "single" => 0.08, "married" => 0.08 }
        }
        
        rates.dig(location, filing_status) || 0.10
      end
    end
  end
end

# Usage
agent = RAAF::Agent.new(
  name: "TaxAssistant",
  instructions: "Help with tax calculations",
  model: "gpt-4o"
)

agent.add_tool(MyApp::Tools::CustomCalculator.new)
```

### Advanced Custom Tool with External API

```ruby
# lib/my_app/tools/crm_integration.rb
module MyApp
  module Tools
    class CRMIntegration < RAAF::FunctionTool
      include RAAF::Logger
      
      def initialize(api_key:, base_url:)
        @api_key = api_key
        @base_url = base_url
        @http_client = build_http_client
        
        super(
          method(:search_customers),
          name: "search_customers",
          description: "Search customers in CRM system",
          parameters: {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "Search query (name, email, company)"
              },
              limit: {
                type: "integer",
                minimum: 1,
                maximum: 50,
                default: 10,
                description: "Maximum number of results"
              },
              filters: {
                type: "object",
                properties: {
                  status: {
                    type: "string",
                    enum: ["active", "inactive", "prospect"]
                  },
                  segment: {
                    type: "string",
                    enum: ["enterprise", "smb", "individual"]
                  }
                }
              }
            },
            required: ["query"]
          }
        )
      end
      
      private
      
      def search_customers(query:, limit: 10, filters: {})
        logger.info "Searching CRM for: #{query}"
        
        begin
          response = @http_client.get("/api/customers/search", {
            q: query,
            limit: limit,
            **filters
          })
          
          customers = JSON.parse(response.body)
          
          {
            customers: customers.map { |customer| format_customer(customer) },
            total_count: response.headers['X-Total-Count']&.to_i,
            query: query,
            filters: filters
          }
        rescue => e
          logger.error "CRM search failed: #{e.message}"
          {
            error: "CRM search failed",
            message: e.message,
            customers: []
          }
        end
      end
      
      def format_customer(customer)
        {
          id: customer['id'],
          name: customer['name'],
          email: customer['email'],
          company: customer['company'],
          status: customer['status'],
          last_activity: customer['last_activity_date']
        }
      end
      
      def build_http_client
        # HTTP client configuration
        require 'net/http'
        # Configure with authentication, timeouts, etc.
      end
    end
  end
end
```

### Tool with Streaming Support

```ruby
# lib/my_app/tools/streaming_data_processor.rb
module MyApp
  module Tools
    class StreamingDataProcessor < RAAF::FunctionTool
      def initialize
        super(
          method(:process_large_dataset),
          name: "process_large_dataset",
          description: "Process large dataset with streaming results",
          parameters: {
            type: "object",
            properties: {
              file_path: {
                type: "string",
                description: "Path to dataset file"
              },
              operation: {
                type: "string",
                enum: ["summarize", "analyze", "transform"],
                description: "Processing operation"
              }
            },
            required: ["file_path", "operation"]
          }
        )
      end
      
      def process_large_dataset(file_path:, operation:, &block)
        total_rows = count_rows(file_path)
        processed = 0
        
        File.foreach(file_path).with_index do |line, index|
          # Process line
          result = process_line(line, operation)
          
          processed += 1
          progress = (processed.to_f / total_rows * 100).round(2)
          
          # Stream progress updates
          if block_given?
            yield({
              type: "progress",
              progress: progress,
              processed_rows: processed,
              total_rows: total_rows,
              current_result: result
            })
          end
          
          # Stream intermediate results every 100 rows
          if processed % 100 == 0 && block_given?
            yield({
              type: "intermediate_result",
              progress: progress,
              partial_summary: generate_partial_summary(processed)
            })
          end
        end
        
        # Final result
        final_result = {
          type: "final_result",
          total_processed: processed,
          operation: operation,
          summary: generate_final_summary(file_path, operation)
        }
        
        yield(final_result) if block_given?
        final_result
      end
      
      private
      
      def count_rows(file_path)
        File.foreach(file_path).count
      end
      
      def process_line(line, operation)
        # Line processing logic
      end
      
      def generate_partial_summary(processed_count)
        # Generate summary of processed data
      end
      
      def generate_final_summary(file_path, operation)
        # Generate final summary
      end
    end
  end
end
```

Tool Security and Best Practices
---------------------------------

Tool security is paramount in AI applications because tools often have access to sensitive data, external systems, and computational resources. Security breaches through tool misuse can have severe consequences for organizations and users.

**The AI security challenge:** AI agents present unique security challenges because they can be influenced by user input in ways that traditional applications cannot. Prompt injection, adversarial inputs, and unexpected model behavior can all lead to tool misuse.

Effective tool security requires defending against both traditional security threats and AI-specific attack vectors. This comprehensive approach ensures robust protection across all potential attack surfaces.

**Defense in depth:** Tool security should implement multiple layers of defense rather than relying on single security measures. Input validation, authorization checks, resource limits, and audit logging work together to provide comprehensive protection.

This layered approach ensures that security failures in one area don't compromise the entire system. It also makes security breaches more difficult to execute and easier to detect.

**Risk assessment:** Different tools present different risk profiles based on their capabilities and access patterns. Risk assessment helps prioritize security investments and design appropriate controls for each tool type.

High-risk tools require more stringent security measures, while low-risk tools can use lighter-weight controls. This risk-based approach optimizes security effectiveness while minimizing operational overhead.

### Security Guidelines

1. **Input Validation**

   ```ruby
   def secure_file_operation(file_path:)
     # Validate file path
     unless file_path.start_with?('/safe/directory/')
       raise SecurityError, "File access outside safe directory"
     end
     
     # Check file existence and permissions
     unless File.readable?(file_path)
       raise ArgumentError, "File not readable: #{file_path}"
     end
     
     # Proceed with operation
   end
   ```

2. **Resource Limits**

   ```ruby
   def resource_limited_operation(data:)
     # Set timeout
     Timeout.timeout(30) do
       # Limit memory usage
       if data.size > 10.megabytes
         raise ArgumentError, "Data too large"
       end
       
       # Process data
     end
   end
   ```

3. **Audit Logging**

   ```ruby
   def audited_operation(params)
     start_time = Time.current
     
     begin
       result = perform_operation(params)
       
       log_audit_event(
         operation: self.class.name,
         parameters: params.except(:sensitive_data),
         success: true,
         duration: Time.current - start_time
       )
       
       result
     rescue => e
       log_audit_event(
         operation: self.class.name,
         parameters: params.except(:sensitive_data),
         success: false,
         error: e.message,
         duration: Time.current - start_time
       )
       
       raise
     end
   end
   ```

### Performance Optimization

Tool performance optimization is crucial for maintaining responsive AI agents and efficient resource utilization. Poor tool performance can create bottlenecks that affect entire agent workflows and user experience.

**Performance impact patterns:** Tool performance affects AI applications differently than traditional software. Slow tools can cause conversation delays, increased token usage, and timeout errors that disrupt agent workflows.

Understanding these impact patterns helps prioritize optimization efforts and design appropriate performance requirements for different tool types.

**Optimization strategies:** Tool performance optimization follows established patterns that address common bottlenecks. These strategies include caching, connection pooling, batch processing, and asynchronous execution.

Each strategy addresses different performance challenges and can be combined to achieve optimal results. The key is selecting appropriate strategies based on tool usage patterns and system requirements.

1. **Result Caching**

   ```ruby
   def cached_expensive_operation(params)
     cache_key = "tool_result:#{self.class.name}:#{params.hash}"
     
     Rails.cache.fetch(cache_key, expires_in: 1.hour) do
       perform_expensive_operation(params)
     end
   end
   ```

   **Caching strategy considerations:** Effective caching requires understanding data freshness requirements and cache invalidation patterns. Some tool results can be cached for hours or days, while others need real-time data.

   Cache key design is crucial for avoiding cache collisions while maximizing hit rates. Consider parameter variations, user context, and temporal factors when designing cache keys.

2. **Connection Pooling**

   ```ruby
   class DatabaseTool < RAAF::FunctionTool
     def initialize
       @connection_pool = ConnectionPool.new(size: 5, timeout: 5) do
         create_database_connection
       end
     end
     
     private
     
     def execute_query(sql)
       @connection_pool.with do |connection|
         connection.execute(sql)
       end
     end
   end
   ```

   **Connection management:** Database and API connections are expensive to create and maintain. Connection pooling amortizes this cost across multiple tool calls while managing resource usage.

   Pool sizing depends on expected concurrency, connection limits, and timeout requirements. Monitor pool utilization to optimize sizing and prevent resource exhaustion.

3. **Batch Processing**

   ```ruby
   def batch_process_items(items:)
     items.each_slice(100) do |batch|
       process_batch(batch)
       # Allow other operations between batches
       sleep(0.1)
     end
   end
   ```

   **Batch optimization:** Batch processing reduces per-item overhead and improves throughput for operations that can be parallelized or grouped.

   Batch size selection balances throughput with memory usage and latency requirements. Larger batches improve efficiency but may increase memory consumption and delay feedback.

   **Cooperative scheduling:** Including brief delays between batches allows other operations to execute, preventing batch processing from monopolizing system resources.

Tool Testing
------------

Tool testing is crucial for maintaining reliable AI agent behavior. Unlike traditional software testing, tool testing must consider both functional correctness and AI-specific interaction patterns.

**AI-specific testing challenges:** Tools must work correctly not just with expected inputs, but also with the varied and sometimes unexpected inputs that AI models generate. This requirement makes tool testing more complex than traditional unit testing.

Effective tool testing includes both traditional unit tests and AI-specific integration tests that verify tool behavior in realistic agent scenarios.

**Testing strategy:** Comprehensive tool testing follows a layered approach that includes unit tests for individual tool functions, integration tests for tool interactions, and end-to-end tests for complete agent workflows.

This layered approach ensures that tools work correctly in isolation and as part of complex agent systems. It also makes debugging easier by isolating problems to specific layers.

**Mock and stub strategies:** Tool testing often requires mocking external dependencies like APIs, databases, and file systems. Effective mocking strategies balance test isolation with realistic behavior simulation.

**Test data management:** Tools often work with diverse data types and formats. Comprehensive test data sets ensure that tools handle edge cases and unexpected input appropriately.

### Unit Testing Tools

```ruby
# spec/tools/custom_calculator_spec.rb
RSpec.describe MyApp::Tools::CustomCalculator do
  let(:tool) { described_class.new }
  
  describe '#calculate_tax' do
    it 'calculates tax correctly for California single filer' do
      result = tool.call(
        income: 100000,
        location: "CA",
        filing_status: "single"
      )
      
      expect(result[:tax_rate]).to eq(0.13)
      expect(result[:tax_amount]).to eq(13000)
      expect(result[:after_tax_income]).to eq(87000)
    end
    
    it 'handles invalid location gracefully' do
      result = tool.call(
        income: 100000,
        location: "INVALID",
        filing_status: "single"
      )
      
      expect(result[:tax_rate]).to eq(0.10)  # Default rate
    end
    
    it 'validates required parameters' do
      expect {
        tool.call(location: "CA")  # Missing income
      }.to raise_error(ArgumentError)
    end
  end
end
```

### Integration Testing

```ruby
# spec/integration/agent_with_tools_spec.rb
RSpec.describe 'Agent with Custom Tools' do
  let(:agent) do
    RAAF::Agent.new(
      name: "TaxAssistant",
      instructions: "Help with tax calculations",
      model: "gpt-4o-mini"
    ).tap do |a|
      a.add_tool(MyApp::Tools::CustomCalculator.new)
    end
  end
  
  let(:runner) { RAAF::Runner.new(agent: agent) }
  
  it 'uses custom tool to calculate taxes' do
    result = runner.run("Calculate tax for $100,000 income in California")
    
    expect(result.success?).to be true
    expect(result.messages.last[:content]).to include("$13,000")
    expect(result.tool_calls).to be_present
    expect(result.tool_calls.first[:function][:name]).to eq("calculate_tax")
  end
end
```

Error Handling and Debugging
-----------------------------

Robust error handling is essential for maintaining reliable AI agent behavior. Tool errors can cascade through agent workflows, causing conversation failures and poor user experiences if not handled appropriately.

**Error propagation patterns:** AI agents exhibit different error propagation patterns than traditional applications. Tool errors can cause model confusion, incorrect responses, or complete conversation failures.

Effective error handling prevents error propagation by providing structured error information that models can understand and respond to appropriately.

**Error classification:** Different types of errors require different handling strategies. Transient errors may warrant retries, while permanent errors should fail fast with clear error messages.

Classifying errors appropriately enables agents to respond intelligently to different failure scenarios. This classification also helps with debugging and system monitoring.

**Recovery strategies:** Error handling should include recovery strategies that allow agents to continue functioning despite tool failures. These strategies might include fallback tools, alternative approaches, or graceful degradation.

Effective recovery transforms tool errors from conversation-ending failures into opportunities for agents to demonstrate resilience and problem-solving capabilities.

### Common Tool Errors

1. **Timeout Errors**

   ```ruby
   rescue Timeout::Error => e
     {
       error: "Tool execution timeout",
       message: "Operation exceeded #{timeout} seconds",
       timeout: timeout
     }
   end
   ```

2. **Network Errors**

   ```ruby
   rescue Net::TimeoutError, Net::ConnectError => e
     {
       error: "Network error",
       message: e.message,
       retry_suggested: true
     }
   end
   ```

3. **Parameter Validation Errors**

   ```ruby
   def validate_parameters(params)
     required_params.each do |param|
       unless params.key?(param)
         raise ArgumentError, "Missing required parameter: #{param}"
       end
     end
   end
   ```

### Debug Logging

```ruby
class DebuggableTool < RAAF::FunctionTool
  include RAAF::Logger
  
  def call(*args)
    logger.debug "Tool #{name} called with: #{args.inspect}"
    
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = super(*args)
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    
    logger.debug "Tool #{name} completed in #{duration.round(3)}s"
    logger.debug "Tool #{name} result: #{result.inspect}" if Rails.env.development?
    
    result
  rescue => e
    logger.error "Tool #{name} failed: #{e.message}"
    logger.error e.backtrace.join("\n") if Rails.env.development?
    raise
  end
end
```

**Logging strategy:** Effective debugging requires comprehensive logging that captures tool behavior without overwhelming log systems. The logging strategy should balance information completeness with performance and storage requirements.

**Structured logging:** Structured logging provides machine-readable log entries that enable automated analysis and monitoring. This approach is particularly valuable for production systems where manual log analysis is impractical.

**Privacy considerations:** Debug logging must balance debugging needs with privacy requirements. Sensitive information should be redacted or excluded from logs while maintaining enough information for effective debugging.

**Performance impact:** Logging can have significant performance impact, especially for high-frequency tools. Consider logging overhead when designing debug strategies and use appropriate log levels to control verbosity.

**Environment-specific logging:** Different environments require different logging strategies. Development environments might log detailed information, while production environments should focus on errors and performance metrics.

Next Steps
----------

This comprehensive tool reference provides the foundation for building sophisticated AI agents with diverse capabilities. The next steps depend on your specific use case and development goals.

**For beginners:** Start with Core Tools like WebSearchTool and FileSearchTool to understand basic tool integration patterns. These tools provide immediate value while teaching fundamental concepts.

**For advanced developers:** Explore Custom Tool creation and Enterprise Tool integration to extend RAAF with domain-specific capabilities. Focus on security best practices and performance optimization.

**For production deployments:** Implement comprehensive monitoring, error handling, and security measures. Review tool configurations for appropriate access controls and resource limits.

**For system architects:** Consider tool selection strategies that balance capability with security and performance requirements. Design tool architectures that can evolve with changing business needs.

For advanced tool development:

* **[RAAF Core Guide](core_guide.html)** - Understanding agents and tool integration
* **[RAAF DSL Guide](dsl_guide.html)** - Declarative tool configuration
* **[Performance Guide](performance_guide.html)** - Tool performance optimization
* **[Security Guide](guardrails_guide.html)** - Tool security best practices
* **[Testing Guide](testing_guide.html)** - Comprehensive tool testing strategies