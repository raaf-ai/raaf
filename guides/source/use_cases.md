**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf-ai.dev>.**

RAAF Common Use Cases
=====================

This guide presents real-world examples and patterns for common AI agent use cases including customer service, data analysis, and content creation. Learn proven approaches to implementing AI agents for business applications.

After reading this guide, you will know:

* How to implement customer service automation with RAAF
* Patterns for data analysis and business intelligence agents
* Content creation and management workflows
* Technical support and documentation assistance
* E-commerce and sales automation
* Internal process automation
* Multi-agent orchestration patterns

--------------------------------------------------------------------------------

Customer Service Automation
----------------------------

### Intelligent Support Ticket Routing

Automatically classify and route customer inquiries to the appropriate support teams.

```ruby
class SupportTicketRouter < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "Support Ticket Router"
  instructions """
  You are an intelligent support ticket router. Analyze customer inquiries and:

  1. Classify the ticket type (technical, billing, sales, general)
  2. Determine urgency level (low, medium, high, critical)
  3. Route to the appropriate team
  4. Suggest initial response templates
  5. Extract key information for the assigned agent
  """
  
  model "gpt-4o"
  
  uses_tool :knowledge_base_search
  uses_tool :crm_lookup
  
  tool :classify_ticket do |inquiry:, customer_info:|
    classification = analyze_inquiry(inquiry)
    customer_context = lookup_customer_history(customer_info)
    
    {
      ticket_type: classification[:type],
      urgency: calculate_urgency(inquiry, customer_context),
      assigned_team: route_to_team(classification[:type], classification[:complexity]),
      suggested_tags: classification[:tags],
      customer_context: customer_context,
      initial_response_template: generate_response_template(classification)
    }
  end
  
  tool :escalate_ticket do |ticket_id:, reason:|
    escalation_path = determine_escalation_path(reason)
    
    {
      escalated_to: escalation_path[:team],
      escalation_reason: reason,
      priority_boost: escalation_path[:priority_increase],
      notification_sent: notify_escalation_team(ticket_id, escalation_path)
    }
  end
end

# Usage Example
router = SupportTicketRouter.new
result = router.run("""
Customer email: I've been trying to process payments for 2 hours and keep getting 
error code 500. This is affecting our production system and we're losing sales. 
Customer ID: ENT-12345, Premium plan subscriber since 2021.
""")

puts result.messages.last[:content]
# => "This is a CRITICAL technical issue requiring immediate attention.
#     Routing to: Technical Support - Payment Systems Team
#     Urgency: CRITICAL (affecting production, enterprise customer)
#     Suggested tags: payment-gateway, error-500, production-outage
#     Initial response: Technical team notified, investigating payment gateway issues..."
```

### Multilingual Customer Support

Provide support across multiple languages with automatic translation and cultural context.

```ruby
class MultilingualSupportAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "Multilingual Support Agent"
  instructions """
  You are a multilingual customer support specialist. Your responsibilities:

  1. Detect the customer's language automatically
  2. Respond in their preferred language
  3. Maintain cultural sensitivity and appropriate tone
  4. Access knowledge base in multiple languages
  5. Escalate when language complexity exceeds your capabilities
  """
  
  model "gpt-4o"
  
  uses_tool :language_detection
  uses_tool :translation_service
  uses_tool :cultural_context_api
  uses_tool :multilingual_knowledge_base
  
  tool :handle_multilingual_inquiry do |message:, customer_id: nil|
    detected_language = detect_language(message)
    customer_profile = get_customer_language_preferences(customer_id) if customer_id
    
    # Use customer's preferred language or detected language
    response_language = customer_profile&.dig(:preferred_language) || detected_language
    
    # Get cultural context for appropriate communication style
    cultural_context = get_cultural_context(response_language)
    
    # Search knowledge base in appropriate language
    relevant_articles = search_knowledge_base(message, language: response_language)
    
    {
      detected_language: detected_language,
      response_language: response_language,
      cultural_context: cultural_context,
      relevant_articles: relevant_articles,
      greeting_style: cultural_context[:greeting_style],
      formality_level: cultural_context[:formality_level]
    }
  end
end

# Example conversation
agent = MultilingualSupportAgent.new
result = agent.run("Bonjour, j'ai un problème avec ma commande #12345. Elle n'est pas arrivée.")

puts result.messages.last[:content]
# => "Bonjour ! Je vous remercie de nous avoir contactés. Je comprends que vous avez 
#     un problème avec votre commande #12345 qui n'est pas arrivée. Je vais immédiatement 
#     vérifier le statut de votre commande et vous fournir une mise à jour..."
```

Data Analysis and Business Intelligence
---------------------------------------

### Automated Data Insights Agent

Transform raw data into actionable business insights.

