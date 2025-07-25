**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Cost Management Guide
==========================

This guide covers controlling and optimizing AI costs with provider routing, token management, and comprehensive cost tracking strategies for production RAAF deployments.

**AI costs are different from traditional software costs.** Traditional software has predictable infrastructure costs that scale with usage. AI software has variable, per-use costs that can spiral unpredictably. A single complex query might cost $5, while a thousand simple queries might cost $0.50. This variability makes traditional budgeting and cost control approaches inadequate.

**The cost challenge:** AI costs are multidimensional. You pay for input tokens, output tokens, model complexity, and provider features. Costs vary by model, provider, and even time of day. A poorly optimized AI application can burn through budgets in hours, while a well-optimized one provides sustainable value.

**Cost optimization is a first-class concern.** Unlike traditional performance optimization (which often happens after deployment), AI cost optimization must be built into the architecture from day one. This means intelligent caching, provider routing, token management, and real-time budget controls. The goal isn't just to reduce costs—it's to maximize value per dollar spent.

**Why this matters:** AI applications that ignore cost optimization fail in production. Either they become too expensive to operate, or they provide poor user experiences due to aggressive cost-cutting measures. This guide shows how to build cost-awareness into every layer of your RAAF application.

After reading this guide, you will know:

* How to track and analyze AI provider costs in real-time
* Strategies for optimizing token usage and reducing costs
* Provider routing for cost-effective AI operations
* Budget controls and cost alerting mechanisms
* Cost allocation and chargeback patterns
* Best practices for cost-effective agent design
* Long-term cost optimization strategies

--------------------------------------------------------------------------------

Understanding AI Costs
-----------------------

**AI costs are like utility bills, not subscription fees.** Traditional software costs are mostly fixed—you pay for licenses, servers, and bandwidth. AI costs are consumption-based—you pay for what you use, when you use it. This creates both opportunities and risks.

**The cost structure reality:** AI costs aren't just about "API calls." They're about token consumption, model complexity, provider features, and hidden costs like failed requests and retries. A simple "Hello" might cost $0.0001, but a complex analysis might cost $0.50. Understanding this granularity is crucial for optimization.

**Cost sources in RAAF applications:**

* **Token Usage** - Input and output tokens charged by AI providers (the primary cost driver)
* **Model Selection** - Different models have different pricing tiers (10x+ cost differences)
* **Request Volume** - Total number of API calls (including failed and retry requests)
* **Provider Features** - Function calling, embeddings, fine-tuning (often premium-priced)
* **Infrastructure** - Compute resources for running RAAF applications (typically minor vs. AI costs)

**The compounding effect:** Small inefficiencies compound rapidly. A 10% increase in token usage becomes a 10% increase in costs. A poor model choice can double your costs. Failed requests that get retried cost money without providing value. This is why cost optimization requires systematic approaches, not ad-hoc fixes.

### Cost Breakdown Analysis

