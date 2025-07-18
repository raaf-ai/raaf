**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Deployment Guide
=====================

This guide covers deploying RAAF agents to production with Docker, Kubernetes, monitoring, and best practices for scalable AI systems.

**Production deployment is where theory meets reality.** Local development environments are forgiving—unlimited resources, predictable behavior, and easy debugging. Production is unforgiving—resource constraints, unpredictable load, network failures, and the need for 24/7 reliability. AI systems add extra complexity: variable token costs, external API dependencies, and the challenge of maintaining consistent performance across unpredictable workloads.

**Why AI deployment is different:** Traditional applications have predictable resource usage patterns. AI applications consume tokens (money) with every request, depend on external APIs that can fail or rate-limit, and have response times that vary dramatically based on query complexity. A simple "hello" might cost $0.001 and take 200ms, while a complex analysis might cost $0.50 and take 30 seconds.

**The deployment challenge:** You need to balance cost, performance, reliability, and scalability. This means intelligent caching to reduce API calls, robust error handling for external dependencies, monitoring that tracks both technical metrics and business costs, and scaling strategies that account for both computational and financial resources.

**Deployment strategy:** This guide presents a layered approach—from simple Docker containers to sophisticated Kubernetes deployments with autoscaling, monitoring, and disaster recovery. Each layer adds operational complexity but provides greater reliability and scalability. Choose the approach that matches your operational maturity and scaling requirements.

After reading this guide, you will know:

* How to containerize RAAF applications with Docker
* Kubernetes deployment patterns and configurations
* Production environment setup and configuration
* Monitoring, logging, and observability strategies
* Security considerations for production deployments
* Scaling strategies and load balancing
* Backup and disaster recovery procedures

--------------------------------------------------------------------------------

Production Environment Setup
----------------------------

### Production Environment Challenges

Production environments present unique challenges that don't manifest in development or staging environments. AI systems are particularly susceptible to production-specific issues.

**Common production failure modes**:

- External API rate limiting and throttling
- Network latency and connection failures
- Resource constraints affecting performance
- Unexpected load patterns and traffic spikes
- Integration failures with production services

**Impact of production failures**: System reliability issues directly impact business outcomes, customer satisfaction, and revenue. A production failure rate of 73% represents a critical system reliability problem requiring immediate infrastructure and architecture improvements.

### Why Production Environments Are AI's Worst Enemy

**Your Development Environment**: Unlimited resources, fast network, predictable load
**Your Production Environment**: Resource constraints, network failures, traffic spikes, angry users

**What we learned**: Production environments are hostile to AI systems in ways that regular web apps never experience:

1. **API Rate Limits**: OpenAI throttles your requests when you need them most
2. **Network Latency**: 500ms to AI providers feels like forever to users
3. **Memory Pressure**: Context windows consume RAM exponentially
4. **Cost Explosions**: Traffic spikes can trigger $10,000/hour bills
5. **Cascading Failures**: One slow AI call blocks everything else

### Core Production Deployment Principles

Production AI systems require specialized deployment principles that address unique challenges:

1. **Production environments are hostile** - They're resource-constrained, network-partitioned, and subject to failures that never happen in development. AI applications face additional challenges: external API dependencies that can fail, variable costs that can spiral out of control, and performance characteristics that change based on workload complexity.

2. **Plan for failure** - Every external dependency will fail. Every network will partition. Every rate limit will be hit. Build resilience into every layer.

3. **Monitor everything** - If you can't measure it, you can't fix it. AI systems need monitoring that traditional apps never dreamed of.

**Resource planning principles:** AI applications have different resource patterns than traditional web applications. CPU usage is often low (most work happens at AI providers), but memory usage can be high for large context windows. Network becomes critical—poor connections to AI providers directly impact user experience. Storage needs are moderate unless you're caching responses or storing conversation history.

**Scalability considerations:** Unlike traditional applications that scale linearly, AI applications have more complex scaling patterns. Token costs scale with usage, external API rate limits create bottlenecks, and some operations (like long-running analysis) benefit from dedicated resources. Your infrastructure needs to handle both quick chat responses and long-running background tasks.

### System Requirements

**Minimum Requirements (Single Server):**

- CPU: 2 cores (sufficient for API orchestration)
- RAM: 4GB (for Ruby processes and caching)
- Storage: 20GB SSD (logs, cache, application)
- Network: 100Mbps (adequate for most AI API calls)

**Recommended for Production:**

- CPU: 8+ cores (handle concurrent requests and background jobs)
- RAM: 16GB+ (aggressive caching and multiple processes)
- Storage: 100GB+ SSD (extensive logging and response caching)
- Network: 1Gbps (fast AI provider connections)
- Load balancer support (distribute tRAAFic and provide failover)

