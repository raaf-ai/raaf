# RAAF Rails

[![Gem Version](https://badge.fury.io/rb/raaf-rails.svg)](https://badge.fury.io/rb/raaf-rails)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Rails** gem provides comprehensive Rails integration for the Ruby AI Agents Factory (RAAF) ecosystem. It offers Rails engine functionality, web dashboard, API endpoints, generators, and seamless integration with Rails applications.

## Overview

RAAF (Ruby AI Agents Factory) Rails extends the core Rails capabilities from `raaf-core` to provide Rails integration and web interface for Ruby AI Agents Factory (RAAF). This gem provides comprehensive Rails integration including web-based dashboard, REST API, real-time conversations, and deployment tools.

## Features

- **Web Dashboard** - Complete web interface for managing AI agents
- **REST API** - RESTful API for agent interactions and management
- **Real-time Chat** - WebSocket-based real-time conversations
- **Authentication** - Support for Devise, Doorkeeper, and custom auth
- **Background Jobs** - Sidekiq integration for async processing
- **Monitoring** - Built-in analytics and performance monitoring
- **Deployment Tools** - Easy deployment and scaling utilities

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-rails'
```

And then execute:

```bash
bundle install
```

## Quick Start

### 1. Mount the Engine

In your Rails application's `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  mount RubyAIAgentsFactory::Rails::Engine, at: "/agents"
end
```

### 2. Configure the Integration

Create `config/initializers/raaf.rb`:

```ruby
RubyAIAgentsFactory::Rails.configure do |config|
  config.authentication_method = :devise
  config.enable_dashboard = true
  config.enable_api = true
  config.enable_websockets = true
  config.dashboard_path = "/agents"
  config.api_path = "/api/v1"
end
```

### 3. Generate Migrations

```bash
rails generate raaf:install
rails db:migrate
```

### 4. Start Using

Visit `http://localhost:3000/agents` to access the dashboard.

## Configuration

### Authentication Methods

#### Devise Integration

```ruby
# config/initializers/raaf.rb
RubyAIAgentsFactory::Rails.configure do |config|
  config.authentication_method = :devise
end
```

#### Custom Authentication

```ruby
# config/initializers/raaf.rb
RubyAIAgentsFactory::Rails.configure do |config|
  config.authentication_method = :custom
  config.authentication_handler = ->(request) {
    # Your custom authentication logic
    User.find_by(api_key: request.headers["X-API-Key"])
  }
end
```

### Dashboard Configuration

```ruby
RubyAIAgentsFactory::Rails.configure do |config|
  config.enable_dashboard = true
  config.dashboard_path = "/admin/agents"
  config.dashboard_title = "AI Agents Dashboard"
  config.dashboard_theme = "dark"
end
```

### API Configuration

```ruby
RubyAIAgentsFactory::Rails.configure do |config|
  config.enable_api = true
  config.api_path = "/api/v1"
  config.api_version = "v1"
  config.rate_limit = {
    enabled: true,
    requests_per_minute: 60
  }
end
```

### WebSocket Configuration

```ruby
RubyAIAgentsFactory::Rails.configure do |config|
  config.enable_websockets = true
  config.websocket_path = "/chat"
  config.websocket_origins = ["http://localhost:3000"]
end
```

## Usage

### Creating Agents

#### Via Dashboard

1. Navigate to `/agents/dashboard`
2. Click "New Agent"
3. Fill in agent details (name, instructions, model)
4. Click "Create Agent"

#### Via API

```bash
curl -X POST http://localhost:3000/api/v1/agents \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "name": "Customer Support Agent",
    "instructions": "You are a helpful customer support agent",
    "model": "gpt-4o",
    "tools": ["web_search", "knowledge_base"]
  }'
```

#### Via Rails Console

```ruby
agent = RubyAIAgentsFactory::Rails.create_agent(
  name: "Assistant",
  instructions: "You are a helpful assistant",
  model: "gpt-4o",
  user: current_user
)
```

### Starting Conversations

#### Via API

```bash
curl -X POST http://localhost:3000/api/v1/agents/123/conversations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "message": "Hello, how can you help me?",
    "context": {
      "user_id": 456,
      "session_id": "abc123"
    }
  }'
```

#### Via WebSocket

```javascript
const ws = new WebSocket('ws://localhost:3000/agents/chat');

ws.onopen = function() {
  // Join agent session
  ws.send(JSON.stringify({
    type: 'join_agent',
    agent_id: 'agent_123'
  }));
};

ws.onmessage = function(event) {
  const data = JSON.parse(event.data);
  console.log('Received:', data);
};

// Send message
ws.send(JSON.stringify({
  type: 'chat',
  agent_id: 'agent_123',
  content: 'Hello, assistant!'
}));
```

#### Via Rails Code

```ruby
result = RubyAIAgentsFactory::Rails.start_conversation(
  agent_id: "agent_123",
  message: "Hello!",
  context: { user: current_user }
)

puts result[:message]
```

### Background Jobs

#### Setup Sidekiq

```ruby
# config/initializers/raaf.rb
RubyAIAgentsFactory::Rails.configure do |config|
  config.enable_background_jobs = true
end
```

#### Process Messages Asynchronously

```ruby
# In a controller
def create
  ConversationJob.perform_async(
    current_user.id,
    params[:agent_id],
    params[:message],
    params[:context] || {}
  )
  
  render json: { status: "processing" }
end
```

## Models

### Agent Model

```ruby
agent = RubyAIAgentsFactory::Rails::AgentModel.create!(
  name: "Customer Support",
  instructions: "You are a helpful customer support agent",
  model: "gpt-4o",
  user: current_user,
  tools: ["web_search", "knowledge_base"],
  metadata: {
    department: "support",
    language: "en"
  }
)

# Instance methods
agent.process_message("Hello")
agent.deploy!
agent.undeploy!
agent.conversation_count
agent.total_tokens_used
```

### Conversation Model

```ruby
conversation = RubyAIAgentsFactory::Rails::ConversationModel.create!(
  agent: agent,
  user: current_user,
  context: { session_id: "abc123" }
)

# Add messages
conversation.add_message("Hello", role: "user")
conversation.add_message("Hi there!", role: "assistant")

# Query messages
conversation.messages.count
conversation.messages.by_role("user")
conversation.total_tokens
```

### Message Model

```ruby
message = RubyAIAgentsFactory::Rails::MessageModel.create!(
  conversation: conversation,
  content: "Hello, world!",
  role: "user",
  usage: {
    input_tokens: 10,
    output_tokens: 8,
    total_tokens: 18
  },
  metadata: {
    response_time: 1.25,
    model: "gpt-4o"
  }
)
```

## Controllers

### Custom Controllers

```ruby
class MyAgentsController < RubyAIAgentsFactory::Rails::Controllers::BaseController
  def index
    @agents = current_user.agents
  end

  def chat
    @agent = find_agent(params[:id])
    @conversation = @agent.conversations.create!(user: current_user)
  end
end
```

### API Controllers

```ruby
class Api::V1::MyAgentsController < RubyAIAgentsFactory::Rails::Controllers::Api::V1::BaseController
  def chat
    agent = find_agent(params[:id])
    result = agent.process_message(
      params[:message],
      context: params[:context]
    )
    
    render json: result
  end
end
```

## Helpers

### Agent Helper

```erb
<%= agent_status_badge(@agent) %>
<%= agent_conversation_count(@agent) %>
<%= agent_last_activity(@agent) %>
<%= format_usage(@message.usage) %>
<%= format_response_time(@message.metadata["response_time"]) %>
```

### In Controllers

```ruby
class AgentsController < ApplicationController
  include RubyAIAgentsFactory::Rails::Helpers::AgentHelper

  def show
    @agent = find_agent(params[:id])
    @status = agent_status(@agent)
    @metrics = agent_metrics(@agent)
  end
end
```

## Monitoring and Analytics

### Built-in Dashboard

Visit `/agents/dashboard/analytics` to view:
- Conversation volume over time
- Token usage statistics
- Response time metrics
- Popular agents
- Error rates

### Custom Analytics

```ruby
# In a controller
def analytics
  @analytics = {
    conversations_count: current_user.conversations.count,
    total_tokens: current_user.total_tokens_used,
    avg_response_time: current_user.average_response_time,
    top_agents: current_user.agents.by_usage.limit(10)
  }
end
```

### Metrics Collection

```ruby
# Custom metrics
RubyAIAgentsFactory::Rails.collect_metric(
  :conversation_started,
  agent_id: agent.id,
  user_id: current_user.id
)

RubyAIAgentsFactory::Rails.collect_metric(
  :token_usage,
  value: usage[:total_tokens],
  agent_id: agent.id
)
```

## Deployment

### Environment Variables

```bash
# Database
export DATABASE_URL="postgres://user:pass@localhost/db"

# Redis (for Sidekiq and WebSockets)
export REDIS_URL="redis://localhost:6379"

# OpenAI API
export OPENAI_API_KEY="your-api-key"

# Rails configuration
export RAILS_ENV="production"
export SECRET_KEY_BASE="your-secret-key"

# RAAF configuration
export RAAF_DASHBOARD_PATH="/admin/agents"
export RAAF_API_PATH="/api/v1"
export RAAF_WEBSOCKET_ORIGINS="https://yourdomain.com"
```

### Docker Deployment

```dockerfile
FROM ruby:3.2

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
```

### Scaling

```ruby
# config/initializers/raaf.rb
RubyAIAgentsFactory::Rails.configure do |config|
  # Use Redis for shared state in multi-server deployments
  config.websocket_adapter = :redis
  config.cache_store = :redis_cache_store
  config.session_store = :redis_session_store
end
```

## Development

### Setup

```bash
git clone https://github.com/raaf-ai/ruby-ai-agents-factory
cd ruby-ai-agents-factory/gems/raaf-rails
bundle install
```

### Running Tests

```bash
bundle exec rspec
```

### Running Example App

```bash
cd spec/dummy
rails server
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for your changes
5. Ensure all tests pass (`bundle exec rspec`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).