**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF DSL Guide
==============

This guide covers the declarative Domain Specific Language (DSL) for Ruby AI Agents Factory (RAAF). The DSL provides an elegant, Ruby-idiomatic way to configure agents, tools, and workflows.

After reading this guide, you will know:

* How to use the declarative agent builder DSL
* Built-in tool presets and shortcuts  
* Advanced DSL patterns and configurations
* Prompt management with Ruby classes and templates
* Testing agents built with the DSL
* Best practices for DSL-based agent design

NOTE: For comprehensive prompt management documentation, see the [Prompting Guide](prompting.md).

--------------------------------------------------------------------------------

Introduction
------------

The RAAF DSL transforms agent configuration from imperative code to declarative specifications. Instead of writing procedural setup code, you describe what you want your agent to be and do.

**Why declarative matters:** Imperative code tells the computer how to do something step by step. Declarative code tells the computer what you want to achieve and lets it figure out how. This shift is powerful because it separates intent from implementation.

Consider building a house: imperative instructions would be "nail board A to board B, then nail board C to board B." Declarative instructions would be "build a wall with a door here and a window there." The declarative approach focuses on the desired outcome, not the construction process.

The same principle applies to AI agents. Instead of writing code that calls methods in a specific order, you declare the agent's characteristics and capabilities. This makes the configuration more readable, maintainable, and flexible.

