# Agentic Evaluators

Comprehensive guide to RAAF Eval's agentic evaluation capabilities for assessing AI agent task completion and tool usage.

## Overview

Agentic evaluators assess AI agent behavior across two critical dimensions:

1. **Task Completion** - Did the agent successfully complete its assigned task?
2. **Tool Correctness** - Did the agent use tools appropriately and correctly?

These evaluators use LLM-as-judge methodology to evaluate:
- Task goal achievement and output quality
- Tool selection, parameter usage, and sequencing
- Agent execution trace analysis
- Required steps completion

**Key Features:**
- LLM-based evaluation with explainable reasoning
- Three-tier threshold configuration (good/average/bad)
- Comprehensive RSpec matcher integration
- Detailed analysis of task completion and tool usage
- Support for multi-step task evaluation
- Tool sequence and parameter validation

## Quick Start

```ruby
require 'raaf/eval'

# Create field context
field_context = RAAF::Eval::DSL::FieldContext.new(
  field_name: :output,
  value: "Analysis complete with 3 key insights...",
  test_case: nil
)

# Example 1: Task Completion Evaluation
task_evaluator = RAAF::Eval::Evaluators::LLM::TaskCompletion.new

result = task_evaluator.evaluate(
  field_context,
  task_description: "Analyze market trends and provide insights",
  expected_output: "Comprehensive analysis with actionable insights",
  actual_output: "Analysis complete with 3 key insights...",
  required_steps: [
    "Load market data",
    "Identify trends",
    "Generate insights"
  ]
)

puts result[:label]  # => "good"
puts result[:score]  # => 0.87
puts result[:details][:completion_analysis][:goal_achieved]  # => true

# Example 2: Tool Correctness Evaluation
tool_evaluator = RAAF::Eval::Evaluators::LLM::ToolCorrectness.new

result = tool_evaluator.evaluate(
  field_context,
  task_context: "Research weather in Tokyo",
  available_tools: ["weather_api", "web_search", "calculator"],
  tools_used: [
    {
      tool: "weather_api",
      params: { location: "Tokyo", units: "celsius" },
      result: "Sunny, 22°C"
    }
  ],
  expected_tools: ["weather_api"]
)

puts result[:label]  # => "good"
puts result[:score]  # => 0.92
puts result[:details][:tool_selection_analysis]  # => "appropriate tools from available set"

# RSpec Integration
RSpec.describe "My Agent" do
  it "completes tasks successfully" do
    result = task_evaluator.evaluate(field_context, **options)
    expect(result).to have_high_task_completion
    expect(result).to complete_task_successfully
    expect(result).to meet_task_requirements
  end

  it "uses tools correctly" do
    result = tool_evaluator.evaluate(field_context, **options)
    expect(result).to have_correct_tool_usage
    expect(result).to use_tools_correctly
    expect(result).to select_appropriate_tools
  end
end
```

## Core Evaluators

### TaskCompletion

Evaluates whether an AI agent successfully completed its assigned task using LLM-as-judge methodology.

**Score Range:** 0.0 (complete failure) to 1.0 (perfect completion)

**Default Thresholds:**
- Good: ≥ 0.85 (task fully completed with high quality)
- Average: ≥ 0.65 (task mostly completed with minor issues)
- Bad: < 0.65 (significant failures or incomplete task)

**Required Options:**
- `task_description` (String) - Description of task to be completed
- `expected_output` (String) - Expected output or outcome
- `actual_output` (String) - Actual agent output (defaults to field_context.value)

**Optional Options:**
- `required_steps` (Array<String>) - List of required task steps
- `execution_trace` (Hash/String) - Agent execution log or trace
- `good_threshold` (Float) - Override good threshold (0.0-1.0)
- `average_threshold` (Float) - Override average threshold (0.0-1.0)
- `model` (String) - LLM model to use for judging

**Example Usage:**