```ruby
class DataInsightsAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "Data Insights Analyst"
  instructions """
  You are a senior data analyst AI. Your role is to:

  1. Analyze datasets and identify trends, patterns, and anomalies
  2. Generate executive summaries with key insights
  3. Create data visualizations and charts
  4. Provide actionable recommendations
  5. Explain complex data findings in business terms
  """
  
  model "gpt-4o"
  
  uses_tool :code_interpreter, languages: ["python", "r"]
  uses_tool :database_query
  uses_tool :file_processor
  
  tool :analyze_sales_data do |data_source:, time_period:, metrics: []|
    # Load and analyze sales data
    analysis_code = generate_analysis_script(data_source, time_period, metrics)
    results = execute_python_analysis(analysis_code)
    
    {
      summary: results[:summary],
      trends: results[:trends],
      anomalies: results[:anomalies],
      visualizations: results[:charts],
      recommendations: generate_recommendations(results),
      confidence_score: calculate_confidence(results)
    }
  end
  
  tool :create_dashboard do |metrics:, data_sources:, update_frequency:|
    dashboard_config = {
      widgets: design_dashboard_widgets(metrics),
      data_connections: setup_data_connections(data_sources),
      refresh_schedule: setup_refresh_schedule(update_frequency),
      alerts: configure_alert_thresholds(metrics)
    }
    
    dashboard_url = deploy_dashboard(dashboard_config)
    
    {
      dashboard_url: dashboard_url,
      widgets_created: dashboard_config[:widgets].count,
      data_sources_connected: data_sources.count,
      alerts_configured: dashboard_config[:alerts].count
    }
  end
end

# Usage Example
analyst = DataInsightsAgent.new
result = analyst.run("""
Analyze our Q4 2024 sales data. Focus on:

- Revenue trends by product category
- Customer acquisition costs
- Regional performance
- Seasonal patterns
- Identify any concerning drops or unusual spikes
""")

puts result.messages.last[:content]
# => "Q4 2024 Sales Analysis Summary:
#     
#     KEY FINDINGS:
#     📈 Revenue up 23% vs Q4 2023 ($2.1M → $2.6M)
#     🏆 Enterprise software category led growth (+45%)
#     🌍 APAC region showed strongest performance (+31%)
#     ⚠️  Customer acquisition cost increased 18% - needs attention
#     
#     RECOMMENDATIONS:
#     1. Expand enterprise software offerings
#     2. Investigate APAC success factors for other regions
#     3. Optimize marketing spend to reduce CAC..."
```

### Predictive Analytics Assistant

Forecast business metrics and identify future opportunities or risks.

```ruby
class PredictiveAnalyticsAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "Predictive Analytics Specialist"
  instructions """
  You are an expert in predictive analytics and forecasting. Your capabilities include:

  1. Building and evaluating predictive models
  2. Time series forecasting
  3. Risk assessment and scenario planning
  4. A/B test design and analysis
  5. Statistical significance testing
  """
  
  model "gpt-4o"
  
  uses_tool :code_interpreter, languages: ["python", "r"]
  uses_tool :statistical_analysis
  uses_tool :data_visualization
  
  tool :forecast_revenue do |historical_data:, forecast_period:, confidence_level: 0.95|
    model_results = build_forecasting_models(historical_data, forecast_period)
    
    {
      forecast: model_results[:predictions],
      confidence_intervals: model_results[:confidence_bands],
      model_accuracy: model_results[:accuracy_metrics],
      key_drivers: identify_forecast_drivers(model_results),
      scenarios: generate_scenarios(model_results),
      recommendations: generate_forecast_recommendations(model_results)
    }
  end
  
  tool :analyze_customer_churn_risk do |customer_data:, features:|
    churn_model = train_churn_prediction_model(customer_data, features)
    at_risk_customers = identify_at_risk_customers(churn_model)
    
    {
      model_performance: churn_model[:metrics],
      at_risk_customers: at_risk_customers,
      risk_factors: churn_model[:feature_importance],
      intervention_strategies: suggest_retention_strategies(at_risk_customers),
      expected_impact: calculate_intervention_impact(at_risk_customers)
    }
  end
end

# Example usage for business forecasting
predictor = PredictiveAnalyticsAgent.new
result = predictor.run("""
Based on our historical revenue data (attached CSV), create a 6-month revenue forecast.
Include confidence intervals and identify the key factors driving the predictions.
Also flag any potential risks or opportunities.
""")

puts result.messages.last[:content]
# => "6-Month Revenue Forecast Analysis:
#     
#     FORECAST SUMMARY:
#     📊 Expected revenue: $3.2M - $3.8M (95% confidence)
#     📈 Growth trajectory: +12% vs same period last year
#     🎯 Most likely outcome: $3.5M
#     
#     KEY DRIVERS:
#     • Seasonal uptick in Q1 (+15% historical average)
#     • New product launch expected +8% boost
#     • Enterprise deals pipeline suggests +22% in B2B segment
#     
#     RISKS & OPPORTUNITIES:
#     ⚠️  Economic headwinds could reduce growth to +6%
#     🚀 Potential partnership could add $400K if finalized..."
```

