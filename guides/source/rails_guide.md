**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Rails Integration Guide
============================

This guide covers integrating Ruby AI Agents Factory (RAAF) into Rails applications. You'll learn how to add AI agents to your Rails app, use the built-in dashboard, implement real-time monitoring, and follow Rails conventions.

**Rails + AI: A natural fit.** Rails applications already handle user interactions, manage data, and coordinate complex workflows. Adding AI agents extends these capabilities with intelligent automation, natural language interfaces, and automated decision-making. The combination creates applications that feel more responsive, intelligent, and capable.

But integrating AI into Rails requires careful consideration of performance, security, and user experience. AI operations can be slow and expensive, so you need caching, background processing, and intelligent routing. You need to integrate AI responses with existing Rails patterns like controllers, views, and models. Most importantly, you need to maintain the Rails philosophy of convention over configuration while adding AI capabilities.

RAAF's Rails integration provides opinionated patterns that feel natural to Rails developers. It leverages Rails' strengths—routing, ActiveRecord, ActionCable, background jobs—while adding AI-specific features like intelligent caching, real-time monitoring, and conversational interfaces.

After reading this guide, you will know:

* How to set up RAAF in a Rails application
* How to use the RAAF Rails engine and dashboard
* Patterns for controller integration and middleware
* Real-time monitoring with ActionCable and WebSockets
* Database integration for agent memory and tracing
* Deployment considerations for Rails + RAAF applications

--------------------------------------------------------------------------------

Getting Started
---------------

### Installation

Add RAAF Rails to your Gemfile:

```ruby
# Gemfile
gem 'raaf-rails'
gem 'raaf-core'
gem 'raaf-tracing'  # For dashboard functionality
```

Install and generate configuration:

```bash
bundle install
rails generate raaf:install
```

This creates:

* `config/initializers/raaf.rb` - RAAF configuration
* `config/raaf.yml` - Environment-specific settings  
* Migration for tracing tables (if using database tracing)

### Basic Configuration

```ruby
# config/initializers/raaf.rb
RAAF.configure do |config|
  config.default_model = "gpt-4o"
  config.log_level = Rails.env.production? ? :info : :debug
  config.dashboard_enabled = true
  config.dashboard_path = "/raaf"
end
```

Environment-specific configuration:

```yaml
# config/raaf.yml
development:
  openai_api_key: <%= ENV['OPENAI_API_KEY'] %>
  dashboard_enabled: true
  tracing_enabled: true
  log_level: debug

production:
  openai_api_key: <%= ENV['OPENAI_API_KEY'] %>
  dashboard_enabled: <%= ENV['RAAF_DASHBOARD_ENABLED'] %>
  tracing_enabled: true
  log_level: info
  dashboard_auth: <%= ENV['RAAF_DASHBOARD_AUTH'] %>
```

Rails Engine and Dashboard
--------------------------

RAAF Rails includes a built-in engine with a comprehensive dashboard for monitoring agent performance, viewing traces, and managing costs.

### Mounting the Engine

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount RAAF::Rails::Engine => '/raaf', as: 'raaf'
  
  # Your application routes
end
```

### Dashboard Features

The dashboard provides:

* **Agent Performance** - Response times, token usage, success rates
* **Live Tracing** - Real-time conversation monitoring
* **Cost Analytics** - Provider costs, usage trends, budget tracking
* **Error Monitoring** - Failed agent calls, tool errors, rate limits
* **System Health** - Provider status, connection monitoring

### Dashboard Authentication

For production, secure the dashboard:

```ruby
# config/initializers/raaf.rb
RAAF.configure do |config|
  config.dashboard_auth = lambda do |request|
    # Example: Basic HTTP auth
    authenticate_or_request_with_http_basic do |username, password|
      username == ENV['RAAF_DASHBOARD_USER'] && 
      password == ENV['RAAF_DASHBOARD_PASSWORD']
    end
  end
end
```

Controller Integration
----------------------

### Basic Agent Usage

```ruby
class ChatController < ApplicationController
  def create
    agent = RAAF::Agent.new(
      name: "CustomerSupport",
      instructions: "You are a helpful customer support agent for our Rails app.",
      model: "gpt-4o"
    )
    
    runner = RAAF::Runner.new(
      agent: agent,
      context_variables: {
        user_id: current_user.id,
        session_id: session.id
      }
    )
    
    result = runner.run(params[:message])
    
    render json: {
      response: result.messages.last[:content],
      usage: result.usage,
      success: result.success?
    }
  end