```ruby
evaluator = RAAF::Eval::Evaluators::LLM::TaskCompletion.new

# Basic usage
result = evaluator.evaluate(
  field_context,
  task_description: "Research and summarize AI trends",
  expected_output: "Comprehensive summary with key trends",
  actual_output: agent_output
)

# With required steps
result = evaluator.evaluate(
  field_context,
  task_description: "Analyze market data",
  expected_output: "Statistical analysis with visualizations",
  actual_output: agent_result,
  required_steps: [
    "Load data",
    "Clean data",
    "Generate insights",
    "Create report"
  ],
  execution_trace: agent_execution_log
)

# With custom thresholds
result = evaluator.evaluate(
  field_context,
  task_description: "Complete the analysis",
  expected_output: "Detailed findings",
  actual_output: output,
  good_threshold: 0.90,
  average_threshold: 0.75
)
```

**Result Structure:**

```ruby
{
  label: "good",
  score: 0.87,
  message: "[GOOD] Task Completion: 87%",
  details: {
    evaluated_field: :output,
    method: "llm_judge",
    task_description: "Analyze market data",
    expected_output: "Statistical analysis with visualizations",
    actual_output: "Analysis complete with findings...",
    required_steps_provided: true,
    required_steps_count: 4,
    execution_trace_provided: true,
    completion_analysis: {
      goal_achieved: true,
      output_quality: "high",
      completeness: "87% of expected elements present",
      steps_completed: "4/4 steps executed successfully",
      issues_found: ["minor formatting inconsistency"],
      reasoning: "Task fully completed with excellent quality, minor formatting issue in section 2"
    },
    completion_percentage: 87,
    evaluation_note: "Task completed successfully with high quality output",
    thresholds: {
      good: 0.85,
      average: 0.65,
      used: "default"
    }
  }
}
```

### ToolCorrectness

Evaluates whether an AI agent used tools correctly and appropriately using LLM-as-judge methodology.

**Score Range:** 0.0 (incorrect tool usage) to 1.0 (perfect tool usage)

**Default Thresholds:**
- Good: ≥ 0.85 (tools used correctly with optimal choices)
- Average: ≥ 0.65 (tools used adequately with minor issues)
- Bad: < 0.65 (significant tool usage errors)

**Required Options:**
- `task_context` (String) - Context/description of the task being performed
- `available_tools` (Array<String>) - List of tools available to agent
- `tools_used` (Array<Hash>) - Tools actually used with parameters and results
  - Format: `[{ tool: "tool_name", params: {...}, result: "..." }, ...]`

**Optional Options:**
- `expected_tools` (Array<String>) - Expected tools to be used
- `tool_sequence_matters` (Boolean) - Whether tool order matters (default: false)
- `tool_capabilities` (Hash) - Description of what each tool does
- `good_threshold` (Float) - Override good threshold (0.0-1.0)
- `average_threshold` (Float) - Override average threshold (0.0-1.0)
- `model` (String) - LLM model to use for judging

**Example Usage:**

```ruby
evaluator = RAAF::Eval::Evaluators::LLM::ToolCorrectness.new

# Basic usage
result = evaluator.evaluate(
  field_context,
  task_context: "Research weather in Tokyo",
  available_tools: ["weather_api", "web_search", "calculator"],
  tools_used: [
    {
      tool: "weather_api",
      params: { location: "Tokyo" },
      result: "Sunny, 22°C"
    }
  ]
)

# With expected tools and sequence
result = evaluator.evaluate(
  field_context,
  task_context: "Calculate quarterly revenue growth",
  available_tools: ["database_query", "calculator", "chart_generator"],
  tools_used: [
    {
      tool: "database_query",
      params: { query: "SELECT revenue FROM quarterly_data" },
      result: "Q1: $100k, Q2: $150k"
    },
    {
      tool: "calculator",
      params: { operation: "growth_rate", values: [100000, 150000] },
      result: "50% growth"
    }
  ],
  expected_tools: ["database_query", "calculator"],
  tool_sequence_matters: true
)

# With tool capabilities
result = evaluator.evaluate(
  field_context,
  task_context: "Analyze customer data",
  available_tools: ["sql_query", "python_script", "data_viz"],
  tools_used: tool_usage_log,
  tool_capabilities: {
    "sql_query" => "Query database for structured data",
    "python_script" => "Run custom analysis scripts",
    "data_viz" => "Generate charts and visualizations"
  }
)
```

**Result Structure:**