```ruby
# lib/raaf/cost/analyzer.rb
module RAAF
  module Cost
    class Analyzer
      include Singleton
      
      def initialize
        @cost_data = {}
        @pricing_models = load_pricing_models
        @usage_tracker = {}
      end
      
      def track_request(provider, model, usage, context = {})
        cost = calculate_cost(provider, model, usage)
        
        request_data = {
          provider: provider,
          model: model,
          usage: usage,
          cost: cost,
          context: context,
          timestamp: Time.current
        }
        
        store_cost_data(request_data)
        update_usage_tracker(request_data)
        
        cost
      end
      
      def get_cost_breakdown(time_range = 24.hours.ago..Time.current, group_by: :model)
        relevant_data = @cost_data.values.flatten.select do |data|
          time_range.cover?(data[:timestamp])
        end
        
        case group_by
        when :model
          group_by_model(relevant_data)
        when :provider
          group_by_provider(relevant_data)
        when :agent_type
          group_by_agent_type(relevant_data)
        when :user
          group_by_user(relevant_data)
        else
          relevant_data
        end
      end
      
      def calculate_cost(provider, model, usage)
        pricing = @pricing_models.dig(provider.to_s, model.to_s)
        return 0 unless pricing
        
        input_cost = (usage[:prompt_tokens] || 0) * pricing[:input] / 1_000_000
        output_cost = (usage[:completion_tokens] || 0) * pricing[:output] / 1_000_000
        
        input_cost + output_cost
      end
      
      def get_daily_costs(days = 30)
        end_date = Date.current
        start_date = end_date - days.days
        
        daily_costs = {}
        
        (start_date..end_date).each do |date|
          day_range = date.beginning_of_day..date.end_of_day
          daily_costs[date] = @cost_data.values.flatten
            .select { |data| day_range.cover?(data[:timestamp]) }
            .sum { |data| data[:cost] }
        end
        
        daily_costs
      end
      
      def get_cost_trends
        daily_costs = get_daily_costs(30)
        costs_array = daily_costs.values
        
        return {} if costs_array.empty?
        
        {
          total_cost_30_days: costs_array.sum,
          avg_daily_cost: costs_array.sum / costs_array.size,
          min_daily_cost: costs_array.min,
          max_daily_cost: costs_array.max,
          trend: calculate_trend(costs_array),
          projected_monthly_cost: (costs_array.last(7).sum / 7) * 30
        }
      end
      
      private
      
      def load_pricing_models
        {
          'openai' => {
            'gpt-4o' => { input: 5.00, output: 15.00 },
            'gpt-4o-mini' => { input: 0.15, output: 0.60 },
            'gpt-4-turbo' => { input: 10.00, output: 30.00 },
            'gpt-3.5-turbo' => { input: 0.50, output: 1.50 },
            'text-embedding-3-small' => { input: 0.02, output: 0 },
            'text-embedding-3-large' => { input: 0.13, output: 0 }
          },
          'anthropic' => {
            'claude-3-5-sonnet-20241022' => { input: 3.00, output: 15.00 },
            'claude-3-5-haiku-20241022' => { input: 0.25, output: 1.25 },
            'claude-3-opus-20240229' => { input: 15.00, output: 75.00 },
            'claude-3-sonnet-20240229' => { input: 3.00, output: 15.00 },
            'claude-3-haiku-20240307' => { input: 0.25, output: 1.25 }
          },
          'groq' => {
            'llama-3.1-405b-reasoning' => { input: 0.59, output: 0.79 },
            'llama-3.1-70b-versatile' => { input: 0.59, output: 0.79 },
            'mixtral-8x7b-32768' => { input: 0.27, output: 0.27 }
          }
        }
      end
      
      def group_by_model(data)
        grouped = data.group_by { |d| d[:model] }
        grouped.transform_values do |entries|
          {
            total_cost: entries.sum { |e| e[:cost] },
            total_tokens: entries.sum { |e| e[:usage][:total_tokens] || 0 },
            request_count: entries.size,
            avg_cost_per_request: entries.sum { |e| e[:cost] } / entries.size
          }
        end
      end
      
      def group_by_provider(data)
        grouped = data.group_by { |d| d[:provider] }
        grouped.transform_values do |entries|
          {
            total_cost: entries.sum { |e| e[:cost] },
            request_count: entries.size,
            models_used: entries.map { |e| e[:model] }.uniq
          }
        end
      end
      
      def group_by_agent_type(data)
        grouped = data.group_by { |d| d.dig(:context, :agent_type) || 'unknown' }
        grouped.transform_values do |entries|
          {
            total_cost: entries.sum { |e| e[:cost] },
            request_count: entries.size,
            avg_cost_per_request: entries.sum { |e| e[:cost] } / entries.size
          }
        end
      end
      
      def calculate_trend(costs_array)
        return 'stable' if costs_array.size < 2
        
        recent_avg = costs_array.last(7).sum / 7.0
        previous_avg = costs_array.first(7).sum / 7.0
        
        change_percent = ((recent_avg - previous_avg) / previous_avg) * 100
        
        case change_percent
        when -Float::INFINITY..-10 then 'decreasing'
        when -10..10 then 'stable'
        when 10..Float::INFINITY then 'increasing'
        else 'stable'
        end
      end
      
      def store_cost_data(request_data)
        date_key = request_data[:timestamp].to_date
        @cost_data[date_key] ||= []
        @cost_data[date_key] << request_data
        
        # Keep only last 90 days
        cutoff_date = 90.days.ago.to_date
        @cost_data.delete_if { |date, _| date < cutoff_date }
      end
      
      def update_usage_tracker(request_data)
        key = "#{request_data[:provider]}_#{request_data[:model]}"
        @usage_tracker[key] ||= { requests: 0, total_cost: 0, total_tokens: 0 }
        
        @usage_tracker[key][:requests] += 1
        @usage_tracker[key][:total_cost] += request_data[:cost]
        @usage_tracker[key][:total_tokens] += request_data[:usage][:total_tokens] || 0
      end
    end
  end
end
```

Budget Controls and Alerting
-----------------------------

**Budget controls are circuit breakers for AI costs.** Just as electrical systems need circuit breakers to prevent overload, AI systems need budget controls to prevent cost overruns. Without these controls, a single bug or attack can result in thousands of dollars in API charges.

**Why traditional budgeting fails:** Traditional budgeting assumes predictable, monthly costs. AI costs can spike within minutes. A misconfigured agent or a denial-of-service attack can exhaust monthly budgets in hours. Budget controls need to be real-time, not monthly.

**Budget strategy:** This implementation provides multi-level budget controls—daily, weekly, and monthly limits with escalating alerts. The key insight is that budgets should be enforced at request time, not discovered after the fact. Prevention is cheaper than remediation.

### Budget Manager

