---
title: Prompt Management Guide
description: Learn how to create, manage, and use prompts effectively in RAAF
keywords: prompts, templates, ruby, markdown, erb, phlex
---

# Prompt Management Guide

RAAF provides a powerful and flexible prompt management system through the DSL module. This guide covers everything you need to know about creating, managing, and using prompts in your AI agents.

## Overview

The RAAF prompt system supports multiple formats for defining prompts:

1. **Ruby Classes (Recommended)** - Type-safe, testable prompt classes with validation
2. **Markdown Files** - Simple text files with variable interpolation
3. **ERB Templates** - Full Ruby templating with helper methods

## Why Use the Prompt System?

- **Consistency**: Maintain consistent prompts across your application
- **Reusability**: Define prompts once, use them anywhere
- **Validation**: Ensure required context variables are provided
- **Testing**: Write tests for your prompts like any other Ruby code
- **Version Control**: Track prompt changes in your repository
- **Dynamic Content**: Generate prompts based on runtime conditions

## Ruby Prompt Classes (Recommended)

Ruby prompt classes are the preferred way to define prompts in RAAF. They provide type safety, validation, and full IDE support.

### Basic Prompt Class

```ruby
class CustomerServicePrompt < RAAF::DSL::Prompts::Base
  # Define required variables
  requires :company_name, :issue_type
  
  # Define optional variables with defaults
  optional :tone, default: "professional"
  optional :language, default: "English"
  
  def system
    <<~SYSTEM
      You are a customer service representative for #{@company_name}.
      Your tone should be #{@tone} and helpful.
      Respond in #{@language}.
    SYSTEM
  end
  
  def user
    "Customer has a #{@issue_type} issue that needs resolution."
  end
end
```

### Using Ruby Prompts

```ruby
# With an agent
agent = RAAF::DSL::AgentBuilder.build do
  name "SupportAgent"
  prompt CustomerServicePrompt
  model "gpt-4o"
end

# Run with context
result = agent.run("Help me with my order") do
  context_variable :company_name, "ACME Corp"
  context_variable :issue_type, "shipping"
  context_variable :tone, "friendly"
end
```

### Advanced Prompt Features

```ruby
class AnalysisPrompt < RAAF::DSL::Prompts::Base
  requires :data_type, :metrics
  optional :format, default: "detailed"
  
  # Add metadata
  def prompt_id
    "analysis-v2"
  end
  
  def version
    "2.0.0"
  end
  
  # Dynamic content based on conditions
  def system
    base = "You are a data analyst specializing in #{@data_type} analysis."
    
    if @format == "detailed"
      base += "\nProvide comprehensive analysis with visualizations."
    else
      base += "\nProvide concise summary points."
    end
    
    base
  end
  
  # Use Ruby logic for complex prompts
  def user
    <<~USER
      Analyze the following metrics:
      #{@metrics.map { |m| "- #{m}" }.join("\n")}
      
      Format: #{@format}
    USER
  end
end
```

### Prompt Inheritance

```ruby
# Base prompt with common behavior
class BaseAssistantPrompt < RAAF::DSL::Prompts::Base
  optional :personality, default: "helpful"
  
  def base_instructions
    "You are a #{@personality} AI assistant."
  end
end

# Specialized prompts
class TechnicalAssistantPrompt < BaseAssistantPrompt
  requires :expertise_area
  
  def system
    <<~SYSTEM
      #{base_instructions}
      You specialize in #{@expertise_area}.
      Provide accurate technical information.
    SYSTEM
  end
end

class CreativeAssistantPrompt < BaseAssistantPrompt
  requires :creative_style
  
  def system
    <<~SYSTEM
      #{base_instructions}
      Your creative style is #{@creative_style}.
      Think outside the box and be imaginative.
    SYSTEM
  end
end
```

## File-Based Prompts

For simpler use cases, you can define prompts in Markdown or ERB files.

### Markdown Prompts

Create a file `prompts/research.md`:

```markdown
---
id: research-assistant
version: 1.0
category: research
---
# System
You are a research assistant specializing in {{topic}}.
Research depth: {{depth}}
Language: {{language}}

# User
Please research and provide information about {{query}}.
```

Use it in your code:

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "Researcher"
  prompt "research.md"
  model "gpt-4o"
end

result = agent.run("Tell me about quantum computing") do
  context_variable :topic, "physics"
  context_variable :depth, "comprehensive"
  context_variable :language, "English"
  context_variable :query, "quantum computing basics"
end
```

### ERB Template Prompts

For more complex file-based prompts, use ERB templates. Create `prompts/analysis.md.erb`:

```erb
---
id: data-analyst
version: 2.0
---
# System
You are a data analyst specializing in <%= domain %> analysis.