```ruby
{
  label: "good",
  score: 0.92,
  message: "[GOOD] Tool Correctness: 92%",
  details: {
    evaluated_field: :tools,
    method: "llm_judge",
    task_context: "Research weather in Tokyo",
    available_tools_count: 3,
    tools_used_count: 1,
    expected_tools_provided: true,
    tool_sequence_matters: false,
    tool_selection_analysis: "appropriate tools from available set",
    parameter_correctness_analysis: "all parameters valid and appropriate",
    sequence_analysis: "logical tool ordering",
    output_handling_analysis: "tool outputs used effectively",
    overall_reasoning: "Excellent tool usage with appropriate selection and correct parameters",
    correctness_percentage: 92,
    evaluation_note: "Tools used correctly with appropriate selection and parameters",
    thresholds: {
      good: 0.85,
      average: 0.65,
      used: "default"
    }
  }
}
```

## RSpec Integration

RAAF Eval provides 12 custom RSpec matchers for agentic evaluation testing:

### TaskCompletion Matchers

#### have_high_task_completion

Validates task completion score meets threshold:

```ruby
result = task_evaluator.evaluate(field_context, **options)

# Default threshold (0.85)
expect(result).to have_high_task_completion

# Custom threshold
expect(result).to have_high_task_completion(min_score: 0.90)
```

#### complete_task_successfully

Validates task goal was achieved:

```ruby
expect(result).to complete_task_successfully
```

#### meet_task_requirements

Validates all required steps were completed:

```ruby
result = task_evaluator.evaluate(
  field_context,
  task_description: "Multi-step analysis",
  expected_output: "Complete report",
  actual_output: output,
  required_steps: ["Load data", "Clean data", "Analyze", "Report"]
)

expect(result).to meet_task_requirements
```

#### be_valid_task_completion_result

Validates task completion result structure:

```ruby
expect(result).to be_valid_task_completion_result
```

#### have_better_task_completion_than

Compares task completion across configurations:

```ruby
baseline = task_evaluator.evaluate(field_context, **baseline_options)
improved = task_evaluator.evaluate(field_context, **improved_options)

expect(improved).to have_better_task_completion_than(baseline)
```

### ToolCorrectness Matchers

#### have_correct_tool_usage

Validates tool usage score meets threshold:

```ruby
result = tool_evaluator.evaluate(field_context, **options)

# Default threshold (0.85)
expect(result).to have_correct_tool_usage

# Custom threshold
expect(result).to have_correct_tool_usage(min_score: 0.90)
```

#### use_tools_correctly

Validates tools were used appropriately:

```ruby
expect(result).to use_tools_correctly
```

#### select_appropriate_tools

Validates appropriate tool selection:

```ruby
expect(result).to select_appropriate_tools
```

#### have_valid_tool_parameters

Validates tool parameters are correct:

```ruby
expect(result).to have_valid_tool_parameters
```

#### have_minimal_tool_issues

Validates tool usage issues are minimal:

```ruby
# Default max: 1
expect(result).to have_minimal_tool_issues

# Custom threshold
expect(result).to have_minimal_tool_issues(max_issues: 2)
```

#### be_valid_tool_correctness_result

Validates tool correctness result structure:

```ruby
expect(result).to be_valid_tool_correctness_result
```

#### have_better_tool_usage_than

Compares tool usage across configurations:

```ruby
baseline = tool_evaluator.evaluate(field_context, **baseline_options)
improved = tool_evaluator.evaluate(field_context, **improved_options)

expect(improved).to have_better_tool_usage_than(baseline)
```

## Common Patterns

### Pattern 1: Full Agent Evaluation

Evaluate both task completion and tool usage:

```ruby
RSpec.describe "MyAgent" do
  let(:field_context) do
    RAAF::Eval::DSL::FieldContext.new(
      field_name: :output,
      value: agent_output,
      test_case: nil
    )
  end

  let(:task_evaluator) { RAAF::Eval::Evaluators::LLM::TaskCompletion.new }
  let(:tool_evaluator) { RAAF::Eval::Evaluators::LLM::ToolCorrectness.new }

  describe "task completion" do
    it "completes assigned tasks" do
      result = task_evaluator.evaluate(
        field_context,
        task_description: "Analyze market trends",
        expected_output: "Comprehensive analysis",
        actual_output: agent_output
      )

      expect(result).to have_high_task_completion
      expect(result).to complete_task_successfully
    end
  end

  describe "tool usage" do
    it "uses tools correctly" do
      result = tool_evaluator.evaluate(
        field_context,
        task_context: "Market analysis",
        available_tools: ["data_query", "analyzer", "reporter"],
        tools_used: agent_tool_log
      )

      expect(result).to have_correct_tool_usage
      expect(result).to use_tools_correctly
      expect(result).to have_minimal_tool_issues
    end
  end
end
```