Content Creation and Management
-------------------------------

### AI Content Strategy Agent

Plan and create comprehensive content strategies across multiple channels.

```ruby
class ContentStrategyAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "Content Strategy Specialist"
  instructions """
  You are a senior content strategist and marketer. Your expertise includes:

  1. Content strategy development and planning
  2. SEO optimization and keyword research
  3. Multi-channel content adaptation
  4. Brand voice consistency
  5. Performance analysis and optimization
  """
  
  model "gpt-4o"
  
  uses_tool :web_search
  uses_tool :seo_analyzer
  uses_tool :competitor_analysis
  uses_tool :content_calendar
  
  tool :develop_content_strategy do |brand_info:, target_audience:, goals:, channels:|
    market_research = conduct_market_research(brand_info, target_audience)
    competitor_analysis = analyze_competitors(brand_info[:industry])
    content_gaps = identify_content_gaps(market_research, competitor_analysis)
    
    {
      content_pillars: define_content_pillars(brand_info, goals),
      content_calendar: create_content_calendar(content_gaps, channels),
      keyword_strategy: develop_keyword_strategy(target_audience, goals),
      channel_strategy: optimize_channel_strategy(channels, target_audience),
      content_templates: create_content_templates(brand_info),
      success_metrics: define_success_metrics(goals)
    }
  end
  
  tool :create_content_piece do |topic:, channel:, brand_voice:, target_keywords:|
    content_outline = research_and_outline(topic, target_keywords)
    optimized_content = create_seo_optimized_content(content_outline, brand_voice)
    
    {
      title: optimized_content[:title],
      content: optimized_content[:body],
      meta_description: optimized_content[:meta_description],
      target_keywords: target_keywords,
      word_count: optimized_content[:word_count],
      readability_score: calculate_readability(optimized_content[:body]),
      social_media_adaptations: adapt_for_social_channels(optimized_content, channel)
    }
  end
end

# Example content strategy development
strategist = ContentStrategyAgent.new
result = strategist.run("""
Develop a comprehensive content strategy for our SaaS startup. We're targeting 
small business owners in the US, focusing on productivity and automation tools. 
Our channels include blog, LinkedIn, Twitter, and YouTube. Goal is to generate 
50 qualified leads per month through content.
""")

puts result.messages.last[:content]
# => "Content Strategy for SaaS Productivity Platform:
#     
#     CONTENT PILLARS:
#     1. 'Automation Made Simple' - How-to guides and tutorials
#     2. 'Small Business Success Stories' - Case studies and interviews
#     3. 'Productivity Hacks' - Tips and best practices
#     4. 'Tool Comparisons' - Honest reviews and comparisons
#     
#     CHANNEL STRATEGY:
#     📝 Blog: 2 long-form posts/week (SEO-focused)
#     💼 LinkedIn: Daily posts + 2 articles/week
#     🐦 Twitter: 3 tweets/day + engagement
#     📺 YouTube: 1 tutorial video/week..."
```

### Technical Documentation Assistant

Generate and maintain comprehensive technical documentation.

