# RAAF Rails

[![🚀 Rails CI](https://github.com/raaf-ai/raaf/actions/workflows/rails-ci.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/rails-ci.yml)
[![⚡ Quick Check](https://github.com/raaf-ai/raaf/actions/workflows/rails-quick-check.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/rails-quick-check.yml)
[![🌙 Nightly](https://github.com/raaf-ai/raaf/actions/workflows/rails-nightly.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/rails-nightly.yml)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%203.2-ruby.svg)](https://www.ruby-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Rails** gem provides comprehensive Rails integration for the Ruby AI Agents Factory (RAAF). This gem adds web dashboards, REST APIs, WebSocket support, and seamless Rails application integration to the RAAF ecosystem.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-rails'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install raaf-rails
```

## Quick Start

```ruby
# Mount the engine in config/routes.rb
Rails.application.routes.draw do
  mount RAAF::Rails::Engine, at: "/agents"
end

# Configure in config/initializers/raaf.rb
RAAF::Rails.configure do |config|
  config.authentication_method = :devise
  config.enable_dashboard = true
  config.enable_api = true
end

# Create and use agents
agent = RAAF::Rails.create_agent(
  name: "Assistant",
  instructions: "You are a helpful assistant",
  model: "gpt-4o",
  user: current_user
)

result = RAAF::Rails.start_conversation(
  agent_id: agent.id,
  message: "Hello!",
  context: { user: current_user }
)
```

## Core Components

### Rails Engine
The mountable engine that provides dashboard, API, and WebSocket endpoints.

```ruby
# config/routes.rb
mount RAAF::Rails::Engine, at: "/agents"

# Access points:
# - /agents/dashboard - Web dashboard
# - /agents/api/v1 - REST API
# - /agents/chat - WebSocket endpoint
```

### Dashboard Controller
Web interface for managing agents, conversations, and analytics.

```ruby
# Provided actions:
# - index: Dashboard overview
# - agents: Agent management
# - conversations: Conversation history
# - analytics: Usage metrics
```

### WebSocket Handler
Real-time bidirectional communication for chat interfaces.

```ruby
# JavaScript client example
const ws = new WebSocket('ws://localhost:3000/agents/chat');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Agent:', data.message);
};

ws.send(JSON.stringify({
  type: 'chat',
  agent_id: 'agent_123',
  content: 'Hello!'
}));
```

### Agent Helper
View helpers for Rails applications.

```erb
<%= agent_status_badge(@agent) %>
<%= format_agent_response(@response) %>
<%= agent_model_options %>
<%= format_agent_tools(@agent.tools) %>
<%= agent_deploy_button(@agent) %>
<%= render_agent_metrics(@agent) %>
```

## Configuration

### Basic Configuration

```ruby
RAAF::Rails.configure do |config|
  # Authentication
  config.authentication_method = :devise  # :devise, :custom, :none
  
  # Features
  config.enable_dashboard = true
  config.enable_api = true
  config.enable_websockets = true
  config.enable_background_jobs = true
  
  # Paths
  config.dashboard_path = "/dashboard"
  config.api_path = "/api/v1"
  config.websocket_path = "/chat"
  
  # Security
  config.allowed_origins = ["*"]
  config.rate_limit = {
    enabled: true,
    requests_per_minute: 60
  }
  
  # Monitoring
  config.monitoring = {
    enabled: true,
    metrics: [:usage, :performance, :errors]
  }
end
```

### Custom Authentication

```ruby
RAAF::Rails.configure do |config|
  config.authentication_method = :custom
  config.authentication_handler = ->(request) {
    # Your custom authentication logic
    User.find_by(api_key: request.headers["X-API-Key"])
  }
end
```

## Creating Agents

### Via Dashboard

1. Navigate to `/agents/dashboard`
2. Click "New Agent"
3. Fill in agent details
4. Configure tools and handoffs
5. Deploy the agent

### Via API

```bash
curl -X POST http://localhost:3000/api/v1/agents \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "name": "Support Agent",
    "instructions": "You help customers with their questions",
    "model": "gpt-4o",
    "tools": ["web_search", "knowledge_base"]
  }'
```

### Via Rails Code

```ruby
# In a controller or service
agent = RAAF::Rails.create_agent(
  name: "Sales Assistant",
  instructions: "You help with sales inquiries",
  model: "gpt-4o",
  user: current_user,
  tools: ["product_search", "price_calculator"],
  metadata: {
    department: "sales",
    region: "north"
  }
)

# Deploy the agent
agent.deploy!
```

## Starting Conversations

### Via API

```bash
curl -X POST http://localhost:3000/api/v1/agents/123/conversations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "message": "What products do you have?",
    "context": {
      "user_id": 456,
      "session_id": "abc123"
    }
  }'
```

### Via WebSocket

```javascript
// Connect to WebSocket
const ws = new WebSocket('ws://localhost:3000/agents/chat');

// Handle connection
ws.onopen = () => {
  // Join agent session
  ws.send(JSON.stringify({
    type: 'join_agent',
    agent_id: 'agent_123'
  }));
};

// Handle messages
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  
  switch(data.type) {
    case 'message':
      console.log('Agent:', data.content);
      break;
    case 'typing':
      console.log('Agent is typing...');
      break;
    case 'error':
      console.error('Error:', data.message);
      break;
  }
};

// Send message
ws.send(JSON.stringify({
  type: 'chat',
  agent_id: 'agent_123',
  content: 'Hello, I need help!'
}));
```

### Via Rails Code

```ruby
# Synchronous conversation
result = RAAF::Rails.start_conversation(
  agent_id: agent.id,
  message: "Hello!",
  context: {
    user: current_user,
    session_id: session.id,
    metadata: { source: "web" }
  }
)

puts result[:message]
puts result[:usage]

# Asynchronous with background jobs
ConversationJob.perform_async(
  current_user.id,
  agent.id,
  "Hello!",
  { session_id: session.id }
)
```

## Models

### AgentModel

```ruby
# Creating agents
agent = RAAF::Rails::AgentModel.create!(
  name: "Customer Support",
  instructions: "You are a helpful support agent",
  model: "gpt-4o",
  user: current_user,
  status: "draft"
)

# Instance methods
agent.deploy!                    # Deploy the agent
agent.undeploy!                 # Undeploy the agent
agent.process_message(msg)      # Process a message
agent.add_tool(tool)           # Add a tool
agent.add_handoff(other_agent) # Add handoff target

# Scopes and queries
AgentModel.deployed            # All deployed agents
AgentModel.by_user(user)      # User's agents
AgentModel.with_tool("web")   # Agents with specific tool
```

### ConversationModel

```ruby
# Creating conversations
conversation = RAAF::Rails::ConversationModel.create!(
  agent: agent,
  user: current_user,
  context: { session_id: "abc123" }
)

# Managing messages
conversation.add_message("Hello", role: "user")
response = agent.process_message("Hello")
conversation.add_message(response[:content], role: "assistant")

# Queries
conversation.messages.by_role("user")
conversation.total_tokens
conversation.duration
conversation.successful?
```

### MessageModel

```ruby
# Message structure
message = RAAF::Rails::MessageModel.create!(
  conversation: conversation,
  content: "How can I help you?",
  role: "assistant",
  usage: {
    input_tokens: 15,
    output_tokens: 20,
    total_tokens: 35
  },
  metadata: {
    model: "gpt-4o",
    response_time: 1.5,
    tool_calls: []
  }
)

# Scopes
MessageModel.by_role("assistant")
MessageModel.with_tool_calls
MessageModel.recent(24.hours)
```

## Background Jobs

### Setup Sidekiq

```ruby
# Gemfile
gem 'sidekiq'

# config/initializers/raaf.rb
RAAF::Rails.configure do |config|
  config.enable_background_jobs = true
end

# config/routes.rb
require 'sidekiq/web'
mount Sidekiq::Web => '/sidekiq'
```

### ConversationJob

```ruby
# Async message processing
ConversationJob.perform_async(
  user_id,
  agent_id,
  message,
  context
)

# Custom job
class CustomAgentJob < ApplicationJob
  def perform(agent_id, task)
    agent = AgentModel.find(agent_id)
    agent.perform_task(task)
  end
end
```

## Analytics & Monitoring

### Built-in Analytics

```ruby
# Access analytics in controller
def analytics
  @stats = {
    total_conversations: current_user.conversations.count,
    total_tokens: current_user.messages.sum("(usage->>'total_tokens')::int"),
    avg_response_time: current_user.messages.average("(metadata->>'response_time')::float"),
    conversations_by_day: current_user.conversations.group_by_day(:created_at).count
  }
end
```

### Custom Metrics

```ruby
# Collect custom metrics
RAAF::Rails.collect_metric(
  :conversation_started,
  agent_id: agent.id,
  user_id: current_user.id,
  value: 1
)

# Query metrics
metrics = RAAF::Rails.metrics_for(:conversation_started, 
  start_date: 1.week.ago,
  end_date: Time.current
)
```

## Deployment

### Environment Variables

```bash
# Required
export OPENAI_API_KEY="sk-..."
export DATABASE_URL="postgresql://..."
export REDIS_URL="redis://..."
export SECRET_KEY_BASE="..."

# Optional RAAF configuration
export RAAF_DASHBOARD_PATH="/admin/agents"
export RAAF_API_PATH="/api/v1"
export RAAF_ENABLE_DASHBOARD="true"
export RAAF_ENABLE_API="true"
export RAAF_ENABLE_WEBSOCKETS="true"
export RAAF_AUTHENTICATION_METHOD="devise"
```

### Docker Support

```dockerfile
FROM ruby:3.2-alpine

RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    nodejs \
    yarn

WORKDIR /app

COPY Gemfile* ./
RUN bundle install --jobs 4

COPY . .

RUN rails assets:precompile

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
```

### Production Considerations

```ruby
# config/environments/production.rb
config.force_ssl = true
config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }

# config/initializers/raaf.rb (production)
RAAF::Rails.configure do |config|
  config.authentication_method = :devise
  config.allowed_origins = ["https://yourdomain.com"]
  config.rate_limit = {
    enabled: true,
    requests_per_minute: 100
  }
  config.websocket_adapter = :redis
end
```

## Advanced Usage

### Custom Controllers

```ruby
class MyAgentsController < RAAF::Rails::Controllers::BaseController
  before_action :set_agent
  
  def chat
    @conversation = @agent.conversations.create!(user: current_user)
    @messages = @conversation.messages.recent(50)
  end
  
  private
  
  def set_agent
    @agent = current_user.agents.find(params[:id])
  end
end
```

### Custom API Endpoints

```ruby
module Api
  module V1
    class CustomAgentsController < RAAF::Rails::Controllers::Api::V1::BaseController
      def analyze
        agent = find_agent(params[:id])
        
        result = agent.process_message(
          params[:text],
          context: { analysis_type: params[:type] }
        )
        
        render json: {
          analysis: result[:content],
          confidence: result[:metadata][:confidence],
          usage: result[:usage]
        }
      end
    end
  end
end
```

### Extending WebSocket Handler

```ruby
class CustomWebsocketHandler < RAAF::Rails::WebsocketHandler
  def handle_custom_event(ws, message)
    case message["event"]
    when "file_upload"
      handle_file_upload(ws, message)
    when "voice_message"
      handle_voice_message(ws, message)
    end
  end
  
  private
  
  def handle_file_upload(ws, message)
    # Process file upload
    file_url = message["file_url"]
    agent_id = message["agent_id"]
    
    # Process with agent
    agent = AgentModel.find(agent_id)
    result = agent.process_file(file_url)
    
    send_message(ws, {
      type: "file_processed",
      result: result
    })
  end
end
```

## Testing

### RSpec Integration

```ruby
# spec/rails_helper.rb
require 'raaf/rails/testing'

RSpec.configure do |config|
  config.include RAAF::Rails::Testing::Helpers
end

# spec/models/agent_spec.rb
RSpec.describe AgentModel, type: :model do
  let(:agent) { create(:agent) }
  
  it "processes messages" do
    result = agent.process_message("Hello")
    expect(result[:content]).to be_present
    expect(result[:usage][:total_tokens]).to be > 0
  end
end
```

### Testing Helpers

```ruby
# Test agent creation
agent = create_test_agent(
  name: "Test Agent",
  model: "gpt-4o-mini"
)

# Test conversations
with_conversation(agent, user) do |conversation|
  response = conversation.add_user_message("Hello")
  expect(response).to include("assistant")
end

# Mock WebSocket connections
mock_websocket do |ws|
  ws.send_message(type: "chat", content: "Hello")
  expect(ws.received_messages.last).to include("response")
end
```

## Troubleshooting

### Common Issues

1. **WebSocket Connection Failed**
   ```ruby
   # Check CORS settings
   config.allowed_origins = ["http://localhost:3000"]
   
   # Ensure Redis is running for ActionCable
   config.websocket_adapter = :redis
   ```

2. **Authentication Errors**
   ```ruby
   # Verify authentication method
   config.authentication_method = :devise
   
   # Check current_user is available
   before_action :authenticate_user!
   ```

3. **Background Jobs Not Processing**
   ```ruby
   # Start Sidekiq worker
   bundle exec sidekiq
   
   # Check Redis connection
   Sidekiq.redis { |r| r.ping }
   ```

### Debug Mode

```ruby
# Enable debug logging
RAAF::Rails.configure do |config|
  config.debug = true
  config.log_level = :debug
end

# Check logs
tail -f log/development.log | grep RAAF
```

## Development

After checking out the repo, run:

```bash
bundle install
bundle exec rake spec
```

To install this gem onto your local machine:

```bash
bundle exec rake install
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/raaf-ai/raaf. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/raaf-ai/raaf/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).