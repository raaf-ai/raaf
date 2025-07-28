# Configuration API

## Overview

The RAAF Rails configuration API provides a flexible way to customize the behavior of AI agents within your Rails application. All configuration is done through the `RAAF::Rails.configure` method.

## Basic Configuration

```ruby
# config/initializers/raaf.rb
RAAF::Rails.configure do |config|
  config.authentication_method = :devise
  config.enable_dashboard = true
  config.enable_api = true
end
```

## Configuration Options

### Authentication

#### authentication_method

Specifies the authentication method to use.

- **Type**: Symbol
- **Default**: `:none`
- **Options**: `:devise`, `:doorkeeper`, `:custom`, `:none`

```ruby
config.authentication_method = :devise
```

#### authentication_handler

Custom authentication handler for the `:custom` authentication method.

- **Type**: Proc
- **Default**: `nil`

```ruby
config.authentication_handler = ->(request) {
  # Extract token from request
  token = request.headers["Authorization"]&.gsub("Bearer ", "")
  
  # Find user by token
  User.find_by(api_token: token)
}
```

### Features

#### enable_dashboard

Enable or disable the web dashboard.

- **Type**: Boolean
- **Default**: `true`

```ruby
config.enable_dashboard = true
```

#### enable_api

Enable or disable the REST API.

- **Type**: Boolean
- **Default**: `true`

```ruby
config.enable_api = true
```

#### enable_websockets

Enable or disable WebSocket support.

- **Type**: Boolean
- **Default**: `true`

```ruby
config.enable_websockets = true
```

#### enable_background_jobs

Enable or disable background job processing.

- **Type**: Boolean
- **Default**: `true`

```ruby
config.enable_background_jobs = true
```

### Paths

#### dashboard_path

The mount path for the dashboard.

- **Type**: String
- **Default**: `"/dashboard"`

```ruby
config.dashboard_path = "/admin/agents"
```

#### api_path

The mount path for the API.

- **Type**: String
- **Default**: `"/api/v1"`

```ruby
config.api_path = "/api/v2"
```

#### websocket_path

The mount path for WebSocket connections.

- **Type**: String
- **Default**: `"/chat"`

```ruby
config.websocket_path = "/ws"
```

### Security

#### allowed_origins

CORS allowed origins for API and WebSocket connections.

- **Type**: Array
- **Default**: `["*"]`

```ruby
config.allowed_origins = [
  "http://localhost:3000",
  "https://myapp.com",
  "https://app.myapp.com"
]
```

#### rate_limit

Rate limiting configuration.

- **Type**: Hash
- **Default**: `{ enabled: true, requests_per_minute: 60 }`

```ruby
config.rate_limit = {
  enabled: true,
  requests_per_minute: 100,
  requests_per_hour: 1000,
  requests_per_day: 10000
}
```

### Monitoring

#### monitoring

Monitoring and metrics configuration.

- **Type**: Hash
- **Default**: `{ enabled: true, metrics: [:usage, :performance, :errors] }`

```ruby
config.monitoring = {
  enabled: true,
  metrics: [:usage, :performance, :errors, :costs],
  export_interval: 300, # seconds
  retention_days: 30
}
```

## Advanced Configuration

### Database Configuration

```ruby
config.database = {
  pool_size: 10,
  timeout: 5000,
  reaping_frequency: 10
}
```

### Caching Configuration

```ruby
config.cache = {
  store: :redis_cache_store,
  expires_in: 1.hour,
  namespace: "raaf"
}
```

### Logging Configuration

```ruby
config.logging = {
  level: :info,
  format: :json,
  destination: Rails.root.join("log/raaf.log")
}
```

## Environment-Specific Configuration

```ruby
RAAF::Rails.configure do |config|
  case Rails.env
  when "development"
    config.enable_dashboard = true
    config.authentication_method = :none
    config.logging[:level] = :debug
  when "production"
    config.enable_dashboard = false
    config.authentication_method = :devise
    config.allowed_origins = ["https://myapp.com"]
    config.rate_limit[:requests_per_minute] = 100
  when "test"
    config.enable_background_jobs = false
    config.authentication_method = :none
  end
end
```

## Configuration from Environment Variables

```ruby
RAAF::Rails.configure do |config|
  # Read from environment
  config.authentication_method = ENV.fetch("RAAF_AUTH_METHOD", "none").to_sym
  config.enable_dashboard = ENV.fetch("RAAF_ENABLE_DASHBOARD", "true") == "true"
  config.api_path = ENV.fetch("RAAF_API_PATH", "/api/v1")
  
  # Parse JSON configuration
  if ENV["RAAF_RATE_LIMIT"]
    config.rate_limit = JSON.parse(ENV["RAAF_RATE_LIMIT"], symbolize_names: true)
  end
end
```

## Dynamic Configuration

```ruby
RAAF::Rails.configure do |config|
  # Load from database
  if settings = SystemSetting.find_by(key: "raaf_config")
    config.merge!(settings.value)
  end
  
  # Load from YAML file
  yaml_config = Rails.root.join("config/raaf.yml")
  if yaml_config.exist?
    config.merge!(YAML.load_file(yaml_config)[Rails.env])
  end
end
```

## Validation

Configuration is validated on initialization:

```ruby
RAAF::Rails.configure do |config|
  config.authentication_method = :invalid # Raises error
end
# => RAAF::ConfigurationError: Invalid authentication_method: :invalid

RAAF::Rails.configure do |config|
  config.rate_limit = { enabled: "yes" } # Raises error
end
# => RAAF::ConfigurationError: rate_limit.enabled must be boolean
```

## Accessing Configuration

```ruby
# Get current configuration
config = RAAF::Rails.config

# Check specific settings
if RAAF::Rails.config.enable_dashboard
  # Dashboard is enabled
end

# Access nested configuration
rate_limit = RAAF::Rails.config.rate_limit[:requests_per_minute]
```

## Reconfiguring at Runtime

```ruby
# Reconfigure specific settings
RAAF::Rails.configure do |config|
  config.rate_limit[:requests_per_minute] = 200
end

# Reset to defaults
RAAF::Rails.reset_configuration!
```

## Configuration Hooks

```ruby
RAAF::Rails.configure do |config|
  # Before configuration
  config.before_configure do
    Rails.logger.info "Configuring RAAF..."
  end
  
  # After configuration
  config.after_configure do
    Rails.logger.info "RAAF configured successfully"
    
    # Validate external dependencies
    if config.authentication_method == :devise && !defined?(Devise)
      raise "Devise is required for :devise authentication"
    end
  end
end
```