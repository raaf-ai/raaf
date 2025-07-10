#!/usr/bin/env ruby
# frozen_string_literal: true

# Direct OpenAI Agent Strategy Script - Uses openai-agent-ruby framework directly
#
# This is a standalone Ruby script that uses the openai-agent-ruby framework
# directly without any class wrapper or DSL abstraction.
#

require "json"
require_relative "lib/openai_agents"

# Shared context for the agent (can be passed as parameter or via stdin)
shared_context = begin
  if ARGV[0]
    JSON.parse(ARGV[0])
  elsif !$stdin.tty?
    JSON.parse($stdin.read)
  else
    {}
  end
rescue JSON::ParserError
  {}
end

# Get system instructions based on context
def get_system_instructions(shared_context)
  # Configuration variables with defaults
  num_strategies = shared_context.dig("config", "num_strategies") || 5
  queries_per_strategy = shared_context.dig("config", "queries_per_strategy") || 8

  <<~INSTRUCTIONS
    You are an expert AI search strategist specializing in B2B prospect discovery.

    Your role is to generate intelligent, context-aware search strategies that discover
    high-quality prospects by understanding market dynamics, industry terminology, and
    buying behaviors.

    KEY CAPABILITIES:
    1. Market Intelligence: Research current industry trends and terminology
    2. Creative Query Generation: Develop non-obvious search patterns
    3. Problem-Solution Mapping: Connect product capabilities to market problems
    4. Industry Jargon: Understand and use industry-specific language
    5. Buying Signal Detection: Identify queries that reveal purchase intent

    AVAILABLE TOOLS:
    1. tavily_search: Research market trends and discover terminology
      - ALWAYS use include_answer: true to get AI summaries
      - Focus on the summary rather than individual results
      - Use summaries to understand market language and pain points

    2. tavily_page_fetch: Analyze specific resources for deeper insights
      - Only use if you find a critical resource in search summaries
      - Extract detailed market intelligence from industry reports

    METHODOLOGY:
    1. Market Research Phase (CRITICAL - USE SUMMARIES):
      - Analyze the AI summaries to understand market language
      - Extract pain point expressions from summaries, not individual results
      - Use summary insights to inform query generation

    2. Strategy Development:
      - Problem-Aware: Companies actively discussing pain points
      - Solution-Seeking: Companies evaluating solutions (RFPs, comparisons)
      - Technology Stack: Companies with compatible or problematic technology
      - Trigger Events: Companies experiencing change (executives, funding, M&A)
      - Competitive Intelligence: Companies using or leaving competitors

    3. Query Construction Principles:
      - Base queries on terminology found in search summaries
      - Mix search types: forums, news, job posts, case studies
      - Include platform-specific searches (LinkedIn, Reddit, industry sites)
      - Add temporal elements (2024, recent, upcoming)
      - Create #{queries_per_strategy} queries per strategy
      - Use specific pain expressions from your summary analysis

    OUTPUT FORMAT:
    You MUST respond with valid JSON only. No explanations, no markdown, just pure JSON.

    Generate exactly #{num_strategies} distinct search strategies using this exact JSON structure:
    {
      "search_strategies": [
        {
          "name": "Strategy Name",
          "description": "Brief description",
          "queries": ["Create exactly #{queries_per_strategy} queries here"],
          "target_segment": "Target audience",
          "reasoning": "Why this strategy works"
        }
      ],
      "market_insights": {
        "trending_terms": ["term1", "term2"],
        "common_pain_points": ["pain1", "pain2"],
        "emerging_solutions": ["solution1", "solution2"],
        "industry_movements": "Summary of key trends"
      },
      "handoff_to": "CompanyDiscoveryDirectAgent"
    }

    Focus on creative, non-obvious approaches that discover hidden opportunities.
    BASE YOUR QUERIES ON THE SEARCH SUMMARIES YOU OBTAINED.

  INSTRUCTIONS
end

