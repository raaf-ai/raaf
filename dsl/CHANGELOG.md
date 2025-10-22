# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2025-10-22

### ⚠️ Breaking Changes

This is a major release with breaking API changes. All `uses_*` tool registration methods have been removed in favor of a unified `tool` and `tools` API. See [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md) for detailed migration instructions.

### Removed (Breaking)
- **Removed `uses_tool` method** - Use `tool` instead
- **Removed `uses_tools` method** - Use `tools` instead
- **Removed `uses_native_tool` method** - Use `tool` with class argument
- **Removed `uses_external_tool` method** - Use `tool` instead
- **Removed `uses_tool_if` method** - Use `tool ... if condition` instead
- **Removed `use_tool_conditionally` method** - Use Ruby conditionals
- **Removed `register_tool` method** - Legacy method, use `tool`

### Added
- **Lazy Tool Loading** - Tools are now loaded only when needed, not at agent initialization
- **Unified `tool` method** - Single method handles all tool registration patterns:
  - Symbol identifiers: `tool :web_search`
  - Class references: `tool RAAF::Tools::CustomTool`
  - With options: `tool :search, max_results: 10`
  - With aliases: `tool :search, as: :web_search`
  - Inline definitions with blocks
- **Unified `tools` method** - Register multiple tools at once: `tools :search, :calculator`
- **Enhanced Error Messages** - New `ToolResolutionError` with detailed debugging information:
  - Lists all searched namespaces
  - Provides actionable fix suggestions
  - Shows similar tool names for typos
  - Includes clear emoji indicators
- **Automatic Namespace Search** - Tool resolution now searches multiple namespaces:
  - `RAAF::DSL::Tools::[Identifier]`
  - `RAAF::Tools::[Identifier]`
  - `Ai::Tools::[Identifier]`
  - `[Identifier]` (direct constant lookup)

### Changed
- **Tool Loading Performance** - 6.25x faster agent initialization through lazy loading
- **Tool Resolution Logic** - Now uses `ToolRegistry.resolve_tool_class` for consistent resolution
- **Error Handling** - All tool registration errors now use `ToolResolutionError` with rich context
- **Memory Usage** - Reduced memory footprint during agent initialization

### Performance Improvements
- Agent initialization: **6.25x faster** (from 37.50ms to 6.00ms for 100 initializations)
- Memory usage: **Reduced by ~40%** during initialization phase
- Tool loading: **Deferred until first use** instead of eager loading

### Migration Guide
See [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md) for:
- Complete list of removed methods and their replacements
- Step-by-step migration instructions
- Before/after code examples for all patterns
- Common migration issues and solutions
- Performance verification steps

### Technical Details
- Implemented lazy loading via `RegisteredTool` wrapper class
- Added `loaded?` tracking to prevent duplicate loading
- Unified all tool registration through single `tool_registration` private method
- Standardized error handling with structured error data

## [0.1.0] - 2024-07-15

### Added
- Initial implementation
- Basic functionality
- Documentation and examples
