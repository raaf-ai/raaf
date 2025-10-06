# Spec Requirements Document

> Spec: Perplexity Provider
> Created: 2025-10-05
> Status: Planning

## Overview

Implement a Perplexity provider for RAAF that enables web-grounded AI search capabilities through Perplexity's Sonar API. This provider will allow RAAF agents to leverage Perplexity's real-time web search and citation capabilities as a first-class provider, enabling grounded, fact-based responses with web citations.

## User Stories

### Web-Grounded Agent Queries

As a developer, I want to use Perplexity as a provider in RAAF agents, so that my agents can perform web-grounded searches and return factual, cited responses.

**Workflow:**
1. Developer creates a RAAF agent with Perplexity provider
2. Agent receives a query requiring current/factual information
3. Perplexity searches the web and returns grounded response with citations
4. Developer can access search results, citations, and metadata

### Seamless Provider Switching

As a developer, I want to switch between Perplexity and other providers, so that I can choose the best provider for different query types (web-grounded vs. general reasoning).

**Workflow:**
1. Developer configures multiple providers (OpenAI, Anthropic, Perplexity)
2. For factual/current queries, use Perplexity
3. For reasoning/analysis, use OpenAI or Anthropic
4. All use the same RAAF agent interface

## Spec Scope

1. **PerplexityProvider Implementation** - Create a provider class following RAAF's ModelInterface that connects to Perplexity's API
2. **Chat Completion Support** - Implement standard chat completion with Sonar and Sonar Pro models
3. **JSON Schema Support** - Implement response_format parameter for structured outputs using JSON schema
4. **Web Search Integration** - Support web_search_options parameter for controlling search behavior
5. **Citation Handling** - Parse and expose citations/sources from Perplexity responses
6. **Model Support** - Support sonar, sonar-pro, sonar-reasoning-pro, and sonar-deep-research models
7. **DSL Agent Compatibility** - Ensure compatibility with RAAF DSL agents using schema definitions

## Out of Scope

- Function/tool calling support (Perplexity API does not currently support this)
- Multi-agent handoffs (requires function calling)
- Streaming implementation (defer to future iteration)
- Custom embeddings support

## Expected Deliverable

1. Developers can instantiate `RAAF::Models::PerplexityProvider.new` with API key
2. Agents using Perplexity provider can perform web-grounded queries and receive cited responses
3. All tests pass, including provider-specific tests for citation handling

## Spec Documentation

- Tasks: @.agent-os/specs/2025-10-05-perplexity-provider/tasks.md
- Technical Specification: @.agent-os/specs/2025-10-05-perplexity-provider/sub-specs/technical-spec.md
- Tests Specification: @.agent-os/specs/2025-10-05-perplexity-provider/sub-specs/tests.md
