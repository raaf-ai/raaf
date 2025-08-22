**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf-ai.dev>.**

RAAF DSL Guide
==============

This guide covers the declarative Domain Specific Language (DSL) for Ruby AI Agents Factory (RAAF). The DSL provides an elegant, Ruby-idiomatic way to configure agents, tools, and workflows with modern RAAF capabilities.

After reading this guide, you will know:

* How to build agents with the modern AgentBuilder DSL
* Current tool integration patterns and best practices
* Advanced prompt management with Ruby classes (preferred over files)
* Multi-agent orchestration and handoff patterns  
* Context variables and the immutable ContextVariables system
* Testing strategies for DSL-based agents
* Integration with Rails applications

INFO: The DSL uses ResponsesProvider by default for Python SDK compatibility and built-in retry logic.

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
  model: "gpt-4o"  # Uses ResponsesProvider by default
)

def lookup_order(order_id:)
  # Implementation
end

def send_email(to:, subject:, body:)
  # Implementation  
end

agent.add_tool(method(:lookup_order))
agent.add_tool(method(:send_email))

# DSL approach (recommended for modern RAAF)
agent = RAAF::DSL::AgentBuilder.build do
  name "CustomerService"
  instructions "Help customers with inquiries"
  model "gpt-4o"  # Automatically uses ResponsesProvider with built-in retry
  
  # Tools with keyword arguments for OpenAI compatibility
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

# Create a minimal agent with modern RAAF standards
agent = RAAF::DSL::AgentBuilder.build do
  name "WeatherBot"
  instructions "Provide weather information for any location using available tools."
  model "gpt-4o"  # Uses ResponsesProvider automatically for Python SDK compatibility
end

# Create runner (automatically uses ResponsesProvider with built-in retry)
runner = RAAF::Runner.new(agent: agent)

# Run conversation
result = runner.run("What's the weather like in Tokyo?")
puts result.messages.last[:content]
```

**Minimal viable agent:** This example shows the absolute minimum needed to create a functional agent. Just three lines of configuration create a working AI agent with specific instructions and model selection.

The DSL handles all the complexity—provider configuration, API communication, response formatting—while you focus on the agent's purpose. This is the power of good abstraction: complex systems become simple to use.

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

RAAF DSL uses an immutable ContextVariables system that ensures thread safety and prevents accidental mutations during agent execution.

WARNING: RAAF ContextVariables uses an immutable pattern. Each `.set()` call returns a **NEW instance**. Always capture the returned value to avoid empty context.

```ruby
# Build context using the immutable pattern
def build_agent_context(user, session_data)
  context = RAAF::DSL::ContextVariables.new
  context = context.set(:user_id, user.id)
  context = context.set(:user_preferences, user.preferences)
  context = context.set(:session_data, session_data)
  context = context.set(:environment, ENV['RACK_ENV'] || 'development')
  context  # Return the built context
end

agent = RAAF::DSL::AgentBuilder.build do
  name "ContextAwareAgent"
  instructions "Use context variables in your responses. Access user data via context."
  model "gpt-4o"
  
  # Tool that uses context variables
  tool :get_user_preference do |preference_key:|
    context.get(:user_preferences)[preference_key]
  end
end

# Usage with context
context = build_agent_context(current_user, session_data)
runner = RAAF::Runner.new(agent: agent, context_variables: context)
result = runner.run("What's my preferred theme?")
```

### ObjectProxy System for Lazy Context Handling

RAAF DSL includes an advanced ObjectProxy system for lazy-loaded context variables and complex object handling. This system enables sophisticated context management with deferred evaluation.

```ruby
# ObjectProxy for lazy context loading
agent = RAAF::DSL::AgentBuilder.build do
  name "SmartAgent"
  instructions "Access complex data structures efficiently"
  model "gpt-4o"
  
  # Tool using ObjectProxy for database access
  tool :get_user_orders do |user_id:|
    # ObjectProxy enables lazy loading of complex relationships
    user_proxy = RAAF::DSL::ObjectProxy.new do
      User.includes(:orders, :preferences).find(user_id)
    end
    
    # Data is only loaded when accessed
    {
      user_name: user_proxy.name,
      order_count: user_proxy.orders.count,
      total_spent: user_proxy.orders.sum(:total),
      last_order: user_proxy.orders.last&.created_at
    }
  end
  
  # ObjectProxy for API integrations
  tool :get_weather_data do |location:|
    weather_proxy = RAAF::DSL::ObjectProxy.new do
      WeatherAPI.fetch_detailed_forecast(location)
    end
    
    # Lazy evaluation prevents unnecessary API calls
    {
      current_temp: weather_proxy.current.temperature,
      conditions: weather_proxy.current.conditions,
      forecast: weather_proxy.forecast.today.summary
    }
  end