**Dependencies and Rationale:**

- Ruby 3.1+ (performance improvements and better memory management)
- Redis (essential for caching expensive AI responses and job queues)
- PostgreSQL/MySQL (conversation history, analytics, and configuration)
- Python 3.8+ (NLP features like tokenization and content moderation)

**Why these dependencies matter:** Redis isn't just a cache—it's your defense against spiraling AI costs. A well-configured Redis can reduce API calls by 70-90% for common queries. PostgreSQL provides ACID transactions for critical operations like billing and audit trails. Python provides local NLP capabilities that reduce reliance on external APIs for basic operations.

### Environment Configuration

```bash
# Production environment variables
export RAILS_ENV=production
export RACK_ENV=production

# RAAF Configuration
export RAAF_LOG_LEVEL=info
export RAAF_DEFAULT_MODEL=gpt-4o-mini
export RAAF_MAX_CONCURRENT_AGENTS=100
export RAAF_RESPONSE_TIMEOUT=60

# AI Provider Keys
export OPENAI_API_KEY=sk-...
export ANTHROPIC_API_KEY=sk-ant-...
export GROQ_API_KEY=gsk_...

# Database Configuration
export DATABASE_URL=postgresql://user:pass@host:5432/raaf_production

# Redis Configuration  
export REDIS_URL=redis://localhost:6379/1
export RAAF_CACHE_URL=redis://localhost:6379/2

# Security
export SECRET_KEY_BASE=your-secret-key
export RAAF_DASHBOARD_AUTH_TOKEN=secure-dashboard-token

# Monitoring
export SENTRY_DSN=https://...
export DATADOG_API_KEY=...
export NEW_RELIC_LICENSE_KEY=...
```

Docker Deployment
-----------------

### Environment Consistency Requirements

AI systems are particularly sensitive to environment differences that can cause significant behavioral changes between development and production.

**Environment consistency challenges**:

- Dependency version differences affect NLP processing
- Library variations change tokenization behavior
- Environment configuration impacts API routing
- File system differences affect model access
- Network configuration affects provider connections

**Behavioral impact**: Minor environment differences can cause substantial changes in AI behavior, response quality, and system costs. A single Python patch version difference can alter NLP preprocessing, affecting prompt interpretation and AI responses.

Containerization addresses these consistency issues by ensuring identical runtime environments across development, staging, and production.

### Why "It Works on My Machine" Is Deadly for AI

**Traditional Web Apps**: Different environments might change performance or cause bugs
**AI Apps**: Different environments can completely change AI behavior, costs, and security

**What breaks between environments:**

- **Python versions**: Different NLP behavior
- **Library versions**: Different tokenization 
- **Environment variables**: Different API endpoints
- **File permissions**: Different model access
- **Network configurations**: Different provider routing

### Containerization Benefits

Containers provide consistent runtime environments that eliminate environment-specific deployment issues.

**Before Docker**:

- ❌ 2 hours to set up development environment
- ❌ Different behavior in staging vs production
- ❌ "Environment configuration" as a specialized skill
- ❌ Deployment anxiety

**After Docker**:

- ✅ 5 minutes to get fully working environment
- ✅ Identical behavior across all environments
- ✅ New developers productive immediately
- ✅ Deploy with confidence

### What Makes AI Containerization Different

**Traditional apps**: Package code, install dependencies, run server
**AI apps**: Package code, Python NLP libraries, model files, API configurations, security secrets, health checks for external services

**Containers solve environment consistency.** The "it works on my machine" problem becomes critical in production AI applications where small configuration differences can lead to different model behavior, unexpected costs, or security vulnerabilities. Containers provide reproducible environments that behave identically across development, testing, and production.

**AI-specific containerization challenges:** AI applications have unique requirements: Python dependencies for NLP, large model files for local processing, and complex environment variables for API keys and configurations. The container needs to be secure (no leaked API keys), efficient (minimal image size), and reliable (proper health checks for external dependencies).

**Container strategy:** This Dockerfile follows security best practices—non-root user, minimal attack surface, and proper dependency management. It also optimizes for AI workloads with Python NLP libraries and efficient layer caching to reduce build times during development.

### Dockerfile

```dockerfile
# Dockerfile
FROM ruby:3.1-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    libpq-dev \
    nodejs \
    npm \
    python3 \
    python3-pip \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies for NLP features
RUN pip3 install \
    spacy \
    numpy \
    scikit-learn \
    && python3 -m spacy download en_core_web_sm

# Set working directory
WORKDIR /app

# Copy dependency files
COPY Gemfile Gemfile.lock ./
COPY package.json package-lock.json ./

# Install Ruby dependencies
RUN bundle config --global frozen 1 \
    && bundle install --without development test

# Install Node.js dependencies
RUN npm ci --only=production

# Copy application code
COPY . .

# Precompile assets (if Rails app)
RUN bundle exec rails assets:precompile

# Create non-root user
RUN addgroup --system --gid 1001 raaf \
    && adduser --system --uid 1001 --gid 1001 raaf

# Change ownership and switch to non-root user
RUN chown -R raaf:raaf /app
USER raaf

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Start application
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
```

