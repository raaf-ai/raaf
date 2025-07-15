# Changelog

All notable changes to the Ruby AI Agents Factory (RAAF) main gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release of the main RAAF gem
- Comprehensive integration of all RAAF subgems
- Global configuration system
- Complete example suite
- Full documentation

## [0.1.0] - 2024-01-15

### Added
- Initial release of Ruby AI Agents Factory main gem
- Integration of all core components:
  - Core framework (raaf-core)
  - Provider integrations (raaf-providers)
  - Tool collections (raaf-tools-basic, raaf-tools-advanced)
  - Safety features (raaf-guardrails)
  - Monitoring (raaf-tracing)
  - Streaming capabilities (raaf-streaming)
  - Memory management (raaf-memory)
  - Extension system (raaf-extensions)
  - DSL support (raaf-dsl)
  - Debug tools (raaf-debug)
  - Testing utilities (raaf-testing)
  - Visualization (raaf-visualization)
  - Compliance features (raaf-compliance)
  - Rails integration (raaf-rails)
- Global configuration system
- Comprehensive documentation and examples
- Graceful handling of missing subgems
- Automatic logging configuration
- Version management

### Dependencies
- Ruby 3.0+ required
- All RAAF subgems as dependencies
- Optional Rails integration

### Notes
- This is the main convenience gem that includes all RAAF functionality
- Users can install individual subgems if they prefer a modular approach
- Full backward compatibility with existing RAAF installations