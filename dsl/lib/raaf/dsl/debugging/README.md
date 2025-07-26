# RAAF DSL Debugging Tools

This directory contains debugging utilities for the RAAF DSL framework. These tools help developers understand agent execution, inspect prompts, analyze context flow, and debug multi-agent workflows.

## Available Debugging Tools

### 1. ContextInspector
Inspects and displays context variables during agent execution.

### 2. PromptInspector  
Shows actual prompts sent to the AI after variable substitution.

### 3. LLMInterceptor
Intercepts and logs OpenAI API calls for deep visibility.

### 4. SwarmDebugger
Comprehensive debugger for multi-agent workflows with session tracking.

## Integration Example

Here's how to use all debugging tools together for comprehensive debugging:

```ruby
# Complete debugging setup for multi-agent workflow
class DebuggedWorkflow
  def initialize
    @swarm_debugger = RAAF::DSL::Debugging::SwarmDebugger.new(enabled: true)
    @context_inspector = RAAF::DSL::Debugging::ContextInspector.new
    @prompt_inspector = RAAF::DSL::Debugging::PromptInspector.new
    @llm_interceptor = RAAF::DSL::Debugging::LLMInterceptor.new
  end
  
  def run_with_debugging(initial_context = {})
    # Start workflow debugging session
    @swarm_debugger.start_workflow_session("Customer Support Workflow")
    
    # Create agents
    triage_agent = CustomerTriageAgent.new(
      context: initial_context,
      debug: true
    )
    
    specialist_agent = SpecialistAgent.new(
      context: initial_context,
      debug: true
    )
    
    # Run with full debugging
    @llm_interceptor.intercept_openai_calls do
      # Debug first agent
      result1 = @swarm_debugger.debug_agent_execution(triage_agent, initial_context) do
        # Inspect context before execution
        @context_inspector.inspect_context(triage_agent)
        
        # Inspect prompts being used
        @prompt_inspector.inspect_prompts(triage_agent)
        
        # Run the agent
        triage_agent.run
      end
      
      # Check for handoff
      if result1[:handoff_to] == "specialist"
        # Debug handoff
        @swarm_debugger.debug_handoff_decision(
          from_agent: triage_agent,
          to_agent: specialist_agent,
          context_variables: result1[:context_variables],
          reason: "Technical issue requiring specialist"
        )
        
        # Debug second agent
        result2 = @swarm_debugger.debug_agent_execution(specialist_agent, result1[:context_variables]) do
          @context_inspector.inspect_context(specialist_agent)
          @prompt_inspector.inspect_prompts(specialist_agent)
          specialist_agent.run
        end
      end
    end
    
    # End session and get summary
    @swarm_debugger.end_workflow_session
  end
end

# Usage
workflow = DebuggedWorkflow.new
workflow.run_with_debugging(
  user_query: "My payment is failing",
  user_tier: "premium"
)
```

## Debugging Specific Issues

### When Tools Aren't Being Called

```ruby
# Focus on API interception to see tool configurations
interceptor = RAAF::DSL::Debugging::LLMInterceptor.new
interceptor.intercept_openai_calls do
  # The interceptor will log:
  # - Tool definitions sent to OpenAI
  # - Tool choice settings
  # - Any validation warnings
  agent_with_tools.run
end
```

### When Context Is Lost Between Agents

```ruby
# Use context inspector to track context evolution
inspector = RAAF::DSL::Debugging::ContextInspector.new
debugger = RAAF::DSL::Debugging::SwarmDebugger.new(enabled: true)

# The debugger tracks context changes automatically
debugger.start_workflow_session("Context Tracking")
# ... run agents ...
# Context evolution is captured in the session
```

### When Prompts Aren't Working As Expected

```ruby
# Combine prompt and LLM inspection
prompt_inspector = RAAF::DSL::Debugging::PromptInspector.new
llm_interceptor = RAAF::DSL::Debugging::LLMInterceptor.new

llm_interceptor.intercept_openai_calls do
  # See the exact prompt
  prompt_inspector.inspect_prompts(agent)
  
  # See what the AI receives
  result = agent.run
  
  # Compare expected vs actual behavior
end
```

## Best Practices

1. **Enable debugging selectively** - Use debug flags on agents to avoid overwhelming output
2. **Use SwarmDebugger for workflows** - It provides the most comprehensive view
3. **Combine tools strategically** - Each tool has a specific purpose
4. **Check logs in order** - Context → Prompts → API calls → Results
5. **Use structured logging** - The tools output structured data for easier parsing

## Environment Variables

Set these to control debugging output:

```bash
# Rails environment
RAILS_LOG_LEVEL=debug

# Enable agent debug mode globally
RAAF_DEBUG=true

# Control specific debugging aspects
RAAF_DEBUG_PROMPTS=true
RAAF_DEBUG_CONTEXT=true
RAAF_DEBUG_API=true
```