### Docker Compose for Development

```yaml
# docker-compose.yml
version: '3.8'

services:
  app:
    build: .
    ports:

      - "3000:3000"
    environment:

      - DATABASE_URL=postgresql://postgres:password@db:5432/raaf_development
      - REDIS_URL=redis://redis:6379/1
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    depends_on:

      - db
      - redis
    volumes:

      - .:/app
      - bundle_cache:/usr/local/bundle
    command: bundle exec rails server -b 0.0.0.0

  db:
    image: postgres:15
    environment:

      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=raaf_development
    volumes:

      - postgres_data:/var/lib/postgresql/data
    ports:

      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:

      - "6379:6379"
    volumes:

      - redis_data:/data

  worker:
    build: .
    environment:

      - DATABASE_URL=postgresql://postgres:password@db:5432/raaf_development
      - REDIS_URL=redis://redis:6379/1
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    depends_on:

      - db
      - redis
    volumes:

      - .:/app
      - bundle_cache:/usr/local/bundle
    command: bundle exec sidekiq

volumes:
  postgres_data:
  redis_data:
  bundle_cache:
```

### Production Docker Compose

```yaml
# docker-compose.prod.yml
version: '3.8'

services:
  app:
    image: raaf-app:latest
    ports:

      - "3000:3000"
    environment:

      - RAILS_ENV=production
      - DATABASE_URL=${DATABASE_URL}
      - REDIS_URL=${REDIS_URL}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
    deploy:
      replicas: 3
      restart_policy:
        condition: on-failure
        max_attempts: 3
      resources:
        limits:
          memory: 1G
          cpus: '0.5'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  worker:
    image: raaf-app:latest
    environment:

      - RAILS_ENV=production
      - DATABASE_URL=${DATABASE_URL}
      - REDIS_URL=${REDIS_URL}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    command: bundle exec sidekiq
    deploy:
      replicas: 2
      restart_policy:
        condition: on-failure
      resources:
        limits:
          memory: 512M
          cpus: '0.25'

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

networks:
  default:
    external:
      name: raaf-network
```

Kubernetes Deployment
---------------------

### Container Orchestration Requirements

While containers provide environment consistency, production systems require orchestration for scaling, load balancing, and resource management.

**Scaling challenges with manual container management**:

- Manual container restart during failures
- Uneven load distribution across containers
- Resource contention and memory pressure
- Cost management across multiple instances
- Service discovery and coordination

**Production orchestration needs**: Automatic scaling, load balancing, self-healing, resource management, and service discovery capabilities that manual container management cannot provide efficiently.

### Why Docker Alone Isn't Enough for AI at Scale

**Docker gives you**: Consistent environments
**Production needs**: Orchestration, scaling, self-healing, resource management, service discovery

**What we learned the hard way:**

- **Containers crash**: Who restarts them?
- **Load is uneven**: Who balances it?
- **Resources are constrained**: Who manages them?
- **Configs change**: Who updates them?
- **Services need to find each other**: Who coordinates them?

### Kubernetes Orchestration Benefits

Kubernetes provides comprehensive container orchestration that addresses production scaling and operational challenges.

**Before Kubernetes (Manual Hell)**:

- ❌ Manual container management
- ❌ No automatic scaling
- ❌ Manual load balancing
- ❌ 3 AM phone calls for restarts
- ❌ Configuration scattered everywhere

**After Kubernetes (Automated Heaven)**:

- ✅ Self-healing containers
- ✅ Automatic scaling based on demand
- ✅ Intelligent load balancing
- ✅ Sleep through the night
- ✅ Centralized configuration management

### Why AI Applications Love Kubernetes

**Traditional apps**: Scale based on CPU and memory
**AI apps**: Scale based on token usage, queue depth, provider latency, and cost budgets

**What Kubernetes gives AI systems:**

- **Heterogeneous workloads**: Quick chat responses on small pods, long analysis on large pods
- **Custom scaling**: Scale based on AI-specific metrics (token usage, queue depth)
- **Resource isolation**: Expensive AI tasks don't starve quick responses
- **Configuration security**: API keys managed safely with secrets
- **Service mesh**: Intelligent routing to AI providers