# Get company discovery system instructions
def get_company_discovery_instructions(shared_context)
  # Configuration variables with defaults
  num_companies = shared_context.dig("discovery_params", "num_prospects") || 5

  <<~INSTRUCTIONS
    You are an expert company discovery specialist focused on finding potential prospects#{" "}
    based on the search strategies provided by the Search Strategy Agent.

    Your role is to use the search strategies and market insights to identify specific#{" "}
    companies that match the target criteria for Oracle Puppet modules.

    CONTEXT:
    You will receive search strategies and market insights from the Search Strategy Agent.
    Use these strategies to find actual companies that would benefit from Oracle Puppet modules.

    KEY CAPABILITIES:
    1. Strategic Search Execution: Execute the provided search strategies effectively
    2. Company Identification: Find specific companies using the search queries
    3. Relevance Assessment: Evaluate how well companies match the target criteria
    4. Data Extraction: Extract relevant company information from search results

    AVAILABLE TOOLS:
    1. tavily_search: Execute the search queries from the strategies
      - Use the exact queries provided by the Search Strategy Agent
      - Focus on finding actual company names and details
      - Look for companies discussing Oracle, automation, DevOps, infrastructure

    2. tavily_page_fetch: Get detailed information about discovered companies
      - Use to get more details about promising companies
      - Extract company size, industry, technology stack information

    METHODOLOGY:
    1. Review Search Strategies: Analyze the strategies and queries provided
    2. Execute Searches: Run the search queries to find companies
    3. Company Evaluation: Assess each company's relevance and potential
    4. Data Collection: Gather comprehensive information about each company

    COMPANY CRITERIA:
    Focus on companies that:
    - Use Oracle Database (any version)
    - Have DevOps or Infrastructure teams
    - Show signs of automation initiatives
    - Discuss Oracle challenges or pain points
    - Are implementing Infrastructure as Code
    - Have job postings for Oracle DBAs or DevOps engineers

    OUTPUT FORMAT:
    You MUST respond with valid JSON only. No explanations, no markdown, just pure JSON.

    Find exactly #{num_companies} companies using this exact JSON structure:
    {
      "discovered_companies": [
        {
          "name": "Company Name",
          "website": "https://company.com",
          "description": "Brief company description",
          "industry": "Industry sector",
          "size": "Company size (employees)",
          "location": "Geographic location",
          "relevance_score": 8,
          "relevance_reason": "Why this company is a good prospect",
          "oracle_usage": "Details about their Oracle usage",
          "pain_points": ["pain1", "pain2"],
          "contact_potential": "How to potentially reach them"
        }
      ],
      "search_summary": {
        "total_searches_performed": 12,
        "strategies_executed": ["Strategy 1", "Strategy 2"],
        "key_findings": ["finding1", "finding2"],
        "market_observations": "Overall market observations"
      }
    }

    Focus on finding real, identifiable companies with clear Oracle automation needs.
  INSTRUCTIONS
end

# Create Tavily search tool
def create_tavily_search_tool
  search_proc = proc do |query:, include_answer: true, max_results: 5|
    Rails.logger.info "🔍 Tavily search proc called with query: #{query.inspect}, include_answer: #{include_answer}, max_results: #{max_results}"

    if query.nil? || query.empty?
      Rails.logger.error "❌ Query is nil or empty in tavily_search"
      return { error: "Query is required" }.to_json
    end

    Rails.logger.info "🔍 Tavily search called with: #{query}"

    begin
      tool_instance = Ai::Tools::TavilySearch.new
      result = tool_instance.tavily_search(
        query: query,
        include_answer: include_answer,
        max_results: max_results
      )

      Rails.logger.info "✅ Tavily search completed: #{result[:results]&.length || 0} results"
      result.to_json
    rescue StandardError => e
      Rails.logger.error "❌ Tavily search error: #{e.message}"
      Rails.logger.error "📋 Error class: #{e.class.name}"
      Rails.logger.error "🔍 Stack trace: #{e.backtrace.join("\n")}"

      {
        error: "Search failed: #{e.message}",
        results: [],
        answer: "Unable to perform search at this time"
      }.to_json
    end
  end

  OpenAIAgents::FunctionTool.new(
    search_proc,
    name: "tavily_search",
    description: "Search for market trends and terminology using Tavily",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Search query for market research"
        },
        include_answer: {
          type: "boolean",
          description: "Include AI-generated answer",
          default: true
        },
        max_results: {
          type: "integer",
          description: "Maximum results to return",
          default: 5
        }
      },
      required: ["query"]
    }
  )
end