end
```

**ObjectProxy benefits:**
- **Lazy evaluation** - Expensive operations only execute when data is accessed
- **Memory efficiency** - Large objects aren't loaded unnecessarily
- **Error isolation** - Failed proxy creation doesn't break the entire context
- **Performance optimization** - Database queries and API calls are deferred

**Context as configuration:** Context variables bridge the gap between static agent definition and dynamic runtime behavior. They provide a way to inject environment-specific information without hardcoding it into the agent's instructions.

The context block uses Ruby's block syntax to define lazy-evaluated values. This means `Time.now` is called when the context is accessed, not when the agent is defined. This lazy evaluation prevents stale timestamps and allows dynamic configuration based on runtime conditions.

Context variables are accessible to tools and can influence the agent's behavior without requiring code changes. This makes agents more flexible and environment-aware.

**Context variable patterns:** Effective context design follows several key patterns. **Environment context** provides deployment-specific information like API endpoints, feature flags, and resource limits. **User context** includes authentication details, preferences, and personalization data. **Session context** tracks conversation state, workflow progress, and temporary data.

**Lazy evaluation benefits:** The lazy evaluation pattern prevents common configuration pitfalls. Static timestamps become stale, database connections may timeout, and feature flags can change between agent definition and execution. Lazy evaluation ensures context reflects current reality, not initialization state.

This pattern is particularly valuable for complex deployments where agents might be defined at application startup but executed hours later. The context remains fresh and relevant throughout the agent's lifecycle.

**Security and context:** Context variables can contain sensitive information like API keys, user tokens, and access credentials. The DSL provides mechanisms to mark context variables as sensitive, ensuring they're not logged or exposed in debugging output.

When designing context structures, separate public context (safe to log) from private context (contains secrets). This separation makes security reviews easier and reduces the risk of accidental exposure.

### Prompt Management

The DSL includes a sophisticated prompt management system with Ruby prompt classes as the preferred approach for type safety, testability, and IDE support.

INFO: Always prefer Ruby prompt classes over Markdown files for better maintainability and validation.

NOTE: All RSpec testing utilities have been moved to the `raaf-testing` gem for better organization and optional dependency management. Use `require 'raaf-testing'` to access all testing features.

```ruby
# PREFERRED: Ruby prompt classes with RAAF DSL Base
class CustomerServicePrompt < RAAF::DSL::Prompts::Base
  def system
    <<~SYSTEM
      You are a customer service agent for #{company_name}.
      Handle #{issue_type} issues with a #{tone || 'professional'} tone.
      Always ask clarifying questions when details are unclear.
    SYSTEM
  end
  
  def user
    "Customer needs help with a #{@issue_type} issue."
  end
  
  # Define JSON schema for structured responses if needed
  def schema
    {
      type: "object",
      properties: {
        resolution: { type: "string" },
        next_steps: { type: "array", items: { type: "string" } },
        escalation_needed: { type: "boolean" }
      },
      required: ["resolution", "escalation_needed"]
    }
  end
end

# Use prompt class in agent
agent = RAAF::DSL::AgentBuilder.build do
  name "SupportAgent"
  prompt_class CustomerServicePrompt  # Type-safe with validation
  model "gpt-4o"
end

# Create prompt instance with validation
prompt = CustomerServicePrompt.new(
  company_name: "ACME Corp",
  issue_type: "billing"
  # tone defaults to "professional"
)

