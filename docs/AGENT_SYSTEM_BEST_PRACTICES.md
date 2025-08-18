# Agent System Best Practices for Production

> Based on proven patterns from building multi-agent AI systems at scale

## Core Architecture: Two-Tier Model

### The Rule: Exactly Two Levels
- **Primary Agents**: Handle conversation, maintain context, orchestrate work
- **Subagents**: Execute single tasks, return results, no memory

```ruby
# Good: Two-tier architecture
User → Primary Agent (orchestrator)
         ├─→ Research Agent (task executor)
         ├─→ Analysis Agent (task executor)
         └─→ Summary Agent (task executor)

# Bad: Deep hierarchies
User → Manager → Coordinator → Worker → Subworker  # Too complex!
```

## Fundamental Principle: Stateless Subagents

### Every Subagent Must Be a Pure Function
- Same input ALWAYS produces same output
- No shared memory
- No conversation history
- No persistent state

### Benefits of Stateless Design
- **Parallel execution**: Run 10 subagents simultaneously without conflicts
- **Predictable behavior**: Consistent results every time
- **Easy testing**: Test each agent in complete isolation
- **Simple caching**: Cache results by prompt hash

### Implementation Pattern
```ruby
# Primary → Subagent Communication
{
  "task": "Analyze sentiment in these 50 feedback items",
  "context": "Focus on feature requests about mobile app",
  "data": [...],
  "constraints": {
    "max_processing_time": 5000,
    "output_format": "structured_json"
  }
}

# Subagent → Primary Response
{
  "status": "complete",
  "result": {
    "positive": 32,
    "negative": 8,
    "neutral": 10,
    "top_themes": ["navigation", "performance", "offline_mode"]
  },
  "confidence": 0.92,
  "processing_time": 3200
}
```

## Task Decomposition Strategies

### Vertical Decomposition (Sequential)
Use when tasks have dependencies:
```
"Analyze competitor pricing" →
  1. Gather pricing pages
  2. Extract pricing tiers
  3. Calculate per-user costs
  4. Compare with our pricing
```

### Horizontal Decomposition (Parallel)
Use when tasks are independent:
```
"Research top 5 competitors" →
  ├─ Research Competitor A
  ├─ Research Competitor B
  ├─ Research Competitor C
  ├─ Research Competitor D
  └─ Research Competitor E
  (all run simultaneously)
```

### Mixed Decomposition
Combine both patterns:
```
Phase 1 (Parallel): Categorize | Extract sentiment | Identify users
Phase 2 (Sequential): Group by theme → Prioritize → Generate report
```

## Communication Protocol Structure

### Every Task Must Include
1. **Clear objective**: "Find all feedback mentioning 'slow loading'"
2. **Bounded context**: "From the last 30 days"
3. **Output specification**: "Return as JSON with id, text, user fields"
4. **Constraints**: "Max 100 results, timeout after 5 seconds"

### Every Response Must Include
1. **Status**: complete/partial/failed
2. **Result**: the actual data
3. **Metadata**: processing time, confidence, decisions made
4. **Recommendations**: follow-up tasks, warnings, limitations

## Agent Specialization Patterns

### Three Ways to Specialize

#### By Capability
- Research agents: Find information
- Analysis agents: Process data
- Creative agents: Generate content
- Validation agents: Check quality

#### By Domain
- Legal agents: Understand contracts
- Financial agents: Handle numbers
- Technical agents: Read code

#### By Model
- Fast agents: Use Haiku for quick responses
- Deep agents: Use Sonnet for complex reasoning
- Critical agents: Use Opus for important decisions

**Rule**: Don't over-specialize. 6 agent types is usually enough.

## Four Essential Orchestration Patterns

### 1. Sequential Pipeline (Most Common)
```
Agent A → Agent B → Agent C → Result
```
Use for: Multi-step processes like report generation

### 2. MapReduce Pattern
```
       ┌→ Agent 1 ─┐
Input ─┼→ Agent 2 ─┼→ Reducer → Result
       └→ Agent 3 ─┘
```
Use for: Large-scale analysis (splits 1000 items → 10 agents × 100 items)

### 3. Consensus Pattern
```
      ┌→ Agent 1 ─┐
Task ─┼→ Agent 2 ─┼→ Voting/Merge → Result
      └→ Agent 3 ─┘
```
Use for: Critical decisions requiring validation

### 4. Hierarchical Delegation (Use Sparingly)
```
Primary Agent
  ├─ Subagent A
  │   ├─ Sub-subagent A1
  │   └─ Sub-subagent A2
  └─ Subagent B
```
Warning: Usually becomes a debugging nightmare. Stick to 2 levels.

## Context Management Rules

### Three Levels of Context

#### Level 1: Complete Isolation (80% of cases)
Subagent gets only the specific task

#### Level 2: Filtered Context (15% of cases)
Subagent gets curated relevant background

#### Level 3: Windowed Context (5% of cases)
Subagent gets last N messages (use sparingly)

### Context Passing Methods