### Pattern 2: Multi-Step Task Validation

Validate complex multi-step task execution:

```ruby
RSpec.describe "Multi-step Agent" do
  let(:evaluator) { RAAF::Eval::Evaluators::LLM::TaskCompletion.new }

  it "completes all required steps" do
    result = evaluator.evaluate(
      field_context,
      task_description: "Complete data analysis pipeline",
      expected_output: "Statistical report with visualizations",
      actual_output: agent_output,
      required_steps: [
        "Load data from source",
        "Clean and validate data",
        "Perform statistical analysis",
        "Generate visualizations",
        "Create summary report"
      ],
      execution_trace: agent_execution_log
    )

    expect(result).to have_high_task_completion(min_score: 0.90)
    expect(result).to complete_task_successfully
    expect(result).to meet_task_requirements
    expect(result).to be_valid_task_completion_result
  end
end
```

### Pattern 3: Tool Sequence Validation

Validate tool usage order when sequence matters:

```ruby
RSpec.describe "Sequential Tool Agent" do
  let(:evaluator) { RAAF::Eval::Evaluators::LLM::ToolCorrectness.new }

  it "uses tools in correct sequence" do
    result = evaluator.evaluate(
      field_context,
      task_context: "Data processing pipeline",
      available_tools: ["loader", "validator", "processor", "saver"],
      tools_used: [
        { tool: "loader", params: { source: "db" }, result: "data loaded" },
        { tool: "validator", params: { rules: [...] }, result: "validation passed" },
        { tool: "processor", params: { operation: "transform" }, result: "processed" },
        { tool: "saver", params: { destination: "output" }, result: "saved" }
      ],
      expected_tools: ["loader", "validator", "processor", "saver"],
      tool_sequence_matters: true
    )

    expect(result).to have_correct_tool_usage(min_score: 0.90)
    expect(result).to use_tools_correctly
    expect(result).to select_appropriate_tools
    expect(result).to have_valid_tool_parameters
  end
end
```

### Pattern 4: Baseline Comparison

Compare agent improvements across iterations:

```ruby
RSpec.describe "Agent Improvement" do
  let(:task_evaluator) { RAAF::Eval::Evaluators::LLM::TaskCompletion.new }
  let(:tool_evaluator) { RAAF::Eval::Evaluators::LLM::ToolCorrectness.new }

  it "improves task completion over baseline" do
    baseline = task_evaluator.evaluate(
      baseline_field_context,
      task_description: "Analyze trends",
      expected_output: "Trend analysis",
      actual_output: baseline_output
    )

    improved = task_evaluator.evaluate(
      improved_field_context,
      task_description: "Analyze trends",
      expected_output: "Trend analysis",
      actual_output: improved_output
    )

    expect(improved).to have_better_task_completion_than(baseline)
  end

  it "improves tool usage over baseline" do
    baseline = tool_evaluator.evaluate(
      baseline_field_context,
      task_context: "Analysis task",
      available_tools: tools,
      tools_used: baseline_tool_log
    )

    improved = tool_evaluator.evaluate(
      improved_field_context,
      task_context: "Analysis task",
      available_tools: tools,
      tools_used: improved_tool_log
    )

    expect(improved).to have_better_tool_usage_than(baseline)
  end
end
```

### Pattern 5: Quality Monitoring

Monitor agent quality across test suite:

