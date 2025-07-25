**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf-ai.dev>.**

Getting Started with RAAF
========================

This guide covers getting up and running with Ruby AI Agents Factory (RAAF).

After reading this guide, you will know:

* How to install RAAF, create your first AI agent, and add tools
* The general layout of a RAAF application
* The basic principles of agents, runners, and multi-agent workflows
* How to add memory, monitoring, and security to your agents
* How to deploy AI agents to production

--------------------------------------------------------------------------------

Introduction
------------

Welcome to Ruby AI Agents Factory (RAAF)! In this guide, we'll walk through the core concepts of building AI agent systems with Ruby. You don't need any experience with AI agents to follow along with this guide.

Before we dive into the mechanics, let's establish a foundational understanding. Traditional software development involves writing explicit instructions for every possible scenario. AI agent development is different—you're building systems that can reason, decide, and adapt to situations you haven't explicitly programmed for.

This shift requires a different mindset. Instead of thinking "how do I handle this specific case," you think "how do I give the system enough context and tools to handle this class of problems." It's the difference between writing a script and mentoring an intern—you provide guidance, examples, and capabilities, then let the system figure out the specifics.

The challenges are real: AI systems can be unpredictable, debugging is different from traditional code, and the cost model is based on tokens rather than CPU cycles. But the opportunities are transformational—you can build systems that understand natural language, adapt to new situations, and handle complex reasoning tasks that would require massive amounts of traditional code.

RAAF is an AI agent framework built for the Ruby programming language. RAAF takes advantage of many features of Ruby so that you understand some of the basic terms and vocabulary you will see in this tutorial.

Why Ruby for AI agents? While Python dominates the AI/ML landscape, Ruby brings unique advantages to agent development:

- **Expressiveness**: Ruby's syntax mirrors natural language, making agent instructions more intuitive
- **Metaprogramming**: Ruby's dynamic nature allows for flexible tool definition and agent composition
- **Mature ecosystem**: Rails, gems, and robust libraries provide a solid foundation for production systems
- **Developer happiness**: Ruby's design philosophy aligns well with the iterative nature of AI development

RAAF chose Ruby not just for preference, but because building AI agents is fundamentally about communication and composition—areas where Ruby excels. The framework leverages Ruby's strengths while abstracting away the complexity of AI model integration.