```ruby
class TechnicalDocumentationAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "Technical Documentation Specialist"
  instructions """
  You are an expert technical writer specializing in developer documentation. You excel at:

  1. Creating clear, comprehensive API documentation
  2. Writing step-by-step tutorials and guides
  3. Maintaining documentation consistency and accuracy
  4. Code example generation and testing
  5. Information architecture and organization
  """
  
  model "gpt-4o"
  
  uses_tool :code_interpreter
  uses_tool :file_search
  uses_tool :git_integration
  uses_tool :documentation_analyzer
  
  tool :generate_api_documentation do |api_specification:, examples_required: true|
    parsed_spec = parse_api_specification(api_specification)
    
    documentation = {
      overview: create_api_overview(parsed_spec),
      authentication: document_authentication(parsed_spec[:auth]),
      endpoints: document_endpoints(parsed_spec[:endpoints]),
      data_models: document_data_models(parsed_spec[:models]),
      error_codes: document_error_handling(parsed_spec[:errors])
    }
    
    if examples_required
      documentation[:code_examples] = generate_code_examples(parsed_spec)
      documentation[:tutorials] = create_getting_started_tutorial(parsed_spec)
    end
    
    documentation
  end
  
  tool :update_existing_docs do |documentation_path:, changes_description:|
    current_docs = analyze_existing_documentation(documentation_path)
    change_impact = assess_change_impact(changes_description, current_docs)
    
    {
      affected_sections: change_impact[:sections],
      suggested_updates: generate_update_suggestions(change_impact),
      new_content_needed: identify_new_content_requirements(change_impact),
      migration_guide: create_migration_guide(change_impact) if change_impact[:breaking_changes]
    }
  end
end

# Example documentation generation
doc_agent = TechnicalDocumentationAgent.new
result = doc_agent.run("""
Generate comprehensive API documentation for our new RAAF agents API. Include:

- Authentication with API keys
- Agent creation and management endpoints
- Conversation endpoints with streaming support
- Webhook configuration
- Include code examples in Python, JavaScript, and Ruby
""")

puts result.messages.last[:content]
# => "# RAAF Agents API Documentation
#     
#     ## Overview
#     The RAAF Agents API allows you to create, manage, and interact with AI agents 
#     programmatically. This RESTful API supports real-time conversations, streaming 
#     responses, and webhook integrations.
#     
#     ## Authentication
#     All API requests require an API key in the Authorization header:
#     ```
#     Authorization: Bearer your-api-key-here
#     ```
#     
#     ## Quick Start
#     Here's how to create your first agent and start a conversation..."
```

E-commerce and Sales Automation
-------------------------------

### Intelligent Product Recommendation Engine

Provide personalized product recommendations based on customer behavior and preferences.

```ruby
class ProductRecommendationAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "Product Recommendation Specialist"
  instructions """
  You are an expert e-commerce recommendation engine. Your capabilities include:

  1. Analyzing customer behavior and purchase history
  2. Understanding product catalogs and relationships
  3. Providing personalized recommendations
  4. Explaining recommendation reasoning
  5. Adapting to inventory and business constraints
  """
  
  model "gpt-4o"
  
  uses_tool :customer_analytics
  uses_tool :product_catalog_search
  uses_tool :recommendation_algorithms
  uses_tool :inventory_check
  
  tool :generate_recommendations do |customer_id:, context:, max_recommendations: 5|
    customer_profile = analyze_customer_profile(customer_id)
    browsing_behavior = get_recent_browsing_data(customer_id)
    purchase_history = get_purchase_history(customer_id)
    
    # Generate recommendations using multiple algorithms
    collaborative_recs = collaborative_filtering(customer_profile, purchase_history)
    content_based_recs = content_based_filtering(browsing_behavior, context)
    trending_recs = get_trending_products(customer_profile[:segment])
    
    # Combine and rank recommendations
    final_recommendations = rank_and_combine_recommendations(
      collaborative_recs, content_based_recs, trending_recs, max_recommendations
    )
    
    {
      recommendations: final_recommendations,
      reasoning: explain_recommendations(final_recommendations, customer_profile),
      confidence_scores: calculate_confidence_scores(final_recommendations),
      alternative_products: find_alternative_products(final_recommendations),
      upsell_opportunities: identify_upsell_opportunities(final_recommendations, customer_profile)
    }
  end
  
  tool :explain_recommendation do |product_id:, customer_id:, recommendation_context:|
    product_details = get_product_details(product_id)
    customer_profile = analyze_customer_profile(customer_id)
    recommendation_factors = analyze_recommendation_factors(product_id, customer_id)
    
    {
      primary_reasons: recommendation_factors[:primary],
      secondary_factors: recommendation_factors[:secondary],
      customer_fit_analysis: analyze_customer_product_fit(customer_profile, product_details),
      social_proof: get_social_proof_data(product_id),
      personalized_message: create_personalized_pitch(product_details, customer_profile)
    }
  end
end

# Example usage
recommender = ProductRecommendationAgent.new
result = recommender.run("""
Customer ID 12345 is browsing our electronics section, specifically looking at laptops.
They previously purchased a professional camera and editing software. Generate 
personalized recommendations and explain why each product would be a good fit.
""")

puts result.messages.last[:content]
# => "Based on your professional photography background and current laptop search, 
#     here are my top recommendations:
#     
#     🖥️ MacBook Pro 16\" M3 - Perfect for photo editing with your Adobe suite
#     📱 iPad Pro with Apple Pencil - Great for client presentations and on-location editing
#     🔌 Thunderbolt 4 Hub - Essential for connecting your camera and external drives
#     📦 Peak Design Laptop Bag - Matches your camera gear aesthetic
#     
#     Each recommendation considers your creative workflow and previous purchases..."
```

### Sales Process Automation Agent

Automate lead qualification, follow-ups, and sales process management.

```ruby
class SalesAutomationAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "Sales Process Automation Specialist"
  instructions """
  You are a sales automation expert focused on lead qualification and process optimization. 
  Your responsibilities include:

  1. Lead scoring and qualification
  2. Automated follow-up sequences
  3. Meeting scheduling and preparation
  4. Proposal generation and customization
  5. Pipeline management and forecasting
  """
  
  model "gpt-4o"
  
  uses_tool :crm_integration
  uses_tool :calendar_management
  uses_tool :email_automation
  uses_tool :proposal_generator
  
  tool :qualify_lead do |lead_data:, qualification_criteria:|
    lead_score = calculate_lead_score(lead_data, qualification_criteria)
    qualification_assessment = assess_qualification_criteria(lead_data)
    next_actions = determine_next_actions(lead_score, qualification_assessment)
    
    {
      lead_score: lead_score,
      qualification_status: qualification_assessment[:status],
      qualifying_factors: qualification_assessment[:positive_factors],
      disqualifying_factors: qualification_assessment[:negative_factors],
      recommended_actions: next_actions,
      priority_level: determine_priority(lead_score),
      follow_up_timeline: suggest_follow_up_timeline(qualification_assessment)
    }
  end
  
  tool :generate_personalized_proposal do |prospect_info:, product_requirements:, budget_range:|
    company_analysis = analyze_prospect_company(prospect_info)
    solution_mapping = map_solutions_to_requirements(product_requirements)
    pricing_strategy = develop_pricing_strategy(budget_range, solution_mapping)
    
    proposal = {
      executive_summary: create_executive_summary(company_analysis, solution_mapping),
      proposed_solution: detail_proposed_solution(solution_mapping, prospect_info),
      implementation_plan: create_implementation_timeline(solution_mapping),
      pricing: format_pricing_proposal(pricing_strategy),
      roi_analysis: calculate_roi_projection(solution_mapping, company_analysis),
      next_steps: outline_next_steps(proposal)
    }
    
    proposal
  end