```ruby
RSpec.describe "Agent Quality Monitoring" do
  let(:task_evaluator) { RAAF::Eval::Evaluators::LLM::TaskCompletion.new }
  let(:tool_evaluator) { RAAF::Eval::Evaluators::LLM::ToolCorrectness.new }

  shared_examples "high quality agent" do
    it "maintains high task completion" do
      result = task_evaluator.evaluate(
        field_context,
        task_description: task_description,
        expected_output: expected_output,
        actual_output: agent_output
      )

      expect(result).to have_high_task_completion(min_score: 0.85)
      expect(result).to complete_task_successfully
    end

    it "maintains correct tool usage" do
      result = tool_evaluator.evaluate(
        field_context,
        task_context: task_description,
        available_tools: available_tools,
        tools_used: tool_log
      )

      expect(result).to have_correct_tool_usage(min_score: 0.85)
      expect(result).to use_tools_correctly
    end
  end

  describe "simple tasks" do
    let(:task_description) { "Simple analysis" }
    let(:expected_output) { "Basic report" }
    it_behaves_like "high quality agent"
  end

  describe "complex tasks" do
    let(:task_description) { "Complex multi-step analysis" }
    let(:expected_output) { "Comprehensive report with insights" }
    it_behaves_like "high quality agent"
  end
end
```

## Threshold Configuration

### Understanding Thresholds

Agentic evaluators use a three-tier threshold system:

- **Good Threshold** (default: 0.85) - Excellent task completion or tool usage
- **Average Threshold** (default: 0.65) - Acceptable performance with minor issues
- **Bad** (< average threshold) - Significant failures or errors

### Threshold Precedence

Thresholds are resolved in this order:

1. **Call-time options** (highest priority)
2. **Instance initialization**
3. **Class constants** (DEFAULT_GOOD_THRESHOLD, DEFAULT_AVERAGE_THRESHOLD)

### Configuration Examples

```ruby
# Method 1: Call-time configuration (highest precedence)
result = evaluator.evaluate(
  field_context,
  task_description: "Task",
  expected_output: "Output",
  actual_output: output,
  good_threshold: 0.90,      # Override for this call only
  average_threshold: 0.75
)

# Method 2: Instance initialization
evaluator = RAAF::Eval::Evaluators::LLM::TaskCompletion.new(
  good_threshold: 0.90,
  average_threshold: 0.75
)
result = evaluator.evaluate(field_context, **options)

# Method 3: Subclass with custom defaults
class StrictTaskCompletion < RAAF::Eval::Evaluators::LLM::TaskCompletion
  DEFAULT_GOOD_THRESHOLD = 0.95
  DEFAULT_AVERAGE_THRESHOLD = 0.80
end

evaluator = StrictTaskCompletion.new
result = evaluator.evaluate(field_context, **options)
```

### Best Practices

**For Task Completion:**
- Production agents: good ≥ 0.85, average ≥ 0.65
- Critical tasks: good ≥ 0.95, average ≥ 0.80
- Experimental agents: good ≥ 0.75, average ≥ 0.50

**For Tool Correctness:**
- Production agents: good ≥ 0.85, average ≥ 0.65
- Tool-heavy workflows: good ≥ 0.90, average ≥ 0.70
- Simple tool usage: good ≥ 0.80, average ≥ 0.60

## Understanding Agentic Metrics

### Task Completion Metrics

**Goal Achievement (Boolean)**
- **True**: Agent successfully completed the assigned task
- **False**: Task failed or incomplete
- **Impact**: Primary indicator of agent success

**Output Quality (String: "high" / "medium" / "low")**
- **High**: Output meets or exceeds expectations
- **Medium**: Acceptable output with minor issues
- **Low**: Significant quality problems
- **Impact**: Differentiates between barely passing and excellent completion

**Completeness (String: percentage)**
- **Format**: "87% of expected elements present"
- **Calculation**: Coverage of expected output elements
- **Impact**: Quantifies how much of the expected output was delivered

**Steps Completed (String: "X/Y steps")**
- **Format**: "4/4 steps executed successfully"
- **Applies**: Only when required_steps provided
- **Impact**: Validates process adherence

### Tool Correctness Metrics

**Tool Selection Analysis (String)**
- **Good**: "appropriate tools from available set"
- **Bad**: "some invalid tool selections"
- **Impact**: Validates agent chose correct tools for task

**Parameter Correctness (String)**
- **Good**: "parameters provided for all tools"
- **Bad**: "some tools missing parameters"
- **Impact**: Ensures tools called with valid parameters

