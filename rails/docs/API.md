# RAAF Rails API Documentation

## Overview

The RAAF Rails gem provides comprehensive API documentation for integrating AI agents into Rails applications. This document covers all public APIs, configurations, and extension points.

## Table of Contents

- [Configuration API](#configuration-api)
- [Engine API](#engine-api)
- [Model APIs](#model-apis)
- [Controller APIs](#controller-apis)
- [Helper APIs](#helper-apis)
- [WebSocket API](#websocket-api)
- [Background Job APIs](#background-job-apis)
- [REST API Endpoints](#rest-api-endpoints)

## Configuration API

### RAAF::Rails.configure

Configure the Rails integration with various options.

```ruby
RAAF::Rails.configure do |config|
  # Authentication configuration
  config.authentication_method = :devise # :devise, :doorkeeper, :custom, :none
  config.authentication_handler = ->(request) { User.find_by_token(request.headers["X-API-Key"]) }
  
  # Feature toggles
  config.enable_dashboard = true
  config.enable_api = true
  config.enable_websockets = true
  config.enable_background_jobs = true
  
  # Path configuration
  config.dashboard_path = "/dashboard"
  config.api_path = "/api/v1"
  config.websocket_path = "/chat"
  
  # Security settings
  config.allowed_origins = ["http://localhost:3000", "https://myapp.com"]
  config.rate_limit = {
    enabled: true,
    requests_per_minute: 60,
    requests_per_hour: 1000
  }
  
  # Monitoring configuration
  config.monitoring = {
    enabled: true,
    metrics: [:usage, :performance, :errors],
    export_interval: 300 # seconds
  }
end
```

### Configuration Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `authentication_method` | Symbol | `:none` | Authentication method to use |
| `authentication_handler` | Proc | `nil` | Custom authentication handler |
| `enable_dashboard` | Boolean | `true` | Enable web dashboard |
| `enable_api` | Boolean | `true` | Enable REST API |
| `enable_websockets` | Boolean | `true` | Enable WebSocket support |
| `enable_background_jobs` | Boolean | `true` | Enable background job processing |
| `dashboard_path` | String | `"/dashboard"` | Dashboard mount path |
| `api_path` | String | `"/api/v1"` | API mount path |
| `websocket_path` | String | `"/chat"` | WebSocket mount path |
| `allowed_origins` | Array | `["*"]` | CORS allowed origins |
| `rate_limit` | Hash | See above | Rate limiting configuration |
| `monitoring` | Hash | See above | Monitoring configuration |

## Engine API

### RAAF::Rails::Engine

The Rails engine that provides all RAAF functionality.

```ruby
# Mount in routes.rb
Rails.application.routes.draw do
  mount RAAF::Rails::Engine, at: "/agents"
end

# Access engine configuration
RAAF::Rails::Engine.config

# Access engine routes
RAAF::Rails::Engine.routes
```

### Engine Initializers

The engine provides several initializers:

- `raaf.setup` - Initial setup and configuration
- `raaf.assets` - Asset pipeline configuration
- `raaf.middleware` - Middleware installation
- `raaf.routes` - Route configuration

## Model APIs

### RAAF::Rails::AgentModel

The ActiveRecord model for managing AI agents.

#### Class Methods

```ruby
# Create a new agent
agent = RAAF::Rails::AgentModel.create!(
  name: "Customer Support",
  instructions: "You are a helpful customer support agent",
  model: "gpt-4o",
  user: current_user,
  tools: ["web_search", "knowledge_base"],
  metadata: { department: "support" }
)

# Scopes
RAAF::Rails::AgentModel.deployed              # All deployed agents
RAAF::Rails::AgentModel.draft                 # All draft agents
RAAF::Rails::AgentModel.by_user(user)        # User's agents
RAAF::Rails::AgentModel.with_tool("search")  # Agents with specific tool
RAAF::Rails::AgentModel.active               # Active agents
```

#### Instance Methods

```ruby
# Deployment
agent.deploy!                      # Deploy the agent
agent.undeploy!                   # Undeploy the agent
agent.deployed?                   # Check if deployed

# Message processing
result = agent.process_message("Hello", context: { user: current_user })
# Returns: { content: String, usage: Hash, metadata: Hash }

# Tools management
agent.add_tool(tool_instance)     # Add a tool
agent.remove_tool(tool_name)      # Remove a tool
agent.has_tool?(tool_name)        # Check if has tool

# Handoffs
agent.add_handoff(other_agent)    # Add handoff target
agent.remove_handoff(agent_name)  # Remove handoff
agent.can_handoff_to?(agent)      # Check if can handoff

# Statistics
agent.conversation_count          # Total conversations
agent.message_count              # Total messages
agent.total_tokens_used          # Total tokens consumed
agent.average_response_time      # Average response time
agent.success_rate               # Success percentage
```

### RAAF::Rails::ConversationModel

Manages conversation sessions between users and agents.

#### Class Methods

```ruby
# Create conversation
conversation = RAAF::Rails::ConversationModel.create!(
  agent: agent,
  user: current_user,
  context: { session_id: "abc123" }
)

# Scopes
RAAF::Rails::ConversationModel.active          # Active conversations
RAAF::Rails::ConversationModel.completed       # Completed conversations
RAAF::Rails::ConversationModel.by_agent(agent) # Agent's conversations
RAAF::Rails::ConversationModel.by_user(user)   # User's conversations
RAAF::Rails::ConversationModel.recent(1.day)   # Recent conversations
```

#### Instance Methods

```ruby
# Message management
conversation.add_message(content, role: "user", metadata: {})
conversation.add_user_message(content)
conversation.add_assistant_message(content, usage: {})

# Status
conversation.active?
conversation.completed?
conversation.mark_completed!

# Statistics
conversation.message_count
conversation.total_tokens
conversation.duration
conversation.last_message
```

### RAAF::Rails::MessageModel

Individual messages within conversations.

#### Class Methods

```ruby
# Create message
message = RAAF::Rails::MessageModel.create!(
  conversation: conversation,
  content: "Hello, how can I help?",
  role: "assistant",
  usage: { input_tokens: 10, output_tokens: 15 },
  metadata: { model: "gpt-4o", response_time: 1.2 }
)

# Scopes
RAAF::Rails::MessageModel.by_role("user")
RAAF::Rails::MessageModel.with_tool_calls
RAAF::Rails::MessageModel.recent(1.hour)
RAAF::Rails::MessageModel.with_errors
```

## Controller APIs

### RAAF::Rails::Controllers::BaseController

Base controller for custom agent controllers.

```ruby
class MyAgentsController < RAAF::Rails::Controllers::BaseController
  # Provided methods:
  # - current_user_agents
  # - find_agent(id)
  # - authorize_agent_access(agent)
  # - handle_agent_error(&block)
  
  def custom_action
    @agent = find_agent(params[:id])
    authorize_agent_access(@agent)
    
    handle_agent_error do
      result = @agent.process_message(params[:message])
      render json: result
    end
  end
end
```

### RAAF::Rails::Controllers::DashboardController

Dashboard controller actions.

```ruby
# Available actions:
# GET /dashboard          - index (overview)
# GET /dashboard/agents   - agents (management)
# GET /dashboard/conversations - conversations
# GET /dashboard/analytics - analytics

# Override in your app:
class CustomDashboardController < RAAF::Rails::Controllers::DashboardController
  def index
    super
    @custom_stats = calculate_custom_stats
  end
end
```

## Helper APIs

### RAAF::Rails::Helpers::AgentHelper

View helpers for agent-related UI.

```ruby
# Status display
agent_status_badge(agent)              # Returns styled status badge
agent_status_badge("deployed")         # Returns badge for status

# Response formatting
format_agent_response(response)        # Format agent response for display
format_agent_response({ content: "Hello", metadata: {} })

# Agent information
agent_conversation_path(agent)         # Path to agent chat
agent_deploy_button(agent)            # Deploy/undeploy button
agent_model_options                   # Options for model select

# Tools display
format_agent_tools(agent.tools)       # Format tools list
format_agent_tools(["search", "calc"])

# Metrics
render_agent_metrics(agent)           # Render agent metrics
```

## WebSocket API

### Client-Side API

```javascript
// Initialize connection
const ws = new WebSocket('ws://localhost:3000/agents/chat');

// Connection events
ws.onopen = (event) => {
  console.log('Connected');
};

ws.onclose = (event) => {
  console.log('Disconnected', event.code, event.reason);
};

ws.onerror = (error) => {
  console.error('WebSocket error:', error);
};

// Message handling
ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  
  switch(message.type) {
    case 'connected':
      handleConnected(message);
      break;
    case 'message':
      handleMessage(message);
      break;
    case 'typing':
      handleTyping(message);
      break;
    case 'error':
      handleError(message);
      break;
  }
};

// Send messages
ws.send(JSON.stringify({
  type: 'join_agent',
  agent_id: 'agent_123'
}));

ws.send(JSON.stringify({
  type: 'chat',
  agent_id: 'agent_123',
  content: 'Hello!'
}));

ws.send(JSON.stringify({
  type: 'typing',
  agent_id: 'agent_123',
  typing: true
}));
```

### Message Types

#### Client to Server

| Type | Fields | Description |
|------|--------|-------------|
| `join_agent` | `agent_id` | Join an agent session |
| `leave_agent` | `agent_id` | Leave an agent session |
| `chat` | `agent_id`, `content`, `context?` | Send chat message |
| `typing` | `agent_id`, `typing` | Typing indicator |
| `ping` | - | Keep-alive ping |

#### Server to Client

| Type | Fields | Description |
|------|--------|-------------|
| `connected` | `connection_id`, `timestamp` | Connection established |
| `joined_agent` | `agent_id`, `agent_name` | Joined agent session |
| `message` | `content`, `role`, `usage`, `metadata` | Chat message |
| `typing` | `user_id`, `typing` | Someone is typing |
| `error` | `message`, `code?` | Error occurred |
| `pong` | `timestamp` | Ping response |

### Server-Side Extension

```ruby
class CustomWebsocketHandler < RAAF::Rails::WebsocketHandler
  # Override message handling
  def handle_message(ws, message)
    case message["type"]
    when "custom_event"
      handle_custom_event(ws, message)
    else
      super
    end
  end
  
  private
  
  def handle_custom_event(ws, message)
    # Custom logic
    send_message(ws, {
      type: "custom_response",
      data: process_custom_event(message)
    })
  end
end
```

## Background Job APIs

### ConversationJob

Process conversations asynchronously.

```ruby
# Enqueue job
ConversationJob.perform_async(
  user_id,        # User ID
  agent_id,       # Agent ID
  message,        # Message content
  context         # Additional context
)

# Custom job options
ConversationJob.set(queue: :high_priority).perform_async(...)
ConversationJob.perform_in(5.minutes, ...)
```

### Custom Jobs

```ruby
class AgentMaintenanceJob < ApplicationJob
  queue_as :maintenance
  
  def perform(agent_id)
    agent = RAAF::Rails::AgentModel.find(agent_id)
    
    # Cleanup old conversations
    agent.conversations.older_than(30.days).destroy_all
    
    # Update statistics
    agent.update!(
      last_maintenance_at: Time.current,
      statistics: calculate_statistics(agent)
    )
  end
  
  private
  
  def calculate_statistics(agent)
    {
      total_conversations: agent.conversations.count,
      total_messages: agent.messages.count,
      average_response_time: agent.messages.average_response_time
    }
  end
end
```

## REST API Endpoints

### Authentication

All API endpoints require authentication based on your configuration.

```bash
# Bearer token
curl -H "Authorization: Bearer YOUR_TOKEN" ...

# API key
curl -H "X-API-Key: YOUR_API_KEY" ...
```

### Agents

#### List Agents
```http
GET /api/v1/agents
```

Response:
```json
{
  "agents": [
    {
      "id": "agent_123",
      "name": "Customer Support",
      "model": "gpt-4o",
      "status": "deployed",
      "created_at": "2024-01-01T00:00:00Z"
    }
  ],
  "meta": {
    "total": 10,
    "page": 1,
    "per_page": 20
  }
}
```

#### Create Agent
```http
POST /api/v1/agents
Content-Type: application/json

{
  "name": "Sales Assistant",
  "instructions": "You help with sales",
  "model": "gpt-4o",
  "tools": ["product_search"],
  "metadata": {
    "department": "sales"
  }
}
```

#### Get Agent
```http
GET /api/v1/agents/:id
```

#### Update Agent
```http
PUT /api/v1/agents/:id
Content-Type: application/json

{
  "instructions": "Updated instructions",
  "tools": ["product_search", "pricing"]
}
```

#### Delete Agent
```http
DELETE /api/v1/agents/:id
```

#### Deploy Agent
```http
POST /api/v1/agents/:id/deploy
```

#### Undeploy Agent
```http
POST /api/v1/agents/:id/undeploy
```

### Conversations

#### List Conversations
```http
GET /api/v1/agents/:agent_id/conversations
```

#### Create Conversation
```http
POST /api/v1/agents/:agent_id/conversations
Content-Type: application/json

{
  "message": "Hello!",
  "context": {
    "session_id": "abc123"
  }
}
```

Response:
```json
{
  "conversation_id": "conv_456",
  "message": "Hello! How can I help you today?",
  "usage": {
    "input_tokens": 10,
    "output_tokens": 15,
    "total_tokens": 25
  },
  "metadata": {
    "model": "gpt-4o",
    "response_time": 1.2
  }
}
```

#### Get Conversation
```http
GET /api/v1/conversations/:id
```

#### Continue Conversation
```http
POST /api/v1/conversations/:id/messages
Content-Type: application/json

{
  "message": "Tell me more"
}
```

### Analytics

#### Agent Analytics
```http
GET /api/v1/agents/:id/analytics?period=7d
```

Response:
```json
{
  "conversations_count": 150,
  "messages_count": 1200,
  "total_tokens": 45000,
  "average_response_time": 1.5,
  "success_rate": 98.5,
  "conversations_by_day": {
    "2024-01-01": 20,
    "2024-01-02": 25
  }
}
```

#### Global Analytics
```http
GET /api/v1/analytics?period=30d
```

### Error Responses

All endpoints return consistent error responses:

```json
{
  "error": {
    "code": "agent_not_found",
    "message": "The requested agent was not found",
    "details": {
      "agent_id": "invalid_123"
    }
  }
}
```

Common error codes:
- `authentication_required`
- `unauthorized`
- `agent_not_found`
- `validation_failed`
- `rate_limit_exceeded`
- `internal_server_error`

## Rate Limiting

API requests are rate limited based on configuration:

```http
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1704067200
```

When rate limited:
```http
HTTP/1.1 429 Too Many Requests
Retry-After: 60
```

## Webhooks

Configure webhooks for agent events:

```ruby
RAAF::Rails.configure do |config|
  config.webhooks = {
    enabled: true,
    endpoints: {
      conversation_started: "https://myapp.com/webhooks/conversation_started",
      conversation_completed: "https://myapp.com/webhooks/conversation_completed",
      agent_deployed: "https://myapp.com/webhooks/agent_deployed"
    },
    secret: "webhook_secret"
  }
end
```

Webhook payload:
```json
{
  "event": "conversation_started",
  "timestamp": "2024-01-01T00:00:00Z",
  "data": {
    "conversation_id": "conv_123",
    "agent_id": "agent_456",
    "user_id": "user_789"
  }
}
```

Verify webhook signature:
```ruby
signature = request.headers["X-RAAF-Signature"]
payload = request.raw_body
expected = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, payload)

if Rack::Utils.secure_compare(signature, expected)
  # Process webhook
end
```