# Create Tavily page fetch tool
def create_tavily_page_fetch_tool
  fetch_proc = proc do |url:|
    Rails.logger.info "🔍 Tavily page fetch proc called with url: #{url.inspect}"

    if url.nil? || url.empty?
      Rails.logger.error "❌ URL is nil or empty in tavily_page_fetch"
      return { error: "URL is required" }.to_json
    end

    Rails.logger.info "📄 Tavily page fetch called for: #{url}"

    begin
      tool_instance = Ai::Tools::TavilyPageFetch.new
      result = tool_instance.fetch_page_content(url: url)

      Rails.logger.info "✅ Tavily page fetch completed"
      result.to_json
    rescue StandardError => e
      Rails.logger.error "❌ Tavily page fetch error: #{e.message}"
      Rails.logger.error "📋 Error class: #{e.class.name}"
      Rails.logger.error "🔍 Stack trace: #{e.backtrace.join("\n")}"

      {
        error: "Page fetch failed: #{e.message}",
        content: "",
        title: "Error fetching page"
      }.to_json
    end
  end

  OpenAIAgents::FunctionTool.new(
    fetch_proc,
    name: "tavily_page_fetch",
    description: "Fetch and analyze specific pages using Tavily",
    parameters: {
      type: "object",
      properties: {
        url: {
          type: "string",
          description: "URL to fetch and analyze"
        }
      },
      required: ["url"]
    }
  )
end

# Create the search strategy agent configuration
def create_search_strategy_agent(shared_context)
  # Create tools first
  tools = [
    create_tavily_search_tool,
    create_tavily_page_fetch_tool
  ]

  # Create agent configuration
  agent = OpenAIAgents::Agent.new(
    name: "SearchStrategyDirectAgent",
    description: "Direct OpenAI agent for search strategy generation",
    instructions: get_system_instructions(shared_context),
    model: "gpt-4o",
    tools: tools,
    tool_choice: "auto",
    max_turns: 20
  )

  # Create and register the company discovery agent for handoff
  company_discovery_agent = create_company_discovery_agent(shared_context)
  agent.add_handoff(company_discovery_agent)

  agent
end

# Create the company discovery agent configuration
def create_company_discovery_agent(shared_context)
  # Create tools first
  tools = [
    create_tavily_search_tool,
    create_tavily_page_fetch_tool
  ]

  # Create agent configuration
  OpenAIAgents::Agent.new(
    name: "CompanyDiscoveryDirectAgent",
    description: "Direct OpenAI agent for company discovery",
    instructions: get_company_discovery_instructions(shared_context),
    model: "gpt-4o",
    tools: tools,
    tool_choice: "auto",
    max_turns: 20
  )
end