**Kubernetes provides production-grade orchestration.** While Docker containers solve environment consistency, Kubernetes solves operational complexity—automated scaling, self-healing, service discovery, and configuration management. For AI applications, Kubernetes offers sophisticated resource management, the ability to scale different components independently, and integrated monitoring.

**AI workload orchestration:** AI applications benefit from Kubernetes' ability to handle heterogeneous workloads. You can run quick chat responses on small pods while dedicating larger resources to long-running analysis tasks. Kubernetes' horizontal pod autoscaling can scale based on custom metrics like token usage or queue depth, not just CPU and memory.

**Configuration management strategy:** AI applications have complex configuration requirements—API keys, model parameters, provider settings, and business logic configurations. Kubernetes ConfigMaps and Secrets provide secure, versioned configuration management that can be updated without redeploying applications.

### Namespace and ConfigMaps

```yaml
# k8s/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: raaf
  labels:
    name: raaf

---
# k8s/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: raaf-config
  namespace: raaf
data:
  RAILS_ENV: "production"
  RAAF_LOG_LEVEL: "info"
  RAAF_DEFAULT_MODEL: "gpt-4o-mini"
  RAAF_MAX_CONCURRENT_AGENTS: "100"
  RAAF_RESPONSE_TIMEOUT: "60"
  DATABASE_HOST: "postgres-service"
  REDIS_HOST: "redis-service"

---
# k8s/secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: raaf-secrets
  namespace: raaf
type: Opaque
data:
  OPENAI_API_KEY: <base64-encoded-key>
  ANTHROPIC_API_KEY: <base64-encoded-key>
  SECRET_KEY_BASE: <base64-encoded-secret>
  DATABASE_PASSWORD: <base64-encoded-password>
```

### Application Deployment

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: raaf-app
  namespace: raaf
  labels:
    app: raaf-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: raaf-app
  template:
    metadata:
      labels:
        app: raaf-app
    spec:
      containers:

      - name: raaf-app
        image: your-registry/raaf-app:latest
        ports:

        - containerPort: 3000
        envFrom:

        - configMapRef:
            name: raaf-config

        - secretRef:
            name: raaf-secrets
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        volumeMounts:

        - name: app-logs
          mountPath: /app/log
      volumes:

      - name: app-logs
        emptyDir: {}

---
# k8s/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: raaf-app-service
  namespace: raaf
spec:
  selector:
    app: raaf-app
  ports:

  - protocol: TCP
    port: 3000
    targetPort: 3000
  type: ClusterIP

---
# k8s/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: raaf-ingress
  namespace: raaf
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rate-limit: "100"
spec:
  tls:

  - hosts:
    - raaf.yourdomain.com
    secretName: raaf-tls
  rules:

  - host: raaf.yourdomain.com
    http:
      paths:

      - path: /
        pathType: Prefix
        backend:
          service:
            name: raaf-app-service
            port:
              number: 3000
```

### Worker Deployment

```yaml
# k8s/worker-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: raaf-worker
  namespace: raaf
  labels:
    app: raaf-worker
spec:
  replicas: 2
  selector:
    matchLabels:
      app: raaf-worker
  template:
    metadata:
      labels:
        app: raaf-worker
    spec:
      containers:

      - name: raaf-worker
        image: your-registry/raaf-app:latest
        command: ["bundle", "exec", "sidekiq"]
        envFrom:

        - configMapRef:
            name: raaf-config

        - secretRef:
            name: raaf-secrets
        resources:
          requests:
            memory: "256Mi"
            cpu: "125m"
          limits:
            memory: "512Mi"
            cpu: "250m"
        livenessProbe:
          exec:
            command:

            - pgrep
            - -f
            - sidekiq
          initialDelaySeconds: 30
          periodSeconds: 30
        volumeMounts:

        - name: worker-logs
          mountPath: /app/log
      volumes:

      - name: worker-logs
        emptyDir: {}
```

### Database and Redis

```yaml
# k8s/postgres.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: raaf
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:

      - name: postgres
        image: postgres:15
        ports:

        - containerPort: 5432
        env:

        - name: POSTGRES_DB
          value: raaf_production

        - name: POSTGRES_USER
          value: raaf

        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: raaf-secrets
              key: DATABASE_PASSWORD
        volumeMounts:

        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
      volumes:

      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pvc

---
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: raaf
spec:
  selector:
    app: postgres
  ports:

  - port: 5432
    targetPort: 5432

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: raaf
spec:
  accessModes:

  - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi

---
# k8s/redis.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: raaf
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:

      - name: redis
        image: redis:7-alpine
        ports:

        - containerPort: 6379
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "100m"

---
apiVersion: v1
kind: Service
metadata:
  name: redis-service
  namespace: raaf