Your skills include:
<% skills.each do |skill| %>
- <%= skill %>
<% end %>

<% if advanced_mode %>
Use advanced statistical methods and machine learning insights.
<% end %>

# User
Analyze this <%= data_type %> data:

<%= code_block(data, "json") %>

Focus on:
<%= numbered_list(focus_areas) %>
```

### ERB Helper Methods

RAAF provides several helper methods for ERB templates:

- `code_block(content, language)` - Format code with syntax highlighting
- `numbered_list(items)` - Create a numbered list
- `bullet_list(items)` - Create a bulleted list
- `timestamp` - Current timestamp
- `format_json(data)` - Pretty-print JSON data

## Prompt Configuration

Configure how RAAF resolves prompts:

```ruby
# config/initializers/raaf_prompts.rb (Rails)
# or at application startup

RAAF::DSL.configure_prompts do |config|
  # Add directories to search for prompt files
  config.add_path "prompts"
  config.add_path "app/prompts"
  config.add_path Rails.root.join("lib/prompts") if defined?(Rails)
  
  # Configure resolver priorities (higher = checked first)
  config.enable_resolver :file, priority: 100
  config.enable_resolver :phlex, priority: 50
  
  # Custom resolver configuration
  config.configure_resolver :file do |resolver|
    resolver.extensions = [".md", ".markdown", ".md.erb"]
    resolver.cache_templates = Rails.env.production? if defined?(Rails)
  end
end
```

## Prompt Resolution

RAAF resolves prompts in the following order:

1. **Direct Ruby Class**: If you pass a class, it's used directly
2. **File Resolution**: Searches for files with configured extensions
3. **Phlex Classes**: Searches for matching Phlex component classes

```ruby
# Direct class (fastest)
agent.prompt ResearchPrompt

# File lookup (searches in configured paths)
agent.prompt "research.md"
agent.prompt "analysis.md.erb"

# Class name lookup
agent.prompt "ResearchPrompt"
```

## Best Practices

### 1. Prefer Ruby Classes

Ruby prompt classes should be your default choice because they provide:

- **Type Safety**: Required variables are enforced
- **IDE Support**: Autocomplete and refactoring work
- **Testability**: Easy to test with RSpec
- **Debugging**: Set breakpoints and inspect values
- **Reusability**: Use inheritance and modules

### 2. Organize Prompts Logically

```
app/
├── prompts/
│   ├── base/
│   │   └── assistant_prompt.rb
│   ├── customer_service/
│   │   ├── greeting_prompt.rb
│   │   ├── resolution_prompt.rb
│   │   └── escalation_prompt.rb
│   └── research/
│       ├── academic_prompt.rb
│       └── market_prompt.rb
```

### 3. Version Your Prompts

```ruby
class AnalysisPrompt < RAAF::DSL::Prompts::Base
  def version
    "2.1.0"  # Semantic versioning
  end
  
  def changelog
    {
      "2.1.0" => "Added support for financial metrics",
      "2.0.0" => "Rewrote for GPT-4 compatibility",
      "1.0.0" => "Initial version"
    }
  end
end
```

### 4. Test Your Prompts

```ruby
RSpec.describe CustomerServicePrompt do
  subject(:prompt) { described_class.new(params) }
  
  let(:params) do
    {
      company_name: "ACME Corp",
      issue_type: "billing",
      tone: "friendly"
    }
  end
  
  it "generates appropriate system message" do
    expect(prompt.system).to include("ACME Corp")
    expect(prompt.system).to include("friendly")
  end
  
  it "requires company_name" do
    params.delete(:company_name)
    expect { prompt }.to raise_error(ArgumentError, /company_name is required/)
  end
  
  it "uses default tone when not specified" do
    params.delete(:tone)
    expect(prompt.system).to include("professional")
  end
end
```

### 5. Use Context Variables Wisely

```ruby
# Good: Clear, specific context
result = agent.run(message) do
  context_variable :customer_tier, "premium"
  context_variable :account_age_days, 365
  context_variable :previous_issues, ["shipping_delay", "wrong_item"]
end

# Bad: Vague or overly complex context
result = agent.run(message) do
  context_variable :data, entire_customer_object  # Too much
  context_variable :info, "some stuff"           # Too vague