# Build the initial message
def build_initial_message(shared_context)
  # Configuration variables with defaults
  num_strategies = shared_context.dig("config", "num_strategies") || 5
  queries_per_strategy = shared_context.dig("config", "queries_per_strategy") || 8

  <<~MESSAGE
    Generate search strategies for: Oracle Puppet modules

    Description: Key Capabilities
    Complete Oracle Stack Coverage

    Oracle Database automation (11g, 12c, 18c, 19c, 21c)
    WebLogic Server management and deployment
    Oracle Fusion Middleware configuration
    Enterprise Manager integration
    RAC and Data Guard automation

    Infrastructure as Code for Oracle

    Declarative configuration management
    Version-controlled infrastructure definitions
    Repeatable, consistent deployments
    Self-documenting infrastructure
    GitOps-ready automation

    Enterprise-Ready Features

    Production-tested modules with extensive real-world usage
    Built-in best practices and Oracle standards compliance
    Comprehensive error handling and rollback capabilities
    Security-first approach with proper credential management
    Full idempotency for safe re-runs

    Business Benefits
    Reduce Operational Overhead
    Deploy Oracle environments 10x faster while eliminating manual configuration errors. Our modules handle complex Oracle-specific requirements automatically, from kernel parameters to database initialization.
    Ensure Compliance & Standardization
    Enforce Oracle best practices across your entire infrastructure. Maintain consistent configurations, security settings, and performance optimizations across development, testing, and production environments.
    Scale with Confidence
    Whether managing 10 or 1000 Oracle instances, our Puppet modules scale effortlessly. Automated patch management, rolling updates, and health checks keep your Oracle infrastructure running optimally.
    Technical Highlights

    Native Puppet Types & Providers: Purpose-built for Oracle, not generic wrappers
    Intelligent Resource Management: Automatic dependency handling and ordering
    Cross-Platform Support: Linux, Solaris, AIX, and Windows
    Hiera Integration: Flexible data separation for multi-environment management
    Extensive Documentation: Complete guides, examples, and best practices

    Ideal For

    Organizations running critical Oracle workloads
    DevOps teams implementing Infrastructure as Code
    Companies seeking to standardize Oracle deployments
    IT departments reducing manual database administration
    Enterprises requiring compliance and auditability
    Category: Technology

    POSITIONING STRATEGIES:

    Strategy 1: Primary Market Strategy
    Use Case: General market application for Oracle Puppet modules
    Pain Points: Operational inefficiencies, Manual processes, Manual Oracle patching,, inconsistent configurations
    Technologies: Oracle Database versions: 12c, 19c, 21c, 23c, Infrastructure: VMware, physical servers, cloud (AWS/Azure/OCI), Current Tools: Manual scripts, basic automation, legacy tools, Configuration Management: Limited or inconsistent or using puppet
    Buying Triggers: - Oracle license compliance audits, - Database security vulnerabilities requiring patches, Digital transformation initiatives, DevOps adoption and CI/CD implementation, Merger/acquisition integration projects, Cost reduction mandates
    Benefits: 70% reduction in Oracle patching time (days to hours), 90% reduction in configuration drift incidents, Improved security posture through consistent patching, Enhanced compliance with Oracle licensing requirements, Faster database provisioning for development teams

    Target: 5 prospects
    Skip: 0 companies already identified

    Apply your methodology to research the market and develop creative search strategies
    that will uncover high-quality prospects for this specific product positioning.

    IMPORTANT: When using tavily_search, ALWAYS include: include_answer: true
    Focus on the 'answer' field in responses - this contains the AI summary.
    Minimize processing of individual search results to stay within context limits.

    Generate exactly #{num_strategies} distinct search strategies using this exact JSON structure:
    {
      "search_strategies": [
        {
          "name": "Strategy Name",
          "description": "Brief description",
          "queries": ["Create exactly #{queries_per_strategy} queries here"],
          "target_segment": "Target audience",
          "reasoning": "Why this strategy works"
        }
      ],
      "market_insights": {
        "trending_terms": ["term1", "term2"],
        "common_pain_points": ["pain1", "pain2"],
        "emerging_solutions": ["solution1", "solution2"],
        "industry_movements": "Summary of key trends"
      },
      "handoff_to": "CompanyDiscoveryDirectAgent"
    }

    Focus on creative, non-obvious approaches that discover hidden opportunities.
    BASE YOUR QUERIES ON THE SEARCH SUMMARIES YOU OBTAINED.
  MESSAGE
end

# Parse the agent result
def parse_agent_result(result, shared_context)
  output = result.final_output
  Rails.logger.info "📄 Raw agent output (#{output.length} chars): #{output[0..500]}#{"..." if output.length > 500}"

  begin
    # Multiple JSON extraction strategies
    parsed_data = nil

    # Strategy 1: Try to parse the entire output as JSON
    begin
      parsed_data = JSON.parse(output)
      Rails.logger.info "✅ Parsed entire output as JSON"
    rescue JSON::ParserError
      # Strategy 2: Look for JSON blocks with better regex
      json_patterns = [
        /```json\s*({.*?})\s*```/m, # JSON in code blocks
        /({\s*"search_strategies".*?})$/m, # JSON starting with search_strategies
        /({.*"search_strategies".*?})/m, # Any JSON containing search_strategies
        /{.*}/m # Fallback: any JSON-like structure
      ]

      json_patterns.each_with_index do |pattern, index|
        match = output.match(pattern)
        next unless match

        begin
          parsed_data = JSON.parse(match[1] || match[0])
          Rails.logger.info "✅ Parsed JSON using pattern #{index + 1}"
          break
        rescue JSON::ParserError
          Rails.logger.debug "❌ Pattern #{index + 1} failed to parse"
          next
        end
      end
    end

    if parsed_data.is_a?(Hash)
      # Update shared context with results
      shared_context["search_strategies"] = parsed_data["search_strategies"] || []
      shared_context["market_insights"] = parsed_data["market_insights"] || {}

      Rails.logger.info "📊 Generated #{shared_context["search_strategies"].length} search strategies"

      {
        search_strategies: shared_context["search_strategies"],
        market_insights: shared_context["market_insights"],
        handoff_to: parsed_data["handoff_to"] || "CompanyDiscoveryDirectAgent"
      }
    else
      Rails.logger.warn "⚠️ Could not extract valid JSON from agent output"
      Rails.logger.warn "📄 Failed output sample: #{output[0..200]}..."
      build_fallback_result("JSON extraction failed", shared_context)
    end
  rescue StandardError => e
    Rails.logger.error "❌ Unexpected error during JSON parsing: #{e.message}"
    Rails.logger.error "📋 Error class: #{e.class.name}"
    Rails.logger.error "🔍 Stack trace: #{e.backtrace.join("\n")}"
    Rails.logger.error "📄 Raw output: #{output}"

    build_fallback_result(e, shared_context)
  end