spec:
  selector:
    app: redis
  ports:

  - port: 6379
    targetPort: 6379
```

Monitoring and Observability
-----------------------------

**Observability is insurance for production systems.** In development, you can debug issues by examining logs and stepping through code. In production, you need telemetry—metrics, traces, and structured logs that help you understand system behavior without direct access to running processes.

**AI monitoring is multi-dimensional.** Traditional applications monitor CPU, memory, and request rates. AI applications also need to monitor token usage, provider latency, cost per request, content quality, and business metrics like user satisfaction. You're not just monitoring technical health—you're monitoring business health.

**Health check philosophy:** Health checks aren't just "is the service running?"—they're "can the service perform its intended function?" For AI applications, this means checking not just database connectivity, but AI provider availability, token budgets, and response quality. A service that's technically healthy but can't afford to make API calls is effectively broken.

### Health Check Endpoints

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Health check endpoints
  get '/health', to: 'health#show'
  get '/ready', to: 'health#ready'
  get '/metrics', to: 'metrics#show'
end

# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def show
    health_status = {
      status: 'healthy',
      timestamp: Time.current.iso8601,
      version: RAAF::VERSION,
      uptime: uptime_seconds,
      checks: perform_health_checks
    }
    
    overall_status = health_status[:checks].all? { |_, status| status[:healthy] }
    
    render json: health_status, status: overall_status ? :ok : :service_unavailable
  end
  
  def ready
    readiness_status = {
      status: 'ready',
      timestamp: Time.current.iso8601,
      checks: perform_readiness_checks
    }
    
    ready = readiness_status[:checks].all? { |_, status| status[:ready] }
    
    render json: readiness_status, status: ready ? :ok : :service_unavailable
  end
  
  private
  
  def perform_health_checks
    {
      database: check_database,
      redis: check_redis,
      ai_providers: check_ai_providers,
      disk_space: check_disk_space,
      memory: check_memory
    }
  end
  
  def perform_readiness_checks
    {
      database: check_database_ready,
      redis: check_redis_ready,
      background_jobs: check_background_jobs
    }
  end
  
  def check_database
    ActiveRecord::Base.connection.execute("SELECT 1")
    { healthy: true, response_time: measure_time { ActiveRecord::Base.connection.execute("SELECT 1") } }
  rescue => e
    { healthy: false, error: e.message }
  end
  
  def check_redis
    Redis.new.ping
    { healthy: true, response_time: measure_time { Redis.new.ping } }
  rescue => e
    { healthy: false, error: e.message }
  end
  
  def check_ai_providers
    provider_status = {}
    
    [RAAF::Models::OpenAIProvider, RAAF::Models::AnthropicProvider].each do |provider_class|
      begin
        provider = provider_class.new
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        provider.list_models
        response_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        
        provider_status[provider_class.name] = { healthy: true, response_time: response_time }
      rescue => e
        provider_status[provider_class.name] = { healthy: false, error: e.message }
      end
    end
    
    provider_status
  end
  
  def uptime_seconds
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
  
  def measure_time
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
  end
end
```

### Prometheus Metrics

```ruby
# app/controllers/metrics_controller.rb
class MetricsController < ApplicationController
  def show
    metrics = []
    
    # Agent metrics
    metrics << "raaf_agent_requests_total #{RAAF::Metrics.get(:agent_requests_total)}"
    metrics << "raaf_agent_response_time_seconds #{RAAF::Metrics.get(:agent_response_time)}"
    metrics << "raaf_agent_errors_total #{RAAF::Metrics.get(:agent_errors_total)}"
    
    # Token usage metrics
    metrics << "raaf_tokens_used_total #{RAAF::Metrics.get(:tokens_used_total)}"
    metrics << "raaf_cost_usd_total #{RAAF::Metrics.get(:cost_usd_total)}"
    
    # System metrics
    metrics << "raaf_memory_usage_bytes #{get_memory_usage}"
    metrics << "raaf_cpu_usage_percent #{get_cpu_usage}"
    
    # Background job metrics
    metrics << "raaf_jobs_queued_total #{Sidekiq::Queue.new.size}"
    metrics << "raaf_jobs_processed_total #{Sidekiq::ProcessSet.new.size}"
    
    render plain: metrics.join("\n"), content_type: 'text/plain'
  end
  
  private
  
  def get_memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i * 1024  # Convert to bytes
  rescue
    0
  end
  
  def get_cpu_usage
    # Implementation depends on your system
    0
  end
end
```

### Logging Configuration