end
```

### Agent Service Object Pattern

```ruby
# app/services/agent_service.rb
class AgentService
  include ActiveModel::Model
  
  attr_accessor :user, :agent_type
  
  def initialize(user:, agent_type: :general)
    @user = user
    @agent_type = agent_type
    @agent = build_agent
    @runner = build_runner
  end
  
  def chat(message, context: {})
    full_context = base_context.merge(context)
    
    result = @runner.run(message, context_variables: full_context)
    
    # Log for analytics
    AgentInteraction.create!(
      user: @user,
      agent_type: @agent_type,
      message: message,
      response: result.messages.last[:content],
      tokens_used: result.usage[:total_tokens],
      duration_ms: result.duration_ms,
      success: result.success?
    )
    
    result
  end
  
  private
  
  def build_agent
    case @agent_type
    when :customer_support
      CustomerSupportAgent.new
    when :data_analyst
      DataAnalystAgent.new
    else
      GeneralAssistantAgent.new
    end
  end
  
  def build_runner
    RAAF::Runner.new(
      agent: @agent,
      memory_manager: build_memory_manager,
      tracer: Rails.application.config.raaf_tracer
    )
  end
  
  def build_memory_manager
    RAAF::Memory::MemoryManager.new(
      store: RAAF::Memory::DatabaseStore.new(
        model: AgentMemory,
        session_column: 'session_id',
        user_column: 'user_id'
      ),
      max_tokens: 8000
    )
  end
  
  def base_context
    {
      user_id: @user.id,
      user_name: @user.name,
      user_role: @user.role,
      session_id: "user_#{@user.id}_#{Date.current}",
      app_environment: Rails.env
    }
  end
end
```

### Using the Service

```ruby
class ChatController < ApplicationController
  def create
    service = AgentService.new(
      user: current_user,
      agent_type: params[:agent_type]&.to_sym || :general
    )
    
    result = service.chat(
      params[:message],
      context: { channel: 'web', feature: params[:feature] }
    )
    
    if result.success?
      render json: { 
        response: result.messages.last[:content],
        agent: result.agent.name,
        usage: result.usage
      }
    else
      render json: { 
        error: result.error 
      }, status: :unprocessable_entity
    end
  end
end
```

Real-time Features with ActionCable
-----------------------------------

### Streaming Responses

```ruby
# app/channels/agent_channel.rb
class AgentChannel < ApplicationCable::Channel
  def subscribed
    stream_from "agent_#{current_user.id}"
  end
  
  def chat(data)
    agent_service = AgentService.new(
      user: current_user,
      agent_type: data['agent_type']&.to_sym
    )
    
    # Stream response chunks in real-time
    agent_service.stream_chat(data['message']) do |chunk|
      ActionCable.server.broadcast(
        "agent_#{current_user.id}",
        {
          type: 'chunk',
          content: chunk.delta,
          chunk_type: chunk.type
        }
      )
    end
    
    ActionCable.server.broadcast(
      "agent_#{current_user.id}",
      {
        type: 'complete',
        message: 'Response complete'
      }
    )
  end
end
```

```javascript
// app/javascript/agent_chat.js
import consumer from "./consumer"

const agentChannel = consumer.subscriptions.create("AgentChannel", {
  received(data) {
    if (data.type === 'chunk') {
      this.appendToResponse(data.content);
    } else if (data.type === 'complete') {
      this.onResponseComplete();
    }
  },
  
  chat(message, agentType) {
    this.perform('chat', {
      message: message,
      agent_type: agentType
    });
  },
  
  appendToResponse(content) {
    const responseElement = document.getElementById('agent-response');
    responseElement.textContent += content;
  },
  
  onResponseComplete() {
    console.log('Agent response complete');
  }
});
```

Database Integration
--------------------

### Agent Memory Storage

```ruby
# db/migrate/xxx_create_agent_memories.rb
class CreateAgentMemories < ActiveRecord::Migration[7.0]
  def change
    create_table :agent_memories do |t|
      t.references :user, null: false, foreign_key: true
      t.string :session_id, null: false
      t.string :role, null: false
      t.text :content
      t.json :metadata
      t.timestamps
    end
    
    add_index :agent_memories, [:user_id, :session_id]
    add_index :agent_memories, :session_id
  end
end
```

```ruby
# app/models/agent_memory.rb
class AgentMemory < ApplicationRecord
  belongs_to :user
  
  validates :session_id, :role, :content, presence: true
  validates :role, inclusion: { in: %w[user assistant system tool] }
  
  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }
end
```

### Agent Interaction Analytics

```ruby
# db/migrate/xxx_create_agent_interactions.rb
class CreateAgentInteractions < ActiveRecord::Migration[7.0]
  def change
    create_table :agent_interactions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :agent_type, null: false
      t.text :message
      t.text :response
      t.integer :tokens_used
      t.integer :duration_ms
      t.boolean :success, default: true
      t.string :error_message
      t.json :context_variables
      t.json :usage_details
      t.timestamps
    end
    
    add_index :agent_interactions, [:user_id, :created_at]
    add_index :agent_interactions, :agent_type
    add_index :agent_interactions, :success
  end
end
```

### Tracing Integration

RAAF Rails automatically integrates with ActiveRecord for trace storage:

```ruby
# app/models/raaf_trace.rb
class RaafTrace < ApplicationRecord
  self.table_name = 'raaf_traces'
  
  has_many :raaf_spans, dependent: :destroy
  
  scope :recent, ->(limit = 100) { order(created_at: :desc).limit(limit) }
  scope :by_agent, ->(agent_name) { where(agent_name: agent_name) }
  scope :errors, -> { where(status: 'error') }
end

# app/models/raaf_span.rb  
class RaafSpan < ApplicationRecord
  self.table_name = 'raaf_spans'
  
  belongs_to :raaf_trace
  
  scope :agent_spans, -> { where(span_type: 'agent') }
  scope :tool_spans, -> { where(span_type: 'tool') }
end
```

Middleware Integration
----------------------

### Request Context Middleware

```ruby
# app/middleware/raaf_context_middleware.rb
class RaafContextMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    request = ActionDispatch::Request.new(env)
    
    # Set global context for RAAF agents
    RAAF::Context.set({
      request_id: request.request_id,
      user_agent: request.user_agent,
      ip_address: request.remote_ip,
      path: request.path,
      method: request.method
    })
    
    @app.call(env)
  ensure
    RAAF::Context.clear
  end
end

# config/application.rb
config.middleware.use RaafContextMiddleware
```

### Error Handling Middleware

```ruby
# app/middleware/raaf_error_middleware.rb
class RaafErrorMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    @app.call(env)
  rescue RAAF::Errors::AgentError => e
    Rails.logger.error "RAAF Agent Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    # Report to error tracking service
    ExceptionNotifier.notify_exception(e, env: env)
    
    # Return user-friendly response
    [500, {}, ["AI service temporarily unavailable"]]
  rescue RAAF::Errors::RateLimitError => e
    Rails.logger.warn "RAAF Rate Limit: #{e.message}"
    [429, {}, ["Too many requests. Please try again later."]]
  end
end
```

Background Job Integration
--------------------------

### Async Agent Processing

```ruby
# app/jobs/agent_processing_job.rb
class AgentProcessingJob < ApplicationJob
  queue_as :agents
  
  def perform(user_id, message, agent_type, context = {})
    user = User.find(user_id)
    service = AgentService.new(user: user, agent_type: agent_type.to_sym)
    
    result = service.chat(message, context: context)
    
    # Broadcast result via ActionCable
    ActionCable.server.broadcast(
      "agent_#{user_id}",
      {
        type: 'response',
        content: result.messages.last[:content],
        success: result.success?,
        usage: result.usage
      }
    )
  rescue => e
    Rails.logger.error "Agent job failed: #{e.message}"
    
    ActionCable.server.broadcast(
      "agent_#{user_id}",
      {
        type: 'error',
        message: 'Agent processing failed'
      }
    )
  end
end
```

### Batch Processing

```ruby
# app/jobs/batch_agent_job.rb
class BatchAgentJob < ApplicationJob
  queue_as :batch_agents
  
  def perform(batch_id)
    batch = AgentBatch.find(batch_id)
    
    batch.items.pending.find_each do |item|
      begin
        agent = build_agent_for_item(item)
        runner = RAAF::Runner.new(agent: agent)
        
        result = runner.run(item.input_message)
        
        item.update!(
          output_content: result.messages.last[:content],
          tokens_used: result.usage[:total_tokens],
          processed_at: Time.current,
          status: 'completed'
        )
      rescue => e
        item.update!(
          error_message: e.message,
          status: 'failed'
        )
      end
    end
    
    batch.update_completion_status!
  end
end
```

Configuration Management
------------------------

### Environment-specific Agents

```ruby
# config/raaf.yml
development:
  agents:
    customer_support:
      model: "gpt-4o-mini"  # Cheaper for development
      instructions: "You are a customer support agent. Keep responses brief for testing."
      tools: ["basic_search"]
    