**Sequence Analysis (String)**
- **Critical**: "tool sequence evaluated" (when sequence matters)
- **Not Critical**: "sequence not critical"
- **Impact**: Validates logical tool ordering

**Output Handling (String)**
- **Good**: "all tools produced results"
- **Bad**: "some tools missing results"
- **Impact**: Ensures tool results properly captured

### Interpretation Guide

**Score Ranges:**
- **0.95 - 1.00**: Exceptional performance, no issues
- **0.85 - 0.94**: Excellent performance, minor improvements possible
- **0.70 - 0.84**: Good performance, some optimization needed
- **0.50 - 0.69**: Acceptable performance, significant issues present
- **0.30 - 0.49**: Poor performance, major problems
- **0.00 - 0.29**: Failure, task largely incomplete or tools misused

## Implementation Status

### Current Status (Phase 4 - Agentic Evaluators)

**Completed:**
- ✅ TaskCompletion evaluator with LLM-as-judge (mock implementation)
- ✅ ToolCorrectness evaluator with LLM-as-judge (mock implementation)
- ✅ 12 RSpec matchers for agentic evaluation
- ✅ Comprehensive test coverage (71 tests passing)
- ✅ Three-tier threshold configuration
- ✅ Detailed result structures with analysis

**Mock Implementation Status:**

Both evaluators currently use heuristic-based mock implementations:

**TaskCompletion Mock:**
- Term coverage analysis (task description keywords in output)
- Length adequacy scoring (output length vs expected)
- Required steps mention detection
- Normalized scoring (0.4-0.95 range)

**ToolCorrectness Mock:**
- Expected tool coverage calculation
- Tool validity checking (used tools in available set)
- Parameter presence validation
- Result availability verification
- Normalized scoring (0.45-0.95 range)

**TODO: Replace with actual RAAF LLM calls:**
```ruby
# Current (mock):
def llm_judge_task_completion(...)
  # TODO: Replace with actual RAAF LLM call
  mock_task_completion_evaluation(...)
end

# Future (actual):
def llm_judge_task_completion(...)
  prompt = build_task_completion_prompt(...)
  response = RAAF::Models::OpenAI.chat(
    model: model || "gpt-4o",
    messages: [
      { role: "system", content: prompt }
    ]
  )
  parse_llm_response(response)
end
```

### Comparison with DeepEval

RAAF Eval's agentic evaluators are inspired by but differ from DeepEval (Python):

**Similar Concepts:**
- LLM-as-judge evaluation methodology
- Task completion assessment
- Tool usage validation
- Explainable AI reasoning