```ruby
# config/initializers/logging.rb
if Rails.env.production?
  # Structured JSON logging for production
  Rails.application.configure do
    config.log_formatter = proc do |severity, datetime, progname, msg|
      {
        timestamp: datetime.iso8601,
        level: severity,
        service: 'raaf',
        pid: Process.pid,
        message: msg,
        environment: Rails.env
      }.to_json + "\n"
    end
  end
  
  # RAAF-specific logging
  RAAF.configure do |config|
    config.logger = Rails.logger
    config.log_level = :info
    config.structured_logging = true
    
    config.log_agent_requests = true
    config.log_token_usage = true
    config.log_errors = true
    config.log_performance_metrics = true
  end
end
```

Scaling Strategies
------------------

**AI applications scale differently than traditional applications.** Traditional web applications scale linearly—double the tRAAFic, double the resources. AI applications have more complex scaling patterns: some requests are cheap and fast, others are expensive and slow. Token costs can spike unpredictably, external API rate limits create bottlenecks, and long-running tasks require different resource allocation than quick responses.

**Scaling dimensions:** You need to scale on multiple axes—computational resources for processing, network capacity for AI provider connections, and financial resources for token costs. Kubernetes' Horizontal Pod Autoscaler can scale based on custom metrics, but you need to define the right metrics for your AI workload.

**Autoscaling strategy:** This configuration scales based on CPU, memory, and custom metrics like request rate. The behavior settings provide stability—scaling up quickly when load increases, but scaling down slowly to avoid thrashing. For AI applications, conservative scale-down policies are especially important because spinning up new instances means cold starts and potential service degradation.

### Horizontal Pod Autoscaler

```yaml
# k8s/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: raaf-app-hpa
  namespace: raaf
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: raaf-app
  minReplicas: 3
  maxReplicas: 20
  metrics:

  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70

  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80

  - type: Pods
    pods:
      metric:
        name: raaf_agent_requests_per_second
      target:
        type: AverageValue
        averageValue: "10"
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:

      - type: Percent
        value: 100
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:

      - type: Percent
        value: 10
        periodSeconds: 60
```

### Load Balancer Configuration

```nginx
# nginx.conf
upstream raaf_app {
    least_conn;
    server raaf-app-1:3000 max_fails=3 fail_timeout=30s;
    server raaf-app-2:3000 max_fails=3 fail_timeout=30s;
    server raaf-app-3:3000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

server {
    listen 80;
    listen 443 ssl http2;
    server_name raaf.yourdomain.com;
    
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req zone=api burst=20 nodelay;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types
        text/plain
        text/css
        text/json
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml;
    
    location / {
        proxy_pass http://raaf_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    location /health {
        proxy_pass http://raaf_app;
        access_log off;
    }
    
    location /metrics {
        proxy_pass http://raaf_app;
        allow 10.0.0.0/8;
        allow 172.16.0.0/12;
        allow 192.168.0.0/16;
        deny all;
    }
}
```

Security Configuration
----------------------

**Security is a journey, not a destination.** AI applications handle sensitive data—user conversations, business logic, and valuable intellectual property. They also have unique attack surfaces: AI prompt injection, model extraction attempts, and API key theft. Security needs to be layered—network, application, and data protection.

**Network security principles:** AI applications need to communicate with external APIs, but should have minimal internal network exposure. Network policies implement "default deny" principles—explicitly allow only necessary communication. This limits the blast radius of potential compromises.

**Defense in depth:** Network policies are one layer of a comprehensive security strategy. They work with Pod Security Standards to limit container privileges, secret management to protect API keys, and monitoring to detect unusual access patterns.

### Network Policies

```yaml
# k8s/network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: raaf-network-policy
  namespace: raaf
spec:
  podSelector:
    matchLabels:
      app: raaf-app
  policyTypes:

  - Ingress
  - Egress
  ingress:

  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:

    - protocol: TCP
      port: 3000
  egress:

  - to: []
    ports:

    - protocol: TCP
      port: 5432  # PostgreSQL

    - protocol: TCP
      port: 6379  # Redis

    - protocol: TCP
      port: 443   # HTTPS for AI providers

    - protocol: TCP
      port: 53    # DNS

    - protocol: UDP
      port: 53    # DNS
```

### Pod Security Standards

```yaml
# k8s/pod-security-policy.yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: raaf-psp
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:

    - ALL
  volumes:

    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
```

Backup and Disaster Recovery
-----------------------------

**Backups are only as good as your ability to restore them.** Many organizations have backup strategies but no recovery strategies. They backup religiously but have never tested restoration under pressure. For AI applications, backup strategies need to account for both data and configuration—losing conversation history is bad, but losing agent configurations can be catastrophic.

**Recovery time objectives:** AI applications often have different recovery requirements than traditional applications. User conversations might be recoverable from cache, but agent configurations and training data are irreplaceable. Your backup strategy should prioritize based on recovery time objectives and business impact.