**The cognitive load problem:** When building complex AI systems, developers often struggle with managing the intricate details of agent setup, tool configuration, and workflow orchestration. Traditional imperative approaches force you to think about both the "what" (the agent's purpose) and the "how" (the implementation details) simultaneously.

This cognitive overhead becomes exponentially more challenging as your AI system grows. With multiple agents, dozens of tools, and complex handoff patterns, imperative code quickly becomes a tangled web of interdependent method calls and configuration objects.

**Declarative as abstraction:** The DSL provides a higher-level abstraction that maps business concepts directly to code structure. When you write `use_web_search` or `handoff_to "Writer"`, you're expressing business logic in terms that both developers and stakeholders can understand. The DSL handles the complex orchestration behind the scenes.

This abstraction is particularly valuable in AI applications because the business logic (agent behavior, tool capabilities, workflow patterns) is often more important than the implementation details. The DSL ensures that your code reflects your business intent, not just technical requirements.

### Benefits of the DSL

* **Declarative** - Describe agent behavior, not implementation steps
  Focus on what the agent should do, not how to wire it up. This shift in perspective makes complex agent configurations much more manageable.

* **Readable** - Configuration reads like natural language
  Team members can understand agent configurations without deep technical knowledge. This improves collaboration and reduces onboarding time.

* **Composable** - Mix and match features easily
  Add capabilities with simple directives like `use_web_search` or `use_database`. The DSL handles the complex integration details.

* **Testable** - Clean separation between configuration and behavior
  Agent configurations become data structures that can be tested independently of their runtime behavior. This makes testing more focused and reliable.

* **Maintainable** - Changes are localized and obvious
  Adding a new tool or capability is a single line change. The DSL prevents configuration drift and makes the agent's capabilities immediately visible.

### DSL vs Imperative Comparison

```ruby
# Imperative approach (still supported)
agent = RAAF::Agent.new(
  name: "CustomerService",
  instructions: "Help customers with inquiries",
  model: "gpt-4o"
)

def lookup_order(order_id:)
  # Implementation
end

def send_email(to:, subject:, body:)
  # Implementation  
end

agent.add_tool(method(:lookup_order))
agent.add_tool(method(:send_email))

# DSL approach (recommended)
agent = RAAF::DSL::AgentBuilder.build do
  name "CustomerService"
  instructions "Help customers with inquiries"
  model "gpt-4o"
  
  tool :lookup_order do |order_id:|
    # Implementation
  end
  
  tool :send_email do |to:, subject:, body:|
    # Implementation
  end
end

**The difference in practice:** The imperative approach requires you to understand the internal mechanics—how to create agents, how to add tools, how to manage the object lifecycle. The DSL approach lets you focus on the agent's purpose and capabilities.

Notice how the DSL version reads like a specification: "This is a CustomerService agent that uses GPT-4o and has these tools." The imperative version reads like assembly instructions: "Create an agent object, configure it, define some methods, attach them as tools."

As your agents become more complex, this difference becomes crucial. A DSL configuration with 20 tools and multiple integrations remains readable. The equivalent imperative code becomes unwieldy and error-prone.

**Maintenance and evolution:** The declarative approach significantly reduces the cost of change. When business requirements evolve—and they always do—you can modify agent behavior by changing declarations rather than rewriting implementation logic. Adding a new tool becomes a single line addition. Changing model parameters or adjusting instructions doesn't require understanding the underlying object graph.

This maintainability advantage compounds over time. Teams can safely modify agent configurations without fear of breaking subtle dependencies. New team members can understand and contribute to agent definitions without deep knowledge of the RAAF internals.

**Testing and validation:** Declarative configurations are inherently more testable. The DSL produces data structures that can be validated, compared, and reasoned about independently of their runtime behavior. This separation enables powerful testing strategies where you can verify agent configurations without executing the full AI pipeline.

For example, you can write tests that verify an agent has the correct tools, uses the appropriate model, and includes necessary context variables—all without making actual API calls or running inference.
```

Basic Agent Builder
-------------------

### Simple Agent Creation

```ruby
require 'raaf-dsl'

agent = RAAF::DSL::AgentBuilder.build do
  name "WeatherBot"
  instructions "Provide weather information for any location"
  model "gpt-4o"
end

# Use the agent
runner = RAAF::Runner.new(agent: agent)
result = runner.run("What's the weather like?")

**Minimal viable agent:** This example shows the absolute minimum needed to create a functional agent. Just three lines of configuration create a working AI agent with specific instructions and model selection.

The DSL handles all the complexity—provider configuration, API communication, response formatting—while you focus on the agent's purpose. This is the power of good abstraction: complex systems become simple to use.
```

### Agent Configuration Options

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "AdvancedAgent"
  instructions """
    You are an advanced AI assistant with multiple capabilities.
    Always be helpful, accurate, and professional.
  """
  
  # Model configuration
  model "gpt-4o"
  temperature 0.7
  max_tokens 2000
  top_p 0.9
  
  # Response format
  response_format :json  # or provide custom schema
  
  # Advanced settings
  parallel_tool_calls true
  tool_choice "auto"  # "none", "auto", or specific tool name
end

**Configuration layers:** The DSL provides multiple layers of configuration, from basic (name, model) to advanced (parallel processing, tool selection). This progressive disclosure means you can start simple and add complexity as needed.

Each configuration option serves a specific purpose:

- **Model parameters** control the AI's behavior (creativity, response length, etc.)
- **Response format** ensures structured output when needed
- **Tool settings** optimize how the agent uses its capabilities
- **Advanced settings** fine-tune performance and behavior

The DSL validates these configurations, catching errors early rather than at runtime.

**Understanding parameter interactions:** Model parameters don't exist in isolation—they interact in complex ways that affect agent behavior. Temperature and top_p both influence randomness, but they work through different mechanisms. High temperature with low top_p creates focused creativity, while low temperature with high top_p produces conservative but varied responses.

Max tokens isn't just a limit—it's a signal to the model about expected response length. Setting it too low can cut off important information, while setting it too high wastes computational resources and can lead to verbose, unfocused responses.

**Response format considerations:** Structured output requirements should drive your response format choice. JSON format is essential when integrating with downstream systems that expect structured data. However, JSON constraints can limit the model's natural language capabilities, creating a trade-off between structure and expressiveness.

For most conversational agents, natural language output with occasional structured elements provides the best balance. Reserve strict JSON formatting for data processing agents or system integrations where structure is mandatory.

**Tool configuration strategy:** Parallel tool calls can dramatically improve performance when agents need to gather information from multiple sources simultaneously. However, parallel execution makes debugging more complex and can overwhelm external APIs with concurrent requests.

The tool_choice parameter provides crucial control over agent behavior. "auto" lets the model decide when to use tools, promoting natural conversation flow. Forcing specific tools can ensure certain operations always occur but may create rigid, unnatural interactions.

Choose your tool configuration based on your agent's primary purpose: informational agents benefit from flexible tool usage, while task-execution agents often need more deterministic tool selection.
```

### Context Variables

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "ContextAwareAgent"
  instructions "Use context variables in your responses"
  model "gpt-4o"
  
  # Set default context variables
  context do
    user_preferences { { theme: 'dark', language: 'en' } }
    session_data { { start_time: Time.now } }
    environment "production"
  end
end

**Context as configuration:** Context variables bridge the gap between static agent definition and dynamic runtime behavior. They provide a way to inject environment-specific information without hardcoding it into the agent's instructions.

The context block uses Ruby's block syntax to define lazy-evaluated values. This means `Time.now` is called when the context is accessed, not when the agent is defined. This lazy evaluation prevents stale timestamps and allows dynamic configuration based on runtime conditions.

Context variables are accessible to tools and can influence the agent's behavior without requiring code changes. This makes agents more flexible and environment-aware.

**Context variable patterns:** Effective context design follows several key patterns. **Environment context** provides deployment-specific information like API endpoints, feature flags, and resource limits. **User context** includes authentication details, preferences, and personalization data. **Session context** tracks conversation state, workflow progress, and temporary data.

**Lazy evaluation benefits:** The lazy evaluation pattern prevents common configuration pitfalls. Static timestamps become stale, database connections may timeout, and feature flags can change between agent definition and execution. Lazy evaluation ensures context reflects current reality, not initialization state.

This pattern is particularly valuable for complex deployments where agents might be defined at application startup but executed hours later. The context remains fresh and relevant throughout the agent's lifecycle.

**Security and context:** Context variables can contain sensitive information like API keys, user tokens, and access credentials. The DSL provides mechanisms to mark context variables as sensitive, ensuring they're not logged or exposed in debugging output.

When designing context structures, separate public context (safe to log) from private context (contains secrets). This separation makes security reviews easier and reduces the risk of accidental exposure.
```

### Prompt Management

The DSL includes a sophisticated prompt management system that supports multiple formats. For comprehensive documentation, see the [Prompting Guide](prompting.md).

```ruby
# PREFERRED: Ruby prompt classes with validation
class CustomerServicePrompt < RAAF::DSL::Prompts::Base
  requires :company_name, :issue_type
  optional :tone, default: "professional"
  
  def system
    "You are a customer service agent for #{@company_name}. Be #{@tone}."
  end
  
  def user
    "Customer has a #{@issue_type} issue."
  end
end

agent = RAAF::DSL::AgentBuilder.build do
  name "SupportAgent"
  prompt CustomerServicePrompt  # Type-safe, testable
  model "gpt-4o"
end

# Alternative: File-based prompts
agent = RAAF::DSL::AgentBuilder.build do
  name "ResearchAgent"
  prompt "research.md"      # Markdown with {{variables}}
  # prompt "analysis.md.erb" # ERB template with Ruby logic
  model "gpt-4o"
end
```

**Why Ruby prompts are preferred:** Ruby prompt classes provide type safety, validation, IDE support, and testability. They can be versioned, documented, and tested like any other Ruby code. File-based prompts are simpler but lack these benefits.

**Prompt resolution:** The DSL automatically resolves prompts from multiple sources:
1. Ruby classes (highest priority)
2. File system (`.md`, `.md.erb` files)
3. Custom resolvers (database, API, etc.)

Configure prompt resolution:

```ruby
RAAF::DSL.configure_prompts do |config|
  config.add_path "prompts"
  config.add_path "app/prompts"
  
  config.enable_resolver :file, priority: 100
  config.enable_resolver :phlex, priority: 50
end
```

Tool Definition DSL
-------------------

### Inline Tool Definition

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "UtilityAgent"
  instructions "Provide various utility functions"
  model "gpt-4o"
  
  # Simple tool with block
  tool :get_current_time do
    Time.now.strftime("%I:%M %p %Z on %B %d, %Y")
  end
  
  # Tool with parameters
  tool :calculate_tip do |amount:, percentage: 15|
    tip = amount * (percentage / 100.0)
    {
      original_amount: amount,
      tip_percentage: percentage,
      tip_amount: tip.round(2),
      total: (amount + tip).round(2)
    }
  end
  
  # Tool with validation
  tool :convert_temperature do |value:, from:, to:|
    raise ArgumentError, "Invalid temperature scale" unless %w[C F K].include?(from) && %w[C F K].include?(to)
    
    case [from, to]
    when ['C', 'F']
      (value * 9.0/5.0) + 32
    when ['F', 'C']
      (value - 32) * 5.0/9.0
    when ['C', 'K']
      value + 273.15
    when ['K', 'C']
      value - 273.15
    else
      value  # Same scale
    end
  end
end

**Tool definition patterns:** The DSL supports multiple patterns for defining tools, each optimized for different scenarios:

1. **Inline blocks** for simple, self-contained logic
2. **Parameter validation** using Ruby's argument patterns
3. **Error handling** with standard Ruby exception mechanisms
4. **Structured responses** using hashes for complex data

The key insight is that tools are just Ruby methods with a specific signature. The DSL automatically handles the integration with the AI model, including parameter extraction, type conversion, and result formatting. You write normal Ruby code; RAAF handles the AI integration.

**The tool contract:** Every tool establishes a contract with the AI model. This contract includes parameter types, expected behavior, and return value structure. The DSL makes this contract explicit through Ruby's parameter syntax, reducing the gap between what the model expects and what your code provides.

This explicit contract is crucial for AI reliability. When models understand exactly what a tool does and what it returns, they can make better decisions about when and how to use it. Clear contracts also make debugging easier—you can verify that tools are called correctly and return expected values.

**Tool granularity decisions:** The granularity of your tools significantly impacts agent effectiveness. Fine-grained tools (like `get_current_time`) are easy to understand and test but may require multiple model calls to accomplish complex tasks. Coarse-grained tools (like `generate_report`) are more efficient but harder for models to use appropriately.

The optimal granularity depends on your agent's role and the complexity of tasks it handles. Customer service agents benefit from fine-grained tools that match natural conversation flow. Data processing agents often need coarse-grained tools that handle complete workflows.

**Parameter design philosophy:** Tool parameters should match how humans think about the task, not how the underlying system works. A temperature conversion tool should accept familiar units like "celsius" and "fahrenheit" rather than numeric codes. This human-centric design makes tools more intuitive for AI models to use correctly.

Default parameters reduce cognitive load for both models and developers. When most tool calls use standard settings, providing sensible defaults eliminates repetitive parameter specification while still allowing customization when needed.

**Error handling strategy:** Tools should handle errors gracefully and provide meaningful feedback. Instead of letting exceptions bubble up, catch them and return structured error information that models can understand and act upon.

This approach transforms errors from conversation-ending failures into opportunities for the model to adjust its approach. A web search tool that returns "search service temporarily unavailable" allows the model to try alternative information sources rather than failing completely.
```

### External Method Tools

```ruby
# Define methods outside the DSL
def fetch_stock_price(symbol:)
  # Implementation
  StockAPI.get_price(symbol)
end

def send_notification(message:, channel: 'general')
  # Implementation
  SlackAPI.send_message(channel, message)
end

agent = RAAF::DSL::AgentBuilder.build do
  name "TradingBot"
  instructions "Help with stock trading information"
  model "gpt-4o"
  
  # Reference external methods
  tool :fetch_stock_price, &method(:fetch_stock_price)
  tool :send_notification, &method(:send_notification)
end

**Separation of concerns:** External method tools promote clean architecture by separating tool implementation from agent configuration. The methods can be tested independently, reused across multiple agents, and organized according to your application's structure.

This pattern is particularly valuable for:

- **Complex business logic** that belongs in service objects
- **Shared functionality** used by multiple agents
- **External integrations** that need their own configuration and error handling
- **Legacy code** that you want to expose to AI agents without modification

The `&method(:name)` syntax creates a method object that the DSL can introspect for parameter information and documentation.

**Architecture benefits:** External method tools enable proper layered architecture in AI applications. Your business logic remains in service objects, domain models, and integration layers where it belongs. The DSL simply provides a bridge between these existing systems and AI agents.

This separation is essential for maintaining systems as they scale. Business logic changes shouldn't require modifying agent definitions, and agent behavior adjustments shouldn't necessitate changing core application code.

**Testing advantages:** External methods can be unit tested independently of the AI system. You can verify business logic correctness without involving language models, making tests faster and more reliable. Integration tests can then focus on the AI-specific behavior without duplicating business logic validation.

This testing separation is particularly valuable for complex integrations where business logic is intricate but the AI integration is straightforward. You can achieve comprehensive test coverage without the complexity and cost of AI-powered testing.

**Reusability patterns:** Well-designed external methods naturally become reusable across multiple agents. A `send_email` method can serve customer service agents, notification systems, and workflow automation. This reusability reduces development time and ensures consistency across your AI system.

The key to effective reusability is designing methods that are generic enough to serve multiple use cases while remaining specific enough to be useful. Focus on the core business operation rather than agent-specific details.

**Legacy integration strategy:** External method tools provide a non-invasive way to AI-enable existing systems. You can expose legacy functionality to AI agents without modifying the original code, reducing risk and implementation time.

This approach is particularly valuable for organizations with established codebases who want to add AI capabilities incrementally. Start with simple read-only tools, then gradually expand to more complex interactions as confidence grows.
```

### Class-Based Tools

```ruby
class DatabaseTool
  def initialize(connection)
    @db = connection
  end
  
  def query(sql:, limit: 100)
    @db.execute(sql).limit(limit).to_a
  end
  
  def insert(table:, data:)
    @db.insert(table, data)
  end
end

agent = RAAF::DSL::AgentBuilder.build do
  name "DataAgent"
  instructions "Query and manipulate database data"
  model "gpt-4o"
  
  # Use class-based tools
  db_tool = DatabaseTool.new(ActiveRecord::Base.connection)
  tool :query_database, &db_tool.method(:query)
  tool :insert_record, &db_tool.method(:insert)
end
```

Built-in Tool Presets
---------------------

The DSL includes shortcuts for common tool types. These presets encapsulate best practices and common configuration patterns, allowing you to add sophisticated capabilities with minimal code.

**The preset philosophy:** Built-in presets represent the distilled wisdom of building AI applications at scale. Each preset embodies lessons learned from real-world deployments, including appropriate defaults, security considerations, and performance optimizations.

Rather than forcing every developer to research and implement these patterns from scratch, presets provide a solid foundation that works well out of the box while remaining customizable for specific needs.

**Configuration vs. implementation:** Presets demonstrate the power of declarative configuration. Instead of writing integration code, you declare intent ("this agent should search the web") and let the preset handle the implementation details. This approach significantly reduces development time and eliminates common integration mistakes.

The preset system also provides upgrade paths. As RAAF evolves, presets can be enhanced with new features, performance improvements, and security updates without requiring changes to your agent definitions.

### Web Search Tools

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "ResearchAgent"
  instructions "Research topics using web search"
  model "gpt-4o"
  
  # Built-in web search
  use_web_search
  
  # With configuration
  use_web_search(
    max_results: 10,
    safe_search: :moderate,
    include_images: true
  )
end
```

**Web search considerations:** Web search capabilities transform agents from static knowledge systems into dynamic research assistants. However, web search also introduces challenges: result quality varies, content may be outdated or biased, and search queries must be carefully crafted to find relevant information.

The `use_web_search` preset handles these challenges through intelligent query optimization, result filtering, and content summarization. It automatically adjusts search strategies based on query type and filters results for relevance and credibility.

**Configuration impact:** The `max_results` parameter balances comprehensiveness with processing time. More results provide broader coverage but increase token usage and processing time. For most applications, 5-10 results provide optimal balance.

Safe search settings become crucial when agents serve diverse audiences or operate in regulated industries. The preset provides granular control over content filtering while maintaining search effectiveness.

**Performance optimization:** Web search can be the slowest operation in an agent workflow. The preset includes caching mechanisms to avoid duplicate searches and result preprocessing to extract key information quickly. These optimizations are particularly important for agents that frequently search for similar topics.

### File Operations

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "FileAgent"
  instructions "Work with files and documents"
  model "gpt-4o"
  
  # File search capability
  use_file_search(
    paths: ['./docs', './src'],
    extensions: ['.md', '.rb', '.json'],
    max_file_size: 1_000_000
  )
  
  # File manipulation
  use_file_operations(
    allowed_directories: ['./workspace'],
    read_only: false
  )
end
```

**File access patterns:** File operations enable agents to work with existing documentation, code repositories, and data files. This capability is essential for knowledge management agents, code analysis tools, and document processing workflows.

The separation between `use_file_search` and `use_file_operations` reflects different security postures. Search operations are generally safe and can be granted broadly, while file manipulation requires careful access control and auditing.

**Security implications:** File operations present significant security risks if not properly constrained. The preset enforces directory restrictions, file type validation, and size limits to prevent malicious usage. Read-only mode provides additional protection when file modification isn't necessary.

These security measures are particularly important for agents that handle user-generated content or operate in multi-tenant environments where data isolation is crucial.

**Performance considerations:** File operations can be resource-intensive, especially when searching large codebases or processing complex documents. The preset includes indexing capabilities and smart caching to minimize disk I/O and improve response times.

File size limits prevent agents from attempting to process unreasonably large files that could cause memory issues or extreme processing delays. These limits should be tuned based on your system's capabilities and typical file sizes.

### Code Execution

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "CodeAgent"
  instructions "Execute code and analyze results"
  model "gpt-4o"
  
  # Code interpreter
  use_code_interpreter(
    languages: ['python', 'ruby', 'javascript'],
    timeout: 30,
    memory_limit: '512MB'
  )
  
  # With libraries
  use_code_interpreter(
    language: 'python',
    libraries: ['numpy', 'pandas', 'matplotlib']
  )
end
```

**Code execution capabilities:** Code interpretation transforms agents from text processors into computational tools capable of data analysis, mathematical calculations, and algorithm implementation. This capability is essential for data science agents, educational tools, and problem-solving assistants.

The sandboxed execution environment ensures safety while maintaining functionality. Code runs in isolated containers with resource limits, preventing malicious code from affecting the host system or other agents.

**Language selection strategy:** Different languages serve different purposes in AI applications. Python excels at data analysis and scientific computing, JavaScript handles web-related tasks and JSON manipulation, while Ruby provides excellent string processing and system automation capabilities.

Choosing the right language mix depends on your agent's primary use cases. Data analysis agents benefit from Python's scientific libraries, while web automation agents might prefer JavaScript's DOM manipulation capabilities.

**Resource management:** Code execution can consume significant computational resources. The preset includes intelligent resource limiting to prevent runaway processes and ensure fair resource allocation across multiple agents.

Timeout settings balance execution capability with system responsiveness. Complex data analysis might require longer timeouts, while simple calculations can use shorter limits to maintain snappy interaction.

**Library ecosystem:** Pre-installed libraries dramatically expand agent capabilities without requiring custom tool development. The preset includes carefully curated library sets that provide maximum functionality while maintaining security and performance.

Library selection should align with your agent's intended use cases. Data science agents benefit from NumPy, Pandas, and Matplotlib, while web-focused agents might need requests, BeautifulSoup, and other web scraping tools.

### Database Operations

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "DatabaseAgent"
  instructions "Query and analyze database information"
  model "gpt-4o"
  
  # Database tools
  use_database(
    connection: ActiveRecord::Base.connection,
    allowed_tables: ['users', 'orders', 'products'],
    read_only: true
  )
end
```

### API Integration

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "APIAgent"
  instructions "Integrate with external APIs"
  model "gpt-4o"
  
  # REST API tools
  use_http_client(
    base_url: 'https://api.example.com',
    headers: { 'Authorization' => "Bearer #{ENV['API_TOKEN']}" },
    timeout: 10
  )
  
  # Specific API integrations
  use_slack_integration(token: ENV['SLACK_TOKEN'])
  use_github_integration(token: ENV['GITHUB_TOKEN'])
end
```

Multi-Agent DSL
---------------

Multi-agent systems represent the next evolution in AI application architecture. Instead of building monolithic agents that handle all tasks, you create specialized agents that collaborate to solve complex problems. This approach mirrors how human teams work: specialists handle their domains of expertise while coordinating to achieve shared goals.

**The specialization advantage:** Specialized agents outperform generalist agents in their domains while maintaining focus and reliability. A research agent optimized for information gathering will consistently produce better results than a general-purpose agent that occasionally does research.

This specialization also improves maintainability. When business requirements change, you can update specific agents without affecting the entire system. Bug fixes and performance improvements can be targeted to the relevant specialist rather than applied broadly.

**Coordination complexity:** Multi-agent systems introduce coordination challenges that don't exist in single-agent applications. Agents must share context, handle failures gracefully, and maintain consistent behavior across handoffs. The DSL provides patterns and tools to manage this complexity effectively.

The key insight is that coordination should be explicit and declarative. Rather than having agents make ad-hoc decisions about when to transfer control, you define clear handoff conditions and context sharing rules.

**Workflow vs. conversation:** Multi-agent systems can follow structured workflows or engage in free-form collaboration. Workflow-based systems provide predictable behavior and clear progress tracking, while conversation-based systems offer more flexibility and natural interaction patterns.

Choose your coordination model based on your application's requirements. Customer service scenarios often benefit from workflow structure, while creative tasks might need conversational flexibility.

### Agent Handoffs

```ruby
# Define multiple agents with handoffs
research_agent = RAAF::DSL::AgentBuilder.build do
  name "Researcher"
  instructions "Research topics thoroughly"
  model "gpt-4o"
  
  use_web_search
  
  # Define handoff conditions
  handoff_to "Writer" do |context, messages|
    # Handoff when research is complete
    messages.last[:content].include?("research complete")
  end
end

writer_agent = RAAF::DSL::AgentBuilder.build do
  name "Writer"
  instructions "Write content based on research"
  model "gpt-4o"
  
  # Access context from previous agent
  tool :get_research_data do
    context[:research_findings]
  end
  
  handoff_to "Editor" do |context, messages|
    messages.last[:content].include?("draft complete")
  end
end

editor_agent = RAAF::DSL::AgentBuilder.build do
  name "Editor"
  instructions "Edit and polish content"
  model "gpt-4o"
  
  # No further handoffs - final agent
end
```

### Workflow Definition

```ruby
workflow = RAAF::DSL::WorkflowBuilder.build do
  name "ContentCreationWorkflow"
  description "Complete content creation pipeline"
  
  # Define the agent sequence
  agent research_agent
  agent writer_agent  
  agent editor_agent
  
  # Shared context across all agents
  shared_context do
    project_id { SecureRandom.uuid }
    created_at { Time.now }
    workflow_version "1.0"
  end
  
  # Error handling
  on_error do |error, current_agent|
    if error.is_a?(RAAF::Errors::ToolError)
      retry_with_agent(current_agent)
    else
      escalate_to_human(error)
    end
  end
end
```

**Workflow orchestration:** Workflows provide structure and predictability to multi-agent systems. They define the sequence of operations, data flow between agents, and error handling strategies. This structure is essential for production systems where consistency and reliability are paramount.

The workflow abstraction separates business process logic from individual agent implementation. You can modify the workflow sequence, add new agents, or change handoff conditions without modifying the underlying agents.

**Shared context strategy:** Shared context enables seamless collaboration between agents while maintaining data consistency. The context acts as a shared workspace where agents can store findings, track progress, and communicate findings to subsequent agents.

Lazy evaluation in shared context ensures that dynamic values like timestamps and generated IDs remain fresh throughout the workflow execution. This approach prevents common issues like stale data and race conditions.

**Error handling philosophy:** Robust error handling is crucial for multi-agent systems because failures can cascade across agents. The workflow DSL provides structured error handling that can recover from transient failures, escalate complex issues, and maintain system state consistency.

Different error types require different handling strategies. Tool errors might warrant retries, while business logic errors might require human intervention or alternative workflow paths.

**Monitoring and observability:** Workflows generate rich telemetry data that enables monitoring, debugging, and performance optimization. The DSL automatically tracks agent handoffs, execution times, and error rates, providing visibility into system behavior.

This observability is particularly valuable for optimizing workflow performance and identifying bottlenecks. You can analyze which agents consume the most time, which handoffs fail most frequently, and how context size affects performance.

Advanced DSL Features
--------------------

Advanced DSL features enable sophisticated agent behaviors that adapt to different environments, generate tools dynamically, and extend the DSL itself. These capabilities are essential for production systems that need to handle varying requirements and integrate with complex existing infrastructure.

**The power of meta-programming:** Ruby's meta-programming capabilities make the DSL extensible and adaptable. You can generate tools programmatically, create custom DSL methods, and build domain-specific abstractions that match your business requirements.

This meta-programming approach is particularly valuable for organizations with unique requirements that don't fit standard patterns. Instead of forcing your use case into existing abstractions, you can extend the DSL to match your domain naturally.

**Environment-aware design:** Production AI systems must operate differently across development, staging, and production environments. The DSL supports environment-specific configuration that ensures appropriate behavior in each context while maintaining consistent agent definitions.

This environment awareness extends beyond simple configuration to include different tool sets, security policies, and performance characteristics. Development agents might include debugging tools that are inappropriate for production, while production agents might include monitoring and alerting capabilities not needed in development.

### Conditional Tool Loading

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "ConditionalAgent"
  instructions "Agent with environment-specific tools"
  model "gpt-4o"
  
  # Load tools based on environment
  if ENV['RACK_ENV'] == 'production'
    tool :send_real_email do |to:, subject:, body:|
      ProductionEmailService.send(to, subject, body)
    end
  else
    tool :send_real_email do |to:, subject:, body:|
      puts "DEV: Email to #{to}: #{subject}"
      { status: 'sent', dev_mode: true }
    end
  end
  
  # Conditional tool presets
  use_database if defined?(ActiveRecord)
  use_redis if defined?(Redis)
end
```

### Dynamic Tool Generation

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "DynamicAgent"
  instructions "Agent with dynamically generated tools"
  model "gpt-4o"
  
  # Generate tools from configuration
  api_endpoints = YAML.load_file('api_config.yml')
  
  api_endpoints.each do |endpoint_name, config|
    tool "call_#{endpoint_name}".to_sym do |**params|
      HTTParty.get(config['url'], query: params)
    end
  end
  
  # Generate CRUD tools for models
  [User, Order, Product].each do |model_class|
    model_name = model_class.name.downcase
    
    tool "find_#{model_name}".to_sym do |id:|
      model_class.find(id)
    end
    
    tool "create_#{model_name}".to_sym do |**attributes|
      model_class.create!(attributes)
    end
  end
end
```

**Dynamic generation benefits:** Dynamic tool generation eliminates repetitive code and ensures consistency across similar tools. Instead of manually defining dozens of similar API integration tools, you can generate them from configuration files or database schemas.

This approach is particularly valuable for organizations with extensive API ecosystems or complex data models. The tool generation can incorporate business rules, validation logic, and security policies automatically.

**Configuration-driven architecture:** Configuration-driven tool generation separates business logic from implementation details. Business analysts can define new API integrations or data model tools without requiring developer intervention.

This separation accelerates development cycles and reduces the risk of implementation errors. The configuration becomes a declarative specification of desired functionality, while the generation code handles the implementation details.

**Maintenance advantages:** Dynamic generation reduces maintenance burden by centralizing tool creation logic. Updates to error handling, logging, or security policies can be applied to all generated tools simultaneously.

This centralization is particularly valuable for large systems with hundreds of tools. Manual maintenance of individual tools becomes impractical at scale, while generated tools remain consistent and up-to-date.

**Runtime flexibility:** Dynamic tool generation can respond to runtime conditions, creating tools based on available services, user permissions, or configuration changes. This flexibility enables adaptive agents that adjust their capabilities based on current context.

However, runtime generation adds complexity and potential performance overhead. Use this pattern judiciously, focusing on scenarios where the flexibility benefits outweigh the added complexity.

### Custom DSL Extensions

```ruby
# Define custom DSL methods
module CustomDSLExtensions
  def use_customer_service_tools
    tool :lookup_customer do |customer_id:|
      Customer.find(customer_id)
    end
    
    tool :create_support_ticket do |title:, description:, priority: 'medium'|
      SupportTicket.create!(
        title: title,
        description: description,
        priority: priority
      )
    end
    
    tool :escalate_to_human do |reason:|
      HumanEscalationService.escalate(reason)
    end
  end
  
  def use_analytics_tools
    tool :track_event do |event_name:, properties: {}|
      Analytics.track(event_name, properties)
    end
    
    tool :get_metrics do |metric_name:, timeframe: '1d'|
      MetricsService.get(metric_name, timeframe)
    end
  end
end

# Extend the DSL
RAAF::DSL::AgentBuilder.include(CustomDSLExtensions)

# Use custom extensions
agent = RAAF::DSL::AgentBuilder.build do
  name "CustomerServiceAgent"
  instructions "Handle customer service inquiries"
  model "gpt-4o"
  
  # Use custom DSL methods
  use_customer_service_tools
  use_analytics_tools
end
```

**Domain-specific abstractions:** Custom DSL extensions enable you to create domain-specific abstractions that match your business vocabulary. Instead of thinking in terms of generic tools, you can work with concepts like "customer service tools" or "analytics tools" that directly map to business capabilities.

These abstractions make agent definitions more readable and maintainable. Business stakeholders can understand what agents do without needing to interpret technical tool names or implementation details.

**Organizational patterns:** Custom extensions promote consistency across your organization's AI applications. When multiple teams build agents, shared extensions ensure common patterns and reduce duplicate implementation.

This organizational benefit extends beyond code reuse to include best practices, security policies, and performance optimizations. Extensions can encapsulate lessons learned from production deployments, making this knowledge available to all teams.

**Evolution and versioning:** Custom extensions provide a controlled way to evolve your AI system architecture. As business requirements change, you can update extensions to reflect new patterns while maintaining backward compatibility for existing agents.

This evolutionary approach is particularly valuable for large organizations where coordinating changes across multiple teams is challenging. Extensions provide a stable interface that can evolve independently of individual agent implementations.

**Testing and validation:** Custom extensions can include built-in validation and testing capabilities. When extensions are created, they can verify that required services are available, configurations are valid, and dependencies are met.

This validation prevents common configuration errors and provides clear error messages when problems occur. Extensions can also include mock implementations for testing purposes, enabling reliable unit testing of agent configurations.

Configuration Management
------------------------

### Environment-Based Configuration

```ruby
# config/agents/customer_service.rb
RAAF::DSL::ConfigurationBuilder.build do
  environment :development do
    model "gpt-4o-mini"  # Cheaper for dev
    temperature 0.3
    max_tokens 1000
    
    tools do
      use_mock_database
      use_debug_logging
    end
  end
  
  environment :production do
    model "gpt-4o"
    temperature 0.7
    max_tokens 2000
    
    tools do
      use_database(connection: ActiveRecord::Base.connection)
      use_monitoring
      use_security_logging
    end
  end
  
  shared do
    name "CustomerServiceAgent"
    instructions "Help customers with their inquiries"
    
    tool :get_order_status do |order_id:|
      OrderService.get_status(order_id)
    end
  end
end

# Load configuration
config = RAAF::DSL::Configuration.load('config/agents/customer_service.rb')
agent = config.build_agent(ENV['RACK_ENV'] || 'development')
```

### Modular Configuration

```ruby
# config/agents/modules/web_tools.rb
RAAF::DSL::ModuleBuilder.build(:web_tools) do
  tool :fetch_url do |url:|
    HTTParty.get(url)
  end
  
  tool :parse_html do |html:|
    Nokogiri::HTML(html)
  end
  
  use_web_search
end

# config/agents/modules/database_tools.rb
RAAF::DSL::ModuleBuilder.build(:database_tools) do
  use_database(
    connection: ActiveRecord::Base.connection,
    allowed_tables: %w[users orders products]
  )
  
  tool :execute_report do |report_name:|
    ReportService.generate(report_name)
  end
end

# Use modules in agent configuration
agent = RAAF::DSL::AgentBuilder.build do
  name "DataAnalystAgent"
  instructions "Analyze data from web and database sources"
  model "gpt-4o"
  
  # Include modules
  include_module :web_tools
  include_module :database_tools
  
  # Agent-specific tools
  tool :generate_insights do |data:|
    InsightEngine.analyze(data)
  end
end
```

Testing DSL-Based Agents
------------------------

### RSpec Integration

```ruby
require 'raaf-dsl/rspec'

RSpec.describe 'Customer Service Agent' do
  let(:agent) do
    RAAF::DSL::AgentBuilder.build do
      name "CustomerServiceAgent"
      instructions "Help customers"
      model "gpt-4o"
      
      tool :lookup_order do |order_id:|
        { id: order_id, status: 'shipped' }
      end
    end
  end
  
  it 'has the correct configuration' do
    expect(agent).to have_name('CustomerServiceAgent')
    expect(agent).to have_model('gpt-4o')
    expect(agent).to have_tool(:lookup_order)
  end
  
  it 'can look up orders' do
    runner = RAAF::Runner.new(agent: agent)
    result = runner.run("What's the status of order 12345?")
    
    expect(result).to be_successful
    expect(result).to have_used_tool(:lookup_order)
    expect(result.messages.last[:content]).to include('shipped')
  end
end
```

### Custom Matchers

```ruby
# spec/support/agent_matchers.rb
RSpec.describe do
  matcher :have_tool do |tool_name|
    match do |agent|
      agent.tools.key?(tool_name)
    end
    
    failure_message do |agent|
      "expected agent to have tool #{tool_name}, but tools were: #{agent.tools.keys}"
    end
  end
  
  matcher :have_handoff_to do |target_agent|
    match do |agent|
      agent.handoffs.any? { |h| h.target_agent == target_agent }
    end
  end
  
  matcher :be_successful do
    match do |result|
      result.success?
    end
  end
  
  matcher :have_used_tool do |tool_name|
    match do |result|
      result.tool_calls.any? { |call| call[:tool_name] == tool_name }
    end
  end
end
```

### Testing Workflows

```ruby
RSpec.describe 'Content Creation Workflow' do
  let(:workflow) do
    RAAF::DSL::WorkflowBuilder.build do
      name "ContentWorkflow"
      
      agent research_agent
      agent writer_agent
      agent editor_agent
      
      shared_context do
        topic "Ruby programming"
        audience "developers"
      end
    end
  end
  
  it 'executes the complete workflow' do
    result = workflow.execute("Create an article about Ruby best practices")
    
    expect(result).to be_successful
    expect(result.agent_sequence).to eq(%w[Researcher Writer Editor])
    expect(result.context[:topic]).to eq("Ruby programming")
  end
  
  it 'handles handoffs correctly' do
    result = workflow.execute("Create content")
    
    expect(result.handoffs).to include(
      { from: 'Researcher', to: 'Writer', reason: 'Research complete' },
      { from: 'Writer', to: 'Editor', reason: 'Draft complete' }
    )
  end
end
```

### Mock Tool Testing

```ruby
RSpec.describe 'Agent with External Dependencies' do
  let(:agent) do
    RAAF::DSL::AgentBuilder.build do
      name "WeatherAgent"
      instructions "Provide weather information"
      model "gpt-4o"
      
      tool :get_weather do |location:|
        WeatherAPI.current_weather(location)
      end
    end
  end
  
  before do
    # Mock external API
    allow(WeatherAPI).to receive(:current_weather).and_return({
      location: 'San Francisco',
      temperature: 68,
      conditions: 'sunny'
    })
  end
  
  it 'uses the weather API' do
    runner = RAAF::Runner.new(agent: agent)
    result = runner.run("What's the weather in San Francisco?")
    
    expect(WeatherAPI).to have_received(:current_weather).with('San Francisco')
    expect(result.messages.last[:content]).to include('68')
  end
end
```

Best Practices
--------------

### DSL Design Guidelines

1. **Keep it Declarative** - Describe what, not how
2. **Use Meaningful Names** - Tool and agent names should be descriptive
3. **Group Related Tools** - Use modules or presets for related functionality
4. **Document Complex Logic** - Add comments for non-obvious configurations
5. **Test Configurations** - Verify DSL configurations work as expected

### Good DSL Examples

```ruby
# ✅ GOOD: Clear, declarative configuration
agent = RAAF::DSL::AgentBuilder.build do
  name "SalesAnalyst"
  instructions """
    Analyze sales data and provide insights.
    Focus on trends, anomalies, and actionable recommendations.
  """
  model "gpt-4o"
  
  # Grouped related tools
  use_database_analytics
  use_chart_generation
  
  # Clear tool purpose
  tool :calculate_growth_rate do |current:, previous:|
    ((current - previous) / previous.to_f * 100).round(2)
  end
  
  tool :identify_top_performers do |data:, metric: 'revenue'|
    data.sort_by { |item| item[metric] }.reverse.first(10)
  end
end
```

### Avoid These Patterns

```ruby
# ❌ BAD: Procedural code in DSL
agent = RAAF::DSL::AgentBuilder.build do
  name "BadAgent"
  instructions "..."
  model "gpt-4o"
  
  # Don't put complex logic in DSL blocks
  tool :complex_operation do |data:|
    results = []
    data.each do |item|
      if item[:type] == 'A'
        processed = process_type_a(item)
        results << processed if processed.valid?
      elsif item[:type] == 'B'
        # ... lots of complex logic
      end
    end
    results
  end
end

# ✅ GOOD: Extract complex logic to methods
def process_data_items(data)
  # Complex logic here
end

agent = RAAF::DSL::AgentBuilder.build do
  name "GoodAgent"  
  instructions "..."
  model "gpt-4o"
  
  tool :process_data, &method(:process_data_items)
end
```

### Performance Considerations

```ruby
# Lazy load expensive resources
agent = RAAF::DSL::AgentBuilder.build do
  name "PerformantAgent"
  instructions "..."
  model "gpt-4o"
  
  # Don't initialize expensive resources in DSL
  tool :query_large_dataset do |query:|
    # Initialize connection only when needed
    @db_connection ||= LargeDatabase.connect
    @db_connection.query(query)
  end
  
  # Use connection pooling for concurrent access
  tool :fetch_from_api do |endpoint:|
    @http_pool ||= ConnectionPool.new(size: 5) { HTTPClient.new }
    @http_pool.with { |client| client.get(endpoint) }
  end
end
```

Integration with Rails
---------------------

### Rails Engine Integration

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount RAAF::Rails::Engine => "/ai"
end

# app/agents/application_agent.rb
class ApplicationAgent < RAAF::DSL::Agent
  include Rails.application.routes.url_helpers
  
  def self.base_configuration
    RAAF::DSL::AgentBuilder.build do
      # Common Rails integrations
      use_active_record
      use_action_mailer
      use_rails_cache
      
      # Rails-specific tools
      tool :render_partial do |template:, locals: {}|
        ApplicationController.new.render_to_string(
          partial: template,
          locals: locals
        )
      end
    end
  end
end

# app/agents/customer_service_agent.rb
class CustomerServiceAgent < ApplicationAgent
  def self.build
    base_configuration.extend do
      name "CustomerService"
      instructions "Help customers with Rails app inquiries"
      
      tool :find_user do |email:|
        User.find_by(email: email)
      end
      
      tool :create_support_ticket do |title:, description:|
        SupportTicket.create!(title: title, description: description)
      end
    end
  end
end
```

### Controller Integration

```ruby
class ChatController < ApplicationController
  def create
    agent = CustomerServiceAgent.build
    
    runner = RAAF::Runner.new(
      agent: agent,
      context_variables: {
        current_user: current_user,
        request_id: request.uuid
      }
    )
    
    result = runner.run(params[:message])
    
    render json: {
      response: result.messages.last[:content],
      success: result.success?
    }
  end
end
```

Next Steps
----------

Now that you understand the RAAF DSL:

* **[RAAF Providers Guide](providers_guide.html)** - Use different AI providers
* **[RAAF Memory Guide](memory_guide.html)** - Advanced context management  
* **[RAAF Testing Guide](testing_guide.html)** - Test DSL configurations
* **[Multi-Agent Guide](multi_agent_guide.html)** - Build complex workflows
* **[Rails Integration](rails_guide.html)** - DSL in Rails applications