```ruby
# lib/raaf/cost/budget_manager.rb
module RAAF
  module Cost
    class BudgetManager
      include Singleton
      
      def initialize
        @budgets = {}
        @spend_tracking = {}
        @alert_thresholds = [50, 75, 90, 100]  # Percentage thresholds
      end
      
      def set_budget(scope, amount, period: :monthly)
        budget_key = "#{scope}_#{period}"
        
        @budgets[budget_key] = {
          scope: scope,
          amount: amount,
          period: period,
          start_date: period_start_date(period),
          end_date: period_end_date(period),
          created_at: Time.current
        }
        
        reset_spend_tracking(budget_key)
      end
      
      def track_spend(scope, cost, context = {})
        %i[daily weekly monthly].each do |period|
          budget_key = "#{scope}_#{period}"
          next unless @budgets[budget_key]
          
          current_spend = get_current_spend(budget_key)
          new_spend = current_spend + cost
          
          @spend_tracking[budget_key] = new_spend
          
          check_budget_alerts(budget_key, new_spend, context)
        end
        
        # Global budget tracking
        track_global_spend(cost, context)
      end
      
      def check_budget_status(scope, period = :monthly)
        budget_key = "#{scope}_#{period}"
        budget = @budgets[budget_key]
        
        return nil unless budget
        
        current_spend = get_current_spend(budget_key)
        remaining = budget[:amount] - current_spend
        percentage_used = (current_spend / budget[:amount]) * 100
        
        {
          budget: budget[:amount],
          spent: current_spend,
          remaining: remaining,
          percentage_used: percentage_used.round(2),
          status: budget_status(percentage_used),
          period_end: budget[:end_date]
        }
      end
      
      def get_all_budgets_status
        status = {}
        
        @budgets.each do |budget_key, budget|
          scope_period = budget_key
          status[scope_period] = check_budget_status(budget[:scope], budget[:period])
        end
        
        status
      end
      
      def enforce_budget_limit(scope, requested_cost, period = :monthly)
        budget_key = "#{scope}_#{period}"
        budget = @budgets[budget_key]
        
        return true unless budget  # No budget set, allow request
        
        current_spend = get_current_spend(budget_key)
        projected_spend = current_spend + requested_cost
        
        if projected_spend > budget[:amount]
          {
            allowed: false,
            reason: 'budget_exceeded',
            current_spend: current_spend,
            budget_limit: budget[:amount],
            requested_cost: requested_cost
          }
        else
          { allowed: true }
        end
      end
      
      private
      
      def period_start_date(period)
        case period
        when :daily
          Date.current.beginning_of_day
        when :weekly
          Date.current.beginning_of_week
        when :monthly
          Date.current.beginning_of_month
        end
      end
      
      def period_end_date(period)
        case period
        when :daily
          Date.current.end_of_day
        when :weekly
          Date.current.end_of_week
        when :monthly
          Date.current.end_of_month
        end
      end
      
      def reset_spend_tracking(budget_key)
        @spend_tracking[budget_key] = 0
      end
      
      def get_current_spend(budget_key)
        budget = @budgets[budget_key]
        return 0 unless budget
        
        # Check if period has reset
        if Time.current > budget[:end_date]
          reset_budget_period(budget_key)
          return 0
        end
        
        @spend_tracking[budget_key] || 0
      end
      
      def reset_budget_period(budget_key)
        budget = @budgets[budget_key]
        budget[:start_date] = period_start_date(budget[:period])
        budget[:end_date] = period_end_date(budget[:period])
        @spend_tracking[budget_key] = 0
      end
      
      def budget_status(percentage_used)
        case percentage_used
        when 0...50 then 'healthy'
        when 50...75 then 'warning'
        when 75...90 then 'critical'
        when 90...100 then 'danger'
        else 'exceeded'
        end
      end
      
      def check_budget_alerts(budget_key, new_spend, context)
        budget = @budgets[budget_key]
        percentage_used = (new_spend / budget[:amount]) * 100
        
        @alert_thresholds.each do |threshold|
          alert_key = "#{budget_key}_#{threshold}"
          
          # Check if we've crossed this threshold
          if percentage_used >= threshold && !alert_sent?(alert_key)
            send_budget_alert(budget, threshold, percentage_used, context)
            mark_alert_sent(alert_key)
          end
        end
      end
      
      def send_budget_alert(budget, threshold, actual_percentage, context)
        alert_data = {
          scope: budget[:scope],
          period: budget[:period],
          threshold: threshold,
          actual_percentage: actual_percentage.round(2),
          budget_amount: budget[:amount],
          current_spend: @spend_tracking["#{budget[:scope]}_#{budget[:period]}"],
          context: context,
          timestamp: Time.current
        }
        
        # Send to notification system
        NotificationService.send_budget_alert(alert_data)
        
        # Log alert
        Rails.logger.warn "Budget alert: #{budget[:scope]} #{budget[:period]} budget at #{actual_percentage.round(2)}% (threshold: #{threshold}%)"
      end
      
      def alert_sent?(alert_key)
        # In production, store this in Redis or database
        @sent_alerts ||= Set.new
        @sent_alerts.include?(alert_key)
      end
      
      def mark_alert_sent(alert_key)
        @sent_alerts ||= Set.new
        @sent_alerts.add(alert_key)
      end
      
      def track_global_spend(cost, context)
        # Track overall spending across all scopes
        @global_spend ||= { daily: 0, weekly: 0, monthly: 0 }
        
        %i[daily weekly monthly].each do |period|
          @global_spend[period] += cost
        end
      end
    end
  end
end
```

### Cost-Aware Agent Service