**Backup validation:** Regular backup testing isn't just good practice—it's essential. Backup scripts that work in development might fail in production due to permissions, network policies, or resource constraints. Test your backups in production-like environments and measure actual recovery times.

### Database Backup Strategy

```bash
#!/bin/bash
# scripts/backup_database.sh

set -e

BACKUP_DIR="/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="raaf_backup_${TIMESTAMP}.sql"

# Create backup directory
mkdir -p $BACKUP_DIR

# Perform database backup
pg_dump $DATABASE_URL > "$BACKUP_DIR/$BACKUP_FILE"

# Compress backup
gzip "$BACKUP_DIR/$BACKUP_FILE"

# Upload to S3 (optional)
if [ ! -z "$AWS_S3_BACKUP_BUCKET" ]; then
    aws s3 cp "$BACKUP_DIR/${BACKUP_FILE}.gz" "s3://$AWS_S3_BACKUP_BUCKET/database/"
fi

# Clean up old backups (keep last 7 days)
find $BACKUP_DIR -name "raaf_backup_*.sql.gz" -mtime +7 -delete

echo "Database backup completed: ${BACKUP_FILE}.gz"
```

### Kubernetes Backup CronJob

```yaml
# k8s/backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: database-backup
  namespace: raaf
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:

          - name: backup
            image: postgres:15
            command:

            - /bin/bash
            - -c
            - |
              pg_dump $DATABASE_URL | gzip > /backup/raaf_backup_$(date +%Y%m%d_%H%M%S).sql.gz
              # Upload to S3 or other storage
            env:

            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: raaf-secrets
                  key: DATABASE_URL
            volumeMounts:

            - name: backup-storage
              mountPath: /backup
          volumes:

          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
          restartPolicy: OnFailure
```

### Disaster Recovery Plan

```yaml
# k8s/disaster-recovery.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: disaster-recovery-procedures
  namespace: raaf
data:
  recovery-steps.md: |
    # RAAF Disaster Recovery Procedures
    
    ## 1. Assessment

    - [ ] Identify scope of outage
    - [ ] Determine if data is intact
    - [ ] Check backup availability
    - [ ] Estimate recovery time
    
    ## 2. Database Recovery
    ```bash
    # Restore from latest backup
    kubectl exec -it postgres-pod -- psql -U raaf -d postgres -c "DROP DATABASE IF EXISTS raaf_production;"
    kubectl exec -it postgres-pod -- psql -U raaf -d postgres -c "CREATE DATABASE raaf_production;"
    kubectl exec -i postgres-pod -- psql -U raaf raaf_production < latest_backup.sql
    ```
    
    ## 3. Application Recovery
    ```bash
    # Scale down to 0
    kubectl scale deployment raaf-app --replicas=0
    
    # Run database migrations if needed
    kubectl run migration --image=raaf-app:latest --rm -it -- bundle exec rails db:migrate
    
    # Scale back up
    kubectl scale deployment raaf-app --replicas=3
    ```
    
    ## 4. Verification

    - [ ] Health checks pass
    - [ ] Sample agent requests work
    - [ ] Dashboard accessible
    - [ ] Background jobs processing
    
    ## 5. Communication

    - [ ] Update status page
    - [ ] Notify stakeholders
    - [ ] Post-mortem scheduling
```

CI/CD Pipeline
--------------

**Continuous deployment reduces risk through smaller, frequent changes.** Large, infrequent deployments are high-risk events that often happen at inconvenient times. Continuous deployment makes deployment a boring, routine operation that can be safely performed during business hours.

**AI deployment challenges:** AI applications have unique deployment requirements. Model configurations can change behavior significantly, API keys need to be rotated securely, and performance can vary based on external provider changes. Your CI/CD pipeline needs to account for these AI-specific concerns.

**Deployment strategy:** This pipeline follows proven patterns—automated testing, immutable deployments, and gradual rollouts. The key insight is that deployment should be fast and reversible. If something goes wrong, you should be able to rollback quickly, not debug in production.

### GitHub Actions Workflow

