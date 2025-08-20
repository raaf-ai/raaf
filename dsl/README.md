# RAAF DSL

[![Gem Version](https://badge.fury.io/rb/raaf-dsl.svg)](https://badge.fury.io/rb/raaf-dsl)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF DSL** gem provides a comprehensive domain-specific language for the Ruby AI Agents Factory (RAAF) ecosystem. It offers an intuitive, declarative syntax for defining AI agents, workflows, tools, and configurations with powerful composition and extension capabilities.

## Overview

RAAF DSL extends the core agent capabilities from `raaf-core` to provide a comprehensive Ruby DSL (Domain-Specific Language) for building intelligent AI agents. This gem provides a declarative, configuration-only approach where all execution is delegated to `raaf-core`, ensuring clean separation of concerns between configuration and execution.

## 📑 Table of Contents

- [🎯 Why AI Agent DSL?](#-why-ai-agent-dsl)
- [✨ Key Features](#-key-features)
  - [🏗️ Declarative Agent Configuration](#️-declarative-agent-configuration)
  - [🌍 Environment-Aware Configuration](#-environment-aware-configuration)
  - [💰 Intelligent Cost Optimization](#-intelligent-cost-optimization)
  - [📝 Phlex-like Prompt System](#-phlex-like-prompt-system)
  - [🔗 Multi-Agent Workflows](#-multi-agent-workflows)
  - [🛠️ Advanced Tool Integration](#️-advanced-tool-integration)
  - [🚀 Seamless Rails Integration](#-seamless-rails-integration)
- [📦 Installation](#-installation)
  - [For Rails Applications (Recommended)](#for-rails-applications-recommended)
  - [For Non-Rails Applications](#for-non-rails-applications)
  - [System Requirements](#system-requirements)
- [🚀 Quick Start](#-quick-start)
  - [Step 1: Generate Configuration](#step-1-generate-configuration)
  - [Step 2: Create Your First Agent](#step-2-create-your-first-agent)
  - [Step 3: Use Your Agent](#step-3-use-your-agent)
  - [Step 4: Environment-Aware Execution](#step-4-environment-aware-execution)
- [🎯 Understanding Context: The Data Flow System](#-understanding-context-the-data-flow-system)
  - [What is Context?](#what-is-context)
  - [Basic Context Structure](#basic-context-structure)
  - [Context Path Navigation](#context-path-navigation)
  - [Context in Multi-Agent Workflows](#context-in-multi-agent-workflows)
  - [Practical Context Patterns](#practical-context-patterns)
  - [Context Validation and Error Handling](#context-validation-and-error-handling)
  - [Context Best Practices](#context-best-practices)
- [Configuration](#configuration)
  - [Environment-Specific Settings](#environment-specific-settings)
  - [Cost Optimization](#cost-optimization)
- [🔧 Advanced Features](#-advanced-features)
  - [🔗 Multi-Agent Orchestration](#-multi-agent-orchestration)
  - [🛠️ Advanced Tool Integration](#️-advanced-tool-integration-1)
  - [📝 Advanced Prompt Engineering](#-advanced-prompt-engineering)
  - [🎯 Schema Validation & Response Processing](#-schema-validation--response-processing)
- [🚀 Rails Integration](#-rails-integration)
  - [Automatic Setup](#automatic-setup)
  - [Rails Generators](#rails-generators)
  - [Deployment Integration](#deployment-integration)
  - [Rails Console Usage](#rails-console-usage)
- [📊 Cost Management & Optimization](#-cost-management--optimization)
  - [Automatic Cost Optimization](#automatic-cost-optimization)
  - [Cost Monitoring](#cost-monitoring)
- [🛡️ Production Considerations](#️-production-considerations)
  - [Error Handling & Resilience](#error-handling--resilience)
  - [Monitoring & Observability](#monitoring--observability)
  - [Security Best Practices](#security-best-practices)
- [🧪 Testing](#-testing)
  - [RSpec Integration](#rspec-integration)
  - [Test Helpers](#test-helpers)
- [📚 API Reference](#-api-reference)
- [📖 Additional Documentation](#-additional-documentation)
- [🤝 Contributing](#-contributing)
  - [Development Setup](#development-setup)
  - [Running Tests](#running-tests)
  - [Code Quality](#code-quality)
  - [Contributing Guidelines](#contributing-guidelines)
  - [Reporting Issues](#reporting-issues)
- [🤖 Development with AI](#-development-with-ai)
- [📄 License](#-license)
- [🏢 Enterprise Support](#-enterprise-support)
  - [Commercial Support Options](#commercial-support-options)
- [🌟 Contributors](#-contributors)
- [🔗 Related Projects](#-related-projects)

## 🎯 Why RAAF DSL?

Building AI agents requires clean, maintainable code with clear separation between configuration and execution. RAAF DSL provides:

- **Declarative Agent Configuration**: Define agents with a clean DSL that delegates execution to `raaf-core`
- **Phlex-inspired Prompt System**: Type-safe prompt classes with validation and contracts
- **Multi-Format Prompt Support**: Ruby classes, Markdown files, and ERB templates
- **Tool Integration**: Easy integration with external tools via the DSL
- **Debugging Tools**: Comprehensive debugging for prompts, context, and API calls
- **Rails Integration**: Seamless integration with Rails applications
- **Lifecycle Hooks**: Global and agent-specific callbacks for monitoring

## ✨ Key Features

### 🏗️ Declarative Agent Configuration
Define AI agents using a clean, readable DSL that makes complex agent configurations simple and maintainable:

```ruby
class DocumentAnalyzer < RAAF::DSL::Agent

  agent_name "DocumentAnalyzerAgent"
  model "gpt-4o"
  max_turns 5
  
  uses_tool :text_extraction, max_pages: 50
  uses_tool :database_query, timeout: 30
  
  schema do
    field :insights, type: :array, required: true
    field :confidence, type: :integer, range: 0..100
  end
end
```

### 🌍 Environment-Aware Configuration
YAML-based configuration with intelligent environment-specific overrides that automatically optimize for your deployment context:

```yaml
development:
  global:
    model: "gpt-4o-mini"  # 95% cost reduction
    max_turns: 2          # Faster development cycles

production:
  global:
    model: "gpt-4o"       # Full performance
    max_turns: 5          # Complete analysis
```

### 💰 Intelligent Cost Optimization
Automatic model switching and turn control that can reduce your AI costs by 50-90% without changing your code:

- **Development**: 50-75% cost reduction with cheaper models
- **Test**: 90%+ cost reduction with minimal turns
- **Production**: Balanced performance and cost optimization

### 📝 Phlex-like Prompt System
Structured prompt building with variable contracts, context mapping, and automatic validation:

```ruby
class ContentAnalysis < RAAF::DSL::Prompts::Base
  required :content_type, :analysis_depth
  required :document_format, path: [:document, :format]
  
  contract_mode :strict  # Validate all variables exist
  
  def system
    <<~SYSTEM
      You are a content analysis specialist processing #{content_type}.
      Focus on #{document_format} documents with #{analysis_depth} analysis.
    SYSTEM
  end
end
```

### 🔗 Multi-Agent Workflows
Orchestrate complex workflows with agent handoffs and sequential processing:

```ruby
class ContentWorkflow < RAAF::DSL::Agent
  
  # Note: processing_workflow is a conceptual example
  # In practice, use handoffs between agents
  # processing_workflow do
  #   extract_content
  #   then_analyze_structure
  #   then_categorize_topics
  #   finally_generate_summary
  # end
end
```

### 🧵 Pipelines (Canonical)

For multi-step workflows, use the canonical operator-style Pipeline DSL:

- Base class: `RAAF::Pipeline`
- Define flow with `flow` and chain agents/services with `>>` (sequential) and `|` (parallel)
- See the complete guide at `docs/PIPELINE_DSL_GUIDE.md`

Example:

```ruby
class AnalyzeThenReport < RAAF::Pipeline
  flow DataAnalyzer >> ReportGenerator
end

result = AnalyzeThenReport.new(raw_data: data).run
```

Legacy: The builder-style pipeline (`RAAF::DSL::AgentPipeline`) remains for backward compatibility but is considered legacy. Prefer `RAAF::Pipeline` for new work and documentation.

### 🛠️ Advanced Tool Integration
Easy integration of external tools with automatic parameter validation and error handling:

```ruby
class ContentAgent < RAAF::DSL::Agent
  uses_tool :document_parser, max_size: '10MB', timeout: 30
  uses_tool :database_query, connection: :primary
  uses_tool :api_client, base_url: ENV['API_BASE_URL']
end
```

### 🚀 Seamless Rails Integration
Full Rails integration with generators, automatic configuration loading, and Rails conventions:

```bash
rails generate raaf:dsl:config
rails generate raaf:dsl:agent DocumentAnalyzer
```

## 📦 Installation

### For Rails Applications (Recommended)

Add this line to your application's Gemfile:

```ruby
gem 'raaf-dsl'
```

Then execute:

```bash
bundle install
```

The gem will automatically integrate with Rails through its built-in Railtie.

### For Non-Rails Applications

Install the gem directly:

```bash
gem install raaf-dsl
```

Then require it in your application:

```ruby
require 'raaf-dsl'
```

### System Requirements

- **Ruby**: 2.7+ (Ruby 3.0+ recommended)
- **Rails**: 6.0+ (for Rails integration features)
- **Dependencies**: ActiveSupport (automatically managed)

## 🚀 Quick Start

### Step 1: Generate Configuration

Set up your project with intelligent defaults:

```bash
rails generate raaf:dsl:config
```

This creates two essential files:

#### `config/ai_agents.yml` - Environment-specific configuration
```yaml
# Shared defaults across environments
defaults: &defaults
  global:
    max_turns: 3
    model: "gpt-4o"
    temperature: 0.7
    timeout: 120

# Development: Optimized for cost and speed
development:
  <<: *defaults
  global:
    model: "gpt-4o-mini"  # 95% cost reduction
    max_turns: 2          # Faster iterations
    temperature: 0.3      # More deterministic

# Test: Minimal configuration for fast tests
test:
  <<: *defaults
  global:
    model: "gpt-4o-mini"
    max_turns: 1          # Single turn for tests
    timeout: 30           # Quick timeouts

# Production: Full performance
production:
  <<: *defaults
  global:
    model: "gpt-4o"
    max_turns: 5
    temperature: 0.7

  # Agent-specific overrides
  agents:
    market_research_agent:
      max_turns: 3
      temperature: 0.5
```

#### `config/initializers/ai_config.rb` - Custom configuration
```ruby
# Optional: Override default gem settings
RAAF::DSL.configure do |config|
  config.default_model = "gpt-4o"
  config.default_max_turns = 3
  config.default_temperature = 0.7
end
```

### Step 2: Create Your First Agent

Generate a complete agent with prompt class:

```bash
rails generate raaf:dsl:agent DocumentAnalyzer
```

This creates two files with full scaffolding:

#### `app/ai/agents/document_analyzer.rb` - Agent class
```ruby
class DocumentAnalyzer < RAAF::DSL::Agent

  # Agent identification and configuration
  agent_name "DocumentAnalyzerAgent"
  description "Performs comprehensive document analysis and content extraction"
  
  # Tool integrations
  uses_tool :text_extraction, max_pages: 50
  uses_tool :database_query, timeout: 30
  
  # Response schema with validation
  schema do
    field :insights, type: :array, required: true do
      field :category, type: :string, required: true
      field :finding, type: :string, required: true
      field :confidence, type: :integer, range: 0..100
    end
    field :summary, type: :string, required: true
    field :methodology, type: :string, required: true
  end
  
  # Optional: Execution hooks
end
```

#### `app/ai/prompts/document_analyzer.rb` - Prompt class
```ruby
class DocumentAnalyzer < RAAF::DSL::Prompts::Base
  # Variable contracts with validation
  required :content_type, :depth, :focus_areas
  required :document_name, path: [:document, :name]
  optional :format, path: [:document, :format], default: "PDF"
  
  # Strict validation mode
  contract_mode :strict

  def system
    <<~SYSTEM
      You are a senior content analyst specializing in #{format} document analysis.
      
      Your role is to analyze #{document_name} focusing on #{content_type}.
      Provide #{depth} level analysis covering: #{focus_areas.join(", ")}.
      
      Requirements:
      - Provide structured insights with confidence scores
      - Include content categorization and themes
      - Suggest content organization improvements
      - Cite specific sections and methodology used
    SYSTEM
  end

  def user
    <<~USER
      Please conduct a comprehensive content analysis for #{document_name}.
      
      Focus Areas: #{focus_areas.join(", ")}
      Analysis Depth: #{depth}
      Document Format: #{format}
      
      Ensure your analysis includes content structure, key themes, and recommendations.
    USER
  end
end
```

### Step 3: Use Your Agent

Now you can use your agent with rich context and automatic configuration:

```ruby
# Initialize with context and parameters
agent = DocumentAnalyzer.new(
  context: { 
    document: { 
      name: "Technical Manual v2.1", 
      format: "PDF" 
    } 
  },
  content_type: "technical documentation",
  depth: "comprehensive",
  focus_areas: ["structure analysis", "key topics", "readability"]
)

# Execute the agent
result = agent.run

# Access structured results
puts "Analysis Summary: #{result.summary}"
result.insights.each do |insight|
  puts "#{insight.category}: #{insight.finding} (#{insight.confidence}% confidence)"
end
```

### Step 4: Environment-Aware Execution

The same code automatically optimizes based on your environment:

```ruby
# Development: Uses gpt-4o-mini, 2 turns, costs ~$0.01
# Test: Uses gpt-4o-mini, 1 turn, costs ~$0.005  
# Production: Uses gpt-4o, 5 turns, costs ~$0.15

# No code changes needed - configuration drives behavior
agent = DocumentAnalyzer.new(context: context, **params)
result = agent.run
```

## 🎯 Understanding Context: The Data Flow System

Context is the core data flow mechanism in AI Agent DSL, enabling rich data sharing between agents, prompts, and tools throughout your workflows.

### What is Context?

Context is a hash-like structure that carries data through your AI agent workflows. It serves as:
- **Shared State**: Data that flows between multiple agents in a workflow
- **Prompt Variables**: Dynamic content that gets injected into your prompts
- **Configuration Data**: Runtime settings and parameters for agents and tools
- **Business Logic**: Domain-specific data like documents, users, products, etc.

### Basic Context Structure

```ruby
# Simple document processing context
context = {
  document: {
    name: "Q3 Financial Report",
    format: "PDF",
    pages: 45,
    metadata: {
      author: "Finance Team",
      created_at: "2024-03-15",
      language: "English"
    }
  },
  processing: {
    analysis_depth: "comprehensive",
    focus_areas: ["revenue trends", "cost analysis", "forecasting"]
  }
}

# Use context with agent
agent = DocumentAnalyzer.new(
  context: context,
  # Additional parameters are merged with context
  urgency: "high"
)
```

### Context Path Navigation

The DSL provides powerful path navigation to access nested context data safely:

```ruby
class DocumentPrompt < RAAF::DSL::Prompts::Base
  # Map context paths to prompt variables
  required :document_name, path: [:document, :name]
  optional :author, path: [:document, :metadata, :author], default: "Unknown"
  required :page_count, path: [:document, :pages]
  
  # Direct parameter requirements
  required :analysis_type
  
  def system
    <<~SYSTEM
      You are analyzing "#{document_name}" by #{author}.
      
      Document Details:
      - Pages: #{page_count}
      - Analysis Type: #{analysis_type}
      
      Provide structured insights based on the document content.
    SYSTEM
  end
end
```

**Path Navigation Features:**
- **Safe Access**: Uses `dig()` internally to prevent nil errors
- **Deep Nesting**: Navigate arbitrarily deep: `[:user, :profile, :settings, :theme]`
- **Default Values**: Fallback when paths don't exist
- **Validation**: Automatic validation of required paths during initialization

### Context in Multi-Agent Workflows

Context flows and evolves through agent handoffs:

```ruby
class ResearchWorkflow < RAAF::DSL::Agent
  
  agent_name "ResearchWorkflow"
  
  # Define workflow steps
  hands_off_to :data_collector, context_additions: { collection_params: { sources: ["web", "database"] } }
  hands_off_to :analyzer, context_additions: { analysis_type: "competitive" }
  hands_off_to :report_generator
end

# Initial context
initial_context = {
  research_topic: "AI Market Trends",
  target_audience: "executives",
  deadline: "2024-04-01"
}

# Context evolution through workflow:
# Step 1: DataCollector receives initial_context + collection_params
# Step 2: Analyzer receives enhanced context + analysis_type + collected data
# Step 3: ReportGenerator receives full context with all accumulated data
```

### Practical Context Patterns

#### Pattern 1: Document Processing
```ruby
context = {
  document: {
    name: "Technical Specification",
    type: "PDF",
    metadata: { size: "120 pages", complexity: "high" }
  },
  processing_requirements: {
    extract_diagrams: true,
    summarize_sections: ["architecture", "implementation"],
    output_format: "structured_json"
  }
}
```

#### Pattern 2: User-Centric Workflows
```ruby
context = {
  user: {
    id: 12345,
    profile: { role: "analyst", experience_level: "senior" },
    preferences: { format: "detailed", include_charts: true }
  },
  session: {
    request_id: "req_abc123",
    timestamp: Time.current,
    previous_queries: ["market analysis", "competitor research"]
  }
}
```

#### Pattern 3: Business Process Context
```ruby
context = {
  company: {
    name: "TechCorp Inc",
    industry: "Software",
    size: "enterprise",
    market_focus: ["B2B", "SaaS"]
  },
  analysis_request: {
    type: "competitive_analysis",
    scope: "Q1 2024",
    competitors: ["CompetitorA", "CompetitorB"],
    deliverables: ["executive_summary", "detailed_report", "recommendations"]
  }
}
```

### Context Validation and Error Handling

The DSL provides comprehensive validation:

```ruby
class ValidatedPrompt < RAAF::DSL::Prompts::Base
  # These will raise errors if missing
  required :company_name, path: [:company, :name]
  required :industry, path: [:company, :industry]
  
  # These are optional with defaults
  optional :company_size, path: [:company, :size], default: "Unknown"
  
  # Strict validation mode (default)
  contract_mode :strict
  
  def system
    "Analyzing #{company_name} in the #{industry} industry (Size: #{company_size})"
  end
end

# Example with complete context
complete_context = {
  company: {
    name: "TechCorp",
    industry: "Software"
  }
}
prompt = ValidatedPrompt.new(context: complete_context, variables: {})

# Example with incomplete context - this will raise an error
incomplete_context = { company: {} }
# This will raise a clear error if context[:company][:name] is missing
# prompt = ValidatedPrompt.new(context: incomplete_context, variables: {})
```

### Context Best Practices

1. **Structure Logically**: Group related data under common keys (`document`, `user`, `company`)

2. **Use Deep Nesting**: Organize complex data hierarchically
   ```ruby
   context = {
     product: {
       core: { name: "ProductX", version: "2.1" },
       market: { segment: "Enterprise", region: "EMEA" },
       metrics: { users: 50000, revenue: 2000000 }
     }
   }
   ```

3. **Provide Meaningful Defaults**: Use defaults for optional context paths
   ```ruby
   optional :theme, path: [:user, :preferences, :theme], default: "light"
   ```

4. **Validate Critical Data**: Use `required` with path for essential data
   ```ruby
   required :api_key, path: [:credentials, :api_key]
   ```

5. **Context Evolution**: Design contexts to grow through workflows
   ```ruby
   # Start simple
   context = { query: "market analysis" }
   
   # Evolve through agents
   # → { query: "...", research_data: {...} }
   # → { query: "...", research_data: {...}, analysis: {...} }
   # → { query: "...", research_data: {...}, analysis: {...}, report: {...} }
   ```

6. **Environment-Specific Context**: Adapt context based on environment
   ```ruby
   context = {
     processing: {
       detail_level: Rails.env.production? ? "comprehensive" : "summary",
       timeout: Rails.env.test? ? 10 : 120
     }
   }
   ```

Context provides the backbone for sophisticated AI agent workflows, enabling rich data flow, dynamic prompt generation, and seamless agent coordination while maintaining type safety and clear error handling.

## Configuration

### Environment-Specific Settings

Configure different models and limits per environment:

```yaml
# config/ai_agents.yml
development:
  global:
    model: "gpt-4o-mini"     # 95% cost reduction
    max_turns: 2             # Faster iterations
    temperature: 0.3

test:
  global:
    model: "gpt-4o-mini"
    max_turns: 1             # Single turn for tests

production:
  global:
    model: "gpt-4o"
    max_turns: 5
    temperature: 0.7

  agents:
    document_analyzer_agent:
      max_turns: 3           # Agent-specific override
      temperature: 0.5
```

### Cost Optimization

The gem automatically optimizes costs across environments:

- **Development**: 50-75% cost reduction (cheaper models + fewer turns)
- **Test**: 90%+ cost reduction (single turns + mini models)  
- **Production**: Balanced performance and cost

## 🔧 Advanced Features

### 🔗 Multi-Agent Orchestration

Create complex workflows with multiple agents working together:

```ruby
# Example agent classes (define these first)
class TextExtractionAgent < RAAF::DSL::Agent
  agent_name "TextExtractionAgent"
end

class StructureAnalysisAgent < RAAF::DSL::Agent
  agent_name "StructureAnalysisAgent"
end

class SummaryGenerationAgent < RAAF::DSL::Agent
  agent_name "SummaryGenerationAgent"
end

class ContentProcessingOrchestrator < RAAF::DSL::Agent

  agent_name "ContentProcessingOrchestrator"
  description "Orchestrates multi-step content analysis workflow"
  
  # Configure handoffs between agents
  configure_handoffs(
    TextExtractionAgent => { max_turns: 3 },
    StructureAnalysisAgent => { max_turns: 2 },
    SummaryGenerationAgent => { temperature: 0.1 }  # More deterministic summaries
  )
  
  # Schema for orchestrator results
  schema do
    field :workflow_status, type: :string, required: true
    field :stage_results, type: :array, required: true do
      field :stage, type: :string, required: true
      field :agent, type: :string, required: true
      field :duration, type: :number, required: true
      field :success, type: :boolean, required: true
    end
    field :final_content, type: :array, required: true
  end
end
```

### 🛠️ Advanced Tool Integration

Create sophisticated tool integrations with validation and error handling:

```ruby
class AdvancedContentAgent < RAAF::DSL::Agent

  # Multiple tools with specific configurations
  uses_tool :document_parser, max_pages: 100, timeout: 45
  uses_tool :database_query, connection: :content, timeout: 30
  uses_tool :api_client, 
    base_url: ENV['CONTENT_API_URL'],
    auth_token: ENV['API_TOKEN'],
    retry_count: 3
  uses_tool :file_processor, 
    allowed_formats: ['pdf', 'docx', 'xlsx', 'txt'],
    max_file_size: '50MB'
  
  # Conditional tool usage
  uses_tool_if Rails.env.production?, :premium_nlp_service
  uses_tool_if lambda { |agent| agent.context[:enable_ocr] }, :ocr_processor
  
  # Tool configuration with lambda options
  configure_tools(
    notification_tool: { 
      recipient: lambda { |agent| agent.context.dig(:user, :email) },
      template_id: lambda { |agent| agent.context[:notification_template] || 'content_ready' }
    }
  )
end
```

### 🐛 Advanced Debugging Tools

The DSL includes comprehensive debugging tools for understanding agent execution:

```ruby
# Context inspection
context_inspector = RAAF::DSL::Debugging::ContextInspector.new
context_inspector.inspect_context(agent_instance)

# Prompt inspection with variable substitution
prompt_inspector = RAAF::DSL::Debugging::PromptInspector.new
prompt_inspector.inspect_prompts(agent_instance)

# API call interception
llm_interceptor = RAAF::DSL::Debugging::LLMInterceptor.new
llm_interceptor.intercept_openai_calls do
  agent.run
end

# Multi-agent workflow debugging
swarm_debugger = RAAF::DSL::Debugging::SwarmDebugger.new(enabled: true)
swarm_debugger.start_workflow_session("Customer Support Workflow")
# ... run agents ...
swarm_debugger.end_workflow_session
```

See the [debugging tools documentation](lib/raaf/dsl/debugging/README.md) for comprehensive examples.

### 📝 Advanced Prompt Engineering

#### Flexible Prompt Resolution System

RAAF DSL includes a powerful prompt resolution framework that supports multiple formats:

```ruby
# Configure prompt resolution
RAAF::DSL.configure_prompts do |config|
  config.add_path "prompts"           # Search in prompts/ directory
  config.add_path "app/prompts"       # Rails-style paths
  
  config.enable_resolver :file, priority: 100    # Handles .md, .md.erb
  config.enable_resolver :phlex, priority: 50    # Ruby prompt classes
end

# Use prompts in multiple ways
agent = MyAgent.new(
  # From Phlex-style Ruby class
  prompt: CustomerServicePrompt,
  
  # From Markdown file with {{variable}} interpolation
  prompt: "customer_service.md",
  
  # From ERB template with full Ruby capabilities
  prompt: "analysis.md.erb",
  
  # Pass context for variable substitution
  context: { company_name: "ACME Corp", tone: "friendly" }
)
```

#### Supported Prompt Formats

1. **Ruby Prompt Classes** (Phlex-style)
   ```ruby
   class ResearchPrompt < RAAF::DSL::Prompts::Base
     required :topic, :depth
     
     def system
       "You are a research assistant specializing in #{@topic}."
     end
   end
   ```

2. **Markdown Files** with frontmatter and interpolation
   ```markdown
   ---
   id: customer-service
   version: 1.0
   ---
   # System
   You are a {{tone}} customer service agent for {{company_name}}.
   
   # User
   Help the customer with their {{issue_type}} issue.
   ```

3. **ERB Templates** with Ruby logic and helpers
   ```erb
   ---
   id: analysis-report
   ---
   # System
   You analyze <%= data_type %> data.
   
   Skills:
   <%= list(skills) %>
   
   # User
   Analyze this data:
   <%= code_block(data, "json") %>
   ```

#### Prompt Resolution Features

- **Automatic format detection** based on file extension
- **Variable interpolation** for Markdown files
- **Full ERB processing** with helper methods
- **YAML frontmatter** for metadata
- **Section markers** for system/user messages
- **Extensible architecture** for custom resolvers

Sophisticated prompt management with contracts and validation:

```ruby
class AdvancedContentAnalysis < RAAF::DSL::Prompts::Base
  # Required variables with strict validation
  required :analysis_depth, :focus_areas, :timeline
  
  # Context mapping with nested paths and defaults
  required :document_name, path: [:document, :name]
  optional :document_size, path: [:document, :pages], default: "Unknown"
  optional :document_type, path: [:document, :type], default: "General"
  optional :source, path: [:document, :source], default: "Not provided"
  optional :language, path: [:document, :metadata, :language], default: "English"
  
  # Optional context variables
  optional :author, path: [:document, :metadata, :author]
  optional :created_date, path: [:document, :metadata, :created]
  
  # Strict contract validation - will raise errors if variables missing
  contract_mode :strict

  def system
    <<~SYSTEM
      You are a senior content analyst with expertise in #{document_type} document analysis.
      
      DOCUMENT PROFILE:
      - Name: #{document_name}
      - Type: #{document_type}
      - Size: #{document_size} pages
      - Language: #{language}
      - Source: #{source}
      #{author ? "- Author: #{author}" : ""}
      #{created_date ? "- Created: #{created_date}" : ""}
      
      ANALYSIS REQUIREMENTS:
      - Depth: #{analysis_depth} analysis
      - Timeline: #{timeline}
      - Focus Areas: #{focus_areas.join(", ")}
      
      ANALYSIS FRAMEWORK:
      1. Content Structure Analysis
      2. Theme and Topic Identification
      3. Writing Quality Assessment
      4. Information Density Evaluation
      5. Readability and Accessibility
      6. Key Insights Extraction
      7. Content Organization Recommendations
      
      Provide specific examples and cite relevant sections.
    SYSTEM
  end

  def user
    analysis_scope = case analysis_depth
                    when 'surface' then 'high-level overview with main themes'
                    when 'standard' then 'comprehensive analysis with detailed insights'
                    when 'deep' then 'exhaustive analysis with structural recommendations'
                    else 'standard comprehensive analysis'
                    end

    <<~USER
      Conduct a #{analysis_scope} of #{document_name}.
      
      Primary Focus: #{focus_areas.join(" + ")}
      Analysis Timeline: #{timeline}
      
      For each focus area, provide:
      - Current content assessment
      - Key themes and patterns
      - Quality and clarity evaluation
      - Improvement recommendations
      
      Include confidence levels for all findings and cite specific sections.
    USER
  end
  
  # Optional: Custom validation logic
  private
  
  def validate_timeline
    valid_timelines = ['immediate', '1 week', '2 weeks', '1 month']
    unless valid_timelines.include?(timeline)
      raise VariableContractError, "Timeline must be one of: #{valid_timelines.join(', ')}"
    end
  end
end
```

### 🎯 Schema Validation & Response Processing

Define complex response schemas with nested validation:

```ruby
class ComprehensiveContentAgent < RAAF::DSL::Agent

  schema do
    # Document overview with nested structure
    field :document_overview, type: :object, required: true do
      field :title, type: :string, required: true
      field :content_type, type: :string, required: true
      field :complexity_level, type: :string, enum: ["basic", "intermediate", "advanced", "expert"]
      field :page_count, type: :integer, range: 1..10000
      field :metadata, type: :object do
        field :language, type: :string, required: true
        field :encoding, type: :string, required: true
        field :format, type: :string
      end
    end
    
    # Content metrics with validation
    field :content_metrics, type: :object do
      field :word_count, type: :integer, min: 1
      field :readability_score, type: :integer, range: 0..100
      field :content_density, type: :string, enum: ["sparse", "moderate", "dense", "very-dense"]
      field :topic_diversity, type: :integer, range: 1..50
    end
    
    # Analysis results with confidence scoring
    field :analysis_results, type: :array, required: true, min_items: 1 do
      field :category, type: :string, required: true
      field :finding, type: :string, required: true, min_length: 10
      field :confidence_score, type: :integer, range: 0..100, required: true
      field :supporting_evidence, type: :array, items_type: :string
      field :improvement_areas, type: :array, items_type: :string
      field :strengths, type: :array, items_type: :string
    end
    
    # Content classification
    field :content_classification, type: :object, required: true do
      field :primary_topics, type: :array, max_items: 10 do
        field :topic, type: :string, required: true
        field :relevance_score, type: :integer, range: 0..100
        field :section_coverage, type: :string
      end
      field :content_quality, type: :string, enum: ["excellent", "good", "fair", "poor"]
      field :organization_patterns, type: :array, items_type: :string
    end
    
    # Recommendations with priority
    field :recommendations, type: :array, required: true do
      field :priority, type: :string, enum: ["high", "medium", "low"], required: true
      field :recommendation, type: :string, required: true, min_length: 20
      field :expected_improvement, type: :string, required: true
      field :implementation_effort, type: :string, enum: ["minimal", "moderate", "significant"]
      field :timeline, type: :string, required: true
    end
    
    # Metadata
    field :analysis_metadata, type: :object, required: true do
      field :analysis_date, type: :string, required: true
      field :processing_tools, type: :array, items_type: :string, required: true
      field :methodology, type: :string, required: true
      field :limitations, type: :array, items_type: :string
      field :analyst_notes, type: :string
    end
  end
end
```

## 🚀 Rails Integration

The gem provides seamless Rails integration through its built-in Railtie:

### Automatic Setup
- **Configuration Loading**: Automatically loads `config/ai_agents.yml` during Rails boot
- **Environment Detection**: Uses `Rails.env` for automatic environment-specific configuration
- **Logger Integration**: Integrates with `Rails.logger` for consistent logging
- **Eager Loading**: Configures proper eager loading for production environments

### Rails Generators
```bash
# Generate configuration files
rails generate raaf:dsl:config

# Generate agent and prompt classes
rails generate raaf:dsl:agent DocumentAnalyzer
rails generate raaf:dsl:agent content/text_processor
```

### Deployment Integration
Works seamlessly with Rails deployment patterns:
- **Heroku**: Environment variables and Rails conventions
- **Docker**: Container-friendly configuration loading
- **Kubernetes**: ConfigMap and Secret integration
- **Capistrano**: Standard Rails deployment workflows

### Rails Console Usage
```ruby
# Rails console integration
rails console

# Use agents directly in console
context = { document: { name: "report.pdf", format: "PDF" } }
params = { processing_params: {} }
agent = DocumentAnalyzer.new(context: context, **params)
result = agent.run

# Access configuration
RAAF::DSL::Config.for_agent("document_analyzer")
```

### 🔗 Lifecycle Hooks & Callbacks

The framework provides comprehensive callback systems for monitoring and extending agent behavior during execution:

#### Global Hooks (RunHooks)
Register global callbacks that trigger for all agents:

```ruby
# Global callbacks for all agents
RAAF::DSL::Hooks::RunHooks.on_agent_start do |agent|
  puts "Agent #{agent.name} is starting"
  # Log to your monitoring system
  MetricsCollector.increment("agent.start", tags: { agent: agent.name })
end

RAAF::DSL::Hooks::RunHooks.on_agent_end do |agent, result|
  puts "Agent #{agent.name} completed with result: #{result.inspect}"
  # Track completion metrics
  MetricsCollector.timing("agent.duration", result[:duration])
end

RAAF::DSL::Hooks::RunHooks.on_tool_start do |agent, tool_name, params|
  puts "Agent #{agent.name} using tool: #{tool_name}"
  # Log tool usage
  ToolUsageLogger.log(agent.name, tool_name, params)
end

RAAF::DSL::Hooks::RunHooks.on_error do |agent, error|
  puts "Error in agent #{agent.name}: #{error.message}"
  # Report to error tracking
  ErrorTracker.report(error, agent: agent.name)
end
```

#### Agent-Specific Hooks (AgentHooks)
Register callbacks for specific agent instances:

```ruby
class DocumentAnalyzer < RAAF::DSL::Agent
  include RAAF::DSL::Hooks::AgentHooks

  agent_name "document_analyzer"
  description "Analyzes documents with lifecycle tracking"

  # Method-based hooks
  on_start :initialize_analysis
  on_end :finalize_analysis
  on_error :handle_analysis_error

  # Block-based hooks
  on_start do |agent|
    @analysis_start_time = Time.now
    puts "Starting document analysis at #{@analysis_start_time}"
  end

  on_tool_start do |agent, tool_name, params|
    puts "Using #{tool_name} with params: #{params.inspect}"
  end

  on_end do |agent, result|
    duration = Time.now - @analysis_start_time
    puts "Analysis completed in #{duration} seconds"
    
    # Update metrics
    AnalysisMetrics.record_completion(duration, result[:success])
  end

  private

  def initialize_analysis
    # Setup analysis environment
    prepare_analysis_workspace
  end

  def finalize_analysis
    # Cleanup and finalize results
    cleanup_analysis_workspace
  end

  def handle_analysis_error(agent, error)
    # Custom error handling
    rollback_analysis_state
    notify_admin_of_failure(error)
  end
end
```

#### Multiple Handlers & Execution Order
Both global and agent-specific hooks support multiple handlers executed in registration order:

```ruby
# Multiple global handlers
RAAF::DSL::Hooks::RunHooks.on_agent_start { |agent| log_to_stdout(agent) }
RAAF::DSL::Hooks::RunHooks.on_agent_start { |agent| log_to_file(agent) }
RAAF::DSL::Hooks::RunHooks.on_agent_start { |agent| send_to_monitoring(agent) }

# Multiple agent-specific handlers
class MyAgent < RAAF::DSL::Agent
  include RAAF::DSL::Hooks::AgentHooks
  
  on_start :prepare_environment
  on_start :load_dependencies
  on_start { |agent| puts "Agent #{agent.name} fully initialized" }
  
  # Executed in order: prepare_environment -> load_dependencies -> block
end
```

#### Available Hook Types

**Global Hooks (RunHooks):**
- `on_agent_start` - When any agent starts
- `on_agent_end` - When any agent completes
- `on_handoff` - When control transfers between agents
- `on_tool_start` - Before tool execution
- `on_tool_end` - After tool execution
- `on_error` - When errors occur

**Agent-Specific Hooks (AgentHooks):**
- `on_start` - When this agent starts
- `on_end` - When this agent completes
- `on_handoff` - When this agent receives handoff
- `on_tool_start` - Before this agent uses tool
- `on_tool_end` - After this agent uses tool
- `on_error` - When error occurs in this agent

#### Hook Execution Flow
1. **Global hooks execute first** (in registration order)
2. **Agent-specific hooks execute second** (in registration order)
3. **Error hooks execute on exceptions** (don't stop execution)
4. **Hooks are thread-safe** and support concurrent execution

#### Real-World Hook Examples

```ruby
# Application monitoring
RAAF::DSL::Hooks::RunHooks.on_agent_start do |agent|
  ApplicationMonitor.track_agent_start(agent.name)
end

# Cost tracking
RAAF::DSL::Hooks::RunHooks.on_tool_end do |agent, tool_name, params, result|
  CostTracker.record_tool_usage(agent.name, tool_name, result[:token_count])
end

# Performance monitoring
RAAF::DSL::Hooks::RunHooks.on_agent_end do |agent, result|
  PerformanceMonitor.record_agent_completion(
    agent: agent.name,
    duration: result[:duration],
    success: result[:success]
  )
end

# Security auditing
RAAF::DSL::Hooks::RunHooks.on_error do |agent, error|
  SecurityAuditor.log_agent_error(agent.name, error.message)
end
```

## 📊 Cost Management & Optimization

### Automatic Cost Optimization
The gem includes intelligent cost optimization that can reduce your AI API costs by 50-90%:

| Environment | Model | Max Turns | Cost Reduction | Use Case |
|-------------|--------|-----------|----------------|----------|
| **Development** | gpt-4o-mini | 2 | 75% | Fast iteration |
| **Test** | gpt-4o-mini | 1 | 90% | Automated testing |
| **Staging** | gpt-4o | 3 | 50% | Pre-production validation |
| **Production** | gpt-4o | 5 | Baseline | Full performance |

### Cost Monitoring
```ruby
# Track costs per agent
class CostTrackingAgent < RAAF::DSL::Agent
  
  
  private
  
  def log_start_time
    @start_time = Time.current
  end
  
  def calculate_cost
    duration = Time.current - @start_time
    estimated_cost = calculate_api_cost(model_name, max_turns)
    Rails.logger.info "Agent #{agent_name}: #{duration}s, ~$#{estimated_cost}"
  end
end
```

## 🛡️ Production Considerations

### Error Handling & Resilience
```ruby
class ProductionAgent < RAAF::DSL::Agent
  
  # Execution hooks for monitoring
  
  # Error handling
  def handle_agent_error(error, context = {})
    # Log to monitoring service
    ErrorTracker.capture_exception(error, context: context)
    
    # Fallback response
    {
      success: false,
      error: "Agent execution failed",
      fallback_data: generate_fallback_response
    }
  end
  
  private
  
  def validate_inputs
    raise ArgumentError, "Invalid context" unless context.valid?
  end
  
  def log_completion
    Rails.logger.info "Agent #{agent_name} completed successfully"
  end
end
```

### Monitoring & Observability
```ruby
# config/initializers/ai_config.rb
RAAF::DSL.configure do |config|
  # Custom monitoring integration
  config.before_agent_execution = lambda do |agent, context|
    StatsD.increment("ai_agent.execution.started", tags: ["agent:#{agent.class.name}"])
  end
  
  config.after_agent_execution = lambda do |agent, result, duration|
    StatsD.timing("ai_agent.execution.duration", duration, tags: ["agent:#{agent.class.name}"])
    StatsD.increment("ai_agent.execution.completed", tags: ["agent:#{agent.class.name}"])
  end
end
```

### Security Best Practices
```ruby
class SecureAgent < RAAF::DSL::Agent
  
  
  private
  
  def sanitize_context
    sensitive_keys = [:password, :api_key, :token, :secret]
    sensitive_keys.each do |key|
      context.delete(key) if context.key?(key)
    end
  end
  
  def clean_logs
    # Ensure no sensitive data in logs
    Rails.logger.info "Agent execution completed (sensitive data redacted)"
  end
end
```

## 🧪 Testing

### RSpec Integration
```ruby
# spec/ai/agents/document_analyzer_spec.rb
RSpec.describe DocumentAnalyzer do
  let(:context) do
    {
      document: {
        name: "Test Document",
        format: "PDF"
      }
    }
  end
  
  let(:agent) do
    described_class.new(
      context: context,
      content_type: "technical documentation",
      depth: "comprehensive"
    )
  end
  
  describe "#run" do
    it "returns structured analysis results" do
      # Use test environment configuration (single turn, mini model)
      result = agent.run
      
      expect(result).to have_key(:insights)
      expect(result).to have_key(:summary)
      expect(result.insights).to be_an(Array)
    end
  end
  
  describe "configuration" do
    it "uses test environment settings" do
      expect(agent.model_name).to eq("gpt-4o-mini")
      expect(agent.max_turns).to eq(1)
    end
  end
end
```

### Test Helpers
```ruby
# spec/support/ai_agent_helpers.rb
module AiAgentHelpers
  def mock_ai_response(agent_class, response_data)
    allow_any_instance_of(agent_class).to receive(:run).and_return(response_data)
  end
  
  def with_ai_config(overrides = {})
    original_config = RAAF::DSL.configuration.dup
    
    overrides.each do |key, value|
      RAAF::DSL.configuration.send("#{key}=", value)
    end
    
    yield
  ensure
    RAAF::DSL.configuration = original_config
  end
end

RSpec.configure do |config|
  config.include AiAgentHelpers
end
```

## 📚 API Reference

For complete API documentation including all classes, methods, parameters, and examples, see:

**[📖 API Reference Documentation](API_REFERENCE.md)**

The API reference covers:
- **Core Classes**: `Agent`, `AgentDsl`, `Prompts::Base`, `Config`, `Tools::Base`
- **Method Signatures**: Complete parameter lists and return values
- **Configuration Options**: All supported YAML configuration keys
- **Error Classes**: Exception types and handling
- **Usage Examples**: Code samples for each API component

## 📖 Additional Documentation

- [**Agent DSL Reference**](docs/agent_dsl.md) - Complete DSL syntax and options
- [**Configuration Guide**](docs/configuration.md) - Environment setup and YAML configuration
- [**Tool Integration**](docs/tools.md) - Building and integrating custom tools
- [**Prompt Engineering**](docs/prompts.md) - Advanced prompt techniques and contracts
- [**Cost Optimization**](docs/cost_optimization.md) - Strategies for reducing AI API costs
- [**Multi-Agent Workflows**](docs/workflows.md) - Orchestrating complex agent interactions
- [**Production Deployment**](docs/deployment.md) - Best practices for production use
- [**Troubleshooting Guide**](docs/troubleshooting.md) - Common issues and solutions

## 🤝 Contributing

We welcome contributions! Here's how to get started:

### Development Setup
```bash
git clone https://github.com/raaf-ai/raaf-dsl.git
cd raaf-dsl
bundle install
```

### Running Tests
```bash
bundle exec rspec
```

### Code Quality
```bash
bundle exec rubocop
bundle exec yard doc
```

### Contributing Guidelines
1. **Fork the repository** and create your feature branch
2. **Write comprehensive tests** for new functionality
3. **Follow Ruby style guidelines** (RuboCop configuration included)
4. **Add documentation** for new features and API changes
5. **Update CHANGELOG.md** with your changes
6. **Submit a pull request** with a clear description

### Reporting Issues
Please use the [GitHub issue tracker](https://github.com/raaf-ai/raaf-dsl/issues) to report bugs or request features. Include:
- Ruby and Rails versions
- Detailed error messages
- Steps to reproduce
- Expected vs actual behavior

## 🤖 Development with AI

This gem is developed extensively using [Claude Code](https://claude.ai/code), Anthropic's AI-powered coding assistant. While we use this gem heavily in our own projects and it has been tested thoroughly, please be aware that some code or documentation may contain AI-generated content that could include inaccuracies or hallucinations.

We recommend:
- **Thorough testing** of all functionality in your specific use case
- **Code review** before production deployment  
- **Reporting issues** if you encounter any problems or unexpected behavior

The combination of AI assistance and human oversight helps us build better software faster, but human validation remains essential.

## 📄 License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## 🏢 Enterprise Support

**AI Agent DSL** is developed and maintained by [Enterprise Modules](https://enterprisemodules.com), specialists in Ruby, Rails, and AI integration solutions.

### Commercial Support Options
- **Priority Support**: Get fast responses to your questions and issues
- **Custom Development**: Tailored AI agent solutions for your content processing needs
- **Training & Consulting**: Expert guidance on AI integration best practices
- **Enterprise Features**: Additional security, monitoring, and deployment features

Contact us at [support@enterprisemodules.com](mailto:support@enterprisemodules.com) for enterprise inquiries.

## 🌟 Contributors

Special thanks to our contributors who make this project possible:

### Contributors
- [Enterprise Modules Team](https://enterprisemodules.com) - Core development and maintenance
- *Join our growing list of contributors!*

## 🔗 Related Projects

- [**RAAF (Ruby AI Agents Factory)**](https://github.com/enterprisemodules/raaf) - Ruby SDK for OpenAI's assistant API
- [**Phlex**](https://github.com/phlex-ruby/phlex) - Framework for building fast, reusable, testable views
- [**ActiveSupport**](https://github.com/rails/rails/tree/main/activesupport) - Ruby extensions and utilities


### Version History
- **v0.1.0** - Initial release with core DSL and Rails integration

---

<div align="center">

**[⭐ Star us on GitHub](https://github.com/raaf-ai/raaf-dsl)** if this project helped you!

Made with ❤️ by [Enterprise Modules](https://enterprisemodules.com)

</div>