```ruby
# app/services/cost_aware_agent_service.rb
class CostAwareAgentService
  include ActiveModel::Model
  
  attr_accessor :user, :agent_type, :budget_scope
  
  def initialize(user:, agent_type:, budget_scope: nil)
    @user = user
    @agent_type = agent_type
    @budget_scope = budget_scope || "user_#{user.id}"
    @cost_analyzer = RAAF::Cost::Analyzer.instance
    @budget_manager = RAAF::Cost::BudgetManager.instance
  end
  
  def run_with_cost_control(message, options = {})
    # Estimate cost before making request
    estimated_cost = estimate_request_cost(message, options)
    
    # Check budget constraints
    budget_check = @budget_manager.enforce_budget_limit(@budget_scope, estimated_cost)
    
    unless budget_check[:allowed]
      return build_budget_exceeded_response(budget_check)
    end
    
    # Select cost-optimal model/provider
    optimal_config = select_optimal_configuration(estimated_cost, options)
    
    # Execute request with cost tracking
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    
    agent = build_agent(optimal_config)
    runner = RAAF::Runner.new(agent: agent)
    
    result = runner.run(message, **options)
    
    # Track actual costs
    actual_cost = @cost_analyzer.track_request(
      optimal_config[:provider],
      optimal_config[:model],
      result.usage,
      {
        user_id: @user.id,
        agent_type: @agent_type,
        estimated_cost: estimated_cost,
        duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      }
    )
    
    # Update budget tracking
    @budget_manager.track_spend(@budget_scope, actual_cost, {
      user_id: @user.id,
      agent_type: @agent_type
    })
    
    # Enhance result with cost information
    enhance_result_with_cost_info(result, actual_cost, estimated_cost)
  end
  
  private
  
  def estimate_request_cost(message, options)
    # Simple token estimation
    estimated_input_tokens = (message.length + (options[:context]&.to_json&.length || 0)) / 4
    estimated_output_tokens = estimate_output_tokens(message)
    
    # Use default model for estimation
    default_model = 'gpt-4o-mini'
    
    @cost_analyzer.calculate_cost(
      'openai',
      default_model,
      {
        prompt_tokens: estimated_input_tokens,
        completion_tokens: estimated_output_tokens,
        total_tokens: estimated_input_tokens + estimated_output_tokens
      }
    )
  end
  
  def estimate_output_tokens(message)
    # Estimate based on message complexity
    base_tokens = message.length / 6  # More conservative estimate for output
    
    # Adjust based on query type
    multiplier = case message.downcase
                when /explain|describe|analyze/
                  2.0
                when /list|summary/
                  1.0
                when /yes|no|short/
                  0.5
                else
                  1.5
                end
    
    (base_tokens * multiplier).round
  end
  
  def select_optimal_configuration(estimated_cost, options)
    # Get user's budget status
    budget_status = @budget_manager.check_budget_status(@budget_scope)
    
    # Select model based on budget constraints and requirements
    if budget_status && budget_status[:percentage_used] > 75
      # Use cheaper models when approaching budget limit
      { provider: 'openai', model: 'gpt-4o-mini' }
    elsif options[:quality] == :high
      # Use high-quality model for explicit high-quality requests
      { provider: 'openai', model: 'gpt-4o' }
    elsif estimated_cost > 0.01
      # Use cheaper model for expensive requests
      { provider: 'groq', model: 'llama-3.1-70b-versatile' }
    else
      # Default balanced option
      { provider: 'openai', model: 'gpt-4o-mini' }
    end
  end
  
  def build_agent(config)
    agent = RAAF::Agent.new(
      name: @agent_type.to_s.camelize,
      instructions: get_agent_instructions(@agent_type),
      model: config[:model]
    )
    
    # Set provider if specified
    if config[:provider] != 'openai'
      agent.provider = get_provider(config[:provider])
    end
    
    agent
  end
  
  def get_provider(provider_name)
    case provider_name
    when 'anthropic'
      RAAF::Models::AnthropicProvider.new
    when 'groq'
      RAAF::Models::GroqProvider.new
    else
      RAAF::Models::ResponsesProvider.new
    end
  end
  
  def build_budget_exceeded_response(budget_check)
    OpenStruct.new(
      success?: false,
      error: 'Budget limit exceeded',
      messages: [{
        role: 'assistant',
        content: "I'm sorry, but this request would exceed your budget limit. " \
                "Current spend: $#{budget_check[:current_spend].round(4)}, " \
                "Budget: $#{budget_check[:budget_limit].round(4)}, " \
                "Requested cost: $#{budget_check[:requested_cost].round(4)}."
      }],
      usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
      cost_info: budget_check
    )
  end
  
  def enhance_result_with_cost_info(result, actual_cost, estimated_cost)
    # Add cost information to result
    result.define_singleton_method(:cost_info) do
      {
        actual_cost: actual_cost.round(6),
        estimated_cost: estimated_cost.round(6),
        cost_accuracy: ((actual_cost / estimated_cost) * 100).round(2),
        budget_status: @budget_manager.check_budget_status(@budget_scope)
      }
    end
    
    result
  end
end
```

Provider Cost Optimization
---------------------------

**Provider diversity is cost insurance.** Relying on a single AI provider creates both technical and financial risk. Providers change pricing, have outages, and implement rate limits. A multi-provider strategy provides cost optimization opportunities and operational resilience.

**The provider arbitrage opportunity:** Different providers have different cost structures. OpenAI might be cheaper for short responses, while Anthropic might be better for long-form content. Groq might be faster and cheaper for simple queries. The key is matching workloads to optimal providers based on cost, performance, and quality requirements.

**Routing intelligence:** This router doesn't just distribute load—it makes intelligent routing decisions based on cost efficiency, performance requirements, and current provider health. It's like having a financial advisor for your AI infrastructure.

### Multi-Provider Cost Router