```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    
    steps:

    - uses: actions/checkout@v3
    
    - name: Set up Ruby
      uses: ruby/setup-ruby@v1
      with:
        ruby-version: 3.1
        bundler-cache: true
    
    - name: Set up test database
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/raaf_test
        RAILS_ENV: test
      run: |
        bundle exec rails db:create
        bundle exec rails db:migrate
    
    - name: Run tests
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/raaf_test
        REDIS_URL: redis://localhost:6379/1
        RAILS_ENV: test
      run: |
        bundle exec rspec
        bundle exec rubocop

  build:
    needs: test
    runs-on: ubuntu-latest
    outputs:
      image: ${{ steps.image.outputs.image }}
    
    steps:

    - uses: actions/checkout@v3
    
    - name: Log in to Container Registry
      uses: docker/login-action@v2
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    
    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v4
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=sha,prefix={{branch}}-
    
    - name: Build and push Docker image
      uses: docker/build-push-action@v4
      with:
        context: .
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
    
    - name: Output image
      id: image
      run: echo "image=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}" >> $GITHUB_OUTPUT

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment: production
    
    steps:

    - uses: actions/checkout@v3
    
    - name: Set up kubectl
      uses: azure/setup-kubectl@v3
      with:
        version: 'v1.24.0'
    
    - name: Configure kubectl
      env:
        KUBE_CONFIG: ${{ secrets.KUBE_CONFIG }}
      run: |
        echo "$KUBE_CONFIG" | base64 -d > kubeconfig
        export KUBECONFIG=kubeconfig
    
    - name: Deploy to Kubernetes
      env:
        IMAGE: ${{ needs.build.outputs.image }}
      run: |
        export KUBECONFIG=kubeconfig
        
        # Update deployment image
        kubectl set image deployment/raaf-app raaf-app=$IMAGE -n raaf
        kubectl set image deployment/raaf-worker raaf-worker=$IMAGE -n raaf
        
        # Wait for rollout
        kubectl rollout status deployment/raaf-app -n raaf --timeout=300s
        kubectl rollout status deployment/raaf-worker -n raaf --timeout=300s
        
        # Verify deployment
        kubectl get pods -n raaf
        kubectl exec deployment/raaf-app -n raaf -- curl -f http://localhost:3000/health

  notify:
    needs: [test, build, deploy]
    runs-on: ubuntu-latest
    if: always()
    
    steps:

    - name: Notify Slack
      uses: 8398a7/action-slack@v3
      with:
        status: ${{ job.status }}
        channel: '#deployments'
        webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

Production Checklist
--------------------

**Checklists ensure deployment reliability.** Production deployments involve many moving parts, and missing a single step can cause outages. Checklists ensure that every deployment follows the same reliable process.

**AI deployment complexity:** AI applications have more moving parts than traditional applications—API keys, model configurations, provider settings, and business logic parameters. A comprehensive checklist ensures that all these components are properly configured and tested.

**Checklist evolution:** This checklist should evolve based on your operational experience. Every production issue should prompt a review—could this have been prevented by a checklist item? Checklists are living documents that improve over time.

### Pre-deployment Checklist

- [ ] **Security**
  - [ ] API keys stored securely
  - [ ] Network policies configured
  - [ ] SSL certificates installed
  - [ ] Security headers configured
  - [ ] Rate limiting enabled

- [ ] **Performance**
  - [ ] Resource limits set
  - [ ] Autoscaling configured
  - [ ] Connection pooling enabled
  - [ ] Caching configured
  - [ ] CDN setup (if applicable)

- [ ] **Monitoring**
  - [ ] Health checks implemented
  - [ ] Metrics collection enabled
  - [ ] Alerting rules configured
  - [ ] Log aggregation setup
  - [ ] Error tracking enabled

- [ ] **Backup & Recovery**
  - [ ] Automated backups configured
  - [ ] Backup restoration tested
  - [ ] Disaster recovery plan documented
  - [ ] RTO/RPO requirements defined

- [ ] **Operations**
  - [ ] Deployment automation setup
  - [ ] Rollback procedures tested
  - [ ] Documentation updated
  - [ ] Team access configured
  - [ ] Support procedures defined

### Post-deployment Verification

```bash
#!/bin/bash
# scripts/verify_deployment.sh

echo "🚀 Verifying RAAF deployment..."

# Check health endpoints
echo "✅ Checking health endpoints..."
curl -f http://your-domain.com/health || exit 1
curl -f http://your-domain.com/ready || exit 1

# Test agent functionality
echo "✅ Testing agent functionality..."
curl -X POST http://your-domain.com/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, test deployment"}' \
  -H "Authorization: Bearer $API_TOKEN" || exit 1

# Check metrics endpoint
echo "✅ Checking metrics..."
curl -f http://your-domain.com/metrics | grep raaf_ || exit 1

# Verify background jobs
echo "✅ Checking background jobs..."
kubectl exec deployment/raaf-worker -n raaf -- bundle exec sidekiq-cli stats

echo "✅ Deployment verification completed successfully!"
```

Next Steps
----------

For ongoing operations:

* **[Performance Guide](performance_guide.html)** - Optimize production performance
* **[RAAF Tracing Guide](tracing_guide.html)** - Advanced monitoring setup
* **[Troubleshooting Guide](troubleshooting.html)** - Production issue resolution
* **[Cost Management Guide](cost_guide.html)** - Control operational costs