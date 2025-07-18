# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-06-20

### Added
- Initial release of RAAF (Ruby AI Agents Factory) gem
- Core Agent class with tool and handoff support
- Runner class for managing agent execution
- FunctionTool wrapper for custom functions
- Streaming support via StreamingRunner and StreamingClient
- Comprehensive tracing and debugging capabilities
- Multi-agent workflows with handoff mechanisms
- Async execution support
- Provider-agnostic design
- Basic test suite and examples
- Documentation and README

### Features
- Agent configuration with instructions, tools, and handoffs
- Tool integration for custom functions
- Agent-to-agent handoffs during conversations
- Real-time streaming of responses
- Configurable tracing with multiple processors
- Support for OpenAI API and custom endpoints
- Error handling and validation
- Ruby 3.0+ compatibility

<!-- [Unreleased]: https://github.com/enterprisemodules/raaf/compare/v0.1.0...HEAD -->
<!-- [0.1.0]: https://github.com/enterprisemodules/raaf/releases/tag/v0.1.0 -->