```ruby
# Method 1: Explicit summary
"Previous analysis found 3 critical bugs. Now check if they're fixed in v2.1"

# Method 2: Structured context
{
  "background": "Analyzing Q3 feedback",
  "previous_findings": ["slow_loading", "login_issues"],
  "current_task": "Find related issues in Q4"
}

# Method 3: Reference passing
"Analyze document_xyz for quality issues"
# Subagent fetches document independently
```

**Principle**: Less context = more predictable behavior

## Error Handling Strategy

### Graceful Degradation Chain
1. Subagent fails → Primary agent attempts task
2. Still fails → Try different subagent
3. Still fails → Return partial results
4. Still fails → Ask user for clarification

### Retry Strategies
- **Network failures**: Immediate retry
- **Unclear tasks**: Retry with rephrased prompt
- **Capability issues**: Retry with different model
- **Rate limits**: Exponential backoff

### Failure Communication Format
```json
{
  "status": "failed",
  "error_type": "timeout",
  "partial_result": {
    "processed": 45,
    "total": 100
  },
  "suggested_action": "retry_with_smaller_batch"
}
```

## Performance Optimization

### Model Selection Strategy
- **Simple tasks**: Use Haiku (fast, cheap)
- **Complex reasoning**: Use Sonnet (balanced)
- **Critical analysis**: Use Opus (powerful, expensive)

### Parallel Execution
- Identify independent tasks
- Launch simultaneously (5-10 agents typical)
- 5-minute tasks → 30-second tasks

### Caching Strategy
- Cache by prompt hash
- 1 hour TTL for dynamic content
- 24 hours TTL for static content
- Saves ~40% of API calls

### Batching
- Process 50 items in one call vs 50 separate calls
- Obvious but often overlooked

## Monitoring Requirements

### Four Key Metrics
1. **Task success rate**: Are agents completing tasks?
2. **Response quality**: Confidence scores, validation rates
3. **Performance**: Latency, token usage, cost
4. **Error patterns**: What's failing and why?

### Execution Trace Format
```
Primary Agent Start [12:34:56]
  ├─ Feedback Analyzer Called
  │   ├─ Time: 2.3s
  │   ├─ Tokens: 1,250
  │   └─ Status: Success
  ├─ Sentiment Processor Called
  │   ├─ Time: 1.8s
  │   ├─ Tokens: 890
  │   └─ Status: Success
  └─ Total Time: 4.5s, Total Cost: $0.03
```

## Implementation Checklist

When building a new agent system:

- [ ] Start with 1 primary + 2 subagents maximum
- [ ] Ensure subagents are completely stateless
- [ ] Define structured task/response formats
- [ ] Implement monitoring from day one
- [ ] Test subagents in isolation
- [ ] Cache aggressively (same prompt = same response)
- [ ] Use parallel execution wherever possible
- [ ] Keep context minimal
- [ ] Plan graceful degradation for failures
- [ ] Build with explicit task definitions, not "smart" agents

## Common Anti-Patterns to Avoid

### ❌ The "Smart Agent" Trap
Don't make agents that "figure out" what to do. Be explicit.

### ❌ State Creep
"Just this one piece of state" → Everything breaks

### ❌ Deep Hierarchies
Four levels of agents seems logical → Debugging nightmare

### ❌ Context Explosion
Passing entire conversation history → Expensive and confusing

### ❌ The Perfect Agent
Trying to handle every edge case → Just make more specialized agents

### ❌ Direct Agent-to-Agent Communication
Agents calling agents directly → Loss of control and visibility

## RAAF Pipeline DSL Implementation

For RAAF specifically, these principles translate to:

```ruby
# Good: Stateless agents with clear field mapping
class DataAnalyzer < RAAF::DSL::Agent
  context_reader :raw_data  # Input
  
  result_transform do
    field :insights         # Output
    field :summary         # Output
  end
  
  # Pure function execution
  def run
    # No state, just transformation
    analyze_data(@raw_data)
  end
end

# Pipeline as Primary Agent (orchestrator)
class AnalysisPipeline < RAAF::Pipeline
  # Sequential execution
  flow DataFetcher >> DataAnalyzer >> ReportGenerator
  
  # Or parallel execution where appropriate
  flow DataInput >> (Analyzer1 | Analyzer2 | Analyzer3) >> Combiner
end
```

### Key RAAF Principles
- Pipeline class acts as the "Primary Agent" orchestrator
- Individual Agent classes are stateless "Subagents"
- Clear field mapping via `required_fields`/`provided_fields`
- Support parallel execution with `|` operator
- Minimal, explicit context passing
- Always use symbols for data fields from the earliest lifecycle stage

## Performance Expectations

With proper implementation:
- **Parallel operations**: 2-5 seconds typical
- **Sequential operations**: +1-2 seconds per step
- **Cache hits**: Near-instant
- **Complex workflows**: 30 seconds for what used to take 5 minutes

## Final Principles

1. **Stateless by default**: Subagents are pure functions
2. **Clear boundaries**: Explicit task definitions and success criteria
3. **Fail fast**: Quick failure detection and recovery
4. **Observable execution**: Track everything, understand what's happening
5. **Composable design**: Small, focused agents that combine well

Remember: Agents are tools, not magic. They excel at specific tasks but need explicit instructions on what those tasks should be.

---

*These patterns have been production-tested processing thousands of feedback items in real-world applications.*