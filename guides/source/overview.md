**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf-ai.dev>.**

Ruby AI Agents Factory (RAAF) Overview
==========================================

Ruby AI Agents Factory (RAAF) is a comprehensive, enterprise-grade [Ruby](https://www.ruby-lang.org/) framework for building sophisticated multi-agent AI workflows. It provides 100% feature parity with [OpenAI's Python Agents SDK](https://openai.github.io/openai-agents-python/) while adding production-ready capabilities including multi-provider support, advanced security, compliance frameworks, and Rails integration.

After reading this guide, you will know:

* What RAAF is and how it compares to other AI frameworks
* The core architecture and philosophy behind RAAF
* Key components and their responsibilities
* How to get started with basic agent development
* Enterprise features for production deployments
* The roadmap and future direction of RAAF

--------------------------------------------------------------------------------

What is RAAF?
-------------

RAAF transforms [Ruby](https://www.ruby-lang.org/) into a first-class language for AI agent development. Unlike simple chatbot frameworks, RAAF provides a complete toolkit for building production-grade AI systems that can:

* Orchestrate multiple specialized agents working together
* Integrate with 100+ different AI providers (OpenAI, Anthropic, Cohere, Groq, etc.)
* Maintain enterprise-grade security and compliance (GDPR, HIPAA, SOC2)
* Scale from simple chatbots to complex multi-agent workflows
* Monitor and analyze AI system performance in real-time

Core Philosophy
---------------

When we started building RAAF, we asked ourselves: "What if AI agents were as easy to build and deploy as Rails applications?" This question shaped everything that followed.

The AI development landscape presents many challenges: rapidly evolving APIs, vendor lock-in concerns, security requirements, and the complexity of building reliable systems. RAAF aims to address these challenges.

RAAF is built on several key principles that address these real-world challenges:

### Modular Architecture: Start Small, Scale When Ready

Remember when you first learned Rails? You didn't need to understand every component on day one. RAAF works the same way.

Many AI frameworks require adopting their entire ecosystem from the start. RAAF takes a different approach - you can start with a simple agent and add capabilities as your needs grow. RAAF provides a coherent set of loosely coupled gems:

<!-- VALIDATION_FAILED: overview.md:46 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
<internal:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_require.rb>:136:in 'Kernel#require': cannot load such file -- raaf (LoadError) 	from <internal:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_require.rb>:136:in 'Kernel#require' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-y0tj84.rb:445:in '<main>'
```

```ruby
# Minimal setup
require 'raaf'

# Full enterprise stack
require 'raaf'
```

This isn't about being minimal for minimalism's sake. It's about respecting your time and cognitive load. Every unnecessary dependency is a potential security vulnerability, a performance bottleneck, and another thing to understand. Start with `raaf`, get something working, then add what you actually need.

The modular approach also means faster deployments. A simple chatbot doesn't need compliance frameworks. A proof-of-concept doesn't need enterprise guardrails. But when you do need them, they're designed to slot in seamlessly without rewriting your existing code.

### Provider Agnostic: Your Insurance Against the Future

Consider this scenario: You build your entire product on GPT-4, and then OpenAI doubles their prices. Or worse, they deprecate the model you're using. This has happened before in the AI space.

Provider lock-in isn't just a technical problem—it's a business risk. RAAF's provider abstraction isn't about being clever with interfaces. It's about protecting your investment. Write your agent logic once, and run it on any AI provider:

```ruby
# Works with OpenAI
agent = RAAF::Agent.new(model: "gpt-4o")

# Switch to Anthropic with no code changes
agent = RAAF::Agent.new(model: "claude-3-5-sonnet-20241022")

# Or use LiteLLM for broad provider access
agent = RAAF::Agent.new(model: "bedrock/claude-3")
```

Notice what's missing? No provider-specific configuration. No adapter classes. No factory patterns. Just change the model name and everything else stays the same. Your tools work. Your conversation history works. Your monitoring works.

This design can potentially save significant migration costs. When [Anthropic](https://www.anthropic.com) releases a new model that's better for your use case, switching can take minutes, not months. When you need to run sensitive operations on-premise, the same code works with local models.

### Ruby Idiomatic: Because Context Switching Kills Productivity

Many AI frameworks feel disconnected from Ruby development patterns. They often force you to think in Python patterns, or invent their own DSLs that feel unfamiliar to Rubyists.

We believe your AI code should feel like Ruby code. Why? Because context switching between "AI mode" and "Ruby mode" slows you down. When everything feels familiar, you can focus on solving problems instead of translating concepts.

RAAF embraces Ruby's strengths—blocks, metaprogramming, and expressive syntax:

```ruby
# Declarative DSL
agent = RAAF::DSL::AgentBuilder.build do
  name "CustomerService"
  instructions "Help customers with their inquiries"
  model "gpt-4o"
  
  use_web_search
  use_file_search
  
  tool :lookup_order do |order_id|
    Order.find(order_id)
  end
end
```

Look at that code. It reads like a specification, not an implementation. That's intentional. Ruby's block syntax naturally maps to the declarative nature of agent configuration. The DSL isn't a separate language you need to learn—it's just Ruby methods and blocks arranged in a way that makes sense.

But here's the real magic: this agent is fully functional. Those tool definitions? They're just Ruby methods. That web search capability? It's a pre-built module you can use or replace. Everything composes naturally because it's all just Ruby objects following familiar patterns.

### Enterprise Ready: Because "It Works on My Machine" Isn't Good Enough

Here's what usually happens: You build a cool AI prototype. It demos well. Everyone's excited. Then someone asks, "Is it GDPR compliant? How do we monitor token usage? What happens when the AI starts hallucinating customer data?"

Suddenly your neat little prototype needs a complete rewrite.

This cycle is common in AI development. That's why RAAF includes production features from day one. Not as afterthoughts or plugins, but as first-class citizens in the framework.

#### The Hidden Costs of "Simple" AI Frameworks

Most AI frameworks show you this:

<!-- VALIDATION_FAILED: overview.md:119 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: undefined local variable or method 'ai' for main /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-rbbf5w.rb:444:in '<main>'
```

```ruby
response = ai.complete("Hello, how are you?")
```

Looks simple, right? But what they don't show you is what happens in production:

- How do you track costs when your AI bill hits $50k/month?
- What happens when the AI leaks sensitive customer data?
- How do you debug when responses suddenly become nonsensical?
- Where are the audit logs when compliance asks what the AI said six months ago?
- How do you handle rate limits, timeouts, and service outages?

These aren't edge cases. They're Tuesday.

#### Production Features That Actually Matter

Here's what RAAF gives you out of the box:

```ruby
# 1. Comprehensive Monitoring - Know Everything, Always
tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)  # Real-time dashboard
tracer.add_processor(RAAF::Tracing::DatadogProcessor.new)  # Your existing APM
tracer.add_processor(RAAF::Tracing::S3Processor.new)      # Long-term storage

# 2. Security Guardrails - Sleep Well at Night
guardrails = RAAF::ParallelGuardrails.new([
  RAAF::Guardrails::PIIDetector.new(        # Catches SSNs, credit cards, etc.
    redact: true,                           # Auto-redact sensitive data
    alert_on_detection: true                # Notify security team
  ),
  RAAF::Guardrails::SecurityGuardrail.new(  # Blocks prompt injection
    block_code_execution: true,             # No arbitrary code
    sanitize_outputs: true                  # Clean responses
  ),
  RAAF::Guardrails::CostGuardrail.new(      # Prevent bill shock
    max_tokens_per_request: 4000,
    max_cost_per_hour: 100.00,
    alert_at_percentage: 80
  )
])

# 3. Compliance Frameworks - Pass Your Audits
compliance = RAAF::Compliance::Manager.new(
  frameworks: [:gdpr, :hipaa, :soc2],
  audit_mode: true,                         # Log everything for auditors
  retention_days: 365,                      # Keep logs for a year
  encryption: :aes_256_gcm                  # Encrypt at rest
)

# 4. Resilience Patterns - Stay Online
runner = RAAF::Runner.new(
  agent: agent,
  tracer: tracer,
  guardrails: guardrails,
  compliance: compliance,
  
  # Circuit breakers for each provider
  circuit_breaker: {
    failure_threshold: 5,       # 5 failures triggers circuit
    timeout: 30,                # Reset after 30 seconds
    half_open_requests: 3       # Test with 3 requests
  },
  
  # Automatic retries with exponential backoff
  retry_config: {
    max_attempts: 3,
    base_delay: 1,              # Start with 1 second
    max_delay: 16,              # Cap at 16 seconds
    jitter: true                # Avoid thundering herd
  },
  
  # Request queuing for rate limits
  queue_config: {
    max_size: 1000,             # Buffer up to 1000 requests
    overflow: :reject,          # Reject when full
    priority_field: :customer_tier  # VIP customers first
  }
)
```

#### What This Actually Means for You

**Monitoring**: Every request, response, tool call, and error is tracked. When your CEO asks "Why did our AI costs triple last week?", you can show them exactly which features drove the increase. The traces integrate with your existing monitoring stack—no need to learn new tools.

**Security**: The guardrails run in parallel (fast) and catch problems before they reach users. That SSN that accidentally got into a prompt? Redacted. That clever user trying prompt injection? Blocked. That recursive loop that would cost $10k? Stopped.

**Compliance**: Full audit trails with encryption. When GDPR auditors show up, you can prove data handling compliance. When HIPAA asks about health information, you have the logs. When SOC2 wants security controls, they're already implemented.

**Resilience**: Providers fail. Networks hiccup. Rate limits hit. Your app keeps running. Circuit breakers prevent cascade failures. Retries handle transient errors. Queues smooth out traffic spikes. These patterns address common failure scenarios in distributed systems.

#### Common AI System Scenarios

**The $47,000 Monday Morning**

```ruby
# Without RAAF: A bug causes infinite recursion
loop do
  response = ai.complete(response)  # Oops, feeding output back as input
end
# Result: $47,000 bill before anyone notices

# With RAAF: Cost guardrails kick in
RAFF::Guardrails::CostGuardrail.new(max_cost_per_hour: 100)
# Result: Stops at $100, alerts team, saves $46,900
```

**The GDPR Nightmare**

```ruby
# Without RAAF: Customer data leaks into training
ai.complete("Summarize user John Smith, SSN 123-45-6789...")
# Result: GDPR violation, potential €20M fine

# With RAAF: PII detected and blocked
RAFF::Guardrails::PIIDetector.new(redact: true)
# Result: "Summarize user [REDACTED], SSN [REDACTED]..."
```

**The 3 AM Outage**

<!-- VALIDATION_FAILED: overview.md:240 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: undefined local variable or method 'openai' for main /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-i3htlp.rb:445:in '<main>'
```

```ruby
# Without RAAF: OpenAI goes down
response = openai.complete(prompt)  # Throws exception
# Result: Your entire app is down

# With RAAF: Automatic failover
runner.run(prompt)  # Seamlessly switches to Anthropic
# Result: Users never notice
```

These scenarios are based on common challenges encountered in AI system development. RAAF's safeguards are designed to address these well-known issues.

### Production-First Design

We believe the best time to think about production is before you write your first line of code. That's why even our simplest examples include proper error handling, timeouts, and monitoring hooks. It's why our documentation covers failure modes, not just happy paths.

This philosophy extends to our architecture decisions:

- **Stateless by default**: Agents don't hold state between requests unless explicitly configured
- **Timeout everything**: Every API call, every tool execution, every operation has configurable timeouts
- **Fail gracefully**: When providers go down (and they will), your application degrades gracefully
- **Monitor everything**: If you can't measure it, you can't improve it

The goal isn't to overwhelm you with complexity. It's to provide a foundation designed with production considerations in mind.

## Architecture Overview

RAAF consists of 13 gems organized into focused components:

### Core Components

* **[Core](core_guide.html)** - Essential agent runtime and execution engine
* **[DSL](dsl_guide.html)** - Declarative configuration DSL
* **[Providers](providers_guide.html)** - Multi-provider support for 100+ LLMs

### Capabilities

* **[Tools](tools_guide.html)** - Comprehensive tool ecosystem
* **[Memory](memory_guide.html)** - Memory management and context persistence
* **Streaming** (integrated in core) - Real-time streaming and async processing via [streaming guide](streaming_guide.html)

### Enterprise Features

* **[Guardrails](guardrails_guide.html)** - Security and safety guardrails
* **[Compliance](compliance_guide.html)** - Enterprise compliance (GDPR, HIPAA, SOC2)
* **[Tracing](tracing_guide.html)** - Comprehensive monitoring with Python SDK compatibility

### Integration & Development

* **[Rails](rails_guide.html)** - Rails integration with web dashboard
* **[Testing](testing_guide.html)** - Testing utilities and mocks
* **Debug** - Interactive debugging and profiling tools
* **Analytics** - Usage tracking and analytics
* **Misc** - Extensions including multimodal, voice workflow, and data pipeline features
* **MCP** - Model Context Protocol support

## Quick Start Example

Here's a complete working example that demonstrates RAAF's power:

```ruby
require 'raaf'

# Create a customer service agent with tools
agent = RAAF::Agent.new(
  name: "CustomerService",
  instructions: "Help customers with order inquiries and product questions",
  model: "gpt-4o"
)

# Add a custom tool
def lookup_order(order_id)
  # Simulate database lookup
  {
    id: order_id,
    status: "shipped",
    tracking: "1Z999AA1012345675",
    estimated_delivery: "2024-01-15"
  }
end

agent.add_tool(method(:lookup_order))

# Set up monitoring and security
tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new)

guardrails = RAAF::ParallelGuardrails.new([
  RAAF::Guardrails::PIIDetector.new(action: :redact)
])

# Create runner with all features
runner = RAAF::Runner.new(
  agent: agent,
  tracer: tracer,
  guardrails: guardrails
)

# Have a conversation
result = runner.run("Hi! Can you help me check the status of order #12345?")
puts result.messages.last[:content]

# The agent will:
# 
# 1. Understand the request
# 2. Call the lookup_order tool with "12345"
# 3. Format a helpful response with the order status
# 4. Log everything for monitoring
# 5. Redact any PII that might have been included
```

## Key Benefits

### For Developers

* **Familiar Ruby patterns** - No need to learn new paradigms
* **Rich ecosystem** - Leverage existing Ruby gems
* **Excellent tooling** - RSpec integration, debugging tools, Rails support
* **Comprehensive documentation** - Guides, API docs, and examples

### For Enterprises

* **Security first** - Built-in guardrails and compliance frameworks
* **Monitoring ready** - Real-time tracing and analytics
* **Scalable architecture** - From prototype to production
* **Multi-provider support** - Never be locked into one AI provider

### For AI Systems

* **Multi-agent workflows** - Specialized agents working together
* **Structured outputs** - Type-safe responses across all providers
* **Memory management** - Intelligent context handling
* **Tool integration** - Seamless connection to external systems

## What's Next?

* **[Getting Started](getting_started.html)** - Set up your first RAAF agent
* **[Core Concepts](core_guide.html)** - Understand agents, runners, and tools
* **[Multi-Agent Workflows](multi_agent_guide.html)** - Build sophisticated agent systems
* **[Enterprise Features](enterprise_guide.html)** - Security, compliance, and monitoring
* **[Rails Integration](rails_guide.html)** - Add AI to your Rails applications

## Community and Support

* **GitHub Repository**: [https://github.com/raaf-ai/raaf](https://github.com/raaf-ai/raaf)
* **Documentation**: [https://raaf-ai.dev](https://raaf-ai.dev)
* **Community Forum**: [https://discuss.raaf-ai.dev](https://discuss.raaf-ai.dev)

RAAF makes Ruby a first-class language for AI agent development. Whether you're building a simple chatbot or a complex multi-agent system, RAAF provides the tools, security, and scalability you need to succeed.