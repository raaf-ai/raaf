# Changelog

All notable changes to the RAAF Rails gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive Rails integration for RAAF ecosystem
- Mountable Rails engine with isolated namespace
- Web dashboard for agent management
- REST API endpoints for agent operations
- WebSocket support for real-time conversations
- Authentication integration (Devise, Doorkeeper, custom)
- Background job processing with Sidekiq
- Agent helper methods for views and controllers
- Comprehensive configuration system
- Rate limiting middleware
- CORS support for API endpoints
- Monitoring and analytics dashboards
- ActiveRecord models for persistence
- I18n support for internationalization
- Asset pipeline integration
- Comprehensive test suite with RSpec
- Example applications demonstrating usage
- Full API documentation

### Changed
- Updated to support Rails 7.0+
- Modernized WebSocket implementation using Action Cable
- Improved error handling and logging
- Enhanced configuration validation

### Security
- Added authentication middleware
- Implemented rate limiting
- Added CORS configuration
- Secure token handling for API access

## [0.1.0] - 2024-07-15

### Added
- Initial release of RAAF Rails gem
- Basic Rails engine structure
- Simple dashboard interface
- Basic API endpoints
- WebSocket handler
- Agent helper module
- Configuration system
- README documentation

### Dependencies
- raaf-core (~> 0.1)
- raaf-memory (~> 0.1)
- raaf-tracing (~> 0.1)
- rails (>= 6.1)

### Known Issues
- WebSocket reconnection needs improvement
- Dashboard styling needs enhancement
- Some API endpoints need optimization

## Version History

### Versioning Strategy

This gem follows Semantic Versioning:
- MAJOR version for incompatible API changes
- MINOR version for backwards-compatible functionality additions
- PATCH version for backwards-compatible bug fixes

### Compatibility

| RAAF Rails Version | Rails Version | Ruby Version | Status |
|-------------------|---------------|--------------|---------|
| 0.1.x | >= 6.1 | >= 2.7 | Maintained |
| 0.2.x | >= 7.0 | >= 3.0 | Development |

### Migration Guides

#### From 0.0.x to 0.1.0

1. Update your Gemfile:
   ```ruby
   gem 'raaf-rails', '~> 0.1.0'
   ```

2. Run migrations:
   ```bash
   rails generate raaf:install
   rails db:migrate
   ```

3. Update configuration:
   ```ruby
   # Old format
   RAAF::Rails.setup do |config|
     # ...
   end
   
   # New format
   RAAF::Rails.configure do |config|
     # ...
   end
   ```

### Deprecations

#### Version 0.1.0
- `RAAF::Rails.setup` - Use `RAAF::Rails.configure` instead
- Direct WebSocket connections - Use Action Cable integration

### Future Releases

#### Version 0.2.0 (Planned)
- GraphQL API support
- Enhanced dashboard UI with React components
- Multi-tenant support
- Advanced analytics and reporting
- Plugin system for custom extensions

#### Version 0.3.0 (Planned)
- Real-time collaboration features
- Advanced agent orchestration
- Performance optimizations
- Enhanced security features

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to contribute to this project.

### Reporting Issues

Please report issues on the [GitHub issue tracker](https://github.com/raaf-ai/raaf/issues).

When reporting issues, please include:
- RAAF Rails version
- Rails version
- Ruby version
- Relevant configuration
- Steps to reproduce
- Error messages and stack traces