end

# Example lead qualification
sales_agent = SalesAutomationAgent.new
result = sales_agent.run("""
New lead from website contact form:

- Company: TechStart Solutions (50 employees)
- Industry: Software Development
- Contact: Sarah Chen (CTO)
- Interest: API management and automation tools
- Budget: $50K-100K annually
- Timeline: Need solution within 3 months
- Current pain: Manual deployment processes taking 40+ hours/week

Qualify this lead and recommend next actions.
""")

puts result.messages.last[:content]
# => "Lead Qualification Assessment:
#     
#     🟢 QUALIFIED LEAD (Score: 85/100)
#     
#     STRONG INDICATORS:
#     ✅ Decision maker role (CTO)
#     ✅ Budget aligns with our enterprise tier
#     ✅ Clear pain point and urgency
#     ✅ Company size fits our ICP
#     ✅ Specific timeline requirement
#     
#     RECOMMENDED ACTIONS:
#     1. Schedule demo within 48 hours
#     2. Prepare ROI calculator showing 40-hour savings
#     3. Share case study: Similar company reduced deployment time 90%
#     4. Priority: HIGH - Fast decision timeline..."
```

Internal Process Automation
---------------------------

### HR Process Automation Agent

Streamline HR processes including recruitment, onboarding, and employee support.

```ruby
class HRProcessAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "HR Process Automation Specialist"
  instructions """
  You are an HR automation expert specializing in employee lifecycle management. 
  Your capabilities include:

  1. Resume screening and candidate evaluation
  2. Interview scheduling and preparation
  3. Onboarding process coordination
  4. Employee query resolution
  5. Performance review automation
  """
  
  model "gpt-4o"
  
  uses_tool :applicant_tracking_system
  uses_tool :calendar_integration
  uses_tool :document_generation
  uses_tool :employee_database
  
  tool :screen_candidates do |job_requirements:, candidate_resumes:|
    screening_results = candidate_resumes.map do |resume|
      skills_match = analyze_skills_match(resume, job_requirements)
      experience_evaluation = evaluate_experience(resume, job_requirements)
      culture_fit_indicators = assess_culture_fit_signals(resume)
      
      {
        candidate_id: resume[:id],
        overall_score: calculate_overall_score(skills_match, experience_evaluation),
        skills_match: skills_match,
        experience_match: experience_evaluation,
        strengths: identify_candidate_strengths(resume, job_requirements),
        concerns: identify_potential_concerns(resume, job_requirements),
        interview_questions: generate_targeted_questions(skills_match, experience_evaluation),
        recommendation: make_screening_recommendation(skills_match, experience_evaluation)
      }
    end
    
    {
      screening_results: screening_results,
      top_candidates: screening_results.sort_by { |r| r[:overall_score] }.reverse.first(5),
      screening_summary: generate_screening_summary(screening_results)
    }
  end
  
  tool :automate_onboarding do |new_employee:, start_date:, department:|
    onboarding_checklist = generate_onboarding_checklist(new_employee, department)
    welcome_materials = prepare_welcome_materials(new_employee)
    system_access = coordinate_system_access(new_employee, department)
    
    {
      onboarding_timeline: create_onboarding_timeline(onboarding_checklist, start_date),
      welcome_package: welcome_materials,
      system_access_requests: system_access,
      buddy_assignment: assign_onboarding_buddy(new_employee, department),
      first_week_schedule: plan_first_week_activities(new_employee, department),
      completion_tracking: setup_completion_tracking(onboarding_checklist)
    }
  end
end