production:
  agents:
    customer_support:
      model: "gpt-4o"
      instructions: "You are a professional customer support agent for our platform."
      tools: ["web_search", "knowledge_base", "ticket_system"]
```

### Agent Factory

```ruby
# app/services/agent_factory.rb
class AgentFactory
  def self.build(type, environment = Rails.env)
    config = Rails.application.config_for(:raaf)
    agent_config = config.dig('agents', type.to_s)
    
    raise ArgumentError, "Unknown agent type: #{type}" unless agent_config
    
    agent = RAAF::Agent.new(
      name: type.to_s.camelize,
      instructions: agent_config['instructions'],
      model: agent_config['model']
    )
    
    # Add tools based on configuration
    agent_config['tools']&.each do |tool_name|
      agent.add_tool(tool_registry[tool_name])
    end
    
    agent
  end
  
  private
  
  def self.tool_registry
    {
      'web_search' => method(:web_search_tool),
      'knowledge_base' => method(:knowledge_base_tool),
      'ticket_system' => method(:ticket_system_tool)
    }
  end
end
```

Testing with Rails
------------------

### RSpec Integration

```ruby
# spec/rails_helper.rb
require 'raaf/testing'

RSpec.configure do |config|
  config.include RAAF::Testing::Helpers
  
  config.before(:each, type: :agent) do
    RAAF.configure do |c|
      c.provider = RAAF::Testing::MockProvider.new
    end
  end
end
```

### Controller Tests

```ruby
# spec/controllers/chat_controller_spec.rb
RSpec.describe ChatController, type: :controller do
  let(:user) { create(:user) }
  let(:mock_provider) { RAAF::Testing::MockProvider.new }
  
  before do
    sign_in user
    allow(RAAF).to receive(:provider).and_return(mock_provider)
  end
  
  describe 'POST #create' do
    it 'processes chat message successfully' do
      mock_provider.add_response("Hello! How can I help you today?")
      
      post :create, params: { message: "Hello" }
      
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)['response']).to include('Hello!')
    end
    
    it 'handles agent errors gracefully' do
      mock_provider.add_error(RAAF::Errors::RateLimitError.new("Rate limited"))
      
      post :create, params: { message: "Hello" }
      
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

### Agent Service Tests

```ruby
# spec/services/agent_service_spec.rb
RSpec.describe AgentService, type: :agent do
  let(:user) { create(:user) }
  let(:service) { AgentService.new(user: user, agent_type: :customer_support) }
  
  describe '#chat' do
    it 'creates agent interaction record' do
      mock_agent_response("Thank you for contacting support!")
      
      expect {
        service.chat("I need help")
      }.to change(AgentInteraction, :count).by(1)
    end
    
    it 'includes user context in agent call' do
      expect(service).to receive(:build_runner).and_call_original
      
      result = service.chat("Hello")
      
      expect(result.context_variables[:user_id]).to eq(user.id)
    end
  end
end
```

Deployment Considerations
-------------------------

### Environment Variables

```bash
# Production environment variables
OPENAI_API_KEY=sk-...
RAAF_DASHBOARD_ENABLED=true
RAAF_DASHBOARD_USER=admin
RAAF_DASHBOARD_PASSWORD=secure_password
RAAF_LOG_LEVEL=info
RAAF_DEFAULT_MODEL=gpt-4o
```

### Docker Configuration

```dockerfile
# Dockerfile
FROM ruby:3.1

# Install system dependencies for RAAF
RUN apt-get update && apt-get install -y \
  python3 \
  python3-pip \
  && pip3 install spacy \
  && python3 -m spacy download en_core_web_sm

WORKDIR /app

COPY Gemfile* ./
RUN bundle install

COPY . .

EXPOSE 3000
CMD ["rails", "server", "-b", "0.0.0.0"]
```

### Kubernetes Deployment

```yaml
# k8s/raaf-rails-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: raaf-rails-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: raaf-rails
  template:
    metadata:
      labels:
        app: raaf-rails
    spec:
      containers:

      - name: app
        image: your-registry/raaf-rails:latest
        ports:

        - containerPort: 3000
        env:

        - name: OPENAI_API_KEY
          valueFrom:
            secretKeyRef:
              name: raaf-secrets
              key: openai-api-key

        - name: RAAF_DASHBOARD_ENABLED
          value: "true"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
```

Performance Monitoring
----------------------