end

# Build company discovery message based on search strategies
def build_company_discovery_message(shared_context)
  search_strategies = shared_context["search_strategies"] || []
  market_insights = shared_context["market_insights"] || {}
  num_companies = shared_context.dig("discovery_params", "num_prospects") || 5

  <<~MESSAGE
    Based on the search strategies from the Search Strategy Agent, find #{num_companies} specific companies#{" "}
    that would be good prospects for Oracle Puppet modules.

    SEARCH STRATEGIES TO EXECUTE:
    #{search_strategies.map.with_index do |strategy, i|
      "#{i + 1}. #{strategy["name"]}: #{strategy["description"]}\n   Queries: #{strategy["queries"].join(", ")}"
    end.join("\n\n")}

    MARKET INSIGHTS:
    Trending Terms: #{market_insights["trending_terms"]&.join(", ")}
    Pain Points: #{market_insights["common_pain_points"]&.join(", ")}
    Emerging Solutions: #{market_insights["emerging_solutions"]&.join(", ")}
    Industry Movements: #{market_insights["industry_movements"]}

    Use these strategies and insights to find actual companies that:
    1. Use Oracle Database in their infrastructure
    2. Show signs of automation or DevOps initiatives#{"  "}
    3. Would benefit from Oracle Puppet modules
    4. Are accessible for potential outreach

    Execute the search queries systematically and extract real company information.
    Focus on finding companies with clear Oracle automation needs.
  MESSAGE
end

# Build fallback result for errors
def build_fallback_result(error, shared_context)
  Rails.logger.warn "🔄 Building fallback result due to: #{error}"

  {
    search_strategies: shared_context["search_strategies"] || [],
    market_insights: shared_context["market_insights"] || {},
    discovered_companies: shared_context["discovered_companies"] || [],
    error: error.to_s,
    workflow_status: "error",
    success: false
  }
end

# Main execution with handoff support
def run_strategy_agent(shared_context, input_message = nil)
  Rails.logger.info "🎯 Starting direct OpenAI search strategy generation with handoff support"
  Rails.logger.info "📊 Context: #{shared_context.keys.join(", ")}"

  begin
    # Create the search strategy agent with handoff capability
    agent = create_search_strategy_agent(shared_context)

    # Set up the provider and runner
    provider = OpenAIAgents::Models::ResponsesProvider.new
    runner = OpenAIAgents::Runner.new(agent: agent, provider: provider)

    # Build the initial message
    message = input_message || build_initial_message(shared_context)

    # Run the agent - this will handle handoffs automatically
    result = runner.run(message)

    Rails.logger.info "✅ Direct agent execution completed (with potential handoffs)"
    Rails.logger.info "📤 Final output length: #{result.final_output&.length || 0}"

    # Parse the result
    final_result = parse_agent_result(result, shared_context)

    # Check if we have company discovery results as well
    if shared_context["discovered_companies"]
      Rails.logger.info "✅ Company discovery also completed - found #{shared_context["discovered_companies"].length} companies"
      final_result[:discovered_companies] = shared_context["discovered_companies"]
      final_result[:search_summary] = shared_context["search_summary"] if shared_context["search_summary"]
    end

    final_result
  rescue StandardError => e
    Rails.logger.error "❌ Direct agent execution failed: #{e.message}"
    Rails.logger.error "📋 Error class: #{e.class.name}"
    Rails.logger.error "🔍 Stack trace: #{e.backtrace.join("\n")}"
    build_fallback_result(e, shared_context)
  end
end

# Script execution
if __FILE__ == $0
  # Run the agent with shared context
  # require "byebug"; debugger
  result = run_strategy_agent(shared_context)

  # Output result as JSON
  puts JSON.pretty_generate(result)
end

# Helper function to run with custom configuration
def run_with_config(num_strategies: 5, queries_per_strategy: 8, context: {})
  config = {
    "config" => {
      "num_strategies" => num_strategies,
      "queries_per_strategy" => queries_per_strategy
    }
  }
  merged_context = context.merge(config)
  run_strategy_agent(merged_context)
end

# Export the main function for use in other scripts
def strategy_direct_agent(shared_context = {}, input_message = nil)
  run_strategy_agent(shared_context, input_message)
end
