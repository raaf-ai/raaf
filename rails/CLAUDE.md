# RAAF Rails - Claude Code Guide

This gem provides Rails integration for RAAF with a comprehensive tracing dashboard and monitoring tools.

## Quick Start

```ruby
# Gemfile
gem 'raaf-rails'

# Mount routes in config/routes.rb
Rails.application.routes.draw do
  mount RAAF::Rails::Engine => "/raaf"
end
```

## Dashboard Access

Navigate to `/raaf/dashboard` in your Rails app to view:
- Agent execution traces
- Performance metrics
- Cost tracking
- Error monitoring
- Timeline visualization

## Controller Integration

```ruby
class ChatController < ApplicationController
  include RAAF::Logger
  
  def create
    # Create agent with Rails tracing
    agent = RAAF::Agent.new(
      name: "ChatBot",
      instructions: "You are a helpful chatbot",
      model: "gpt-4o"
    )
    
    # Set up tracing
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(RAAF::Tracing::ActiveRecordProcessor.new)
    
    runner = RAAF::Runner.new(agent: agent, tracer: tracer)
    
    # Log the interaction
    log_info("Processing chat", user_id: current_user.id)
    
    result = runner.run(params[:message])
    
    render json: {
      response: result.messages.last[:content],
      usage: result.usage
    }
  rescue => e
    log_error("Chat failed", error: e, user_id: current_user.id)
    render json: { error: "Something went wrong" }, status: 500
  end
end
```

## Model Integration

```ruby
class Agent < ApplicationRecord
  include RAAF::Logger
  
  def execute_task(message)
    agent = RAAF::Agent.new(
      name: self.name,
      instructions: self.instructions,
      model: self.model_name
    )
    
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(RAAF::Tracing::ActiveRecordProcessor.new)
    
    runner = RAAF::Runner.new(agent: agent, tracer: tracer)
    
    log_info("Executing task", agent_id: self.id, task: message)
    
    result = runner.run(message)
    
    # Store result in database
    self.executions.create!(
      input: message,
      output: result.messages.last[:content],
      usage_data: result.usage,
      trace_id: result.trace_id
    )
    
    result
  end
end
```

## WebSocket Integration

```ruby
# app/channels/agent_channel.rb
class AgentChannel < ApplicationCable::Channel
  def subscribed
    stream_from "agent_#{params[:agent_id]}"
  end
  
  def execute(data)
    agent = RAAF::Agent.new(
      name: "StreamingAgent",
      instructions: "Respond in real-time",
      model: "gpt-4o"
    )
    
    runner = RAAF::Runner.new(agent: agent)
    
    # Stream response back to client
    runner.run(data['message']) do |chunk|
      ActionCable.server.broadcast(
        "agent_#{params[:agent_id]}",
        { type: 'chunk', content: chunk }
      )
    end
  end
end
```

## Dashboard Components

### Traces View
- Real-time trace visualization
- Span hierarchy display
- Performance metrics
- Error highlighting

### Cost Tracking
- Token usage by model
- Cost breakdown by agent
- Monthly spending trends
- Budget alerts

### Analytics
- Agent performance metrics
- Response time analysis
- Error rate tracking
- Usage patterns

## Configuration

```ruby
# config/initializers/raaf.rb
RAAF::Rails.configure do |config|
  config.dashboard_path = "/admin/raaf"
  config.require_authentication = true
  config.store_traces_in_db = true
  config.trace_retention_days = 30
end
```

## Authentication

```ruby
# Protect dashboard with authentication
RAAF::Rails::Engine.routes.draw do
  authenticate :admin_user do
    resources :traces, :spans, :dashboard
  end
end
```

## Environment Variables

```bash
export RAAF_DASHBOARD_ENABLED="true"
export RAAF_STORE_TRACES="true"
export RAAF_RETENTION_DAYS="30"
```