# Example candidate screening
hr_agent = HRProcessAgent.new
result = hr_agent.run("""
Screen these 5 candidates for our Senior Ruby Developer position. Required skills:

- 5+ years Ruby/Rails experience
- Experience with APIs and microservices
- Database optimization knowledge
- Team leadership experience
- Strong communication skills

Rank candidates and provide interview recommendations.
""")

puts result.messages.last[:content]
# => "Candidate Screening Results:
#     
#     🥇 TOP CANDIDATE: Alex Thompson (Score: 92/100)
#     ✅ 7 years Rails experience with scaling expertise
#     ✅ Led 3-person team for 2 years
#     ✅ Strong API design background
#     ✅ Database optimization at scale
#     📝 Recommended interview focus: System design and team management
#     
#     🥈 STRONG CANDIDATE: Maria Rodriguez (Score: 88/100)
#     ✅ 6 years Rails, strong microservices background
#     ✅ Excellent communication skills evident
#     ⚠️ Limited direct team leadership
#     📝 Recommended interview focus: Leadership scenarios..."
```

### IT Operations Automation Agent

Automate IT operations including monitoring, incident response, and system maintenance.

```ruby
class ITOperationsAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "IT Operations Automation Specialist"
  instructions """
  You are an expert in IT operations automation and incident management. Your expertise includes:

  1. System monitoring and alerting
  2. Incident response and troubleshooting
  3. Automated remediation procedures
  4. Capacity planning and optimization
  5. Security incident handling
  """
  
  model "gpt-4o"
  
  uses_tool :monitoring_systems
  uses_tool :shell_execution
  uses_tool :incident_management
  uses_tool :knowledge_base
  
  tool :analyze_incident do |alert_data:, system_metrics:|
    incident_classification = classify_incident(alert_data)
    impact_assessment = assess_impact(alert_data, system_metrics)
    root_cause_analysis = perform_initial_rca(alert_data, system_metrics)
    
    {
      severity: determine_severity(incident_classification, impact_assessment),
      incident_type: incident_classification[:type],
      affected_systems: identify_affected_systems(alert_data),
      probable_causes: root_cause_analysis[:probable_causes],
      immediate_actions: suggest_immediate_actions(incident_classification),
      escalation_needed: determine_escalation_need(incident_classification, impact_assessment),
      estimated_resolution_time: estimate_resolution_time(incident_classification)
    }
  end
  
  tool :execute_remediation do |incident_type:, remediation_plan:|
    validation_results = validate_remediation_plan(remediation_plan)
    
    if validation_results[:safe_to_execute]
      execution_results = execute_remediation_steps(remediation_plan)
      post_execution_check = verify_remediation_success(execution_results)
      
      {
        execution_status: execution_results[:status],
        steps_completed: execution_results[:completed_steps],
        verification_results: post_execution_check,
        follow_up_actions: determine_follow_up_actions(post_execution_check),
        incident_resolved: post_execution_check[:resolution_confirmed]
      }
    else
      {
        execution_status: "blocked",
        blocking_issues: validation_results[:issues],
        manual_intervention_required: true,
        escalation_recommendation: "immediate"
      }
    end
  end
end

# Example incident analysis and response
it_agent = ITOperationsAgent.new
result = it_agent.run("""
CRITICAL ALERT: API response times increased to 5000ms (normal: 200ms)

- Time: 2024-01-15 14:30 UTC
- Affected endpoints: /api/v1/users, /api/v1/orders
- Error rate: 15% (normal: 0.1%)
- Database connections: 95/100 (high)
- CPU usage: 85% across web servers
- Memory usage: 78% average

Analyze this incident and recommend immediate actions.
""")

