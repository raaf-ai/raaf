# Product Mission

> Last Updated: 2025-11-06
> Version: 1.0.0

## Pitch

RAAF Eval is an integrated AI evaluation and testing framework that helps RAAF developers and testers validate agent behavior when changing LLMs, parameters, or prompts by providing comprehensive span analysis, prompt iteration, and RSpec integration.

## Users

### Primary Customers

- **RAAF Core Developers**: Engineers building and maintaining the RAAF framework who need to validate agent behavior across changes
- **RAAF Users**: Developers building AI applications with RAAF who need to test and optimize their agents

### User Personas

**Senior AI Framework Developer** (30-45 years old)
- **Role:** Lead Engineer on RAAF Core Team
- **Context:** Maintains core agent execution, tracing, and provider integration code
- **Pain Points:** Manual testing of agent changes is time-consuming, difficult to validate behavior across multiple LLMs, no systematic way to track regression when updating prompts
- **Goals:** Automate agent testing, validate behavior across LLM providers, catch regressions before production deployment

**AI Application Developer** (25-40 years old)
- **Role:** Software Engineer building AI-powered applications
- **Context:** Uses RAAF to build multi-agent systems for production applications
- **Pain Points:** Difficult to optimize prompts and settings, no visibility into why agents behave differently with parameter changes, manual testing of agent workflows is tedious
- **Goals:** Optimize agent performance, validate agent behavior changes, maintain consistent agent quality across iterations

## The Problem

### Lack of Systematic Agent Testing

RAAF developers and users currently lack tools to systematically test and validate agent behavior when making changes to LLMs, parameters, or prompts. This leads to manual testing, undiscovered regressions, and uncertainty about the impact of changes.

**Our Solution:** Provide an integrated evaluation framework with span selection, prompt iteration, RSpec integration, and comprehensive UI for testing agent behavior systematically.

### No Visibility into Agent Behavior Changes

When developers change LLM providers, model parameters, or prompts, they have no structured way to compare results and understand the impact. This makes optimization difficult and increases the risk of degraded agent performance.

**Our Solution:** Enable side-by-side comparison of agent behavior across different configurations with full tracing data, making it easy to identify improvements or regressions.

### Manual and Time-Consuming Evaluation Process

Testing agents manually by running code, inspecting outputs, and making changes is slow and error-prone. There's no way to save test scenarios or automate evaluation workflows.

**Our Solution:** Integrate evaluation directly into RSpec test suite and provide a web UI for interactive evaluation, enabling both automated and exploratory testing workflows.

## Differentiators

### Integrated with RAAF Tracing

Unlike standalone evaluation tools, RAAF Eval is deeply integrated with RAAF's comprehensive tracing system. This provides automatic access to all span data, including tool calls, handoffs, and model interactions, without requiring additional instrumentation.

### Active Record Integration for Real Applications

RAAF Eval connects evaluation data directly to Active Record models, enabling testing against real application data and tracking evaluation results over time. This bridges the gap between abstract testing and production scenarios.

### RSpec Native Integration

By integrating directly with RSpec, RAAF Eval fits naturally into existing Ruby testing workflows. Developers can run evals alongside unit and integration tests, use familiar RSpec matchers, and integrate into CI/CD pipelines seamlessly.

## Key Features

### Core Features

- **Span Selection Interface**: Browse and select RAAF trace spans to use as evaluation inputs, with filtering by agent, model, time range, and success/failure status
- **Interactive Prompt Editor**: Modify AI settings (model, temperature, max_tokens) and prompts in a web UI, then re-run evaluations to see impact immediately
- **RSpec Test Integration**: Write evaluation test cases using RSpec syntax that can be run alongside other tests in automated CI/CD pipelines
- **Side-by-Side Comparison**: Compare agent outputs across different configurations (different models, parameters, prompts) to identify optimal settings

### Analysis Features

- **Active Record Linking**: Connect evaluation results to specific Active Record models for tracking evaluation history and relating tests to real application data
- **Evaluation Metrics Dashboard**: View aggregate metrics across evaluations including success rates, token usage, latency, and cost per configuration
- **Historical Tracking**: Track agent performance over time as code, prompts, and models evolve to identify trends and regressions
- **Automated Regression Detection**: Flag when new configurations perform worse than baseline evaluations on key metrics

### Collaboration Features

- **Shareable Evaluation Sessions**: Save and share evaluation configurations and results with team members for collaborative optimization
- **Evaluation Result Export**: Export evaluation data to CSV/JSON for external analysis or integration with other tools