```ruby
# lib/raaf/cost/provider_router.rb
module RAAF
  module Cost
    class ProviderRouter
      def initialize
        @providers = {}
        @cost_analyzer = Analyzer.instance
        @performance_tracker = {}
      end
      
      def register_provider(name, provider, cost_efficiency: 1.0, performance_tier: :standard)
        @providers[name] = {
          provider: provider,
          cost_efficiency: cost_efficiency,  # Lower is better
          performance_tier: performance_tier,
          last_updated: Time.current
        }
      end
      
      def route_request(requirements = {})
        # Filter providers based on requirements
        suitable_providers = filter_providers(requirements)
        
        # Select optimal provider based on cost and performance
        optimal_provider = select_optimal_provider(suitable_providers, requirements)
        
        optimal_provider
      end
      
      def get_cost_comparison(model_type, token_estimate)
        comparison = {}
        
        @providers.each do |name, config|
          provider = config[:provider]
          
          # Get pricing for equivalent model
          equivalent_model = get_equivalent_model(provider, model_type)
          next unless equivalent_model
          
          estimated_cost = @cost_analyzer.calculate_cost(
            provider.class.name.demodulize.downcase.gsub('provider', ''),
            equivalent_model,
            token_estimate
          )
          
          comparison[name] = {
            model: equivalent_model,
            estimated_cost: estimated_cost,
            cost_efficiency: config[:cost_efficiency],
            performance_tier: config[:performance_tier]
          }
        end
        
        comparison.sort_by { |_, data| data[:estimated_cost] }.to_h
      end
      
      def recommend_provider(budget, requirements = {})
        cost_comparison = get_cost_comparison(
          requirements[:model_type] || :general,
          requirements[:token_estimate] || { prompt_tokens: 1000, completion_tokens: 500 }
        )
        
        # Filter by budget
        affordable_providers = cost_comparison.select do |_, data|
          data[:estimated_cost] <= budget
        end
        
        return nil if affordable_providers.empty?
        
        # Recommend best value (cost vs performance)
        affordable_providers.max_by do |_, data|
          performance_score = performance_tier_score(data[:performance_tier])
          cost_score = 1.0 / (data[:estimated_cost] + 0.0001)  # Avoid division by zero
          
          (performance_score * cost_score) / data[:cost_efficiency]
        end
      end
      
      private
      
      def filter_providers(requirements)
        @providers.select do |name, config|
          meets_performance_requirements?(config, requirements) &&
          supports_required_features?(config[:provider], requirements)
        end
      end
      
      def meets_performance_requirements?(config, requirements)
        required_tier = requirements[:performance_tier] || :standard
        
        case required_tier
        when :economy
          true  # All providers meet economy requirements
        when :standard
          %i[standard premium].include?(config[:performance_tier])
        when :premium
          config[:performance_tier] == :premium
        else
          true
        end
      end
      
      def supports_required_features?(provider, requirements)
        # Check if provider supports required features
        return true unless requirements[:features]
        
        requirements[:features].all? do |feature|
          case feature
          when :function_calling
            provider.respond_to?(:supports_function_calling?) && provider.supports_function_calling?
          when :streaming
            provider.respond_to?(:supports_streaming?) && provider.supports_streaming?
          when :embeddings
            provider.respond_to?(:supports_embeddings?) && provider.supports_embeddings?
          else
            true
          end
        end
      end
      
      def select_optimal_provider(suitable_providers, requirements)
        return nil if suitable_providers.empty?
        
        # Score each provider
        scored_providers = suitable_providers.map do |name, config|
          score = calculate_provider_score(config, requirements)
          [name, config, score]
        end
        
        # Select highest scoring provider
        best_provider = scored_providers.max_by { |_, _, score| score }
        best_provider[1][:provider] if best_provider
      end
      
      def calculate_provider_score(config, requirements)
        # Base score from cost efficiency (lower cost efficiency = higher score)
        cost_score = 1.0 / config[:cost_efficiency]
        
        # Performance tier bonus
        performance_score = performance_tier_score(config[:performance_tier])
        
        # Historical performance bonus
        reliability_score = get_reliability_score(config[:provider])
        
        # Combine scores with weights
        (cost_score * 0.4) + (performance_score * 0.3) + (reliability_score * 0.3)
      end
      
      def performance_tier_score(tier)
        case tier
        when :economy then 1.0
        when :standard then 1.5
        when :premium then 2.0
        else 1.0
        end
      end
      
      def get_reliability_score(provider)
        # Get historical success rate and average latency
        # This would be tracked by your monitoring system
        1.0  # Placeholder
      end
      
      def get_equivalent_model(provider, model_type)
        # Map model types to provider-specific models
        model_mappings = {
          openai: {
            general: 'gpt-4o-mini',
            advanced: 'gpt-4o',
            fast: 'gpt-3.5-turbo'
          },
          anthropic: {
            general: 'claude-3-5-haiku-20241022',
            advanced: 'claude-3-5-sonnet-20241022',
            fast: 'claude-3-5-haiku-20241022'
          },
          groq: {
            general: 'llama-3.1-70b-versatile',
            advanced: 'llama-3.1-405b-reasoning',
            fast: 'llama-3.1-70b-versatile'
          }
        }
        
        provider_key = provider.class.name.demodulize.downcase.gsub('provider', '').to_sym
        model_mappings.dig(provider_key, model_type)
      end
    end
  end
end
```

Token Usage Optimization
-------------------------

**Tokens are the currency of AI.** Every character, every space, every piece of context consumes tokens. Token optimization is like optimizing database queries—small improvements compound into significant savings. The difference is that poorly optimized tokens cost money immediately.

**The token efficiency principle:** The same functionality can consume vastly different token counts depending on implementation. Verbose prompts, redundant context, and inefficient formatting can double or triple costs. Token optimization is about achieving the same results with fewer tokens.

**Context compression strategies:** AI models don't always need full context. Often, compressed or summarized context provides equivalent results at fraction of the cost. This token manager implements intelligent compression that maintains accuracy while reducing token consumption.

### Smart Token Manager