puts result.messages.last[:content]
# => "🚨 CRITICAL INCIDENT ANALYSIS
#     
#     SEVERITY: P1 - Critical (Customer-impacting performance degradation)
#     
#     INCIDENT TYPE: Database Connection Pool Exhaustion + High Load
#     
#     IMMEDIATE ACTIONS REQUIRED:
#     1. Scale web servers horizontally (+2 instances) - ETA: 3 minutes
#     2. Increase database connection pool size 100→150
#     3. Enable database query caching for user/order endpoints
#     4. Review recent deployments in last 2 hours
#     
#     ROOT CAUSE ANALYSIS:
#     • Database connection bottleneck (95% utilization)
#     • Possible slow query causing connection hold-up
#     • Need immediate capacity scaling..."
```

Multi-Agent Orchestration Patterns
-----------------------------------

### Research and Writing Workflow

Coordinate multiple agents for comprehensive research and content creation.

```ruby
class ResearchWritingOrchestrator < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "Research & Writing Workflow Orchestrator"
  instructions """
  You coordinate a team of specialized agents to conduct thorough research and 
  create high-quality content. Your workflow includes:

  1. Research planning and source identification
  2. Data gathering and fact verification
  3. Content outlining and structure
  4. Writing and editing coordination
  5. Quality assurance and final review
  """
  
  model "gpt-4o"
  
  # Define the agent team
  uses_agent :research_specialist
  uses_agent :fact_checker
  uses_agent :content_strategist
  uses_agent :writer
  uses_agent :editor
  
  tool :orchestrate_research_project do |topic:, requirements:, deadline:|
    # Phase 1: Research Planning
    research_plan = delegate_to_agent(:research_specialist, 
      "Create comprehensive research plan for: #{topic}")
    
    # Phase 2: Data Gathering
    research_data = delegate_to_agent(:research_specialist,
      "Execute research plan and gather sources", 
      context: { plan: research_plan })
    
    # Phase 3: Fact Verification
    verified_facts = delegate_to_agent(:fact_checker,
      "Verify accuracy of research findings",
      context: { research_data: research_data })
    
    # Phase 4: Content Strategy
    content_strategy = delegate_to_agent(:content_strategist,
      "Develop content strategy and outline",
      context: { topic: topic, research: verified_facts, requirements: requirements })
    
    # Phase 5: Writing
    draft_content = delegate_to_agent(:writer,
      "Write content based on strategy and research",
      context: { strategy: content_strategy, research: verified_facts })
    
    # Phase 6: Editing and Review
    final_content = delegate_to_agent(:editor,
      "Edit and polish content for publication",
      context: { draft: draft_content, requirements: requirements })
    
    {
      research_summary: research_data[:summary],
      fact_check_results: verified_facts[:verification_summary],
      content_strategy: content_strategy,
      final_content: final_content,
      quality_score: final_content[:quality_assessment],
      completion_time: calculate_completion_time,
      workflow_efficiency: assess_workflow_efficiency
    }
  end
end

# Example coordinated research project
orchestrator = ResearchWritingOrchestrator.new
result = orchestrator.run("""
Research and write a comprehensive 3000-word article about:
"The Impact of AI on Small Business Operations in 2024"

Requirements:

- Include current statistics and trends
- Feature 3-5 real case studies
- Provide actionable recommendations
- Target audience: Small business owners
- Deadline: 3 days
""")

puts result.messages.last[:content]
# => "Research & Writing Project Completed Successfully!
#     
#     📊 RESEARCH PHASE: 47 sources analyzed, 23 verified statistics
#     ✅ FACT-CHECK: 94% accuracy rate, 3 statistics updated
#     📝 CONTENT STRATEGY: 6-section structure with case study integration
#     ✍️ WRITING: 3,247 words, readability score 78/100
#     📖 EDITING: Final polish, SEO optimization, call-to-action added
#     
#     DELIVERABLES:
#     • Main article (3,247 words)
#     • Executive summary (500 words)  
#     • Social media excerpts (5 posts)
#     • Key statistics infographic data..."
```

### Customer Journey Automation

Orchestrate multiple agents to handle complete customer journeys from lead to retention.

```ruby
class CustomerJourneyOrchestrator < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "Customer Journey Orchestrator"
  instructions """
  You manage the complete customer experience by coordinating specialized agents 
  across all touchpoints. Your responsibilities include:

  1. Lead qualification and nurturing
  2. Sales process management
  3. Onboarding and implementation
  4. Ongoing support and success
  5. Retention and expansion opportunities
  """
  
  model "gpt-4o"
  
  uses_agent :lead_qualifier
  uses_agent :sales_specialist
  uses_agent :onboarding_coordinator
  uses_agent :customer_success_manager
  uses_agent :support_specialist
  
  tool :manage_customer_lifecycle do |customer_id:, stage:, interaction_data:|
    current_stage = determine_customer_stage(customer_id, stage)
    
    case current_stage
    when 'lead'
      handle_lead_stage(customer_id, interaction_data)
    when 'prospect'
      handle_prospect_stage(customer_id, interaction_data)
    when 'new_customer'
      handle_onboarding_stage(customer_id, interaction_data)
    when 'active_customer'
      handle_customer_success_stage(customer_id, interaction_data)
    when 'at_risk'
      handle_retention_stage(customer_id, interaction_data)
    end
  end
  
  private
  
  def handle_lead_stage(customer_id, interaction_data)
    qualification_result = delegate_to_agent(:lead_qualifier,
      "Qualify lead and determine next actions",
      context: { customer_id: customer_id, interaction: interaction_data })
    
    if qualification_result[:qualified]
      transition_to_prospect(customer_id, qualification_result)
    else
      schedule_nurturing_sequence(customer_id, qualification_result[:disqualification_reason])
    end
  end
  
  def handle_prospect_stage(customer_id, interaction_data)
    sales_action = delegate_to_agent(:sales_specialist,
      "Advance sales process based on prospect interaction",
      context: { customer_id: customer_id, interaction: interaction_data })
    
    case sales_action[:recommended_action]
    when 'schedule_demo'
      schedule_demo_with_prospect(customer_id, sales_action)
    when 'send_proposal'
      generate_and_send_proposal(customer_id, sales_action)
    when 'close_deal'
      initiate_closing_process(customer_id, sales_action)
    end
  end