# Alternative: File-based prompts (less preferred)
# agent = RAAF::DSL::AgentBuilder.build do
#   name "ResearchAgent"
#   prompt "research.md"      # Markdown with {{variables}}
#   model "gpt-4o"
# end
```

**Why Ruby prompts are preferred:** Ruby prompt classes provide type safety, validation, IDE support, and testability. They can be versioned, documented, and tested like any other Ruby code. File-based prompts are simpler but lack these benefits.

**Prompt resolution:** The DSL automatically resolves prompts from multiple sources:
1. Ruby classes (highest priority)
2. File system (`.md`, `.md.erb` files)
3. Custom resolvers (database, API, etc.)

Configure prompt resolution:

<!-- VALIDATION_FAILED: dsl_guide.md:268 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: ArgumentError: wrong number of arguments (given 1, expected 0) /Users/hajee/.rvm/gems/ruby-3.4.5/gems/ostruct-0.6.3/lib/ostruct.rb:240:in 'block (2 levels) in new_ostruct_member!' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-2r7mqn.rb:445:in 'block in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-2r7mqn.rb:191:in 'RAAF::DSL.configure_prompts'
```

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
  instructions "Provide various utility functions with proper tool usage"
  model "gpt-4o"
  
  # Simple tool without parameters
  tool :get_current_time do
    Time.now.strftime("%I:%M %p %Z on %B %d, %Y")
  end
  
  # Tool with keyword arguments (required for OpenAI compatibility)
  tool :calculate_tip do |amount:, percentage: 15|
    raise ArgumentError, "Amount must be positive" if amount <= 0
    
    tip = amount * (percentage / 100.0)
    {
      original_amount: amount,
      tip_percentage: percentage,
      tip_amount: tip.round(2),
      total: (amount + tip).round(2)
    }
  end
  
  # Tool with validation and error handling
  tool :convert_temperature do |value:, from:, to:|
    valid_scales = %w[C F K]
    unless valid_scales.include?(from) && valid_scales.include?(to)
      return { error: "Invalid temperature scale. Use: #{valid_scales.join(', ')}" }
    end
    
    result = case [from, to]
             when ['C', 'F'] then (value * 9.0/5.0) + 32
             when ['F', 'C'] then (value - 32) * 5.0/9.0
             when ['C', 'K'] then value + 273.15
             when ['K', 'C'] then value - 273.15
             else value  # Same scale
             end
    
    {
      original_value: value,
      original_scale: from,
      converted_value: result.round(2),
      converted_scale: to
    }
  end
  
  # Tool that uses context variables
  tool :get_user_setting do |setting_key:|
    user_prefs = context.get(:user_preferences) || {}
    user_prefs[setting_key] || "Setting not found"
  end
end
```

**Modern tool patterns:** The current DSL emphasizes several key patterns for robust tool development:

1. **Keyword arguments** - All tools must use keyword arguments for OpenAI API compatibility
2. **Error handling** - Return structured error information instead of raising exceptions
3. **Context integration** - Access context variables through the `context` object
4. **Validation** - Validate inputs and provide clear error messages
5. **Structured responses** - Return hashes with meaningful keys for complex data

INFO: Always use keyword arguments (`param:`) in tools for proper OpenAI API integration.

**Tool design philosophy:** Modern RAAF tools prioritize reliability and user experience. Instead of raising exceptions that terminate conversations, tools return structured error information that allows agents to handle problems gracefully and suggest alternatives.

This approach transforms errors from conversation-ending failures into opportunities for the model to adjust its approach and maintain helpful dialogue with users.

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

<!-- VALIDATION_FAILED: dsl_guide.md:404 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NoMethodError: private method 'method' called for an instance of DatabaseTool /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-bic4hr.rb:465:in 'block in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-bic4hr.rb:139:in 'BasicObject#instance_eval' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-bic4hr.rb:139:in 'RAAF::DSL::AgentBuilder.build'
```

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

RAAF uses tool-based handoffs exclusively. Handoffs are implemented as function calls (tools) that the LLM must explicitly invoke. The system automatically creates `transfer_to_<agent_name>` tools for handoff targets.

WARNING: Text-based or JSON-based handoff detection in message content is not supported. The LLM must explicitly call handoff tools.