```ruby
# lib/raaf/cost/token_manager.rb
module RAAF
  module Cost
    class TokenManager
      def initialize
        @context_cache = {}
        @compression_enabled = true
      end
      
      def optimize_request(agent, message, context = {})
        # Compress context if enabled
        optimized_context = @compression_enabled ? compress_context(context) : context
        
        # Optimize instructions based on model
        optimized_instructions = optimize_instructions(agent.instructions, agent.model)
        
        # Use context caching if beneficial
        cached_context = get_cached_context(agent.name, optimized_context)
        
        # Create optimized request
        {
          agent: agent.dup.tap do |a|
            a.instructions = optimized_instructions
          end,
          message: message,
          context: cached_context || optimized_context,
          estimated_savings: calculate_estimated_savings(context, optimized_context, cached_context)
        }
      end
      
      def compress_context(context)
        return context if context.empty?
        
        compressed = {}
        
        context.each do |key, value|
          case value
          when String
            compressed[key] = compress_string_value(value)
          when Hash
            compressed[key] = compress_context(value)
          when Array
            compressed[key] = compress_array_value(value)
          else
            compressed[key] = value
          end
        end
        
        compressed
      end
      
      def optimize_instructions(instructions, model)
        # Tailor instructions based on model capabilities
        case model
        when /gpt-4o-mini|gpt-3.5-turbo/
          # Simplify instructions for smaller models
          simplify_instructions(instructions)
        when /claude.*haiku/
          # Optimize for Claude Haiku's concise style
          make_instructions_concise(instructions)
        else
          instructions
        end
      end
      
      def track_token_usage(request_info, actual_usage)
        # Calculate accuracy of estimation
        estimated = estimate_tokens(request_info[:message], request_info[:context])
        accuracy = calculate_estimation_accuracy(estimated, actual_usage)
        
        # Store for improving future estimations
        store_usage_data({
          message_length: request_info[:message].length,
          context_size: request_info[:context].to_json.length,
          estimated_tokens: estimated,
          actual_usage: actual_usage,
          accuracy: accuracy,
          model: request_info[:model],
          timestamp: Time.current
        })
        
        # Update model-specific estimation parameters
        update_estimation_parameters(request_info[:model], accuracy)
      end
      
      def estimate_tokens(message, context = {})
        # Improved token estimation based on historical data
        base_tokens = estimate_base_tokens(message)
        context_tokens = estimate_context_tokens(context)
        
        {
          prompt_tokens: base_tokens + context_tokens,
          completion_tokens: estimate_completion_tokens(message),
          total_tokens: base_tokens + context_tokens + estimate_completion_tokens(message)
        }
      end
      
      def get_optimization_suggestions(usage_history)
        suggestions = []
        
        # Analyze usage patterns
        high_token_requests = usage_history.select { |u| u[:actual_usage][:total_tokens] > 4000 }
        
        if high_token_requests.any?
          suggestions << {
            type: :context_optimization,
            description: "Consider reducing context size for #{high_token_requests.size} high-token requests",
            potential_savings: calculate_context_savings(high_token_requests)
          }
        end
        
        # Check for repetitive patterns
        repeated_contexts = find_repeated_contexts(usage_history)
        if repeated_contexts.any?
          suggestions << {
            type: :context_caching,
            description: "Enable context caching for #{repeated_contexts.size} repeated patterns",
            potential_savings: calculate_caching_savings(repeated_contexts)
          }
        end
        
        # Model recommendations
        model_suggestions = analyze_model_usage(usage_history)
        suggestions.concat(model_suggestions)
        
        suggestions
      end
      
      private
      
      def compress_string_value(value)
        return value if value.length < 100
        
        # Remove extra whitespace
        compressed = value.gsub(/\s+/, ' ').strip
        
        # Remove redundant information
        compressed = remove_redundant_phrases(compressed)
        
        compressed
      end
      
      def compress_array_value(array)
        # Limit array size and compress elements
        limited_array = array.first(10)  # Limit to 10 items
        
        limited_array.map do |item|
          case item
          when String
            compress_string_value(item)
          when Hash
            compress_context(item)
          else
            item
          end
        end
      end
      
      def remove_redundant_phrases(text)
        # Remove common redundant phrases
        redundant_patterns = [
          /\b(please note that|it should be noted that|it is important to)\b/i,
          /\b(in other words|that is to say|in essence)\b/i,
          /\b(basically|essentially|fundamentally)\b/i
        ]
        
        redundant_patterns.each do |pattern|
          text = text.gsub(pattern, '')
        end
        
        text.gsub(/\s+/, ' ').strip
      end
      
      def simplify_instructions(instructions)
        # Simplify language for smaller models
        simplified = instructions
          .gsub(/extremely|incredibly|exceptionally/, 'very')
          .gsub(/utilize|implement|facilitate/, 'use')
          .gsub(/consequently|therefore|thus/, 'so')
        
        # Shorten if too long
        sentences = simplified.split('. ')
        if sentences.length > 3
          simplified = sentences.first(3).join('. ') + '.'
        end
        
        simplified
      end
      
      def make_instructions_concise(instructions)
        # Make instructions more concise for Claude Haiku
        instructions
          .split('. ')
          .map { |sentence| sentence.gsub(/\b(very|really|quite|rather)\b/, '').strip }
          .reject(&:empty?)
          .join('. ')
      end
      
      def get_cached_context(agent_name, context)
        # Simple context caching based on content hash
        context_hash = Digest::SHA256.hexdigest(context.to_json)
        cache_key = "#{agent_name}_#{context_hash}"
        
        @context_cache[cache_key]
      end
      
      def calculate_estimated_savings(original_context, optimized_context, cached_context)
        original_size = original_context.to_json.length
        optimized_size = optimized_context.to_json.length
        cached_size = cached_context&.to_json&.length || optimized_size
        
        {
          compression_savings: ((original_size - optimized_size) / original_size.to_f * 100).round(2),
          cache_savings: cached_context ? ((optimized_size - cached_size) / optimized_size.to_f * 100).round(2) : 0,
          total_size_reduction: original_size - cached_size
        }
      end
      
      def estimate_base_tokens(message)
        # Character to token ratio varies by language and content
        # English: ~4 characters per token
        # Code: ~3 characters per token
        # Numbers/symbols: ~2 characters per token
        
        if code_content?(message)
          message.length / 3.0
        else
          message.length / 4.0
        end.round
      end
      
      def estimate_context_tokens(context)
        return 0 if context.empty?
        
        context_json = context.to_json
        context_json.length / 4.0
      end
      
      def estimate_completion_tokens(message)
        # Estimate based on message type and content
        base_estimate = message.length / 6.0  # Conservative estimate
        
        # Adjust based on query complexity
        complexity_multiplier = case message.downcase
                               when /explain|analyze|describe|elaborate/
                                 2.5
                               when /summarize|brief|short/
                                 0.8
                               when /list|enumerate/
                                 1.2
                               when /yes|no|\?$/
                                 0.3
                               else
                                 1.5
                               end
        
        (base_estimate * complexity_multiplier).round
      end
      
      def code_content?(text)
        # Simple heuristic to detect code content
        code_indicators = [
          /def |function |class |import |require/,
          /\{|\}|\[|\]/,
          /=\s*>|=>|\|>/,
          /\b(if|else|for|while|return)\b/
        ]
        
        code_indicators.any? { |pattern| text.match?(pattern) }
      end
      
      def calculate_estimation_accuracy(estimated, actual)
        total_estimated = estimated[:total_tokens]
        total_actual = actual[:total_tokens] || 0
        
        return 0 if total_actual == 0
        
        accuracy = (1 - (total_estimated - total_actual).abs / total_actual.to_f) * 100
        [accuracy, 0].max.round(2)
      end
      
      def store_usage_data(data)
        # In production, store in database for analysis
        @usage_history ||= []
        @usage_history << data
        @usage_history = @usage_history.last(1000)  # Keep recent data
      end
      
      def update_estimation_parameters(model, accuracy)
        # Adjust estimation parameters based on accuracy
        @model_parameters ||= {}
        @model_parameters[model] ||= { adjustment_factor: 1.0, sample_count: 0 }
        
        params = @model_parameters[model]
        params[:sample_count] += 1
        
        # Adjust factor if accuracy is consistently off
        if accuracy < 80 && params[:sample_count] > 10
          params[:adjustment_factor] *= 1.1
        elsif accuracy > 95 && params[:sample_count] > 10
          params[:adjustment_factor] *= 0.95
        end
      end
    end
  end
end
```