### Application Performance Monitoring

```ruby
# config/initializers/raaf_monitoring.rb
if Rails.env.production?
  RAAF.configure do |config|
    # Enable comprehensive tracing
    config.tracing_enabled = true
    config.trace_sampling_rate = 0.1  # Sample 10% for performance
    
    # Set up alerting
    config.on_error do |error, context|
      # Send to error tracking service
      Sentry.capture_exception(error, extra: context)
    end
    
    config.on_slow_response do |duration, context|
      # Alert on slow responses (>5 seconds)
      if duration > 5000
        AlertService.notify_slow_agent_response(duration, context)
      end
    end
  end
end
```

### Custom Metrics

```ruby
# app/services/agent_metrics_service.rb
class AgentMetricsService
  def self.record_interaction(result, agent_type, user)
    # Custom business metrics
    StatsD.increment('raaf.interactions.total', 
      tags: ["agent_type:#{agent_type}", "success:#{result.success?}"])
    
    StatsD.histogram('raaf.response_time', result.duration_ms,
      tags: ["agent_type:#{agent_type}"])
    
    StatsD.histogram('raaf.token_usage', result.usage[:total_tokens],
      tags: ["agent_type:#{agent_type}", "model:#{result.agent.model}"])
    
    # Cost tracking
    cost = calculate_cost(result.usage, result.agent.model)
    StatsD.histogram('raaf.interaction_cost', cost,
      tags: ["agent_type:#{agent_type}"])
  end
  
  private
  
  def self.calculate_cost(usage, model)
    # Calculate cost based on model pricing
    case model
    when 'gpt-4o'
      (usage[:prompt_tokens] * 0.005 + usage[:completion_tokens] * 0.015) / 1000
    when 'gpt-4o-mini'
      (usage[:prompt_tokens] * 0.00015 + usage[:completion_tokens] * 0.0006) / 1000
    else
      0
    end
  end
end
```

Security Considerations
-----------------------

### API Key Management

```ruby
# config/initializers/raaf.rb
RAAF.configure do |config|
  # Never log API keys
  config.log_filter_params = [:openai_api_key, :anthropic_api_key, :api_key]
  
  # Validate API keys are present
  required_keys = %w[OPENAI_API_KEY]
  required_keys.each do |key|
    raise "Missing required environment variable: #{key}" unless ENV[key]
  end
end
```

### Input Sanitization

```ruby
# app/controllers/chat_controller.rb
class ChatController < ApplicationController
  before_action :sanitize_input
  
  private
  
  def sanitize_input
    params[:message] = ActionController::Base.helpers.sanitize(
      params[:message],
      tags: [],
      attributes: []
    )
    
    # Length limits
    if params[:message].length > 4000
      render json: { error: 'Message too long' }, status: :bad_request
      return
    end
  end
end
```

### Rate Limiting

```ruby
# app/controllers/chat_controller.rb
class ChatController < ApplicationController
  include ActionController::RateLimiting
  
  rate_limit to: 10, within: 1.minute, by: -> { current_user.id }
  rate_limit to: 100, within: 1.hour, by: -> { current_user.id }
end
```

Best Practices
--------------

### Agent Design Patterns

1. **Single Responsibility** - One agent type per specific domain
2. **Stateless Agents** - Keep agents reusable and thread-safe
3. **Context Management** - Use context variables for user-specific data
4. **Error Handling** - Always handle agent failures gracefully
5. **Testing** - Mock agents in tests for faster, reliable testing

### Performance Optimization

1. **Connection Pooling** - Reuse HTTP connections to AI providers
2. **Caching** - Cache frequent agent responses when appropriate
3. **Background Processing** - Use jobs for non-real-time interactions
4. **Model Selection** - Choose appropriate models for different use cases
5. **Token Management** - Monitor and control token usage

### Monitoring and Observability

1. **Comprehensive Logging** - Log all agent interactions and errors
2. **Performance Metrics** - Track response times and token usage
3. **Cost Monitoring** - Monitor AI provider costs and usage
4. **Error Alerting** - Set up alerts for agent failures
5. **Dashboard Usage** - Regularly review the RAAF dashboard

Next Steps
----------

For more advanced topics:

* **[RAAF Streaming Guide](streaming_guide.html)** - Real-time streaming responses
* **[RAAF Tracing Guide](tracing_guide.html)** - Advanced monitoring and observability
* **[Performance Guide](performance_guide.html)** - Optimization techniques
* **[Deployment Guide](deployment_guide.html)** - Production deployment strategies