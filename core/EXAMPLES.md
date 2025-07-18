# Examples

Advanced code examples demonstrating RAAF (Ruby AI Agents Factory) capabilities.

> For basic usage and getting started, see the [Getting Started Guide](GETTING_STARTED.md).

## Table of Contents

1. [Universal Structured Output](#universal-structured-output)
2. [Enterprise Customer Service](#enterprise-customer-service)
3. [Research & Analysis Platform](#research--analysis-platform)
4. [Code Review Assistant](#code-review-assistant)
5. [Data Processing Pipeline](#data-processing-pipeline)
6. [Voice-Enabled Support](#voice-enabled-support)
7. [Multi-Language Support Bot](#multi-language-support-bot)
8. [Financial Analysis Agent](#financial-analysis-agent)
9. [DevOps Automation](#devops-automation)

---

## Universal Structured Output

Demonstrates the `response_format` feature that provides guaranteed structured output across ALL providers.

```ruby
require 'raaf'

# Define a comprehensive product analysis schema
PRODUCT_SCHEMA = {
  type: "json_schema",
  json_schema: {
    name: "product_analysis",
    strict: true,
    schema: {
      type: "object",
      properties: {
        product_name: { type: "string" },
        price: { type: "number", minimum: 0 },
        category: { 
          type: "string",
          enum: ["electronics", "clothing", "food", "books", "other"]
        },
        features: {
          type: "array",
          items: { type: "string" },
          minItems: 1
        },
        rating: { type: "integer", minimum: 1, maximum: 5 },
        pros: { type: "array", items: { type: "string" } },
        cons: { type: "array", items: { type: "string" } },
        in_stock: { type: "boolean" },
        recommendation: { type: "string" }
      },
      required: ["product_name", "price", "category", "features", "pros", "cons", "rating", "in_stock", "recommendation"],
      additionalProperties: false
    }
  }
}.freeze

class UniversalProductAnalyzer
  def initialize(provider: nil)
    # Works with ANY provider - OpenAI, Anthropic, Cohere, Groq, etc.
    @agent = RAAF::Agent.new(
      name: "ProductAnalyzer",
      instructions: build_instructions,
      model: select_model_for_provider(provider),
      response_format: PRODUCT_SCHEMA
    )
    
    @runner = RAAF::Runner.new(
      agent: @agent,
      provider: provider # Uses ResponsesProvider by default
    )
  end
  
  def analyze_product(product_description)
    result = @runner.run(product_description)
    
    # Parse guaranteed JSON output
    analysis = JSON.parse(result.messages.last[:content])
    
    # Return structured product data
    {
      product: analysis,
      raw_response: result.messages.last[:content],
      provider_used: @runner.provider.class.name
    }
  end
  
  private
  
  def build_instructions
    <<~INSTRUCTIONS
      You are a product analysis expert. Analyze the given product description
      and provide comprehensive structured information including:
      
      1. Extract the product name and price
      2. Categorize the product appropriately
      3. List key features and benefits
      4. Provide a rating from 1-5 based on description
      5. List pros and cons
      6. Determine availability status
      7. Give a brief recommendation
      
      Be thorough but concise in your analysis.
    INSTRUCTIONS
  end
  
  def select_model_for_provider(provider)
    case provider&.class&.name
    when /Anthropic/
      "claude-3-5-sonnet-20241022"
    when /Cohere/
      "command-r"
    when /Groq/
      "llama-3.1-70b-versatile"
    else
      "gpt-4o"
    end
  end
end

# Example usage with different providers
product_description = <<~PRODUCT
  The new MacBook Pro 16-inch with M3 Max chip is priced at $3499.
  It features a stunning Liquid Retina XDR display, up to 128GB unified memory,
  and incredible performance for video editing and development work.
  The battery life is exceptional, lasting up to 22 hours.
  However, the price point is quite high and it has limited port selection.
PRODUCT

# Test with default provider (ResponsesProvider)
analyzer_default = UniversalProductAnalyzer.new
result_default = analyzer_default.analyze_product(product_description)

puts "📊 Analysis with Default Provider:"
puts "Provider: #{result_default[:provider_used]}"
puts "Product: #{result_default[:product]['product_name']}"
puts "Price: $#{result_default[:product]['price']}"
puts "Rating: #{result_default[:product]['rating']}/5"
puts "Category: #{result_default[:product]['category']}"
puts "Features: #{result_default[:product]['features'].join(', ')}"
puts "Recommendation: #{result_default[:product]['recommendation']}"

# Test with specific providers (if API keys available)
if ENV['ANTHROPIC_API_KEY']
  anthropic_provider = RAAF::Models::AnthropicProvider.new
  analyzer_anthropic = UniversalProductAnalyzer.new(provider: anthropic_provider)
  result_anthropic = analyzer_anthropic.analyze_product(product_description)
  
  puts "\n🧠 Analysis with Anthropic:"
  puts "Provider: #{result_anthropic[:provider_used]}"
  puts "Product: #{result_anthropic[:product]['product_name']}"
  puts "Same schema, different provider! ✅"
end

if ENV['COHERE_API_KEY']
  cohere_provider = RAAF::Models::CohereProvider.new
  analyzer_cohere = UniversalProductAnalyzer.new(provider: cohere_provider)
  result_cohere = analyzer_cohere.analyze_product(product_description)
  
  puts "\n🤖 Analysis with Cohere:"
  puts "Provider: #{result_cohere[:provider_used]}"
  puts "Product: #{result_cohere[:product]['product_name']}"
  puts "Universal compatibility! ✅"
end

# Demonstrate schema validation
begin
  # This will always return valid JSON matching the schema
  all_results = [result_default]
  all_results << result_anthropic if defined?(result_anthropic)
  all_results << result_cohere if defined?(result_cohere)
  
  puts "\n🔍 Schema Validation Results:"
  all_results.each do |result|
    product = result[:product]
    puts "✅ #{result[:provider_used]}: Valid schema with #{product.keys.length} fields"
    
    # Verify required fields
    required_fields = ['product_name', 'price', 'category', 'rating', 'in_stock']
    missing_fields = required_fields - product.keys
    puts "   Required fields: #{missing_fields.empty? ? 'All present ✅' : 'Missing: ' + missing_fields.join(', ') + ' ❌'}"
  end
  
rescue JSON::ParserError => e
  puts "❌ JSON parsing failed: #{e.message}"
rescue => e
  puts "❌ Validation error: #{e.message}"
end

puts "\n🎯 Key Benefits:"
puts "• Same schema works with ALL providers"
puts "• Automatic provider-specific adaptations"
puts "• Guaranteed JSON output structure"
puts "• Type-safe data extraction"
puts "• Universal compatibility"
```

**Key Features:**
- **Universal Schema**: Same `response_format` works across all providers
- **Automatic Adaptation**: Each provider handles structured output optimally
- **Type Safety**: Guaranteed JSON structure matching your schema
- **Backward Compatibility**: Existing `output_schema` code still works
- **Provider Agnostic**: Switch providers without changing schemas

---

## Enterprise Customer Service

A comprehensive customer service system with multiple specialized agents, guardrails, and full monitoring.

```ruby
require 'raaf'

class EnterpriseCustomerService
  def initialize
    @config = setup_configuration
    @tracker = setup_usage_tracking
    @guardrails = setup_guardrails
    @tracer = setup_tracing
    
    @agents = create_agent_hierarchy
    @handoff_manager = setup_handoffs
  end

  def handle_request(customer_request, customer_id, priority: :normal)
    # Create session context
    session_id = "cs_#{Time.now.to_i}_#{customer_id}"
    
    # Apply guardrails
    @guardrails.validate_input({
      query: customer_request,
      customer_id: customer_id,
      priority: priority
    })
    
    # Execute with full tracing
    @tracer.agent_span("customer_service_session") do |span|
      span.set_attribute("customer.id", customer_id)
      span.set_attribute("session.id", session_id)
      span.set_attribute("priority", priority.to_s)
      
      process_customer_request(customer_request, customer_id, session_id)
    end
  end

  private

  def setup_configuration
    config = RAAF::Configuration.new(environment: "production")
    config.set("agent.max_turns", 15)
    config.set("guardrails.rate_limiting.max_requests_per_minute", 300)
    config
  end

  def setup_usage_tracking
    tracker = RAAF::UsageTracking::UsageTracker.new
    
    # Business alerts
    tracker.add_alert(:high_cost) do |usage|
      usage[:total_cost_today] > 500.0
    end
    
    tracker.add_alert(:poor_satisfaction) do |usage|
      avg_satisfaction = usage[:agent_interactions][:average_satisfaction]
      avg_satisfaction && avg_satisfaction < 3.0
    end
    
    tracker.add_alert(:escalation_rate) do |usage|
      escalations = usage[:agent_interactions][:escalations] || 0
      total = usage[:agent_interactions][:count] || 1
      (escalations.to_f / total) > 0.3  # 30% escalation rate
    end
    
    tracker
  end

  def setup_guardrails
    guardrails = RAAF::Guardrails::GuardrailManager.new
    
    # Content safety
    guardrails.add_guardrail(
      RAAF::Guardrails::ContentSafetyGuardrail.new(strict_mode: true)
    )
    
    # Rate limiting per customer
    guardrails.add_guardrail(
      RAAF::Guardrails::RateLimitGuardrail.new(
        max_requests_per_minute: 10,  # Per customer
        track_by: :customer_id
      )
    )
    
    # Business rules
    guardrails.add_guardrail(CustomerBusinessRulesGuardrail.new)
    
    guardrails
  end

  def setup_tracing
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)
    tracer.add_processor(RAAF::Tracing::FileSpanProcessor.new(
      "/var/log/customer_service_traces.jsonl"
    ))
    tracer
  end

  def create_agent_hierarchy
    # Tier 1: General Support
    general_agent = RAAF::Agent.new(
      name: "GeneralSupport",
      instructions: build_general_support_instructions,
      model: "gpt-4",
      max_turns: 8
    )
    
    # Tier 2: Technical Support
    technical_agent = RAAF::Agent.new(
      name: "TechnicalSupport",
      instructions: build_technical_support_instructions,
      model: "gpt-4",
      max_turns: 12
    )
    
    # Tier 2: Billing Specialist
    billing_agent = RAAF::Agent.new(
      name: "BillingSpecialist",
      instructions: build_billing_specialist_instructions,
      model: "claude-3-sonnet-20240229",
      max_turns: 10
    )
    
    # Tier 3: Manager Escalation
    manager_agent = RAAF::Agent.new(
      name: "CustomerManager",
      instructions: build_manager_instructions,
      model: "gpt-4",
      max_turns: 15
    )
    
    # Add tools to agents
    add_customer_service_tools(general_agent, technical_agent, billing_agent)
    
    {
      general: general_agent,
      technical: technical_agent,
      billing: billing_agent,
      manager: manager_agent
    }
  end

  def add_customer_service_tools(*agents)
    # Order lookup tool
    order_tool = create_order_lookup_tool
    
    # Account management tool
    account_tool = create_account_management_tool
    
    # Knowledge base search
    kb_tool = create_knowledge_base_tool
    
    # Add appropriate tools to each agent
    agents.each do |agent|
      agent.add_tool(order_tool)
      agent.add_tool(kb_tool)
      
      case agent.name
      when "BillingSpecialist"
        agent.add_tool(account_tool)
        agent.add_tool(create_billing_tools)
      when "TechnicalSupport"
        agent.add_tool(create_diagnostic_tools)
      end
    end
  end

  def setup_handoffs
    manager = RAAF::Handoffs::AdvancedHandoff.new
    
    # Define capabilities
    manager.add_agent(@agents[:general], capabilities: [
      :general_inquiry, :product_info, :order_status, :basic_troubleshooting
    ])
    
    manager.add_agent(@agents[:technical], capabilities: [
      :technical_support, :api_issues, :integration_help, :advanced_troubleshooting
    ])
    
    manager.add_agent(@agents[:billing], capabilities: [
      :billing_inquiry, :payment_issues, :refunds, :account_management
    ])
    
    manager.add_agent(@agents[:manager], capabilities: [
      :escalation, :complaints, :refund_approval, :policy_exception
    ])
    
    # Set up handoff relationships
    @agents[:general].add_handoff(@agents[:technical])
    @agents[:general].add_handoff(@agents[:billing])
    @agents[:technical].add_handoff(@agents[:manager])
    @agents[:billing].add_handoff(@agents[:manager])
    
    manager
  end

  def process_customer_request(request, customer_id, session_id)
    # Determine initial agent based on request analysis
    initial_agent = classify_request(request)
    
    # Create enhanced runner with monitoring
    runner = create_monitored_runner(initial_agent, customer_id, session_id)
    
    # Process request with automatic handoffs
    messages = [{ role: "user", content: request }]
    result = runner.run(messages)
    
    # Track satisfaction and outcomes
    track_interaction_outcome(result, customer_id, session_id)
    
    result
  end

  def classify_request(request)
    # Simple classification logic (could use ML model)
    keywords = {
      billing: ["bill", "charge", "payment", "refund", "invoice"],
      technical: ["api", "error", "bug", "integration", "code"],
      manager: ["complaint", "escalate", "manager", "unsatisfied"]
    }
    
    request_lower = request.downcase
    
    keywords.each do |type, words|
      return @agents[type] if words.any? { |word| request_lower.include?(word) }
    end
    
    @agents[:general]  # Default to general support
  end

  def create_monitored_runner(agent, customer_id, session_id)
    runner = RAAF::Runner.new(
      agent: agent,
      tracer: @tracer,
      config: RAAF::RunConfig.new(
        trace_include_sensitive_data: false,  # Privacy compliance
        workflow_name: "customer_service"
      )
    )
    
    # Wrap with monitoring
    MonitoredRunner.new(runner, @tracker, customer_id, session_id)
  end

  def track_interaction_outcome(result, customer_id, session_id)
    # Analyze outcome (simplified - could use sentiment analysis)
    last_message = result.messages.last[:content]
    
    # Determine satisfaction score based on resolution
    satisfaction_score = calculate_satisfaction_score(result, last_message)
    
    # Determine outcome
    outcome = if result.last_agent.name == "CustomerManager"
                :escalated
              elsif last_message.include?("resolved") || last_message.include?("fixed")
                :resolved
              else
                :in_progress
              end
    
    # Track the interaction
    @tracker.track_agent_interaction(
      agent_name: result.last_agent.name,
      user_id: customer_id,
      session_id: session_id,
      duration: calculate_interaction_duration(result),
      satisfaction_score: satisfaction_score,
      outcome: outcome,
      turns: result.turns,
      handoffs: count_handoffs(result)
    )
  end

  # Custom guardrail for business rules
  class CustomerBusinessRulesGuardrail < RAAF::Guardrails::BaseGuardrail
    def validate_input(input)
      # Check for PII in customer requests
      if contains_sensitive_data?(input[:query])
        raise RAAF::Guardrails::GuardrailError, 
              "Request contains sensitive data that cannot be processed"
      end
      
      # Validate customer priority access
      if input[:priority] == :vip && !vip_customer?(input[:customer_id])
        input[:priority] = :normal  # Downgrade non-VIP customers
      end
    end
    
    private
    
    def contains_sensitive_data?(text)
      # Check for SSN, credit card numbers, etc.
      text.match?(/\b\d{3}-\d{2}-\d{4}\b/) ||  # SSN
      text.match?(/\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/)  # Credit card
    end
    
    def vip_customer?(customer_id)
      # Check customer tier (would query database in real implementation)
      %w[vip_001 vip_002 enterprise_001].include?(customer_id)
    end
  end

  # Monitoring wrapper for runners
  class MonitoredRunner
    def initialize(runner, tracker, customer_id, session_id)
      @runner = runner
      @tracker = tracker
      @customer_id = customer_id
      @session_id = session_id
    end
    
    def run(messages, **kwargs)
      start_time = Time.current
      
      begin
        result = @runner.run(messages, **kwargs)
        
        # Track successful API calls
        @tracker.track_api_call(
          provider: "openai",
          model: @runner.agent.model,
          tokens_used: result.usage || { total_tokens: 0 },
          cost: calculate_cost(result.usage),
          duration: Time.current - start_time
        )
        
        result
      rescue => e
        # Track errors
        @tracker.track_error(@customer_id, @session_id, e)
        raise
      end
    end
    
    private
    
    def calculate_cost(usage)
      return 0.0 unless usage
      
      # OpenAI GPT-4 pricing (as of 2024)
      input_cost = (usage[:prompt_tokens] || 0) * 0.00003
      output_cost = (usage[:completion_tokens] || 0) * 0.00006
      
      input_cost + output_cost
    end
  end
  
  # Tool creation methods (simplified)
  def create_order_lookup_tool
    RAAF::FunctionTool.new(
      proc do |order_id|
        # In production, this would query your order database
        {
          order_id: order_id,
          status: "shipped",
          tracking: "1Z999AA1234567890",
          estimated_delivery: "2024-01-20"
        }.to_json
      end,
      name: "lookup_order",
      description: "Look up order status and tracking information",
      parameters: {
        type: "object",
        properties: {
          order_id: { type: "string", description: "Customer order ID" }
        },
        required: ["order_id"]
      }
    )
  end

  def build_general_support_instructions
    <<~INSTRUCTIONS
      You are a friendly and professional customer support representative. 
      
      Your role:
      - Handle general customer inquiries professionally
      - Look up order information when requested
      - Provide product information and guidance
      - Escalate complex issues to appropriate specialists
      
      Escalation rules:
      - Technical issues (API, integration, bugs) → Transfer to TechnicalSupport
      - Billing, payments, refunds → Transfer to BillingSpecialist  
      - Angry customers or policy exceptions → Transfer to CustomerManager
      
      Always be helpful, patient, and professional.
    INSTRUCTIONS
  end

  # Additional instruction builders...
  def build_technical_support_instructions
    "You are a technical support specialist. Handle API issues, integration problems, and complex troubleshooting. Escalate to CustomerManager if customer is unsatisfied with technical resolution."
  end

  def build_billing_specialist_instructions
    "You are a billing specialist. Handle payment issues, refunds, account management, and billing inquiries. You can process refunds up to $500. Escalate larger refunds to CustomerManager."
  end

  def build_manager_instructions
    "You are a customer service manager. Handle escalated issues, complaints, and policy exceptions. You have authority to approve refunds, make policy exceptions, and resolve complex situations."
  end
end

# Usage example
service = EnterpriseCustomerService.new

# Handle various customer requests
result1 = service.handle_request(
  "I need help with API integration errors", 
  "customer_123"
)

result2 = service.handle_request(
  "I want a refund for order #12345", 
  "vip_customer_001",
  priority: :vip
)

puts "Handled #{result1.turns} conversation turns"
puts "Final agent: #{result1.last_agent.name}"
```

---

## Research & Analysis Platform

An AI-powered research platform with multiple data sources, structured output, and comprehensive analysis capabilities.

```ruby
require 'raaf'

class ResearchPlatform
  def initialize
    @research_agent = create_research_agent
    @analysis_agent = create_analysis_agent
    @report_agent = create_report_agent
    
    @tools = setup_research_tools
    @schemas = setup_output_schemas
    
    add_tools_to_agents
  end

  def conduct_comprehensive_research(topic, depth: :standard, format: :report)
    research_config = RAAF::RunConfig.new(
      max_turns: depth == :deep ? 20 : 10,
      trace_include_sensitive_data: true,
      workflow_name: "research_analysis"
    )

    # Phase 1: Information Gathering
    research_data = gather_research_data(topic, research_config)
    
    # Phase 2: Analysis
    analysis_results = analyze_research_data(research_data, research_config)
    
    # Phase 3: Report Generation
    final_report = generate_report(topic, analysis_results, format, research_config)
    
    {
      topic: topic,
      research_data: research_data,
      analysis: analysis_results,
      report: final_report,
      metadata: {
        depth: depth,
        format: format,
        sources_count: count_sources(research_data),
        confidence_score: calculate_confidence(analysis_results)
      }
    }
  end

  private

  def create_research_agent
    RAAF::Agent.new(
      name: "ResearchSpecialist",
      instructions: build_research_instructions,
      model: "gpt-4",
      max_turns: 15
    )
  end

  def create_analysis_agent
    RAAF::Agent.new(
      name: "DataAnalyst",
      instructions: build_analysis_instructions,
      model: "claude-3-sonnet-20240229",
      max_turns: 10
    )
  end

  def create_report_agent
    RAAF::Agent.new(
      name: "ReportWriter",
      instructions: build_report_instructions,
      model: "gpt-4",
      max_turns: 8
    )
  end

  def setup_research_tools
    {
      file_search: RAAF::Tools::FileSearchTool.new(
        search_paths: ["./research_docs", "./papers", "./reports"],
        file_extensions: [".pdf", ".md", ".txt", ".docx"],
        max_results: 20
      ),
      
      web_search: RAAF::Tools::WebSearchTool.new(
        search_engine: "duckduckgo",
        max_results: 15
      ),
      
      academic_search: create_academic_search_tool,
      
      data_analysis: create_data_analysis_tool,
      
      citation_formatter: create_citation_tool
    }
  end

  def setup_output_schemas
    {
      research_findings: RAAF::StructuredOutput::ObjectSchema.build do
        string :topic, required: true
        array :key_findings, required: true, items: {
          type: "object",
          properties: {
            finding: { type: "string" },
            evidence: { type: "string" },
            confidence: { type: "number", minimum: 0.0, maximum: 1.0 },
            source_type: { type: "string", enum: ["academic", "web", "document", "data"] }
          }
        }
        array :sources, required: true, items: {
          type: "object", 
          properties: {
            title: { type: "string" },
            url: { type: "string" },
            type: { type: "string" },
            relevance_score: { type: "number", minimum: 0.0, maximum: 1.0 },
            publication_date: { type: "string" }
          }
        }
        object :methodology, properties: {
          search_strategy: { type: "string" },
          data_sources: { type: "array", items: { type: "string" } },
          limitations: { type: "array", items: { type: "string" } }
        }
        number :overall_confidence, required: true, minimum: 0.0, maximum: 1.0
      end,

      analysis_results: RAAF::StructuredOutput::ObjectSchema.build do
        string :research_topic, required: true
        array :main_themes, required: true, items: {
          type: "object",
          properties: {
            theme: { type: "string" },
            description: { type: "string" },
            supporting_evidence: { type: "array", items: { type: "string" } },
            weight: { type: "number", minimum: 0.0, maximum: 1.0 }
          }
        }
        object :trend_analysis, properties: {
          emerging_trends: { type: "array", items: { type: "string" } },
          declining_trends: { type: "array", items: { type: "string" } },
          stable_patterns: { type: "array", items: { type: "string" } }
        }
        array :recommendations, items: {
          type: "object",
          properties: {
            recommendation: { type: "string" },
            rationale: { type: "string" },
            priority: { type: "string", enum: ["high", "medium", "low"] },
            implementation_complexity: { type: "string", enum: ["low", "medium", "high"] }
          }
        }
        object :gaps_and_limitations, properties: {
          data_gaps: { type: "array", items: { type: "string" } },
          methodological_limitations: { type: "array", items: { type: "string" } },
          future_research_needed: { type: "array", items: { type: "string" } }
        }
      end
    }
  end

  def add_tools_to_agents
    # Research agent gets information gathering tools
    @research_agent.add_tool(@tools[:file_search])
    @research_agent.add_tool(@tools[:web_search])
    @research_agent.add_tool(@tools[:academic_search])
    
    # Analysis agent gets analytical tools
    @analysis_agent.add_tool(@tools[:data_analysis])
    @analysis_agent.add_tool(@tools[:file_search])  # To reference gathered data
    
    # Report agent gets formatting and citation tools
    @report_agent.add_tool(@tools[:citation_formatter])
    @report_agent.add_tool(@tools[:file_search])  # To access previous phases
  end

  def gather_research_data(topic, config)
    runner = RAAF::Runner.new(agent: @research_agent)
    
    messages = [{
      role: "user",
      content: build_research_prompt(topic)
    }]
    
    result = runner.run(messages, config: config)
    
    # Extract and validate structured data
    research_text = result.messages.last[:content]
    parsed_data = extract_research_findings(research_text)
    
    # Validate against schema
    @schemas[:research_findings].validate(parsed_data)
  end

  def analyze_research_data(research_data, config)
    runner = RAAF::Runner.new(agent: @analysis_agent)
    
    analysis_prompt = build_analysis_prompt(research_data)
    messages = [{ role: "user", content: analysis_prompt }]
    
    result = runner.run(messages, config: config)
    
    # Extract and validate analysis
    analysis_text = result.messages.last[:content]
    parsed_analysis = extract_analysis_results(analysis_text)
    
    @schemas[:analysis_results].validate(parsed_analysis)
  end

  def generate_report(topic, analysis_results, format, config)
    runner = RAAF::Runner.new(agent: @report_agent)
    
    report_prompt = build_report_prompt(topic, analysis_results, format)
    messages = [{ role: "user", content: report_prompt }]
    
    result = runner.run(messages, config: config)
    result.messages.last[:content]
  end

  # Tool creation methods
  def create_academic_search_tool
    RAAF::FunctionTool.new(
      proc do |query, limit = 10|
        # In production, integrate with APIs like:
        # - arXiv API
        # - PubMed API  
        # - Google Scholar (via SerpApi)
        # - CrossRef API
        
        # Simulated academic search results
        results = [
          {
            title: "Advanced Applications of #{query}",
            authors: ["Smith, J.", "Doe, A."],
            journal: "Journal of Advanced Research",
            year: 2024,
            doi: "10.1000/182",
            abstract: "This paper explores...",
            citation_count: 45,
            url: "https://example.com/paper1"
          }
        ]
        
        JSON.pretty_generate({
          query: query,
          total_results: results.length,
          results: results
        })
      end,
      name: "academic_search",
      description: "Search academic databases for scholarly articles and papers",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Academic search query" },
          limit: { type: "integer", description: "Maximum results", default: 10 }
        },
        required: ["query"]
      }
    )
  end

  def create_data_analysis_tool
    RAAF::FunctionTool.new(
      proc do |data_type, analysis_type = "summary"|
        # In production, integrate with:
        # - Pandas/NumPy for data analysis
        # - R integration
        # - Statistical analysis libraries
        
        case analysis_type
        when "summary"
          analyze_data_summary(data_type)
        when "trend"
          analyze_trends(data_type)
        when "correlation"
          analyze_correlations(data_type)
        else
          "Unknown analysis type: #{analysis_type}"
        end
      end,
      name: "analyze_data",
      description: "Perform statistical analysis on research data",
      parameters: {
        type: "object",
        properties: {
          data_type: { type: "string", description: "Type of data to analyze" },
          analysis_type: { 
            type: "string", 
            enum: ["summary", "trend", "correlation"],
            description: "Type of analysis to perform"
          }
        },
        required: ["data_type"]
      }
    )
  end

  def create_citation_tool
    RAAF::FunctionTool.new(
      proc do |sources, style = "APA"|
        # Format citations in requested style
        formatted_citations = sources.map do |source|
          format_citation(source, style)
        end
        
        {
          style: style,
          citations: formatted_citations,
          bibliography: formatted_citations.join("\n\n")
        }.to_json
      end,
      name: "format_citations",
      description: "Format academic citations in various styles",
      parameters: {
        type: "object",
        properties: {
          sources: {
            type: "array",
            items: { type: "object" },
            description: "List of sources to cite"
          },
          style: {
            type: "string",
            enum: ["APA", "MLA", "Chicago", "Harvard"],
            default: "APA",
            description: "Citation style"
          }
        },
        required: ["sources"]
      }
    )
  end

  # Prompt builders
  def build_research_instructions
    <<~INSTRUCTIONS
      You are a professional research specialist with expertise in conducting comprehensive literature reviews and data gathering.

      Your responsibilities:
      1. Gather information from multiple sources (documents, web, academic papers)
      2. Evaluate source credibility and relevance
      3. Extract key findings with supporting evidence
      4. Document methodology and limitations
      5. Provide confidence assessments for all findings

      Research process:
      1. Start with broad searches to understand the topic landscape
      2. Use academic sources for scholarly evidence
      3. Supplement with current web sources for recent developments
      4. Cross-reference findings across multiple sources
      5. Note any conflicting information or gaps

      Always be thorough, objective, and cite your sources properly.
    INSTRUCTIONS
  end

  def build_analysis_instructions
    <<~INSTRUCTIONS
      You are a data analyst specializing in research synthesis and trend analysis.

      Your role:
      1. Analyze research findings to identify patterns and themes
      2. Synthesize information across multiple sources
      3. Identify emerging trends and declining patterns
      4. Provide evidence-based recommendations
      5. Highlight data gaps and limitations

      Analysis approach:
      1. Look for recurring themes across sources
      2. Weigh evidence quality and source credibility
      3. Identify contradictions and attempt to resolve them
      4. Consider temporal aspects and trend directions
      5. Assess statistical significance where applicable

      Be analytical, objective, and evidence-based in all assessments.
    INSTRUCTIONS
  end

  def build_report_instructions
    <<~INSTRUCTIONS
      You are a professional report writer specializing in research documentation.

      Your responsibilities:
      1. Create clear, well-structured reports
      2. Present findings in logical sequence
      3. Use appropriate formatting for the requested format
      4. Include proper citations and references
      5. Ensure accessibility for the target audience

      Report structure:
      1. Executive summary
      2. Methodology
      3. Key findings
      4. Analysis and insights
      5. Recommendations
      6. Limitations and future research
      7. References

      Adapt your writing style to the requested format and maintain professional standards.
    INSTRUCTIONS
  end

  def build_research_prompt(topic)
    <<~PROMPT
      Conduct comprehensive research on: #{topic}

      Please gather information from multiple sources and provide:

      1. Key findings with supporting evidence
      2. Source information and credibility assessment
      3. Methodology used for research
      4. Overall confidence in findings
      5. Any limitations or gaps identified

      Use the available tools to search documents, web sources, and academic databases.
      Be thorough and objective in your research.
    PROMPT
  end

  def build_analysis_prompt(research_data)
    <<~PROMPT
      Analyze the following research data and provide comprehensive insights:

      Research Data:
      #{JSON.pretty_generate(research_data)}

      Please provide:

      1. Main themes and patterns identified
      2. Trend analysis (emerging, declining, stable)
      3. Evidence-based recommendations
      4. Data gaps and methodological limitations
      5. Confidence assessment for each conclusion

      Use analytical tools where appropriate and be thorough in your analysis.
    PROMPT
  end

  def build_report_prompt(topic, analysis_results, format)
    <<~PROMPT
      Generate a #{format} on the topic: #{topic}

      Based on the following analysis results:
      #{JSON.pretty_generate(analysis_results)}

      Please create a professional #{format} that includes:

      1. Executive summary
      2. Methodology overview
      3. Key findings presentation
      4. Analysis and insights
      5. Recommendations with rationale
      6. Limitations and future research directions
      7. Proper citations and references

      Format the output appropriately for #{format} style.
    PROMPT
  end

  # Helper methods for data extraction and processing
  def extract_research_findings(text)
    # In production, use more sophisticated parsing
    # This is a simplified version
    {
      topic: extract_topic(text),
      key_findings: extract_findings(text),
      sources: extract_sources(text),
      methodology: extract_methodology(text),
      overall_confidence: calculate_confidence_from_text(text)
    }
  end

  def extract_analysis_results(text)
    # Parse analysis results from agent response
    {
      research_topic: extract_topic(text),
      main_themes: extract_themes(text),
      trend_analysis: extract_trends(text),
      recommendations: extract_recommendations(text),
      gaps_and_limitations: extract_limitations(text)
    }
  end

  # Additional helper methods...
  def count_sources(research_data)
    research_data.dig(:sources)&.length || 0
  end

  def calculate_confidence(analysis_results)
    # Calculate overall confidence based on analysis
    analysis_results.dig(:overall_confidence) || 0.5
  end
end

# Usage example
platform = ResearchPlatform.new

# Conduct research
results = platform.conduct_comprehensive_research(
  "Impact of AI on software development productivity",
  depth: :deep,
  format: :executive_summary
)

puts "Research completed:"
puts "- Sources analyzed: #{results[:metadata][:sources_count]}"
puts "- Confidence score: #{results[:metadata][:confidence_score]}"
puts "- Report length: #{results[:report].length} characters"
```

---

## Code Review Assistant

An intelligent code review system that analyzes code quality, security, and best practices across multiple programming languages.

```ruby
require 'raaf'

class CodeReviewAssistant
  def initialize
    @security_agent = create_security_agent
    @quality_agent = create_quality_agent
    @performance_agent = create_performance_agent
    @documentation_agent = create_documentation_agent
    
    setup_code_analysis_tools
    configure_review_schemas
  end

  def review_code(code_content, language: nil, review_type: :comprehensive)
    # Auto-detect language if not provided
    language ||= detect_language(code_content)
    
    # Configure review based on type
    config = create_review_config(review_type)
    
    # Parallel review execution for efficiency
    review_results = execute_parallel_reviews(code_content, language, config)
    
    # Synthesize final review
    final_review = synthesize_review_results(review_results, code_content, language)
    
    {
      language: language,
      review_type: review_type,
      results: review_results,
      summary: final_review,
      metrics: calculate_review_metrics(review_results),
      recommendations: prioritize_recommendations(review_results)
    }
  end

  def review_pull_request(pr_files, context: {})
    # Review multiple files in context
    file_reviews = pr_files.map do |file|
      {
        filename: file[:filename],
        review: review_code(file[:content], language: detect_language_from_filename(file[:filename]))
      }
    end
    
    # Cross-file analysis
    integration_review = analyze_integration_issues(file_reviews, context)
    
    {
      file_reviews: file_reviews,
      integration_analysis: integration_review,
      overall_score: calculate_pr_score(file_reviews, integration_review),
      blocking_issues: identify_blocking_issues(file_reviews, integration_review)
    }
  end

  private

  def create_security_agent
    RAAF::Agent.new(
      name: "SecurityReviewer",
      instructions: build_security_instructions,
      model: "gpt-4",
      max_turns: 8
    )
  end

  def create_quality_agent
    RAAF::Agent.new(
      name: "QualityReviewer", 
      instructions: build_quality_instructions,
      model: "claude-3-sonnet-20240229",
      max_turns: 10
    )
  end

  def create_performance_agent
    RAAF::Agent.new(
      name: "PerformanceReviewer",
      instructions: build_performance_instructions,
      model: "gpt-4",
      max_turns: 8
    )
  end

  def create_documentation_agent
    RAAF::Agent.new(
      name: "DocumentationReviewer",
      instructions: build_documentation_instructions,
      model: "gpt-4",
      max_turns: 6
    )
  end

  def setup_code_analysis_tools
    # Static analysis tool
    @static_analyzer = create_static_analysis_tool
    
    # Security scanner
    @security_scanner = create_security_scanner_tool
    
    # Complexity analyzer
    @complexity_analyzer = create_complexity_tool
    
    # Best practices checker
    @best_practices_checker = create_best_practices_tool
    
    # Documentation analyzer
    @doc_analyzer = create_documentation_tool
    
    # Add tools to appropriate agents
    [@security_agent, @quality_agent, @performance_agent].each do |agent|
      agent.add_tool(@static_analyzer)
    end
    
    @security_agent.add_tool(@security_scanner)
    @quality_agent.add_tool(@best_practices_checker)
    @performance_agent.add_tool(@complexity_analyzer)
    @documentation_agent.add_tool(@doc_analyzer)
  end

  def configure_review_schemas
    @schemas = {
      security_review: create_security_schema,
      quality_review: create_quality_schema,
      performance_review: create_performance_schema,
      documentation_review: create_documentation_schema
    }
  end

  def execute_parallel_reviews(code_content, language, config)
    # Use Ruby's parallel execution (could use Async gem for true async)
    reviews = {}
    
    # Security review
    security_thread = Thread.new do
      reviews[:security] = conduct_security_review(code_content, language, config)
    end
    
    # Quality review
    quality_thread = Thread.new do
      reviews[:quality] = conduct_quality_review(code_content, language, config)
    end
    
    # Performance review
    performance_thread = Thread.new do
      reviews[:performance] = conduct_performance_review(code_content, language, config)
    end
    
    # Documentation review
    documentation_thread = Thread.new do
      reviews[:documentation] = conduct_documentation_review(code_content, language, config)
    end
    
    # Wait for all reviews to complete
    [security_thread, quality_thread, performance_thread, documentation_thread].each(&:join)
    
    reviews
  end

  def conduct_security_review(code_content, language, config)
    runner = RAAF::Runner.new(agent: @security_agent)
    
    prompt = build_security_review_prompt(code_content, language)
    messages = [{ role: "user", content: prompt }]
    
    result = runner.run(messages, config: config)
    
    # Parse and validate security review
    review_text = result.messages.last[:content]
    parsed_review = parse_security_review(review_text)
    
    @schemas[:security_review].validate(parsed_review)
  end

  def conduct_quality_review(code_content, language, config)
    runner = RAAF::Runner.new(agent: @quality_agent)
    
    prompt = build_quality_review_prompt(code_content, language)
    messages = [{ role: "user", content: prompt }]
    
    result = runner.run(messages, config: config)
    
    review_text = result.messages.last[:content]
    parsed_review = parse_quality_review(review_text)
    
    @schemas[:quality_review].validate(parsed_review)
  end

  def conduct_performance_review(code_content, language, config)
    runner = RAAF::Runner.new(agent: @performance_agent)
    
    prompt = build_performance_review_prompt(code_content, language)
    messages = [{ role: "user", content: prompt }]
    
    result = runner.run(messages, config: config)
    
    review_text = result.messages.last[:content]
    parsed_review = parse_performance_review(review_text)
    
    @schemas[:performance_review].validate(parsed_review)
  end

  def conduct_documentation_review(code_content, language, config)
    runner = RAAF::Runner.new(agent: @documentation_agent)
    
    prompt = build_documentation_review_prompt(code_content, language)
    messages = [{ role: "user", content: prompt }]
    
    result = runner.run(messages, config: config)
    
    review_text = result.messages.last[:content]
    parsed_review = parse_documentation_review(review_text)
    
    @schemas[:documentation_review].validate(parsed_review)
  end

  # Tool creation methods
  def create_static_analysis_tool
    RAAF::FunctionTool.new(
      proc do |code, language|
        # In production, integrate with tools like:
        # - RuboCop for Ruby
        # - ESLint for JavaScript
        # - Pylint for Python
        # - SonarQube API
        
        analyze_code_structure(code, language)
      end,
      name: "static_analysis",
      description: "Perform static code analysis",
      parameters: {
        type: "object",
        properties: {
          code: { type: "string", description: "Code to analyze" },
          language: { type: "string", description: "Programming language" }
        },
        required: ["code", "language"]
      }
    )
  end

  def create_security_scanner_tool
    RAAF::FunctionTool.new(
      proc do |code, language|
        # Security-focused analysis
        vulnerabilities = []
        
        # Check for common vulnerabilities
        vulnerabilities += check_sql_injection(code) if database_code?(code)
        vulnerabilities += check_xss_vulnerabilities(code) if web_code?(code)
        vulnerabilities += check_insecure_patterns(code, language)
        vulnerabilities += check_hardcoded_secrets(code)
        
        {
          language: language,
          total_vulnerabilities: vulnerabilities.length,
          vulnerabilities: vulnerabilities,
          security_score: calculate_security_score(vulnerabilities)
        }.to_json
      end,
      name: "security_scan",
      description: "Scan code for security vulnerabilities",
      parameters: {
        type: "object", 
        properties: {
          code: { type: "string", description: "Code to scan" },
          language: { type: "string", description: "Programming language" }
        },
        required: ["code", "language"]
      }
    )
  end

  def create_complexity_tool
    RAAF::FunctionTool.new(
      proc do |code, language|
        metrics = {
          cyclomatic_complexity: calculate_cyclomatic_complexity(code, language),
          cognitive_complexity: calculate_cognitive_complexity(code, language),
          maintainability_index: calculate_maintainability_index(code, language),
          lines_of_code: count_lines_of_code(code),
          function_count: count_functions(code, language),
          class_count: count_classes(code, language)
        }
        
        {
          language: language,
          metrics: metrics,
          complexity_score: calculate_overall_complexity_score(metrics),
          recommendations: generate_complexity_recommendations(metrics)
        }.to_json
      end,
      name: "analyze_complexity",
      description: "Analyze code complexity metrics",
      parameters: {
        type: "object",
        properties: {
          code: { type: "string", description: "Code to analyze" },
          language: { type: "string", description: "Programming language" }
        },
        required: ["code", "language"]
      }
    )
  end

  # Schema creation methods
  def create_security_schema
    RAAF::StructuredOutput::ObjectSchema.build do
      string :language, required: true
      number :security_score, required: true, minimum: 0.0, maximum: 10.0
      array :vulnerabilities, required: true, items: {
        type: "object",
        properties: {
          type: { type: "string" },
          severity: { type: "string", enum: ["critical", "high", "medium", "low"] },
          description: { type: "string" },
          line_number: { type: "integer" },
          recommendation: { type: "string" },
          cwe_id: { type: "string" }  # Common Weakness Enumeration ID
        }
      }
      array :security_recommendations, items: { type: "string" }
      boolean :blocks_deployment, required: true
    end
  end

  def create_quality_schema
    RAAF::StructuredOutput::ObjectSchema.build do
      string :language, required: true
      number :quality_score, required: true, minimum: 0.0, maximum: 10.0
      object :code_smells, properties: {
        duplicated_code: { type: "array", items: { type: "object" } },
        long_methods: { type: "array", items: { type: "object" } },
        large_classes: { type: "array", items: { type: "object" } },
        dead_code: { type: "array", items: { type: "object" } }
      }
      object :best_practices, properties: {
        naming_conventions: { type: "boolean" },
        error_handling: { type: "boolean" },
        code_organization: { type: "boolean" },
        testing_coverage: { type: "number", minimum: 0.0, maximum: 1.0 }
      }
      array :improvement_suggestions, items: {
        type: "object",
        properties: {
          category: { type: "string" },
          description: { type: "string" },
          priority: { type: "string", enum: ["high", "medium", "low"] },
          effort: { type: "string", enum: ["low", "medium", "high"] }
        }
      }
    end
  end

  # Instruction builders
  def build_security_instructions
    <<~INSTRUCTIONS
      You are a cybersecurity expert specializing in secure code review.

      Your responsibilities:
      1. Identify security vulnerabilities and weaknesses
      2. Assess risk levels and potential impact
      3. Provide specific remediation recommendations
      4. Check for compliance with security standards (OWASP, etc.)
      5. Evaluate authentication and authorization mechanisms

      Focus areas:
      - Injection vulnerabilities (SQL, XSS, etc.)
      - Authentication and session management
      - Cryptographic implementations
      - Input validation and sanitization
      - Access control and permissions
      - Data exposure and privacy
      - Hardcoded secrets and credentials

      Always provide specific, actionable security recommendations.
    INSTRUCTIONS
  end

  def build_quality_instructions
    <<~INSTRUCTIONS
      You are a senior software engineer specializing in code quality and maintainability.

      Your responsibilities:
      1. Evaluate code structure and organization
      2. Identify code smells and anti-patterns
      3. Assess adherence to best practices
      4. Review naming conventions and readability
      5. Evaluate error handling and robustness

      Quality aspects to review:
      - Code organization and modularity
      - Naming conventions and clarity
      - Function/method length and complexity
      - Error handling and edge cases
      - Code duplication and reusability
      - Testing coverage and quality
      - Documentation and comments

      Provide constructive feedback with specific improvement suggestions.
    INSTRUCTIONS
  end

  def build_performance_instructions
    <<~INSTRUCTIONS
      You are a performance optimization expert specializing in code efficiency.

      Your responsibilities:
      1. Identify performance bottlenecks and inefficiencies
      2. Analyze algorithmic complexity
      3. Review resource usage patterns
      4. Evaluate scalability concerns
      5. Suggest optimization strategies

      Performance areas to analyze:
      - Algorithmic complexity (time/space)
      - Database query optimization
      - Memory usage and leaks
      - I/O operations and blocking calls
      - Caching strategies
      - Concurrent programming issues
      - Resource management

      Focus on measurable performance improvements with clear impact.
    INSTRUCTIONS
  end

  def build_documentation_instructions
    <<~INSTRUCTIONS
      You are a technical documentation specialist focused on code documentation quality.

      Your responsibilities:
      1. Evaluate code documentation completeness
      2. Assess comment quality and usefulness
      3. Review API documentation
      4. Check for inline documentation standards
      5. Evaluate code self-documentation

      Documentation aspects to review:
      - Function/method documentation
      - Class and module documentation
      - Inline comments quality
      - README and setup documentation
      - API documentation completeness
      - Code examples and usage
      - Architecture documentation

      Emphasize clear, maintainable, and helpful documentation.
    INSTRUCTIONS
  end

  # Prompt builders
  def build_security_review_prompt(code, language)
    <<~PROMPT
      Please conduct a comprehensive security review of the following #{language} code:

      ```#{language}
      #{code}
      ```

      Analyze for:
      1. Security vulnerabilities (injection, XSS, etc.)
      2. Authentication and authorization issues
      3. Cryptographic problems
      4. Input validation gaps
      5. Data exposure risks
      6. Hardcoded secrets

      Use the security scanning tools available and provide a detailed security assessment.
    PROMPT
  end

  def build_quality_review_prompt(code, language)
    <<~PROMPT
      Please conduct a code quality review of the following #{language} code:

      ```#{language}
      #{code}
      ```

      Evaluate:
      1. Code structure and organization
      2. Naming conventions and readability
      3. Best practices adherence
      4. Code smells and anti-patterns
      5. Error handling implementation
      6. Testing considerations

      Use the static analysis tools and provide specific improvement recommendations.
    PROMPT
  end

  def build_performance_review_prompt(code, language)
    <<~PROMPT
      Please conduct a performance review of the following #{language} code:

      ```#{language}
      #{code}
      ```

      Analyze:
      1. Algorithmic efficiency
      2. Resource usage patterns
      3. Potential bottlenecks
      4. Scalability concerns
      5. Memory management
      6. I/O operations

      Use the complexity analysis tools and suggest performance optimizations.
    PROMPT
  end

  def build_documentation_review_prompt(code, language)
    <<~PROMPT
      Please review the documentation quality of the following #{language} code:

      ```#{language}
      #{code}
      ```

      Assess:
      1. Function/method documentation completeness
      2. Comment quality and usefulness
      3. Code self-documentation
      4. Missing documentation areas
      5. Documentation clarity and accuracy

      Use the documentation analysis tools and suggest improvements.
    PROMPT
  end

  # Helper methods for code analysis
  def detect_language(code)
    # Simple language detection based on syntax patterns
    return "ruby" if code.match?(/def\s+\w+.*\n.*end\b/)
    return "python" if code.match?(/def\s+\w+.*:\n\s+/)
    return "javascript" if code.match?(/function\s+\w+.*\{|\(\s*\)\s*=>\s*\{/)
    return "java" if code.match?/(public|private|protected)\s+(static\s+)?[\w<>]+\s+\w+\s*\(/)
    return "go" if code.match?/func\s+\w+.*\{/)
    
    "unknown"
  end

  def detect_language_from_filename(filename)
    case File.extname(filename)
    when ".rb" then "ruby"
    when ".py" then "python"
    when ".js", ".jsx", ".ts", ".tsx" then "javascript"
    when ".java" then "java"
    when ".go" then "go"
    when ".cpp", ".cc", ".cxx" then "cpp"
    when ".c" then "c"
    when ".cs" then "csharp"
    when ".php" then "php"
    else "unknown"
    end
  end

  def create_review_config(review_type)
    case review_type
    when :quick
      RAAF::RunConfig.new(max_turns: 3, workflow_name: "quick_code_review")
    when :standard
      RAAF::RunConfig.new(max_turns: 5, workflow_name: "standard_code_review")
    when :comprehensive
      RAAF::RunConfig.new(max_turns: 8, workflow_name: "comprehensive_code_review")
    else
      RAAF::RunConfig.new(max_turns: 5, workflow_name: "code_review")
    end
  end

  # Additional helper methods for parsing, analysis, and metrics...
  def synthesize_review_results(review_results, code_content, language)
    # Combine all review results into a comprehensive summary
    overall_score = calculate_overall_score(review_results)
    critical_issues = extract_critical_issues(review_results)
    top_recommendations = extract_top_recommendations(review_results)
    
    {
      overall_score: overall_score,
      critical_issues: critical_issues,
      top_recommendations: top_recommendations,
      review_summary: generate_review_summary(review_results, overall_score)
    }
  end

  def calculate_review_metrics(review_results)
    {
      security_score: review_results.dig(:security, :security_score) || 0,
      quality_score: review_results.dig(:quality, :quality_score) || 0,
      performance_score: review_results.dig(:performance, :performance_score) || 0,
      documentation_score: review_results.dig(:documentation, :documentation_score) || 0,
      total_issues: count_total_issues(review_results),
      blocking_issues: count_blocking_issues(review_results)
    }
  end
end

# Usage example
reviewer = CodeReviewAssistant.new

# Review a single file
code_to_review = File.read("app/controllers/users_controller.rb")
review_result = reviewer.review_code(
  code_to_review,
  language: "ruby",
  review_type: :comprehensive
)

puts "Overall Score: #{review_result[:summary][:overall_score]}/10"
puts "Critical Issues: #{review_result[:metrics][:blocking_issues]}"
puts "Top Recommendation: #{review_result[:recommendations].first}"

# Review a pull request
pr_files = [
  { filename: "app/models/user.rb", content: File.read("app/models/user.rb") },
  { filename: "app/controllers/users_controller.rb", content: File.read("app/controllers/users_controller.rb") }
]

pr_review = reviewer.review_pull_request(pr_files, context: { feature: "user_management" })
puts "PR Score: #{pr_review[:overall_score]}/10"
puts "Blocking Issues: #{pr_review[:blocking_issues].length}"
```

This comprehensive example demonstrates:

1. **Multi-agent Architecture** - Specialized agents for different review aspects
2. **Parallel Processing** - Concurrent reviews for efficiency
3. **Structured Output** - Schema validation for consistent results
4. **Tool Integration** - Static analysis and security scanning tools
5. **Language Support** - Multi-language code analysis
6. **Pull Request Review** - Context-aware multi-file analysis
7. **Enterprise Features** - Comprehensive metrics and reporting

For more examples, see the `examples/` directory in the repository.