Cost Reporting and Analytics
-----------------------------

**Cost visibility drives optimization.** You can't optimize what you can't measure. AI costs are complex and multidimensional—by model, by user, by agent type, by time of day. Cost analytics provide the insights needed to make informed optimization decisions.

**The analytics challenge:** Traditional analytics focus on technical metrics like response time and error rates. AI cost analytics need to track business metrics like cost per user, cost per conversation, and return on investment. This requires different data collection and analysis approaches.

**Actionable insights:** This dashboard doesn't just show costs—it identifies cost drivers, trends, and optimization opportunities. It answers questions like "Which agents are most expensive?" and "What's driving our cost increases?" The goal is to enable data-driven cost optimization decisions.

### Cost Dashboard Controller

```ruby
# app/controllers/admin/cost_controller.rb
class Admin::CostController < ApplicationController
  before_action :authenticate_admin!
  
  def index
    @cost_summary = build_cost_summary
    @budget_status = get_budget_status
    @top_cost_drivers = get_top_cost_drivers
    @cost_trends = get_cost_trends
  end
  
  def detailed_report
    time_range = parse_time_range(params[:time_range] || '30d')
    group_by = params[:group_by] || 'model'
    
    @report = {
      time_range: time_range,
      breakdown: cost_analyzer.get_cost_breakdown(time_range, group_by: group_by.to_sym),
      trends: cost_analyzer.get_cost_trends,
      optimization_suggestions: get_optimization_suggestions(time_range)
    }
    
    respond_to do |format|
      format.html
      format.json { render json: @report }
      format.csv { send_csv_report(@report) }
    end
  end
  
  def budget_management
    @budgets = budget_manager.get_all_budgets_status
    @spending_forecast = calculate_spending_forecast
  end
  
  def optimization_recommendations
    usage_history = get_usage_history(30.days.ago..Time.current)
    @recommendations = token_manager.get_optimization_suggestions(usage_history)
    @potential_savings = calculate_potential_savings(@recommendations)
  end
  
  def cost_alerts
    @alerts = get_recent_cost_alerts
    @alert_settings = get_alert_settings
  end
  
  def update_budget
    scope = params[:scope]
    amount = params[:amount].to_f
    period = params[:period].to_sym
    
    budget_manager.set_budget(scope, amount, period: period)
    
    redirect_to admin_cost_budget_management_path, notice: 'Budget updated successfully'
  end
  
  private
  
  def cost_analyzer
    @cost_analyzer ||= RAAF::Cost::Analyzer.instance
  end
  
  def budget_manager
    @budget_manager ||= RAAF::Cost::BudgetManager.instance
  end
  
  def token_manager
    @token_manager ||= RAAF::Cost::TokenManager.new
  end
  
  def build_cost_summary
    today = Date.current
    yesterday = today - 1.day
    
    {
      today: get_daily_cost(today),
      yesterday: get_daily_cost(yesterday),
      month_to_date: get_month_to_date_cost,
      projected_monthly: calculate_projected_monthly_cost,
      avg_request_cost: calculate_avg_request_cost,
      total_requests_today: count_requests_today
    }
  end
  
  def get_budget_status
    budget_manager.get_all_budgets_status
  end
  
  def get_top_cost_drivers(limit = 10)
    cost_breakdown = cost_analyzer.get_cost_breakdown(30.days.ago..Time.current, group_by: :agent_type)
    
    cost_breakdown
      .sort_by { |_, data| data[:total_cost] }
      .reverse
      .first(limit)
      .to_h
  end
  
  def get_cost_trends
    cost_analyzer.get_cost_trends
  end
  
  def get_optimization_suggestions(time_range)
    usage_history = get_usage_history(time_range)
    token_manager.get_optimization_suggestions(usage_history)
  end
  
  def calculate_spending_forecast
    daily_costs = cost_analyzer.get_daily_costs(30)
    recent_avg = daily_costs.values.last(7).sum / 7.0
    
    {
      daily_average: recent_avg,
      weekly_projection: recent_avg * 7,
      monthly_projection: recent_avg * 30,
      quarterly_projection: recent_avg * 90
    }
  end
  
  def get_usage_history(time_range)
    # This would typically come from your database
    # For now, using the analyzer's data
    cost_analyzer.get_cost_breakdown(time_range, group_by: :model)
  end
  
  def calculate_potential_savings(recommendations)
    recommendations.sum { |rec| rec[:potential_savings] || 0 }
  end
  
  def get_daily_cost(date)
    day_range = date.beginning_of_day..date.end_of_day
    cost_analyzer.get_cost_breakdown(day_range)
      .values
      .sum { |data| data[:total_cost] }
  end
  
  def get_month_to_date_cost
    month_range = Date.current.beginning_of_month..Date.current.end_of_day
    cost_analyzer.get_cost_breakdown(month_range)
      .values
      .sum { |data| data[:total_cost] }
  end
  
  def calculate_projected_monthly_cost
    # Use recent daily average to project monthly cost
    recent_daily_avg = cost_analyzer.get_daily_costs(7).values.sum / 7.0
    recent_daily_avg * Date.current.end_of_month.day
  end
  
  def calculate_avg_request_cost
    today_breakdown = cost_analyzer.get_cost_breakdown(Date.current.beginning_of_day..Time.current)
    
    total_cost = today_breakdown.values.sum { |data| data[:total_cost] }
    total_requests = today_breakdown.values.sum { |data| data[:request_count] }
    
    return 0 if total_requests == 0
    
    total_cost / total_requests
  end
  
  def count_requests_today
    today_breakdown = cost_analyzer.get_cost_breakdown(Date.current.beginning_of_day..Time.current)
    today_breakdown.values.sum { |data| data[:request_count] }
  end
  
  def send_csv_report(report)
    csv_data = generate_csv(report)
    send_data csv_data, 
              filename: "raaf_cost_report_#{Date.current}.csv",
              type: 'text/csv'
  end
  
  def generate_csv(report)
    CSV.generate do |csv|
      csv << ['Category', 'Total Cost', 'Request Count', 'Avg Cost per Request', 'Total Tokens']
      
      report[:breakdown].each do |category, data|
        csv << [
          category,
          data[:total_cost].round(4),
          data[:request_count],
          data[:avg_cost_per_request].round(6),
          data[:total_tokens]
        ]
      end
    end
  end
end
```

