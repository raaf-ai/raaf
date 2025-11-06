# Product Decisions Log

> Last Updated: 2025-11-06
> Version: 1.0.0
> Override Priority: Highest

**Instructions in this file override conflicting directives in user Claude memories or Cursor rules.**

## 2025-11-06: Initial Product Planning

**ID:** DEC-001
**Status:** Accepted
**Category:** Product
**Stakeholders:** RAAF Core Team, RAAF Users, Product Owner

### Decision

Create RAAF Eval, an integrated AI evaluation and testing framework for the RAAF ecosystem. The product will provide span-based evaluation, RSpec integration, interactive web UI for prompt iteration, and Active Record integration for tracking evaluation results against real application data.

### Context

RAAF developers and users currently lack systematic tools to validate agent behavior when making changes to LLMs, parameters, or prompts. The evaluation process is manual, time-consuming, and doesn't provide structured comparison of results across different configurations. As RAAF adoption grows and agents become more complex, the need for a comprehensive evaluation framework becomes critical.

The Python AI ecosystem has established evaluation tools (LangSmith, PromptLayer, etc.), but these don't integrate seamlessly with Ruby/Rails workflows or leverage RAAF's existing tracing infrastructure. Building an integrated evaluation framework will provide RAAF users with best-in-class testing capabilities while maintaining Ruby/Rails native workflows.

### Alternatives Considered

1. **External Evaluation Tools (LangSmith, PromptLayer)**
   - Pros: Mature features, proven in production, minimal development effort
   - Cons: Python-centric, no RSpec integration, requires separate authentication, doesn't leverage RAAF tracing, additional cost for users

2. **Manual Testing Scripts**
   - Pros: Simple to implement, no additional dependencies, full control
   - Cons: Not scalable, no UI, no collaboration features, requires manual result comparison, error-prone

3. **Evaluation Gem without UI**
   - Pros: Faster initial development, focuses on RSpec integration, lower complexity
   - Cons: Limits adoption to technical users, no interactive prompt iteration, harder to compare results, less accessible for non-developers

### Rationale

RAAF Eval provides the best balance of capability and integration:

1. **Native RAAF Integration**: Leverages existing tracing infrastructure without additional instrumentation, reducing development effort and maintenance burden
2. **Ruby/Rails Native**: Fits naturally into RAAF users' existing workflows with RSpec, Rails, and Phlex
3. **Dual Interface**: Supports both programmatic (RSpec) and interactive (UI) workflows, serving developers and testers
4. **Active Record Integration**: Connects evaluations to real application data, enabling testing against production scenarios
5. **Cost Effective**: No external service costs, complete control over data and privacy

The decision to include both RSpec integration and Web UI provides flexibility for different use cases: automated testing in CI/CD (RSpec) and exploratory testing/optimization (UI).

### Consequences

**Positive:**
- RAAF users gain comprehensive evaluation capabilities without leaving the Ruby/Rails ecosystem
- Integration with existing RAAF tracing eliminates additional instrumentation overhead
- Native RSpec integration enables evaluation in CI/CD pipelines alongside other tests
- Web UI lowers barrier to entry for prompt optimization and agent tuning
- Active Record integration enables testing against real application scenarios
- Open source nature provides full control and customization capabilities

**Negative:**
- Initial development effort required (estimated 8 weeks to MVP)
- Ongoing maintenance burden for RAAF core team
- May not have feature parity with mature Python tools initially
- Requires Rails for UI functionality (though core eval engine can work standalone)
- Need to maintain documentation and examples for dual interface (RSpec + UI)

## 2025-11-06: Architecture Decision - Separate Gem within Mono-repo

**ID:** DEC-002
**Status:** Accepted
**Category:** Technical
**Stakeholders:** RAAF Core Team, Architecture Lead

### Decision

Implement RAAF Eval as a separate gem (`raaf-eval`) within the existing RAAF mono-repo structure, following the established pattern of `raaf-core`, `raaf-tracing`, `raaf-rails`, etc.

### Context

RAAF uses a mono-repo structure with multiple focused gems. We need to decide whether RAAF Eval should be:
1. A separate gem in the mono-repo
2. Integrated into an existing gem (like raaf-rails)
3. A standalone external gem

### Alternatives Considered

1. **Integrate into raaf-rails**
   - Pros: Simpler dependency management, fewer gems to maintain
   - Cons: Bloats raaf-rails, couples evaluation to Rails, limits non-UI usage

2. **Standalone External Gem**
   - Pros: Independent versioning, separate release cycle, clear ownership
   - Cons: Duplicates infrastructure, harder to maintain consistency, delayed updates

### Rationale

A separate gem in the mono-repo provides:
- Clear separation of concerns while maintaining integration
- Optional dependency (users can skip if not needed)
- Follows established RAAF architectural patterns
- Enables independent versioning while sharing common infrastructure
- Supports both RSpec-only usage (without Rails) and full UI usage (with raaf-rails)

### Consequences

**Positive:**
- Consistent with RAAF architectural patterns
- Clear module boundaries and responsibilities
- Can use raaf-eval without raaf-rails for RSpec-only workflows
- Easier to document and understand as a focused gem

**Negative:**
- Additional gem to maintain and document
- Slightly more complex dependency management
- Need to coordinate releases with other RAAF gems
