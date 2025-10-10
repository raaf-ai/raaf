# Specification: PerplexitySearch DSL Tool Self-Contained Restructure

## Goal
Restructure the PerplexitySearch DSL tool to be self-contained with direct HTTP implementation while leveraging RAAF Core's Perplexity common modules for validation, search options, and result formatting.

## User Stories

### As a DSL Agent Developer
As a DSL agent developer, I want to use the PerplexitySearch tool without external gem dependencies so that agent discovery and loading is reliable and doesn't fail with initialization errors.

I should be able to use the tool with confidence that it will load properly in the DSL agent discovery system, without worrying about raaf-tools gem dependency issues.

### As a RAAF Framework Maintainer
As a framework maintainer, I want the PerplexitySearch tool to follow the same self-contained pattern as TavilySearch so that our DSL tools have consistent architecture and minimal external dependencies.

The tool should leverage RAAF Core's common Perplexity code to ensure consistency with PerplexityProvider while remaining self-contained.

## Spec Scope

1. **Remove External Dependencies** - Eliminate dependency on raaf-tools gem and RAAF::Tools::PerplexityTool
2. **Direct HTTP Implementation** - Add direct Net::HTTP calls to Perplexity API following TavilySearch pattern
3. **Leverage Core Common Modules** - Use RAAF::Perplexity::Common, SearchOptions, and ResultParser for consistency
4. **Maintain Compatibility** - Keep the same public API and result structure as current implementation
5. **Comprehensive Testing** - Add unit tests for HTTP implementation and integration tests for common module usage

## Out of Scope

- Changing the public API of the PerplexitySearch tool
- Modifying the tool definition format or parameters
- Adding new features or functionality beyond current implementation
- Changing how DSL agents use the tool
- Modifying RAAF Core's Perplexity common modules

## Expected Deliverable

1. Self-contained PerplexitySearch tool that doesn't require raaf-tools gem
2. Direct HTTP implementation that calls api.perplexity.ai
3. Full integration with RAAF Core common modules for validation and formatting
4. Tests verifying both HTTP functionality and common module integration
5. Documentation updates reflecting the new architecture