end

# Example end-to-end customer journey management
journey_orchestrator = CustomerJourneyOrchestrator.new
result = journey_orchestrator.run("""
Customer Jane Smith (ID: 12345) just signed up for our enterprise trial.
She's the Operations Director at a 200-person marketing agency.
Previous interactions show interest in workflow automation and team collaboration features.

Orchestrate her complete journey from trial signup to successful implementation.
""")

puts result.messages.last[:content]
# => "Customer Journey Orchestration Initiated for Jane Smith:
#     
#     🎯 CURRENT STAGE: New Trial Customer
#     
#     ORCHESTRATED ACTIONS:
#     
#     1. IMMEDIATE (0-24 hours):
#        • Welcome email with quick-start guide
#        • Calendar invite for 30-min onboarding call
#        • Access to marketing agency success stories
#     
#     2. WEEK 1: Trial Optimization
#        • Personalized workflow automation demo
#        • Connect with Customer Success Manager
#        • Share team collaboration best practices
#     
#     3. WEEK 2: Value Demonstration
#        • ROI calculator based on her team size
#        • Integration consultation with their existing tools..."
```

Performance Monitoring and Optimization
---------------------------------------

### Agent Performance Analytics

Monitor and optimize multi-agent system performance.

```ruby
class AgentPerformanceAnalyzer < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl
  
  name "Agent Performance Analyzer"
  instructions """
  You analyze and optimize the performance of AI agent systems. Your capabilities include:

  1. Performance metric collection and analysis
  2. Bottleneck identification and resolution
  3. Cost optimization recommendations
  4. Quality assurance and improvement
  5. System scaling recommendations
  """
  
  model "gpt-4o"
  
  uses_tool :performance_monitoring
  uses_tool :cost_analytics
  uses_tool :quality_metrics
  uses_tool :system_optimization
  
  tool :analyze_system_performance do |time_period:, agent_types:|
    performance_data = collect_performance_metrics(time_period, agent_types)
    cost_analysis = analyze_cost_efficiency(performance_data)
    quality_metrics = assess_output_quality(performance_data)
    
    {
      performance_summary: summarize_performance(performance_data),
      cost_efficiency: cost_analysis,
      quality_assessment: quality_metrics,
      bottlenecks: identify_bottlenecks(performance_data),
      optimization_recommendations: generate_optimization_recommendations(performance_data),
      scaling_recommendations: assess_scaling_needs(performance_data)
    }
  end
  
  tool :optimize_agent_configuration do |agent_type:, performance_goals:|
    current_config = get_current_configuration(agent_type)
    performance_baseline = establish_performance_baseline(agent_type)
    optimization_opportunities = identify_optimization_opportunities(current_config, performance_goals)
    
    {
      current_performance: performance_baseline,
      optimization_plan: create_optimization_plan(optimization_opportunities),
      expected_improvements: calculate_expected_improvements(optimization_opportunities),
      implementation_steps: generate_implementation_steps(optimization_opportunities),
      rollback_plan: create_rollback_plan(current_config)
    }
  end
end

# Example system performance analysis
analyzer = AgentPerformanceAnalyzer.new
result = analyzer.run("""
Analyze the performance of our customer service agent system over the last 30 days.
Focus on response times, resolution rates, customer satisfaction, and cost per interaction.
Identify optimization opportunities and provide specific recommendations.
""")

puts result.messages.last[:content]
# => "Customer Service Agent Performance Analysis (Last 30 Days):
#     
#     📊 KEY METRICS:
#     • Average response time: 2.3 seconds (target: <3s) ✅
#     • Resolution rate: 78% (target: >80%) ⚠️
#     • Customer satisfaction: 4.2/5 (target: >4.0) ✅
#     • Cost per interaction: $0.23 (budget: <$0.30) ✅
#     
#     🎯 OPTIMIZATION OPPORTUNITIES:
#     1. Switch 30% of simple queries to gpt-4o-mini (-40% cost)
#     2. Implement response caching for FAQ (+15% speed)
#     3. Add sentiment analysis for better escalation (+12% resolution)
#     4. Optimize prompt length (-25% token usage)
#     
#     💰 PROJECTED SAVINGS: $1,200/month with 8% performance improvement"
```

Next Steps
----------

For implementing these use cases:

* **[RAAF Core Guide](core_guide.html)** - Foundation for building agents
* **[RAAF DSL Guide](dsl_guide.html)** - Declarative agent development
* **[Tool Reference](tool_reference.html)** - Available tools and capabilities
* **[Multi-Agent Guide](multi_agent_guide.html)** - Agent orchestration patterns
* **[Performance Guide](performance_guide.html)** - Optimization strategies
* **[Best Practices](best_practices.html)** - Production deployment guidance