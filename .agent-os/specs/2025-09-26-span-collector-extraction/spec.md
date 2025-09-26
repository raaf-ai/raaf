# Spec Requirements Document

> Spec: Span Collector Extraction
> Created: 2025-09-26
> Status: Planning

## Overview

Remove unnecessary tracing code from business classes by extracting span data collection logic into dedicated collector classes. This refactoring eliminates all `collect_span_attributes` and `collect_result_attributes` methods from Agents, Tools, Pipelines, and other traceable components, making these classes focus purely on their core functionality while specialized collectors handle all tracing concerns.

## User Stories

### Clean Architecture for Tracing

As a RAAF developer, I want to remove all tracing code from my business classes, so that Agents, Tools, and Pipelines contain only their essential functionality without any tracing clutter.

The current implementation forces every traceable component to implement `collect_span_attributes` and `collect_result_attributes` methods, polluting business classes with tracing concerns. This unnecessary code violates the Single Responsibility Principle and makes classes harder to understand and maintain. With dedicated collector classes, business components become cleaner and more focused while collectors handle all tracing extraction externally.

### Maintainable Tracing System

As a RAAF maintainer, I want centralized span data collection logic, so that I can modify what gets traced without touching business logic classes.

Currently, changing what data gets collected in spans requires modifying multiple business classes across the codebase. This makes it difficult to maintain consistency and requires understanding how each component implements its collection methods. With dedicated collectors, all span data logic is centralized in one location per component type, making it easier to understand, test, and modify.

## Spec Scope

1. **Base Collector Architecture** - Create abstract base collector class with simplified DSL for declarative span data extraction
2. **Component-Specific Collectors** - Implement collectors for Core Agent, DSL Agent, Tool, Pipeline, and Job components using clean DSL syntax
3. **Naming-Based Discovery** - Build automatic collector discovery using pure naming conventions (no registry needed)
4. **Traceable Module Integration** - Update Traceable module to use collectors via naming-based discovery instead of calling methods on traced objects
5. **Code Removal** - Delete all unnecessary `collect_span_attributes` and `collect_result_attributes` methods from business classes

## Out of Scope

- Backward compatibility with existing collection methods
- Custom collector registration API for external users
- Changes to span data format or structure
- Modifications to span processors or tracers
- Changes to how spans are sent or stored

## Expected Deliverable

1. **Clean Business Classes**: All Agent, Tool, Pipeline, and Job classes contain zero tracing code - no `collect_span_attributes` or `collect_result_attributes` methods
2. **External Data Collection**: Dedicated collector classes handle all span data extraction using clean DSL syntax, completely separated from business logic
3. **Identical Span Output**: Existing test suite passes and span data output remains exactly the same, ensuring no breaking changes for consumers
4. **Reduced Code Complexity**: Business classes are simpler and more focused, with tracing concerns fully externalized

## Spec Documentation

- Tasks: @.agent-os/specs/2025-09-26-span-collector-extraction/tasks.md
- Technical Specification: @.agent-os/specs/2025-09-26-span-collector-extraction/sub-specs/technical-spec.md
- Tests Specification: @.agent-os/specs/2025-09-26-span-collector-extraction/sub-specs/tests.md