end
```

### 6. Handle Dynamic Content

```ruby
class AdaptivePrompt < RAAF::DSL::Prompts::Base
  requires :user_level, :task_complexity
  
  def system
    instructions = base_instructions
    
    # Adapt based on user level
    case @user_level
    when "beginner"
      instructions += "\nUse simple language and provide examples."
    when "expert"
      instructions += "\nUse technical terms and be concise."
    end
    
    # Adapt based on task
    if @task_complexity == "high"
      instructions += "\nBreak down complex tasks into steps."
    end
    
    instructions
  end
  
  private
  
  def base_instructions
    "You are an adaptive AI assistant."
  end
end
```

## Creating Custom Resolvers

You can extend the prompt system with custom resolvers:

```ruby
class DatabasePromptResolver < RAAF::DSL::PromptResolver
  def initialize(**options)
    super(name: :database, **options)
    @model_class = options[:model_class] || ::Prompt
  end
  
  def can_resolve?(prompt_spec)
    prompt_spec.is_a?(String) && prompt_spec.start_with?("db:")
  end
  
  def resolve(prompt_spec, context = {})
    return nil unless can_resolve?(prompt_spec)
    
    # Extract ID from "db:prompt_id" format
    prompt_id = prompt_spec.sub("db:", "")
    
    # Load from database
    record = @model_class.find_by(identifier: prompt_id)
    return nil unless record
    
    # Build prompt object
    RAAF::DSL::Prompt.new(
      id: record.identifier,
      version: record.version,
      messages: [
        { role: "system", content: interpolate(record.system_prompt, context) },
        { role: "user", content: interpolate(record.user_prompt, context) }
      ].compact,
      metadata: record.metadata
    )
  end
  
  private
  
  def interpolate(text, context)
    return nil if text.blank?
    
    # Replace {{variable}} with context values
    text.gsub(/\{\{(\w+)\}\}/) do |match|
      key = $1.to_sym
      context[key] || match
    end
  end
end

# Register the custom resolver
RAAF::DSL.configure_prompts do |config|
  config.register_resolver :database, DatabasePromptResolver, priority: 200
end

# Use it
agent.prompt "db:customer-service-v2"
```

## Debugging Prompts

RAAF provides tools to debug prompt resolution:

```ruby
# Enable debug mode
RAAF::DSL.configure_prompts do |config|
  config.debug_mode = true
end

# Inspect prompt resolution
prompt_spec = "research.md"
context = { topic: "AI", depth: "detailed" }

resolved = RAAF::DSL.prompt_resolvers.resolve(prompt_spec, context)
puts "Resolved prompt: #{resolved.inspect}"

# Use debug utilities
RAAF::DSL::DebugUtils.inspect_prompts(result) do
  show_system_prompt true
  show_user_prompt true
  show_interpolation true
  highlight_variables true
end
```

## Integration with Agents

### DSL Builder Integration

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "Assistant"
  
  # Multiple ways to set prompts
  prompt ResearchPrompt                    # Ruby class
  prompt "customer_service.md"             # Markdown file
  prompt "analysis.md.erb"                 # ERB template
  
  # With inline context
  prompt ResearchPrompt, topic: "science", depth: "basic"
  
  model "gpt-4o"
end
```

### Direct Integration

```ruby
# Resolve prompt manually
prompt = RAAF::DSL::Prompt.resolve(
  ResearchPrompt,
  topic: "machine learning",
  depth: "comprehensive"
)

# Use with agent
agent = RAAF::Agent.new(
  name: "Researcher",
  instructions: prompt.to_messages.map { |m| m[:content] }.join("\n\n"),
  model: "gpt-4o"
)
```

## Prompt Library

RAAF includes several built-in prompt templates you can extend:

```ruby
# Research assistant
class MyResearchPrompt < RAAF::DSL::Prompts::ResearchTemplate
  def additional_instructions
    "Focus on peer-reviewed sources from the last 5 years."
  end
end

# Customer service
class MySupportPrompt < RAAF::DSL::Prompts::SupportTemplate
  def company_specific_policies
    "Always offer a satisfaction guarantee."
  end
end

# Code assistant
class MyCodePrompt < RAAF::DSL::Prompts::CodeTemplate
  def languages
    ["Ruby", "Python", "JavaScript"]
  end
  
  def coding_style
    "Follow clean code principles and add comprehensive tests."
  end
end
```

## Conclusion

The RAAF prompt system provides a flexible, powerful way to manage prompts for your AI agents. By preferring Ruby classes, you get the benefits of type safety, testability, and full IDE support while maintaining the flexibility to use simpler file-based formats when appropriate.

Remember:
- Start with Ruby prompt classes for new projects
- Use file-based prompts for simple, static content
- Configure the system to match your project structure
- Test your prompts like any other code
- Version and document significant prompt changes

For more examples and advanced usage, see the [DSL Guide](dsl_guide.md) and [Examples](examples.md).