```ruby
# Define specialized agents with tool-based handoffs
research_agent = RAAF::DSL::AgentBuilder.build do
  name "Researcher"
  instructions "Research topics thoroughly. When research is complete, transfer to Writer."
  model "gpt-4o"
  
  use_web_search
end

writer_agent = RAAF::DSL::AgentBuilder.build do
  name "Writer"
  instructions "Write content based on research. When draft is complete, transfer to Editor."
  model "gpt-4o"
  
  # Tool to access research context
  tool :get_research_findings do
    context.get(:research_findings) || "No research data available"
  end
end

editor_agent = RAAF::DSL::AgentBuilder.build do
  name "Editor"
  instructions "Edit and polish content. This is the final step."
  model "gpt-4o"
end

# Configure handoffs (automatically creates transfer tools)
research_agent.add_handoff(writer_agent)  # Creates transfer_to_Writer tool
writer_agent.add_handoff(editor_agent)    # Creates transfer_to_Editor tool

# Alternative: Use string names for handoffs
# research_agent.add_handoff("Writer")
# writer_agent.add_handoff("Editor")

# Multi-agent runner
runner = RAAF::Runner.new(
  agent: research_agent,
  agents: [research_agent, writer_agent, editor_agent]
)

result = runner.run("Research and write about Ruby best practices")
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

<!-- VALIDATION_FAILED: dsl_guide.md:732 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant User /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-ebbk4i.rb:459:in 'block in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-ebbk4i.rb:139:in 'BasicObject#instance_eval' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-ebbk4i.rb:139:in 'RAAF::DSL::AgentBuilder.build'
```

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

<!-- VALIDATION_FAILED: dsl_guide.md:848 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::DSL::Configuration /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-emujnb.rb:480:in '<main>'
```

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
require 'raaf-dsl'
require 'raaf-testing'  # Contains all RSpec matchers and testing utilities

# Automatic setup (recommended)
RAAF::Testing.setup_rspec

RSpec.describe 'Customer Service Agent' do
  let(:agent) do
    RAAF::DSL::AgentBuilder.build do
      name "CustomerServiceAgent"
      instructions "Help customers with order inquiries"
      model "gpt-4o"
      
      tool :lookup_order do |order_id:|
        # Mock data for testing
        { id: order_id, status: 'shipped', tracking: 'ABC123' }
      end
      
      tool :escalate_to_human do |reason:|
        { escalated: true, reason: reason, ticket_id: "TICKET-#{rand(1000)}" }
      end
    end
  end
  
  describe 'agent configuration' do
    it 'has the correct basic configuration' do
      expect(agent.name).to eq('CustomerServiceAgent')
      expect(agent.model).to eq('gpt-4o')
      expect(agent.tools).to include(:lookup_order, :escalate_to_human)
    end
    
    it 'uses ResponsesProvider by default' do
      runner = RAAF::Runner.new(agent: agent)
      expect(runner.instance_variable_get(:@provider)).to be_a(RAAF::Models::ResponsesProvider)
    end
  end
  
  describe 'tool functionality' do
    let(:runner) { RAAF::Runner.new(agent: agent) }
    
    it 'can look up orders with proper tool calling' do
      # Mock the actual LLM response to test tool integration
      allow_any_instance_of(RAAF::Models::ResponsesProvider).to receive(:call).and_return(
        double(success?: true, data: {
          'messages' => [
            { 'role' => 'assistant', 'content' => 'I found your order!', 'tool_calls' => [
              { 'function' => { 'name' => 'lookup_order', 'arguments' => '{"order_id":"12345"}' } }
            ]}
          ]
        })
      )
      
      result = runner.run("What's the status of order 12345?")
      expect(result).to be_truthy
    end
  end
  
  describe 'context handling' do
    let(:context) do
      RAAF::DSL::ContextVariables.new
        .set(:user_id, 'user123')
        .set(:session_id, 'session456')
    end
    
    it 'maintains context throughout execution' do
      runner = RAAF::Runner.new(agent: agent, context_variables: context)
      expect(context.get(:user_id)).to eq('user123')
      expect(context.size).to eq(2)
    end
  end
end
```

### Custom Matchers

<!-- VALIDATION_FAILED: dsl_guide.md:974 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NoMethodError: undefined method 'matcher' for main /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-yri178.rb:446:in 'block in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-yri178.rb:325:in 'RSpec.describe' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-yri178.rb:445:in '<main>'
```

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

<!-- VALIDATION_FAILED: dsl_guide.md:1009 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NoMethodError: undefined method 'execute' for an instance of OpenStruct /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-n1d4ye.rb:461:in 'block (2 levels) in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-n1d4ye.rb:334:in 'Object#it' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-n1d4ye.rb:460:in 'block in <main>'
```

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