Cost Optimization Best Practices
---------------------------------

**Cost optimization is a journey, not a destination.** AI provider pricing changes, model capabilities evolve, and usage patterns shift. Cost optimization requires continuous monitoring, measurement, and adjustment. What works today might not work tomorrow.

**The optimization hierarchy:** Start with the highest-impact, lowest-effort optimizations. Caching and provider routing often provide 50%+ cost reductions with minimal implementation effort. Token optimization and advanced strategies provide incremental improvements but require more sophisticated implementation.

**Measurement-driven optimization:** Every optimization should be measured and validated. Cost optimization decisions should be based on data, not assumptions. This checklist provides a systematic approach to implementing and measuring cost optimization strategies.

### Implementation Checklist

1. **Token Management**
   - ✅ Implement context compression
   - ✅ Use appropriate models for task complexity
   - ✅ Enable context caching where beneficial
   - ✅ Optimize prompt engineering
   - ✅ Monitor token usage patterns

2. **Provider Strategy**
   - ✅ Implement multi-provider routing
   - ✅ Use cost-aware provider selection
   - ✅ Monitor provider pricing changes
   - ✅ Implement failover to cheaper providers
   - ✅ Negotiate volume discounts where applicable

3. **Budget Controls**
   - ✅ Set up budget alerts and limits
   - ✅ Implement user/department cost allocation
   - ✅ Create approval workflows for high-cost requests
   - ✅ Monitor budget burn rates
   - ✅ Regularly review and adjust budgets

4. **Usage Optimization**
   - ✅ Cache frequent responses
   - ✅ Implement request deduplication
   - ✅ Use batch processing where possible
   - ✅ Optimize agent instructions
   - ✅ Monitor and reduce failed requests

5. **Cost Monitoring**
   - ✅ Real-time cost tracking
   - ✅ Detailed cost breakdowns
   - ✅ Cost trend analysis
   - ✅ ROI measurement
   - ✅ Regular cost reviews

### Cost Optimization Strategies

```ruby
# config/initializers/raaf_cost_optimization.rb
RAAF.configure do |config|
  # Enable cost tracking
  config.cost_tracking_enabled = true
  config.detailed_cost_analytics = true
  
  # Budget controls
  config.global_monthly_budget = 1000.00  # $1000/month
  config.cost_alert_thresholds = [50, 75, 90, 95]  # Percentage alerts
  
  # Token optimization
  config.context_compression_enabled = true
  config.context_caching_enabled = true
  config.smart_model_selection = true
  
  # Provider routing for cost optimization
  config.cost_aware_routing = true
  config.prefer_cheaper_providers_threshold = 0.75  # Switch to cheaper when >75% of budget used
  
  # Request optimization
  config.response_caching_enabled = true
  config.request_deduplication_enabled = true
  config.batch_processing_enabled = true
end

# Set up cost-aware agent factory
class CostOptimizedAgentFactory
  def self.create_agent(type, user_budget_status = nil)
    config = agent_configs[type]
    
    # Select model based on budget status
    if user_budget_status && user_budget_status[:percentage_used] > 75
      config = config.merge(model: config[:economy_model])
    end
    
    agent = RAAF::Agent.new(config)
    
    # Wrap with cost controls
    CostAwareAgentService.new(
      user: current_user,
      agent_type: type,
      budget_scope: "user_#{current_user.id}"
    )
  end
  
  private
  
  def self.agent_configs
    {
      customer_support: {
        name: "CustomerSupport",
        instructions: "Provide helpful customer support. Be concise but complete.",
        model: "gpt-4o-mini",
        economy_model: "gpt-3.5-turbo"
      },
      data_analyst: {
        name: "DataAnalyst",
        instructions: "Analyze data and provide insights.",
        model: "gpt-4o",
        economy_model: "gpt-4o-mini"
      }
    }
  end
end
```

Next Steps
----------

For comprehensive cost management:

* **[Performance Guide](performance_guide.html)** - Optimize for both cost and performance
* **[RAAF Tracing Guide](tracing_guide.html)** - Monitor cost and usage metrics
* **[Troubleshooting Guide](troubleshooting.html)** - Resolve cost-related issues
* **[Configuration Reference](configuration_reference.html)** - Production configuration for cost optimization