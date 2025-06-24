# Deployment Guide

Complete guide for deploying OpenAI Agents Ruby applications to production.

## Table of Contents

1. [Production Checklist](#production-checklist)
2. [Environment Setup](#environment-setup)
3. [Configuration](#configuration)
4. [Docker Deployment](#docker-deployment)
5. [Cloud Platforms](#cloud-platforms)
6. [Monitoring & Observability](#monitoring--observability)
7. [Security Considerations](#security-considerations)
8. [Performance Optimization](#performance-optimization)
9. [Troubleshooting](#troubleshooting)

## Production Checklist

Before deploying to production, ensure:

- [ ] API keys are securely managed
- [ ] Guardrails are properly configured
- [ ] Rate limiting is enabled
- [ ] Usage tracking is set up
- [ ] Tracing is configured
- [ ] Error handling is comprehensive
- [ ] Health checks are implemented
- [ ] Monitoring and alerting are in place
- [ ] Backup and recovery plans exist
- [ ] Security best practices are followed

## Environment Setup

### Required Environment Variables

```bash
# API Keys (Required)
export OPENAI_API_KEY="sk-proj-..."
export ANTHROPIC_API_KEY="sk-ant-..."  # If using Anthropic
export GEMINI_API_KEY="..."           # If using Google Gemini

# Application Configuration
export RAILS_ENV="production"          # Or your framework
export OPENAI_AGENTS_ENVIRONMENT="production"
export OPENAI_AGENTS_LOG_LEVEL="info"

# Security
export SECRET_KEY_BASE="..."           # Rails applications
export ENCRYPTION_KEY="..."            # For sensitive data

# Database (if applicable)
export DATABASE_URL="postgres://..."

# Redis (for caching/sessions)
export REDIS_URL="redis://..."
```

### Optional Configuration

```bash
# Tracing
export OPENAI_AGENTS_TRACE_BATCH_SIZE="100"
export OPENAI_AGENTS_TRACE_FLUSH_INTERVAL="5"

# Performance
export RUBY_GC_HEAP_GROWTH_FACTOR="1.1"
export RUBY_GC_HEAP_GROWTH_MAX_SLOTS="100000"

# Monitoring
export DATADOG_API_KEY="..."          # If using Datadog
export NEW_RELIC_LICENSE_KEY="..."    # If using New Relic
```

## Configuration

### Production Configuration File

Create `config/openai_agents.production.yml`:

```yaml
environment: production

# API Configuration
openai:
  api_key: <%= ENV['OPENAI_API_KEY'] %>
  timeout: 30
  max_retries: 3
  api_base: <%= ENV['OPENAI_API_BASE'] || 'https://api.openai.com/v1' %>

anthropic:
  api_key: <%= ENV['ANTHROPIC_API_KEY'] %>
  timeout: 30

# Agent Defaults
agent:
  default_model: "gpt-4o"
  max_turns: 20
  timeout: 120

# Guardrails
guardrails:
  content_safety:
    enabled: true
    strict_mode: true
  rate_limiting:
    enabled: true
    max_requests_per_minute: 300
    max_requests_per_hour: 10000
  length_validation:
    enabled: true
    max_input_length: 50000
    max_output_length: 10000

# Tracing
tracing:
  enabled: true
  include_sensitive_data: false
  processors: ["openai", "file"]
  batch_size: 100
  flush_interval: 5
  export_format: "json"
  file_path: "/var/log/openai_agents_traces.jsonl"

# Logging
logging:
  level: "info"
  output: "file"
  file: "/var/log/openai_agents.log"
  format: "json"
  sanitize_logs: true

# Usage Tracking
usage_tracking:
  enabled: true
  retention_days: 90
  export_enabled: true
  alerts:
    cost_threshold_daily: 1000.0
    error_rate_threshold: 0.05

# Caching
cache:
  enabled: true
  ttl: 3600
  storage: "redis"
  redis_url: <%= ENV['REDIS_URL'] %>
```

### Application Configuration

```ruby
# config/initializers/openai_agents.rb (Rails)
# Or equivalent initialization file

require 'openai_agents'

# Load production configuration
config = OpenAIAgents::Configuration.new(environment: Rails.env)

# Set up comprehensive monitoring
tracker = OpenAIAgents::UsageTracking::UsageTracker.new

# Production alerts
tracker.add_alert(:high_cost) do |usage|
  usage[:total_cost_today] > 1000.0
end

tracker.add_alert(:error_rate) do |usage|
  usage[:error_rate] > 0.05
end

tracker.add_alert(:rate_limit) do |usage|
  usage[:rate_limit_hits] > 10
end

# Production tracer
tracer = OpenAIAgents::Tracing::SpanTracer.new
tracer.add_processor(OpenAIAgents::Tracing::OpenAIProcessor.new)
tracer.add_processor(OpenAIAgents::Tracing::FileSpanProcessor.new(
  "/var/log/openai_agents_traces.jsonl"
))

# Guardrails
guardrails = OpenAIAgents::Guardrails::GuardrailManager.new
guardrails.add_guardrail(OpenAIAgents::Guardrails::ContentSafetyGuardrail.new)
guardrails.add_guardrail(OpenAIAgents::Guardrails::RateLimitGuardrail.new(
  max_requests_per_minute: 300
))
guardrails.add_guardrail(OpenAIAgents::Guardrails::LengthGuardrail.new(
  max_input_length: 50000,
  max_output_length: 10000
))

# Make components globally available
OpenAIAgents.configure do |config|
  config.tracker = tracker
  config.tracer = tracer
  config.guardrails = guardrails
end
```

## Docker Deployment

### Dockerfile

```dockerfile
FROM ruby:3.2-alpine

# Install system dependencies
RUN apk add --no-cache \
    build-base \
    git \
    postgresql-dev \
    redis

# Set working directory
WORKDIR /app

# Copy dependency files
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle config --global frozen 1 && \
    bundle install --without development test

# Copy application code
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S appuser && \
    adduser -u 1001 -S appuser -G appuser

# Create necessary directories
RUN mkdir -p /var/log && \
    chown -R appuser:appuser /app /var/log

# Switch to non-root user
USER appuser

# Set environment
ENV RAILS_ENV=production
ENV OPENAI_AGENTS_ENVIRONMENT=production
ENV OPENAI_AGENTS_LOG_LEVEL=info

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Expose port
EXPOSE 3000

# Start command
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
```

### Docker Compose

```yaml
# docker-compose.yml
version: '3.8'

services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - RAILS_ENV=production
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - DATABASE_URL=postgres://postgres:password@db:5432/myapp_production
      - REDIS_URL=redis://redis:6379/0
    depends_on:
      - db
      - redis
    volumes:
      - ./logs:/var/log
    restart: unless-stopped

  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=myapp_production
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
    depends_on:
      - app
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
```

### Nginx Configuration

```nginx
# nginx.conf
events {
    worker_connections 1024;
}

http {
    upstream app {
        server app:3000;
    }

    server {
        listen 80;
        server_name your-domain.com;
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name your-domain.com;

        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;

        # Security headers
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";

        # Proxy settings
        location / {
            proxy_pass http://app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Timeouts for long-running AI requests
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 120s;
        }

        # Health check endpoint
        location /health {
            proxy_pass http://app/health;
            access_log off;
        }
    }
}
```

## Cloud Platforms

### AWS Deployment

#### Using ECS Fargate

```yaml
# ecs-task-definition.json
{
  "family": "openai-agents-app",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "app",
      "image": "your-ecr-repo/openai-agents-app:latest",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "RAILS_ENV",
          "value": "production"
        }
      ],
      "secrets": [
        {
          "name": "OPENAI_API_KEY",
          "valueFrom": "arn:aws:secretsmanager:region:account:secret:openai-api-key"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/openai-agents-app",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

#### CloudFormation Template

```yaml
# cloudformation.yml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'OpenAI Agents Ruby Application'

Parameters:
  OpenAIAPIKey:
    Type: String
    NoEcho: true
    Description: OpenAI API Key

Resources:
  # VPC and networking (simplified)
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.0.0.0/16
      EnableDnsHostnames: true
      EnableDnsSupport: true

  # ECS Cluster
  ECSCluster:
    Type: AWS::ECS::Cluster
    Properties:
      ClusterName: openai-agents-cluster

  # Application Load Balancer
  ALB:
    Type: AWS::ElasticLoadBalancingV2::LoadBalancer
    Properties:
      Type: application
      Scheme: internet-facing
      SecurityGroups: [!Ref ALBSecurityGroup]
      Subnets: [!Ref PublicSubnet1, !Ref PublicSubnet2]

  # ECS Service
  ECSService:
    Type: AWS::ECS::Service
    Properties:
      Cluster: !Ref ECSCluster
      TaskDefinition: !Ref ECSTaskDefinition
      DesiredCount: 2
      LaunchType: FARGATE
      NetworkConfiguration:
        AwsvpcConfiguration:
          SecurityGroups: [!Ref AppSecurityGroup]
          Subnets: [!Ref PrivateSubnet1, !Ref PrivateSubnet2]
          AssignPublicIp: ENABLED
```

### Google Cloud Platform

#### Cloud Run Deployment

```yaml
# cloudrun.yml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: openai-agents-app
  annotations:
    run.googleapis.com/ingress: all
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/maxScale: "10"
        run.googleapis.com/cpu-throttling: "false"
        run.googleapis.com/memory: "2Gi"
        run.googleapis.com/cpu: "1000m"
    spec:
      containerConcurrency: 1000
      timeoutSeconds: 300
      containers:
      - image: gcr.io/PROJECT-ID/openai-agents-app:latest
        ports:
        - containerPort: 3000
        env:
        - name: RAILS_ENV
          value: "production"
        - name: OPENAI_API_KEY
          valueFrom:
            secretKeyRef:
              name: openai-api-key
              key: key
        resources:
          limits:
            cpu: "1000m"
            memory: "2Gi"
```

### Heroku Deployment

```bash
# Create Heroku app
heroku create your-app-name

# Set environment variables
heroku config:set OPENAI_API_KEY=your-key
heroku config:set RAILS_ENV=production
heroku config:set OPENAI_AGENTS_ENVIRONMENT=production

# Add Redis addon
heroku addons:create heroku-redis:mini

# Deploy
git push heroku main

# Scale dynos
heroku ps:scale web=2
```

## Monitoring & Observability

### Health Checks

```ruby
# app/controllers/health_controller.rb (Rails)
class HealthController < ApplicationController
  def show
    health_status = {
      status: "healthy",
      timestamp: Time.current.iso8601,
      version: Rails.application.config.version,
      checks: {}
    }

    # Check database connection
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      health_status[:checks][:database] = "healthy"
    rescue => e
      health_status[:checks][:database] = "unhealthy"
      health_status[:status] = "unhealthy"
    end

    # Check Redis connection
    begin
      Redis.current.ping
      health_status[:checks][:redis] = "healthy"
    rescue => e
      health_status[:checks][:redis] = "unhealthy"
      health_status[:status] = "unhealthy"
    end

    # Check OpenAI API
    begin
      # Simple API test
      health_status[:checks][:openai] = "healthy"
    rescue => e
      health_status[:checks][:openai] = "unhealthy"
      health_status[:status] = "degraded"  # Not critical
    end

    status_code = health_status[:status] == "healthy" ? 200 : 503
    render json: health_status, status: status_code
  end
end
```

### Metrics Collection

```ruby
# config/initializers/metrics.rb
require 'prometheus/client'

# Create metrics registry
METRICS = Prometheus::Client.registry

# Agent execution metrics
AGENT_REQUESTS = Prometheus::Client::Counter.new(
  :agent_requests_total,
  docstring: 'Total number of agent requests',
  labels: [:agent_name, :status]
)

AGENT_DURATION = Prometheus::Client::Histogram.new(
  :agent_request_duration_seconds,
  docstring: 'Agent request duration',
  labels: [:agent_name]
)

TOKEN_USAGE = Prometheus::Client::Counter.new(
  :tokens_used_total,
  docstring: 'Total tokens used',
  labels: [:provider, :model]
)

API_COST = Prometheus::Client::Counter.new(
  :api_cost_total,
  docstring: 'Total API costs',
  labels: [:provider, :model]
)

# Register metrics
METRICS.register(AGENT_REQUESTS)
METRICS.register(AGENT_DURATION)
METRICS.register(TOKEN_USAGE)
METRICS.register(API_COST)

# Instrument runner
class InstrumentedRunner < OpenAIAgents::Runner
  def run(messages, **kwargs)
    start_time = Time.current
    
    begin
      result = super
      AGENT_REQUESTS.increment(
        labels: { agent_name: @agent.name, status: 'success' }
      )
      result
    rescue => e
      AGENT_REQUESTS.increment(
        labels: { agent_name: @agent.name, status: 'error' }
      )
      raise
    ensure
      duration = Time.current - start_time
      AGENT_DURATION.observe(
        duration,
        labels: { agent_name: @agent.name }
      )
    end
  end
end
```

### Logging

```ruby
# config/initializers/logging.rb
require 'logger'

# Structured JSON logging
class JSONLogger < Logger
  def format_message(severity, timestamp, progname, msg)
    log_entry = {
      timestamp: timestamp.iso8601,
      level: severity,
      message: msg.is_a?(String) ? msg : msg.inspect,
      service: "openai-agents",
      environment: Rails.env
    }
    
    # Add request context if available
    if defined?(Current) && Current.request_id
      log_entry[:request_id] = Current.request_id
    end
    
    JSON.generate(log_entry) + "\n"
  end
end

# Configure Rails logger
Rails.logger = JSONLogger.new(STDOUT)
Rails.logger.level = Logger::INFO

# Log agent interactions
class LoggingRunner < OpenAIAgents::Runner
  def run(messages, **kwargs)
    Rails.logger.info("Agent execution started", {
      agent_name: @agent.name,
      message_count: messages.length,
      user_message: messages.last&.dig(:content)&.truncate(100)
    })
    
    result = super
    
    Rails.logger.info("Agent execution completed", {
      agent_name: @agent.name,
      turns: result.turns,
      final_agent: result.last_agent.name,
      tokens_used: result.usage&.dig(:total_tokens)
    })
    
    result
  rescue => e
    Rails.logger.error("Agent execution failed", {
      agent_name: @agent.name,
      error: e.class.name,
      message: e.message
    })
    raise
  end
end
```

## Security Considerations

### API Key Management

```ruby
# Use Rails credentials or environment variables
credentials = Rails.application.credentials

config = OpenAIAgents::Configuration.new
config.set("openai.api_key", credentials.openai_api_key)

# Rotate keys regularly
class APIKeyRotator
  def self.rotate_openai_key
    old_key = Rails.application.credentials.openai_api_key
    new_key = generate_new_key  # Implement key generation
    
    # Update configuration
    update_credentials(openai_api_key: new_key)
    
    # Graceful transition
    sleep(60)  # Allow pending requests to complete
    
    # Verify new key works
    test_api_key(new_key)
    
    # Revoke old key
    revoke_api_key(old_key)
  end
end
```

### Input Sanitization

```ruby
# Enhanced guardrails for production
class ProductionGuardrails
  def self.create
    manager = OpenAIAgents::Guardrails::GuardrailManager.new
    
    # Content safety with strict filtering
    manager.add_guardrail(
      OpenAIAgents::Guardrails::ContentSafetyGuardrail.new(
        strict_mode: true,
        block_categories: [:hate, :violence, :self_harm, :sexual]
      )
    )
    
    # Input length limits
    manager.add_guardrail(
      OpenAIAgents::Guardrails::LengthGuardrail.new(
        max_input_length: 50000,
        max_output_length: 10000
      )
    )
    
    # Rate limiting with IP tracking
    manager.add_guardrail(
      OpenAIAgents::Guardrails::RateLimitGuardrail.new(
        max_requests_per_minute: 300,
        track_by_ip: true
      )
    )
    
    # Custom business logic validation
    manager.add_guardrail(BusinessRuleGuardrail.new)
    
    manager
  end
end

class BusinessRuleGuardrail < OpenAIAgents::Guardrails::BaseGuardrail
  def validate_input(input)
    # Check for PII
    if contains_pii?(input)
      raise OpenAIAgents::Guardrails::GuardrailError, "Input contains PII"
    end
    
    # Check for malicious patterns
    if contains_injection_patterns?(input)
      raise OpenAIAgents::Guardrails::GuardrailError, "Potential injection detected"
    end
  end
  
  private
  
  def contains_pii?(input)
    # Implement PII detection
    input.match?(/\b\d{3}-\d{2}-\d{4}\b/) || # SSN
    input.match?(/\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/) # Credit card
  end
  
  def contains_injection_patterns?(input)
    # Check for common injection patterns
    dangerous_patterns = [
      /ignore\s+previous\s+instructions/i,
      /system\s*:\s*you\s+are/i,
      /\/\*.*\*\//m
    ]
    
    dangerous_patterns.any? { |pattern| input.match?(pattern) }
  end
end
```

## Performance Optimization

### Connection Pooling

```ruby
# config/initializers/openai_agents.rb
require 'connection_pool'

# Create connection pool for OpenAI API
OPENAI_POOL = ConnectionPool.new(size: 10, timeout: 5) do
  OpenAIAgents::Models::ResponsesProvider.new(
    api_key: Rails.application.credentials.openai_api_key
  )
end

# Use pooled connections
class PooledRunner < OpenAIAgents::Runner
  def initialize(agent:, **kwargs)
    super(agent: agent, provider: nil, **kwargs)
  end
  
  private
  
  def provider
    OPENAI_POOL.with { |provider| provider }
  end
end
```

### Caching

```ruby
# Cache agent responses for identical inputs
class CachedRunner < OpenAIAgents::Runner
  def run(messages, **kwargs)
    cache_key = generate_cache_key(messages, @agent.name)
    
    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      super(messages, **kwargs)
    end
  end
  
  private
  
  def generate_cache_key(messages, agent_name)
    content = messages.map { |m| m[:content] }.join("|")
    "agent_response:#{agent_name}:#{Digest::SHA256.hexdigest(content)}"
  end
end
```

### Async Processing

```ruby
# Use background jobs for long-running operations
class AgentJob < ApplicationJob
  queue_as :agents
  
  def perform(agent_config, messages, user_id)
    agent = create_agent(agent_config)
    runner = OpenAIAgents::Runner.new(agent: agent)
    
    result = runner.run(messages)
    
    # Notify user of completion
    ActionCable.server.broadcast(
      "user_#{user_id}",
      {
        type: "agent_response",
        result: result.to_h
      }
    )
  rescue => e
    # Handle errors gracefully
    Rails.logger.error("Agent job failed", {
      user_id: user_id,
      error: e.message
    })
    
    ActionCable.server.broadcast(
      "user_#{user_id}",
      {
        type: "agent_error",
        error: "Something went wrong. Please try again."
      }
    )
  end
end
```

## Troubleshooting

### Common Issues

#### High API Costs
```ruby
# Monitor and alert on costs
tracker.add_alert(:cost_spike) do |usage|
  current_hour_cost = usage[:cost_current_hour]
  average_hour_cost = usage[:cost_average_hour]
  
  current_hour_cost > (average_hour_cost * 3)
end

# Implement cost controls
class CostControlledRunner < OpenAIAgents::Runner
  MAX_DAILY_COST = 1000.0
  
  def run(messages, **kwargs)
    current_cost = UsageTracker.current.daily_cost
    
    if current_cost > MAX_DAILY_COST
      raise "Daily cost limit exceeded: $#{current_cost}"
    end
    
    super
  end
end
```

#### Memory Leaks
```ruby
# Monitor memory usage
def check_memory_usage
  memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
  
  if memory_mb > 1000  # 1GB limit
    Rails.logger.warn("High memory usage: #{memory_mb}MB")
    
    # Force garbage collection
    GC.start
    
    # Restart if memory is still high
    if memory_mb > 1500
      Process.kill('TERM', Process.pid)
    end
  end
end

# Check memory periodically
Thread.new do
  loop do
    check_memory_usage
    sleep(60)
  end
end
```

#### Rate Limiting Issues
```ruby
# Implement exponential backoff
class ResilientRunner < OpenAIAgents::Runner
  def run(messages, **kwargs)
    retry_count = 0
    max_retries = 3
    
    begin
      super
    rescue OpenAIAgents::RateLimitError => e
      retry_count += 1
      
      if retry_count <= max_retries
        delay = 2 ** retry_count
        Rails.logger.info("Rate limited, retrying in #{delay}s")
        sleep(delay)
        retry
      else
        raise
      end
    end
  end
end
```

### Debugging Production Issues

```ruby
# Enhanced error reporting
class ProductionRunner < OpenAIAgents::Runner
  def run(messages, **kwargs)
    start_time = Time.current
    
    super
  rescue => e
    # Capture context for debugging
    error_context = {
      agent_name: @agent.name,
      messages_count: messages.length,
      duration: Time.current - start_time,
      error_class: e.class.name,
      error_message: e.message,
      backtrace: e.backtrace.first(10)
    }
    
    # Send to error tracking service
    Sentry.capture_exception(e, extra: error_context)
    
    # Log for internal debugging
    Rails.logger.error("Agent execution failed", error_context)
    
    raise
  end
end
```

For more deployment examples and platform-specific guidance, see the cloud provider documentation and the [examples](examples/) directory.