<!-- VALIDATION_FAILED: dsl_guide.md:1047 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NoMethodError: undefined method 'before' for main /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-64n8aa.rb:457:in 'block in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-64n8aa.rb:325:in 'RSpec.describe' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-64n8aa.rb:444:in '<main>'
```

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

<!-- VALIDATION_FAILED: dsl_guide.md:1185 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NoMethodError: undefined method 'routes' for an instance of Rails::Application /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-i1j87.rb:445:in '<main>'
```

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

## Latest DSL Agent Features

### Agent Hooks and Lifecycle Management

RAAF DSL provides comprehensive lifecycle hooks for advanced agent behavior customization:

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "HookedAgent"
  instructions "Agent with lifecycle hooks"
  model "gpt-4o"
  
  # Pre-execution hook
  before_run do |context, message|
    puts "Starting agent run for: #{message}"
    context.set(:start_time, Time.now)
  end
  
  # Post-execution hook
  after_run do |context, result|
    duration = Time.now - context.get(:start_time)
    puts "Agent completed in #{duration}s"
  end
  
  # Error handling hook
  on_error do |error, context|
    puts "Agent error: #{error.message}"
    # Log error, send notification, etc.
  end
end
```

### Smart Agent Classes

Create reusable agent classes with inheritance and mixins:

```ruby
# Base agent class with common functionality
class SmartAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::Agents::AgentDsl
  include RAAF::DSL::Hooks::AgentHooks
  
  # Default configuration for all smart agents
  agent_name "SmartAgent"
  model "gpt-4o"
  max_turns 10
  
  # Common tools available to all smart agents
  uses_tool :get_current_time
  uses_tool :log_event
  
  # Prompt class integration
  prompt_class BasePrompt
  
  # Schema definition
  schema do
    field :response, type: :string, required: true
    field :confidence, type: :number, range: 0..1
    field :follow_up_needed, type: :boolean
  end
end

# Specialized agent inheriting from SmartAgent
class CustomerServiceAgent < SmartAgent
  agent_name "CustomerServiceAgent"
  
  # Override prompt class
  prompt_class CustomerServicePrompt
  
  # Add specialized tools
  uses_tool :lookup_customer
  uses_tool :create_ticket
  uses_tool :escalate_to_human
  
  # Custom schema for customer service
  schema do
    field :customer_id, type: :string
    field :resolution, type: :string, required: true
    field :satisfaction_score, type: :integer, range: 1..5
  end
end
```

### Testing with Mock Context

```ruby
RSpec.describe CustomerServiceAgent do
  let(:agent) { CustomerServiceAgent.new }
  let(:mock_context) do
    RAAF::DSL::ContextVariables.new
      .set(:customer_id, "CUST123")
      .set(:environment, "test")
  end
  
  describe "context handling" do
    it "properly manages immutable context" do
      original_size = mock_context.size
      
      # Verify immutability - original context unchanged
      new_context = mock_context.set(:new_key, "value")
      expect(mock_context.size).to eq(original_size)
      expect(new_context.size).to eq(original_size + 1)
    end
    
    it "integrates with ObjectProxy for lazy loading" do
      proxy = RAAF::DSL::ObjectProxy.new do
        expensive_database_call
      end
      
      # Proxy doesn't execute until accessed
      expect { proxy }.not_to receive(:expensive_database_call)
      
      # Only when accessed does it execute
      expect(proxy.data).to be_present
    end
  end
end
```

TIP: Use the latest DSL features for production-ready agents with proper error handling, context management, and testing support.

Next Steps
----------

Now that you understand the modern RAAF DSL with latest features:

* **[RAAF Providers Guide](providers_guide.html)** - Use different AI providers with ResponsesProvider
* **[RAAF Memory Guide](memory_guide.html)** - Advanced context management with ObjectProxy 
* **[RAAF Testing Guide](testing_guide.html)** - Test DSL configurations with modern patterns
* **[Multi-Agent Guide](multi_agent_guide.html)** - Build complex workflows with tool-based handoffs
* **[Rails Integration](rails_guide.html)** - DSL in Rails applications with hooks and lifecycle management