- [Official Ruby Programming Language website](https://www.ruby-lang.org/en/documentation/)
- [List of Free Programming Books](https://github.com/EbookFoundation/free-programming-books/blob/main/books/free-programming-books-langs.md#ruby)

RAAF Philosophy
---------------

RAAF is an AI agent development framework written in the Ruby programming language. It is designed to make programming AI agents easier by making assumptions about what every developer needs to get started. It allows you to write less code while accomplishing more than many other AI frameworks. Experienced RAAF developers also report that it makes AI agent development more fun.

RAAF is opinionated software. It makes the assumption that there is a "best" way to do things, and it's designed to encourage that way - and in some cases to discourage alternatives. If you learn "The RAAF Way" you'll probably discover a tremendous increase in productivity. If you persist in bringing old habits from other AI frameworks to your RAAF development, and trying to use patterns you learned elsewhere, you may have a less happy experience.

Why does this matter? Because AI agent development is still evolving, and without strong opinions, you'll spend more time debating architecture than building solutions. RAAF's opinions aren't arbitrary—they're distilled from real-world experience with production AI systems. The framework pushes you toward patterns that are debuggable, scalable, and maintainable.

These opinions show up in subtle ways: the runner pattern separates concerns cleanly, tools are first-class citizens rather than afterthoughts, and memory management is explicit rather than hidden. Fight these patterns, and you'll find yourself writing more code to achieve less. Embrace them, and you'll discover that complex AI workflows become surprisingly straightforward.

The RAAF philosophy includes several major guiding principles:

- **Convention Over Configuration:** RAAF has opinions about the best way to build AI agents, and defaults to this set of conventions, rather than require that you define them yourself through endless configuration files. This isn't about limiting flexibility—it's about providing a solid foundation so you can focus on building features rather than infrastructure.

- **Modular Architecture:** Use only the components you need. Start with core agents and add enterprise features as you grow. This approach recognizes that AI systems evolve—what starts as a simple chatbot might become a complex multi-agent workflow. The modular design lets you add complexity gradually without architectural rewrites.

- **Provider Agnostic:** Write once, run on any AI provider. Never be locked into a single vendor. The AI landscape changes rapidly, and vendor lock-in is a real risk. RAAF's abstraction layer means you can switch from OpenAI to Claude to local models without rewriting your application logic.

- **Enterprise Ready:** Security, compliance, and monitoring are built-in from day one, not afterthoughts. Most AI frameworks treat security as a separate concern, but real-world AI systems need guardrails, audit trails, and compliance features from the start. RAAF makes these features accessible without requiring security expertise.

- **Ruby Idiomatic:** RAAF feels natural to Ruby developers with familiar patterns and conventions. You shouldn't need to learn a new programming paradigm just to build AI agents. RAAF leverages Ruby's strengths—blocks, metaprogramming, and expressive syntax—to make AI development feel like regular Ruby development.

Creating Your First Agent
--------------------------

We're going to build an AI agent called `customer_service` - a simple customer service bot that demonstrates several of RAAF's built-in features.

But first, let's understand what we're building. A customer service agent isn't just a chatbot—it's a digital employee that can understand customer problems, access relevant data, and take action. The difference between a simple Q&A bot and a true AI agent is the ability to use tools: looking up orders, processing refunds, scheduling callbacks, and escalating complex issues to humans.

This tutorial will show you how to build that capability step by step. We'll start with a basic agent, then add tools, memory, monitoring, and security. Each addition solves a real problem you'll encounter in production AI systems.

TIP: Any commands prefaced with a dollar sign `$` should be run in the terminal.

### Prerequisites

For this project, you will need:

* Ruby 3.0 or newer
* An OpenAI API key (or another supported provider key)
* A code editor

If you need to install Ruby, follow the [official Ruby installation guide](https://www.ruby-lang.org/en/documentation/installation/).

Let's verify the correct version of Ruby is installed. To display the current version, open a terminal and run the following. You should see a version number printed out:

```bash
$ ruby --version
ruby 3.2.0 (or higher)
```

The version shown should be Ruby 3.0.0 or higher.

### Installing RAAF

RAAF is distributed as Ruby gems. For this tutorial, we'll start with the core gem:

```bash
$ gem install raaf
```

If you're using Bundler in a project, add to your Gemfile:

<!-- VALIDATION_FAILED: getting_started.md:107 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:301:in 'Gem::Dependency#to_specs': Could not find 'raaf' (>= 0) among 224 total gem(s) (Gem::MissingSpecError) Checked in 'GEM_PATH=/Users/hajee/.rvm/gems/ruby-3.4.5:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/gems/3.4.0' , execute `gem env` for more information 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:313:in 'Gem::Dependency#to_spec' 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_gem.rb:56:in 'Kernel#gem' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-i6er8g.rb:444:in '<main>'
```

```ruby
gem 'raaf'
```

Then run:

```bash
$ bundle install
```

### Setting Up Your API Key

RAAF works with many AI providers. For this tutorial, we'll use OpenAI. 

**Getting an OpenAI API Key:**

If you don't have an OpenAI API key yet, you can create one by:

1. Visiting the [OpenAI API Keys page](https://platform.openai.com/api-keys)
2. Signing up for an OpenAI account if you don't have one
3. Creating a new API key from your dashboard
4. Adding billing information to your account (required for API usage)

**Why OpenAI for this tutorial?** While RAAF supports many providers, OpenAI offers the most reliable and well-documented API, making it ideal for learning. Their models are also optimized for tool usage, which is crucial for building agents that can take action rather than just chat.

**Cost considerations:** API calls cost money based on token usage. A typical conversation might cost $0.01-$0.10, but complex agent workflows with multiple tool calls can cost more. Always set usage limits in your OpenAI dashboard to avoid unexpected charges.

Once you have your API key, set it as an environment variable:

```bash
$ export OPENAI_API_KEY="your-openai-api-key-here"
```

For a more permanent setup, add this to your shell profile (`.bashrc`, `.zshrc`, etc.) or create a `.env` file:

```bash
# .env
OPENAI_API_KEY=your-openai-api-key-here
```

### Creating Your First Agent

Let's create a simple "Hello World" agent. Create a new file called `hello_agent.rb`:

```ruby
require 'raaf'

# Create a basic agent
agent = RAAF::Agent.new(
  name: "GreetingAgent",
  instructions: "You are a friendly assistant that greets users warmly.",
  model: "gpt-4o"
)

# Create a runner to execute the agent
runner = RAAF::Runner.new(agent: agent)

# Run a conversation
result = runner.run("Hello there!")
puts result.messages.last[:content]
```

Run your first agent:

```bash
$ ruby hello_agent.rb
```

You should see a friendly greeting from your AI agent!

**What just happened?** Let's break down this simple example:

1. **Agent Creation**: We defined an agent with a name, instructions, and model. The instructions are crucial—they're how you encode your domain knowledge into the AI system.

2. **Runner Pattern**: The runner acts as an execution engine. It manages the conversation state, handles API calls, and coordinates between the agent and the AI model. This separation of concerns is fundamental to RAAF's architecture.

3. **Stateless Design**: Notice that the agent itself doesn't maintain conversation state. That's the runner's job. This design choice enables you to reuse the same agent definition across multiple conversations simultaneously.

4. **Model Selection**: We chose GPT-4o, which offers excellent reasoning capabilities but costs more than GPT-4o-mini. In production, you might use different models for different tasks based on complexity and cost requirements.

### Directory Structure

When building more complex RAAF applications, we recommend organizing your code like this:

```
my_ai_app/
├── Gemfile
├── .env
├── agents/
│   ├── customer_service_agent.rb
│   ├── research_agent.rb
│   └── writer_agent.rb
├── tools/
│   ├── database_tool.rb
│   ├── email_tool.rb
│   └── weather_tool.rb
├── config/
│   ├── agent_config.rb
│   └── provider_config.rb
└── lib/
    └── my_ai_app.rb
```

Let's create this structure for our customer service agent:

```bash
$ mkdir my_ai_app
$ cd my_ai_app
$ mkdir agents tools config lib
```

Adding Your First Tool
-----------------------

Tools give agents the ability to interact with external systems. Let's create a customer lookup tool.

**Why tools matter:** This is where AI agents become truly powerful. Without tools, an AI agent is just a sophisticated chatbot—it can understand and respond, but it can't act. Tools bridge the gap between AI reasoning and real-world action.

Think of tools as the agent's hands and eyes. They allow the agent to:

- Read data from databases
- Make API calls to external services
- Perform calculations
- Send emails or notifications
- Process files
- And much more

The key insight is that you're not just building a chat interface—you're building a digital employee that can actually get things done.

Create `tools/customer_lookup_tool.rb`:

```ruby
class CustomerLookupTool
  def self.call(customer_id:)
    # In a real app, this would query your database
    customers = {
      "12345" => {
        name: "Alice Johnson",
        email: "alice@example.com",
        status: "Premium",
        orders: 15,
        last_order: "2024-01-10"
      },
      "67890" => {
        name: "Bob Smith", 
        email: "bob@example.com",
        status: "Standard",
        orders: 3,
        last_order: "2023-12-15"
      }
    }
    
    customer = customers[customer_id]
    if customer
      customer
    else
      { error: "Customer not found" }
    end
  end
end
```

Now create `agents/customer_service_agent.rb`:

<!-- VALIDATION_FAILED: getting_started.md:271 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
<internal:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_require.rb>:136:in 'Kernel#require': cannot load such file -- raaf (LoadError) 	from <internal:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_require.rb>:136:in 'Kernel#require' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-ywj7fd.rb:444:in '<main>'
```

```ruby
require 'raaf'
require_relative '../tools/customer_lookup_tool'

class CustomerServiceAgent
  def self.create
    agent = RAAF::Agent.new(
      name: "CustomerService",
      instructions: "You help customers with their inquiries. Use the customer_lookup tool to find customer information when given a customer ID.",
      model: "gpt-4o"
    )
    
    # Add the customer lookup tool
    agent.add_tool(CustomerLookupTool.method(:call))
    
    agent
  end
end
```

Create `lib/my_ai_app.rb` to tie it all together:

<!-- VALIDATION_FAILED: getting_started.md:293 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
/var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-bhxd9v.rb:444:in 'Kernel#require_relative': cannot load such file -- /private/var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/agents/customer_service_agent (LoadError) 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-bhxd9v.rb:444:in '<main>'
```

```ruby
require_relative '../agents/customer_service_agent'

class MyAIApp
  def self.run(message)
    agent = CustomerServiceAgent.create
    runner = RAAF::Runner.new(agent: agent)
    result = runner.run(message)
    puts result.messages.last[:content]
  end
end
```

Test your customer service agent:

<!-- VALIDATION_FAILED: getting_started.md:308 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
/var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-p146qy.rb:445:in 'Kernel#require_relative': cannot load such file -- /private/var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/lib/my_ai_app (LoadError) 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-p146qy.rb:445:in '<main>'
```

```ruby
# test_agent.rb
require_relative 'lib/my_ai_app'

MyAIApp.run("Hi! Can you help me look up customer ID 12345?")
```

The agent will:

1. Understand you want customer information
2. Call the `customer_lookup` tool with ID "12345"
3. Use the customer data to craft a helpful response

**What's happening under the hood:** When you mention a customer ID, the agent recognizes that it needs to look up customer information. It automatically calls the `customer_lookup` tool with the appropriate parameters, receives the structured data, and then crafts a natural language response based on that data.

This is the magic of AI agents—they can understand intent, select the right tool, and compose responses that feel natural while being grounded in real data. The agent acts as an intelligent layer between human requests and your application's functionality.

Using the DSL
-------------

RAAF includes a declarative DSL that makes agent creation more elegant. First, add the DSL gem:

**Why use the DSL?** The imperative approach works fine for simple agents, but as your agents become more complex, the DSL provides crucial advantages:

- **Declarative clarity**: Describe what the agent should do, not how to set it up
- **Composition**: Mix and match capabilities with simple directives
- **Readability**: Agent configurations read like documentation
- **Maintainability**: Changes are localized and obvious

The DSL transforms agent building from procedural setup code into expressive configuration. It's the difference between assembly instructions and a blueprint.

<!-- VALIDATION_FAILED: getting_started.md:339 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:301:in 'Gem::Dependency#to_specs': Could not find 'raaf' (>= 0) among 224 total gem(s) (Gem::MissingSpecError) Checked in 'GEM_PATH=/Users/hajee/.rvm/gems/ruby-3.4.5:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/gems/3.4.0' , execute `gem env` for more information 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:313:in 'Gem::Dependency#to_spec' 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_gem.rb:56:in 'Kernel#gem' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-79fz38.rb:445:in '<main>'
```

```ruby
# Gemfile
gem 'raaf'
```

Now rewrite your agent using the DSL:

```ruby
require 'raaf'
require_relative '../tools/customer_lookup_tool'

agent = RAAF::DSL::AgentBuilder.build do
  name "CustomerService"
  instructions "You help customers with their inquiries"
  model "gpt-4o"
  
  # Add tools
  tool :customer_lookup, &CustomerLookupTool.method(:call)
  
  # Or define tools inline
  tool :get_current_time do
    Time.now.strftime("%I:%M %p %Z on %B %d, %Y")
  end
  
  tool :escalate_to_human do |issue:|
    "Escalating issue to human agent: #{issue}"
  end
end

# Use the agent
runner = RAAF::Runner.new(agent: agent)
result = runner.run("What time is it and can you look up customer 67890?")
puts result.messages.last[:content]
```

### Using Prompts

RAAF provides a flexible prompt management system. The recommended approach is to use Ruby prompt classes for better type safety and testability:

```ruby
# Define a prompt class
class CustomerServicePrompt
  def initialize(company_name:, tone: "professional")
    @company_name = company_name
    @tone = tone
  end
  
  def system
    "You are a customer service agent for #{@company_name}. Be #{@tone} and helpful."
  end
  
  def user
    "Please help the customer with their inquiry."
  end
end

# Create prompt instance
support_prompt = CustomerServicePrompt.new(
  company_name: "ACME Corp",
  tone: "friendly"
)

# Use with DSL
agent = RAAF::DSL::AgentBuilder.build do
  name "SupportAgent"
  prompt support_prompt
  model "gpt-4o"
end

# Run
runner = RAAF::Runner.new(agent: agent)
result = runner.run("I need help with my order")
```

For simple cases, you can also use file-based prompts. See the [Prompting Guide](prompting.md) for comprehensive documentation.

Adding Memory
-------------

For conversational agents, you'll want to maintain context across multiple interactions. Add the memory gem:

**Why memory matters:** Real conversations have context. Users expect agents to remember what they've talked about, their preferences, and the current state of their problem. Without memory, every interaction starts from scratch, creating a frustrating experience.

But memory in AI systems is different from traditional application state. You're not just storing data—you're managing the context that gets sent to the AI model. This context has a token limit, so you need strategies for what to keep, what to summarize, and what to forget.

Think of memory management as curating a conversation history. You want to preserve the essential information while staying within the model's context window.

<!-- VALIDATION_FAILED: getting_started.md:426 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:301:in 'Gem::Dependency#to_specs': Could not find 'raaf' (>= 0) among 224 total gem(s) (Gem::MissingSpecError) Checked in 'GEM_PATH=/Users/hajee/.rvm/gems/ruby-3.4.5:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/gems/3.4.0' , execute `gem env` for more information 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:313:in 'Gem::Dependency#to_spec' 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_gem.rb:56:in 'Kernel#gem' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-6lja5l.rb:445:in '<main>'
```

```ruby
# Gemfile
gem 'raaf'
```

Update your application to use memory:

```ruby
require 'raaf'
require 'raaf'

class MyAIApp
  def initialize
    # Create a memory manager
    @memory_manager = RAAF::Memory::MemoryManager.new(
      store: RAAF::Memory::InMemoryStore.new,
      max_tokens: 4000
    )
    
    @agent = CustomerServiceAgent.create
  end
  
  def run(message)
    runner = RAAF::Runner.new(
      agent: @agent,
      memory_manager: @memory_manager
    )
    
    result = runner.run(message)
    puts result.messages.last[:content]
  end
end

# Usage
app = MyAIApp.new

puts "=== Turn 1 ==="
app.run("Hi, I'm Alice and I need help with my account")

puts "\n=== Turn 2 ==="
app.run("Can you look up my customer information? My ID is 12345")

puts "\n=== Turn 3 ==="
app.run("What was my last order date?")
```

The agent will remember Alice's name and customer ID across turns!

**Memory in action:** Notice how the agent maintains context across multiple interactions. It remembers Alice's name from the first turn and connects it to the customer ID in the second turn. By the third turn, it can reference Alice's specific order information without being reminded.

This is the power of intelligent memory management. The system isn't just storing raw conversation history—it's maintaining the contextual understanding that makes conversations feel natural and productive.

Adding Monitoring
-----------------

Production agents need monitoring. Add the tracing gem:

**Why monitoring is crucial:** AI systems are fundamentally different from traditional applications. You can't just monitor CPU and memory usage—you need to track token consumption, model performance, tool execution times, and conversation quality. Without proper monitoring, you're flying blind.

Monitoring AI agents involves several dimensions:

- **Performance**: Response times, token usage, and API latency
- **Quality**: Are responses relevant and helpful?
- **Reliability**: Are tools working correctly?
- **Cost**: Token consumption can add up quickly
- **Security**: Are there unusual patterns that might indicate problems?

RAAF's tracing system captures all these dimensions, giving you visibility into how your AI system is actually performing in production.

<!-- VALIDATION_FAILED: getting_started.md:495 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:301:in 'Gem::Dependency#to_specs': Could not find 'raaf' (>= 0) among 224 total gem(s) (Gem::MissingSpecError) Checked in 'GEM_PATH=/Users/hajee/.rvm/gems/ruby-3.4.5:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/gems/3.4.0' , execute `gem env` for more information 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:313:in 'Gem::Dependency#to_spec' 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_gem.rb:56:in 'Kernel#gem' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-ztvto2.rb:445:in '<main>'
```

```ruby
# Gemfile
gem 'raaf'
```

Set up monitoring:

<!-- VALIDATION_FAILED: getting_started.md:502 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
<internal:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_require.rb>:136:in 'Kernel#require': cannot load such file -- raaf (LoadError) 	from <internal:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_require.rb>:136:in 'Kernel#require' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-4pqdhx.rb:444:in '<main>'
```

```ruby
require 'raaf'
require 'raaf'

class MyAIApp
  def initialize
    # Set up comprehensive tracing
    @tracer = RAAF::Tracing::SpanTracer.new
    @tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new)
    
    # Optionally send to OpenAI dashboard (requires additional setup)
    # @tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)
    
    @memory_manager = RAAF::Memory::MemoryManager.new(
      store: RAAF::Memory::InMemoryStore.new,
      max_tokens: 4000
    )
    
    @agent = CustomerServiceAgent.create
  end
  
  def run(message)
    runner = RAAF::Runner.new(
      agent: @agent,
      memory_manager: @memory_manager,
      tracer: @tracer
    )
    
    result = runner.run(message)
    puts result.messages.last[:content]
  end
end
```

Now you'll see detailed trace information in your console, including:

- Token usage
- Tool calls
- Response times
- Error information

**Understanding the trace data:** Each trace entry tells a story about your agent's behavior. High token usage might indicate inefficient prompts or excessive context. Slow tool calls could reveal API bottlenecks. Error patterns help you identify reliability issues before they become customer problems.

This observability is your feedback loop for improving agent performance. You might discover that certain tools are called too frequently, that some conversations consume excessive tokens, or that specific user patterns trigger errors. This data drives optimization decisions.

Adding Security
---------------

For production use, add security guardrails:

**Why security is non-negotiable:** AI systems face unique security challenges. Traditional input validation isn't enough when dealing with natural language that can contain prompt injections, PII, or malicious content. AI models can be tricked into ignoring their instructions or revealing sensitive information.

Guardrails are your safety net. They filter inputs and outputs to:

- Detect and block prompt injection attempts
- Redact personally identifiable information (PII)
- Flag toxic or inappropriate content
- Ensure compliance with regulations like GDPR or HIPAA

Think of guardrails as security middleware for AI. They run before and after the AI model, ensuring that dangerous content never reaches the model and that problematic responses never reach users.

<!-- VALIDATION_FAILED: getting_started.md:563 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:301:in 'Gem::Dependency#to_specs': Could not find 'raaf' (>= 0) among 224 total gem(s) (Gem::MissingSpecError) Checked in 'GEM_PATH=/Users/hajee/.rvm/gems/ruby-3.4.5:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/gems/3.4.0' , execute `gem env` for more information 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:313:in 'Gem::Dependency#to_spec' 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_gem.rb:56:in 'Kernel#gem' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-os6oht.rb:445:in '<main>'
```

```ruby
# Gemfile
gem 'raaf'
```

Set up security:

```ruby
require 'raaf'
require 'raaf'

class MyAIApp
  def initialize
    # Set up security guardrails
    @guardrails = RAAF::ParallelGuardrails.new([
      RAAF::Guardrails::PIIDetector.new(action: :redact),
      RAAF::Guardrails::SecurityGuardrail.new(action: :block)
    ])
    
    @tracer = RAAF::Tracing::SpanTracer.new
    @tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new)
    
    @memory_manager = RAAF::Memory::MemoryManager.new(
      store: RAAF::Memory::InMemoryStore.new,
      max_tokens: 4000
    )
    
    @agent = CustomerServiceAgent.create
  end
  
  def run(message)
    runner = RAAF::Runner.new(
      agent: @agent,
      memory_manager: @memory_manager,
      tracer: @tracer,
      guardrails: @guardrails
    )
    
    result = runner.run(message)
    puts result.messages.last[:content]
  end
end

# Test with PII - it will be automatically redacted
app = MyAIApp.new
app.run("My social security number is 123-45-6789 and I need help")
# The SSN will be redacted as "[REDACTED]" before being processed

**Security in action:** When you run this example, the guardrails will detect the Social Security Number and automatically redact it before the content reaches the AI model. The agent will receive the sanitized version: "My social security number is [REDACTED] and I need help."

This protection works both ways—if the AI model somehow generates PII in its response, the guardrails will catch and redact it before it reaches the user. This defense-in-depth approach ensures that sensitive information is protected at every stage of processing.
```

Multi-Agent Workflows
---------------------

One of RAAF's most powerful features is multi-agent workflows. Let's create a research and writing system:

**Why multiple agents?** Complex tasks often require different types of thinking. A research agent needs to be thorough and analytical. A writing agent needs to be creative and engaging. An editing agent needs to be critical and precise.

Instead of trying to build one super-agent that does everything mediocrely, you build specialized agents that excel at specific tasks and coordinate between them. This approach mirrors how human teams work—different people with different strengths collaborating to achieve a common goal.

Multi-agent workflows also provide natural checkpoints. Each handoff is an opportunity to review progress, change direction, or involve human oversight. This makes complex workflows more reliable and debuggable.

```ruby
require 'raaf'

# Create specialized agents
research_agent = RAAF::Agent.new(
  name: "Researcher",
  instructions: "You research topics thoroughly and provide detailed information. When your research is complete, hand off to the Writer to create content.",
  model: "gpt-4o"
)

writer_agent = RAAF::Agent.new(
  name: "Writer",
  instructions: "You write engaging content based on research provided to you. Keep it concise and compelling.",
  model: "gpt-4o"
)

# Set up handoffs between agents
research_agent.add_handoff(writer_agent)

# Create runner with multiple agents
runner = RAAF::Runner.new(
  agent: research_agent,  # Starting agent
  agents: [research_agent, writer_agent]
)

result = runner.run("Write a brief article about the benefits of Ruby programming")
puts result.messages.last[:content]

# The research agent will gather information, then automatically hand off to the writer

**Handoff mechanics:** The research agent doesn't just dump information and disappear. It actively decides when its work is complete and hands off to the writer with context intact. The writer receives not just the user's original request, but also all the research findings and context from the first agent.

This creates a seamless workflow where each agent builds on the previous agent's work, resulting in output that's better than any single agent could produce alone.
```

Using Different Providers
--------------------------

RAAF works with many AI providers. Add the providers gem:

**Provider diversity strategy:** The AI landscape is rapidly evolving. New models appear regularly, pricing changes, and different providers excel at different tasks. Being locked into a single provider is a significant business risk.

RAAF's provider abstraction means you can:

- Use the best model for each specific task
- Switch providers if pricing or availability changes
- Test new models without rewriting your application
- Implement fallback strategies for reliability

This flexibility isn't theoretical—it's practical insurance against vendor lock-in and changing market conditions.

**Important Note on Provider Switching**: While RAAF makes it technically easy to switch providers, each AI model behaves differently. The same prompt that works perfectly with one provider might produce completely different results with another. **ALWAYS** test your entire application thoroughly after switching providers, as you may need to adjust prompts, parameters, and even your agent's logic to accommodate the new model's behavior patterns.

<!-- VALIDATION_FAILED: getting_started.md:680 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:301:in 'Gem::Dependency#to_specs': Could not find 'raaf-core' (>= 0) among 224 total gem(s) (Gem::MissingSpecError) Checked in 'GEM_PATH=/Users/hajee/.rvm/gems/ruby-3.4.5:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/gems/3.4.0' , execute `gem env` for more information 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:313:in 'Gem::Dependency#to_spec' 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_gem.rb:56:in 'Kernel#gem' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-8smgqt.rb:445:in '<main>'
```

```ruby
# Gemfile
gem 'raaf-core'
```

Use Anthropic's Claude:

```ruby
require 'raaf'
require 'raaf-providers'

# Set your Anthropic API key
ENV['ANTHROPIC_API_KEY'] = 'your-anthropic-key'

# Create Claude agent
agent = RAAF::Agent.new(
  name: "ClaudeAgent",
  instructions: "You are Claude, a helpful AI assistant.",
  model: "claude-3-5-sonnet-20241022"
)

runner = RAAF::Runner.new(agent: agent)
result = runner.run("What makes you different from other AI assistants?")
puts result.messages.last[:content]
```

Or use Groq for high-speed inference:

```ruby
# Set your Groq API key
ENV['GROQ_API_KEY'] = 'your-groq-key'

agent = RAAF::Agent.new(
  name: "FastAgent",
  instructions: "You provide quick, helpful responses.",
  model: "mixtral-8x7b-32768"  # Groq model
)
```

Building for Production
-----------------------

For production environments, create a comprehensive setup:

**Production readiness:** The gap between a demo and a production AI system is enormous. Production systems need security, compliance, monitoring, error handling, and scalability considerations that demos can ignore.

This comprehensive setup demonstrates the enterprise features that separate toy projects from production systems. Each component addresses a specific production concern:

- **Compliance**: Meet regulatory requirements (GDPR, HIPAA, SOC2)
- **Security**: Protect against AI-specific threats and data breaches  
- **Monitoring**: Track performance, costs, and quality metrics
- **Memory**: Handle long conversations and context management
- **Streaming**: Provide responsive user experiences
- **Rails integration**: Work within existing application architectures

Building these features from scratch would take months. RAAF provides them as composable modules you can add as needed.

<!-- VALIDATION_FAILED: getting_started.md:737 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:301:in 'Gem::Dependency#to_specs': Could not find 'raaf' (>= 0) among 224 total gem(s) (Gem::MissingSpecError) Checked in 'GEM_PATH=/Users/hajee/.rvm/gems/ruby-3.4.5:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/gems/3.4.0' , execute `gem env` for more information 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:313:in 'Gem::Dependency#to_spec' 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_gem.rb:56:in 'Kernel#gem' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-wzjqb.rb:445:in '<main>'
```

```ruby
# Gemfile
gem 'raaf'
```

Production configuration:

<!-- VALIDATION_FAILED: getting_started.md:744 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
<internal:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_require.rb>:136:in 'Kernel#require': cannot load such file -- raaf (LoadError) 	from <internal:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_require.rb>:136:in 'Kernel#require' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-tu811f.rb:444:in '<main>'
```

```ruby
require 'raaf'
require 'raaf'
require 'raaf'
require 'raaf'

class ProductionAIApp
  def initialize
    # Enterprise compliance
    @compliance = RAAF::Compliance::Manager.new(
      frameworks: [:gdpr, :hipaa, :soc2],
      policy_enforcement: :strict
    )
    
    # Comprehensive security
    @guardrails = RAAF::ParallelGuardrails.new([
      RAAF::Guardrails::PIIDetector.new(action: :redact),
      RAAF::Guardrails::SecurityGuardrail.new(action: :block),
      RAAF::Guardrails::ToxicityDetector.new(action: :flag)
    ])
    
    # Production monitoring
    @tracer = RAAF::Tracing::SpanTracer.new
    @tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)
    @tracer.add_processor(RAAF::Tracing::DatadogProcessor.new)
    
    # Persistent memory with vector search
    @memory_manager = RAAF::Memory::MemoryManager.new(
      store: RAAF::Memory::VectorStore.new,
      max_tokens: 8000,
      pruning_strategy: :semantic_similarity
    )
    
    @agent = create_production_agent
  end
  
  private
  
  def create_production_agent
    RAAF::DSL::AgentBuilder.build do
      name "ProductionAgent"
      instructions "You are a production AI assistant with enterprise features"
      model "gpt-4o"
      
      # Add production tools
      use_web_search
      use_file_search
      
      tool :database_lookup do |query:|
        # Production database integration
        DatabaseService.query(query)
      end
      
      tool :send_email do |to:, subject:, body:|
        # Production email service
        EmailService.send(to: to, subject: subject, body: body)
      end
    end
  end
end
```

Next Steps
----------

Congratulations! You now have a solid foundation in RAAF. Here's what to explore next:

### Core Concepts

* **[RAAF Architecture](core_guide.html)** - Deep dive into agents, runners, and the execution model
* **[Tool System](tools_guide.html)** - Build powerful integrations with external systems
* **[Structured Outputs](structured_outputs.html)** - Ensure type-safe responses

### Advanced Features  

* **[Multi-Agent Workflows](multi_agent_guide.html)** - Build sophisticated agent orchestration
* **[Memory Management](memory_guide.html)** - Advanced context and persistence strategies
* **[Provider Integration](providers_guide.html)** - Use different AI providers and routing

### Enterprise

* **[Security & Guardrails](raaf_guardraaf_guide.html)** - Protect your AI systems
* **[Monitoring & Tracing](tracing_guide.html)** - Comprehensive observability
* **[Compliance](compliance_guide.html)** - GDPR, HIPAA, and SOC2 compliance

### Integration

* **[Rails Integration](rails_guide.html)** - Add AI to your Rails applications
* **[Streaming & Async](streaming_guide.html)** - Real-time and background processing
* **[Testing](testing_guide.html)** - Test your AI agents effectively

### Configuration and Monitoring

* **[Configuration Reference](configuration_reference.html)** - Production configuration patterns
* **[Monitoring Guide](tracing_guide.html)** - Observability and monitoring
* **[Performance Tuning](performance_guide.html)** - Optimize for scale
* **[Monitoring Setup](monitoring_setup.html)** - Production monitoring configuration

Common Patterns
----------------

### Customer Service Bot
<!-- VALIDATION_FAILED: getting_started.md:846 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant OrderService /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-xv8t9o.rb:449:in 'block in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-xv8t9o.rb:139:in 'BasicObject#instance_eval' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-xv8t9o.rb:139:in 'RAAF::DSL::AgentBuilder.build'
```

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "CustomerService"
  instructions "Help customers with orders and account issues"
  model "gpt-4o"
  
  tool :lookup_order, &OrderService.method(:find)
  tool :update_account, &AccountService.method(:update)
  tool :escalate_to_human, &SupportService.method(:escalate)
end
```

### Data Analysis Agent
<!-- VALIDATION_FAILED: getting_started.md:859 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant DataService /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-dvu5yg.rb:451:in 'block in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-dvu5yg.rb:139:in 'BasicObject#instance_eval' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-dvu5yg.rb:139:in 'RAAF::DSL::AgentBuilder.build'
```

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "DataAnalyst"
  instructions "Analyze data and provide insights"
  model "gpt-4o"
  
  use_code_interpreter  # For running Python/R code
  
  tool :query_database, &DataService.method(:query)
  tool :generate_chart, &ChartService.method(:create)
end
```

### Content Creation Workflow
<!-- VALIDATION_FAILED: getting_started.md:873 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
ruby: /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-pohxfm.rb:445: syntax errors found (SyntaxError)   443 |   # Guide code starts here   444 |   # Research → Write → Review workflow > 445 | ... )       |     ^ unexpected ')'; expected a value in the hash literal       |     ^ expected a `=>` between the hash key and value       |     ^ unexpected ')'; expected an expression after the operator > 446 | ... )       |     ^ unexpected ')'; expected a value in the hash literal       |     ^ expected a `=>` between the hash key and value       |     ^ unexpected ')'; expected an expression after the operator > 447 | ... )       |     ^ unexpected ')'; expected a value in the hash literal       |     ^ expected a `=>` between the hash key and value       |     ^ unexpected ')'; expected an expression after the operator   448 |    449 | research_agent.add_handoff(writer_agent)
```

```ruby
# Research → Write → Review workflow
research_agent = RAAF::Agent.new(name: "Researcher", ...)
writer_agent = RAAF::Agent.new(name: "Writer", ...)
editor_agent = RAAF::Agent.new(name: "Editor", ...)

research_agent.add_handoff(writer_agent)
writer_agent.add_handoff(editor_agent)
```

Troubleshooting
---------------

### Common Issues

**"No API key found"**
```bash
# Check if your key is set
echo $OPENAI_API_KEY

# If empty, set it
export OPENAI_API_KEY="your-key-here"
```

**"Model not found"**  
Make sure you're using a valid model name:
<!-- VALIDATION_FAILED: getting_started.md:899 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
ruby: /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-idjw7j.rb:445: syntax errors found (SyntaxError)   443 |   # Guide code starts here   444 |   # OpenAI models > 445 | "gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo"       |         ^ unexpected ',', ignoring it       |         ^ unexpected ',', expecting end-of-input       |                        ^ unexpected ',', ignoring it       |                        ^ unexpected ',', expecting end-of-input   446 |    447 | # Anthropic models > 448 | "claude-3-5-sonnet-20241022", "claude-3-opus-20240229"       |                             ^ unexpected ',', ignoring it       |                             ^ unexpected ',', expecting end-of-input   449 |    450 | # Groq models   > 451 | "mixtral-8x7b-32768", "llama3-70b-8192"       |                     ^ unexpected ',', ignoring it       |                     ^ unexpected ',', expecting end-of-input   452 |    453 |
```

```ruby
# OpenAI models
"gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo"

# Anthropic models
"claude-3-5-sonnet-20241022", "claude-3-opus-20240229"

# Groq models  
"mixtral-8x7b-32768", "llama3-70b-8192"
```

**Memory issues with long conversations**
```ruby
memory_manager = RAAF::Memory::MemoryManager.new(
  store: RAAF::Memory::InMemoryStore.new,
  max_tokens: 4000,  # Adjust for your model
  pruning_strategy: :sliding_window
)
```

**Slow tool execution**
<!-- VALIDATION_FAILED: getting_started.md:920 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::ParallelGuardrails /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-2jge76.rb:445:in '<main>'
```

```ruby
# Use parallel guardrails for better performance
guardrails = RAAF::ParallelGuardrails.new([
  RAAF::Guardrails::PIIDetector.new,
  RAAF::Guardrails::SecurityGuardrail.new
])
```

### Getting Help

* **[API Documentation](api_reference.html)** - Complete API reference
* **[Troubleshooting Guide](troubleshooting.html)** - Common issues and solutions
* **[Examples Repository](https://github.com/raaf-ai/raaf/tree/main/examples)** - Working code examples
* **[Community Forum](https://discuss.raaf-ai.dev)** - Get help from the community

You're now ready to build sophisticated AI agent systems with RAAF! Start simple and gradually add more advanced features as your needs grow.