**RAAF Enhancements:**
- Ruby/RSpec native integration
- Three-tier threshold configuration with precedence
- Execution trace analysis support
- Tool sequence validation
- Comprehensive RSpec matchers (12 vs DeepEval's limited set)
- Detailed analysis structures

**Different Implementation:**
- RAAF uses structured evaluation prompts
- Explicit tool capabilities documentation
- Parameter and result validation
- Better integration with RAAF tracing ecosystem

## Best Practices

### 1. Provide Complete Task Context

```ruby
# ✅ Good - Complete context
result = task_evaluator.evaluate(
  field_context,
  task_description: "Analyze Q4 sales data and identify top 3 growth opportunities",
  expected_output: "Detailed report with specific recommendations and supporting data",
  actual_output: agent_output,
  required_steps: ["Load Q4 data", "Analyze trends", "Identify opportunities", "Generate report"]
)

# ❌ Bad - Vague context
result = task_evaluator.evaluate(
  field_context,
  task_description: "Analyze data",
  expected_output: "Report",
  actual_output: agent_output
)
```

### 2. Document Tool Capabilities

```ruby
# ✅ Good - Documented capabilities
result = tool_evaluator.evaluate(
  field_context,
  task_context: "Customer data analysis",
  available_tools: ["sql_query", "python_script", "data_viz"],
  tools_used: tool_log,
  tool_capabilities: {
    "sql_query" => "Query customer database for structured data",
    "python_script" => "Run custom pandas analysis scripts",
    "data_viz" => "Generate matplotlib charts and visualizations"
  }
)

# ❌ Bad - No capabilities
result = tool_evaluator.evaluate(
  field_context,
  task_context: "Analysis",
  available_tools: ["tool1", "tool2"],
  tools_used: tool_log
)
```

### 3. Validate Tool Sequence When It Matters

```ruby
# ✅ Good - Sequence validation for pipelines
result = tool_evaluator.evaluate(
  field_context,
  task_context: "ETL pipeline",
  available_tools: ["extract", "transform", "load"],
  tools_used: tool_log,
  tool_sequence_matters: true,  # Order is critical
  expected_tools: ["extract", "transform", "load"]
)

# ✅ Also Good - Skip sequence when order doesn't matter
result = tool_evaluator.evaluate(
  field_context,
  task_context: "Data gathering",
  available_tools: ["api1", "api2", "api3"],
  tools_used: tool_log,
  tool_sequence_matters: false  # Parallel API calls
)
```

### 4. Use Execution Traces for Complex Tasks

```ruby
# ✅ Good - Provide execution trace
result = task_evaluator.evaluate(
  field_context,
  task_description: "Multi-step analysis",
  expected_output: "Complete report",
  actual_output: agent_output,
  execution_trace: {
    steps: ["init", "load", "process", "output"],
    timing: { total_ms: 1250, load_ms: 200, process_ms: 1000 },
    state_changes: [...]
  }
)
```

### 5. Compare Baseline for Improvements

```ruby
# ✅ Good - Track improvements
baseline = task_evaluator.evaluate(baseline_field_context, **baseline_options)
improved = task_evaluator.evaluate(improved_field_context, **improved_options)

RSpec.describe "Agent Improvements" do
  it "shows measurable task completion improvement" do
    expect(improved).to have_better_task_completion_than(baseline)
  end

  it "shows measurable tool usage improvement" do
    baseline_tool = tool_evaluator.evaluate(baseline_field_context, **baseline_tool_options)
    improved_tool = tool_evaluator.evaluate(improved_field_context, **improved_tool_options)

    expect(improved_tool).to have_better_tool_usage_than(baseline_tool)
  end
end
```

### 6. Set Appropriate Thresholds for Context

```ruby
# ✅ Good - Context-appropriate thresholds

# Critical production agent - strict thresholds
strict_evaluator = RAAF::Eval::Evaluators::LLM::TaskCompletion.new(
  good_threshold: 0.95,
  average_threshold: 0.85
)

# Experimental agent - lenient thresholds
experimental_evaluator = RAAF::Eval::Evaluators::LLM::TaskCompletion.new(
  good_threshold: 0.75,
  average_threshold: 0.55
)

# Standard agent - default thresholds
standard_evaluator = RAAF::Eval::Evaluators::LLM::TaskCompletion.new
```

### 7. Validate Complete Tool Information

```ruby
# ✅ Good - Complete tool information
tools_used = [
  {
    tool: "weather_api",
    params: { location: "Tokyo", units: "celsius", lang: "en" },  # All params
    result: "Sunny, 22°C, humidity 65%"  # Complete result
  },
  {
    tool: "translator",
    params: { text: "Sunny, 22°C", target_lang: "ja" },
    result: "晴れ、22°C"
  }
]

result = tool_evaluator.evaluate(
  field_context,
  task_context: "Get Tokyo weather in Japanese",
  available_tools: ["weather_api", "translator"],
  tools_used: tools_used
)

# ❌ Bad - Incomplete tool information
tools_used = [
  { tool: "api", params: {}, result: "" }  # Missing critical information
]
```

## Next Steps

1. **Replace Mock Implementations**: Integrate actual RAAF LLM calls for production use
2. **Add Execution Trace Parsing**: Enhanced analysis of agent execution logs
3. **Tool Dependency Validation**: Check tool dependencies and prerequisites
4. **Cost Tracking**: Track evaluation costs for LLM-as-judge calls
5. **Async Evaluation**: Support asynchronous evaluation for large agent logs

## Related Documentation

- [LLM Evaluators](LLM_EVALUATORS.md) - DeepEval-inspired LLM evaluation
- [G-Eval Framework](G_EVAL.md) - Custom criteria evaluation
- [RAG Evaluators](RAG_EVALUATORS.md) - RAG-specific metrics
- [RSpec Integration](../RSPEC_INTEGRATION.md) - Complete RSpec matcher reference
