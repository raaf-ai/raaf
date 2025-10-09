# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-10-09-dsl-level-hooks/spec.md

> Created: 2025-10-09
> Version: 1.0.0

## Test Coverage

### Unit Tests

**File: `dsl/spec/raaf/dsl/hooks/dsl_hooks_spec.rb`**

#### `on_context_built` Hook Tests

```ruby
RSpec.describe "DSL Hook: on_context_built", type: :unit do
  let(:agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "ContextTestAgent"
      model "gpt-4o"

      on_context_built do |data|
        @context_data = data[:context]
      end
    end
  end

  it "fires after context assembly" do
    agent = agent_class.new(product_name: "Test Product", company_name: "Test Company")

    # Mock RAAF core to avoid actual AI calls
    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(messages: [{ content: "test response" }], usage: {})
    )

    agent.run

    expect(agent.instance_variable_get(:@context_data)).to be_a(RAAF::DSL::ContextVariables)
    expect(agent.instance_variable_get(:@context_data)[:product_name]).to eq("Test Product")
  end

  it "receives complete context with all variables" do
    agent = agent_class.new(var1: "value1", var2: "value2", var3: "value3")

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(messages: [{ content: "test" }], usage: {})
    )

    agent.run

    context = agent.instance_variable_get(:@context_data)
    expect(context[:var1]).to eq("value1")
    expect(context[:var2]).to eq("value2")
    expect(context[:var3]).to eq("value3")
  end
end
```

#### `on_validation_failed` Hook Tests

```ruby
RSpec.describe "DSL Hook: on_validation_failed", type: :unit do
  let(:agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "ValidationTestAgent"
      model "gpt-4o"

      schema do
        field :results, :array, required: true do
          field :id, :integer, required: true
          field :name, :string, required: true
        end
      end

      on_validation_failed do |data|
        @validation_errors = data[:validation_errors]
        @raw_response = data[:raw_response]
      end
    end
  end

  it "fires when schema validation fails" do
    agent = agent_class.new

    # Mock AI response with invalid schema (missing required field)
    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(
        messages: [{
          content: JSON.generate({
            results: [{ id: 1 }]  # Missing required 'name' field
          })
        }],
        usage: {}
      )
    )

    expect { agent.run }.to raise_error(RAAF::Errors::ValidationError)

    errors = agent.instance_variable_get(:@validation_errors)
    expect(errors).to include(match(/name.*required/i))
  end

  it "receives validation errors and raw response" do
    agent = agent_class.new

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(
        messages: [{
          content: JSON.generate({
            results: [{ id: "not_an_integer", name: "Valid Name" }]
          })
        }],
        usage: {}
      )
    )

    expect { agent.run }.to raise_error(RAAF::Errors::ValidationError)

    raw_response = agent.instance_variable_get(:@raw_response)
    expect(raw_response).to be_present
  end
end
```

#### `on_result_ready` Hook Tests

```ruby
RSpec.describe "DSL Hook: on_result_ready", type: :unit do
  let(:agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "ResultReadyTestAgent"
      model "gpt-4o"

      result_transform do
        field :transformed_field, from: :raw_field
        field :computed_field do |result|
          "Computed: #{result[:raw_data]}"
        end
      end

      on_result_ready do |data|
        @transformed_result = data[:result]
        @timestamp = data[:timestamp]
      end
    end
  end

  it "fires after result transformations complete" do
    agent = agent_class.new

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(
        messages: [{
          content: JSON.generate({
            raw_field: "raw_value",
            raw_data: "test data"
          })
        }],
        usage: {}
      )
    )

    agent.run

    result = agent.instance_variable_get(:@transformed_result)
    expect(result[:transformed_field]).to eq("raw_value")
    expect(result[:computed_field]).to eq("Computed: test data")
  end

  it "receives transformed data not raw AI output" do
    agent = agent_class.new

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(
        messages: [{
          content: JSON.generate({ raw_field: "original" })
        }],
        usage: {}
      )
    )

    agent.run

    result = agent.instance_variable_get(:@transformed_result)
    expect(result[:transformed_field]).to eq("original")
    expect(result[:raw_field]).to be_nil  # Original key removed by transformation
  end

  it "includes timestamp with result" do
    agent = agent_class.new

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(messages: [{ content: JSON.generate({ raw_field: "test" }) }], usage: {})
    )

    agent.run

    timestamp = agent.instance_variable_get(:@timestamp)
    expect(timestamp).to be_a(Time)
    expect(timestamp).to be_within(1.second).of(Time.now)
  end
end
```

#### `on_prompt_generated` Hook Tests

```ruby
RSpec.describe "DSL Hook: on_prompt_generated", type: :unit do
  let(:agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "PromptTestAgent"
      model "gpt-4o"

      instructions "You are a #{role} assistant"

      on_prompt_generated do |data|
        @system_prompt = data[:system_prompt]
        @user_prompt = data[:user_prompt]
      end
    end
  end

  it "fires after prompts are generated" do
    agent = agent_class.new(role: "helpful")

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(messages: [{ content: "response" }], usage: {})
    )

    agent.run("Test query")

    system_prompt = agent.instance_variable_get(:@system_prompt)
    expect(system_prompt).to include("You are a helpful assistant")
  end

  it "receives both system and user prompts" do
    agent = agent_class.new(role: "research")

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(messages: [{ content: "response" }], usage: {})
    )

    agent.run("Analyze this data")

    user_prompt = agent.instance_variable_get(:@user_prompt)
    expect(user_prompt).to include("Analyze this data")
  end
end
```

#### `on_tokens_counted` Hook Tests

```ruby
RSpec.describe "DSL Hook: on_tokens_counted", type: :unit do
  let(:agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "TokensTestAgent"
      model "gpt-4o"

      on_tokens_counted do |data|
        @token_usage = data
      end
    end
  end

  it "fires after token counting" do
    agent = agent_class.new

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(
        messages: [{ content: "response" }],
        usage: {
          input_tokens: 100,
          output_tokens: 50,
          total_tokens: 150
        }
      )
    )

    agent.run

    usage = agent.instance_variable_get(:@token_usage)
    expect(usage[:input_tokens]).to eq(100)
    expect(usage[:output_tokens]).to eq(50)
    expect(usage[:total_tokens]).to eq(150)
  end

  it "includes estimated cost calculation" do
    agent = agent_class.new

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(
        messages: [{ content: "response" }],
        usage: {
          input_tokens: 1000,
          output_tokens: 500,
          total_tokens: 1500
        }
      )
    )

    agent.run

    usage = agent.instance_variable_get(:@token_usage)
    expect(usage[:estimated_cost]).to be_a(Float)
    expect(usage[:estimated_cost]).to be > 0
  end
end
```

### Integration Tests

**File: `dsl/spec/raaf/dsl/integration/dsl_hooks_integration_spec.rb`**

#### Complete Lifecycle with All Hooks

```ruby
RSpec.describe "DSL Hooks Integration", type: :integration do
  let(:agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "FullLifecycleAgent"
      model "gpt-4o"

      schema do
        field :results, :array, required: true
      end

      result_transform do
        field :transformed_results, from: :results
      end

      # Track all hook executions
      on_context_built do |data|
        @hook_sequence ||= []
        @hook_sequence << { hook: :on_context_built, timestamp: Time.now }
      end

      on_prompt_generated do |data|
        @hook_sequence ||= []
        @hook_sequence << { hook: :on_prompt_generated, timestamp: Time.now }
      end

      on_result_ready do |data|
        @hook_sequence ||= []
        @hook_sequence << { hook: :on_result_ready, timestamp: Time.now, data: data[:result] }
      end

      on_tokens_counted do |data|
        @hook_sequence ||= []
        @hook_sequence << { hook: :on_tokens_counted, timestamp: Time.now }
      end
    end
  end

  it "executes all DSL hooks in correct order" do
    agent = agent_class.new

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(
        messages: [{ content: JSON.generate({ results: [1, 2, 3] }) }],
        usage: { input_tokens: 50, output_tokens: 25, total_tokens: 75 }
      )
    )

    agent.run

    sequence = agent.instance_variable_get(:@hook_sequence)
    expect(sequence.map { |s| s[:hook] }).to eq([
      :on_context_built,
      :on_prompt_generated,
      :on_tokens_counted,
      :on_result_ready
    ])
  end

  it "provides transformed data in on_result_ready" do
    agent = agent_class.new

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(
        messages: [{ content: JSON.generate({ results: [1, 2, 3] }) }],
        usage: {}
      )
    )

    agent.run

    sequence = agent.instance_variable_get(:@hook_sequence)
    result_ready_hook = sequence.find { |s| s[:hook] == :on_result_ready }

    expect(result_ready_hook[:data][:transformed_results]).to eq([1, 2, 3])
    expect(result_ready_hook[:data][:results]).to be_nil  # Original key removed
  end
end
```

#### Backward Compatibility Tests

```ruby
RSpec.describe "DSL Hooks Backward Compatibility", type: :integration do
  let(:legacy_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "LegacyAgent"
      model "gpt-4o"

      # Only core hooks - no DSL hooks
      on_agent_end do |result|
        @core_hook_fired = true
        @core_result = result
      end
    end
  end

  it "legacy agents continue working without DSL hooks" do
    agent = legacy_agent_class.new

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(messages: [{ content: "response" }], usage: {})
    )

    expect { agent.run }.not_to raise_error

    expect(agent.instance_variable_get(:@core_hook_fired)).to be true
    expect(agent.instance_variable_get(:@core_result)).to be_present
  end

  it "agents can use both core and DSL hooks" do
    hybrid_agent = Class.new(RAAF::DSL::Agent) do
      agent_name "HybridAgent"
      model "gpt-4o"

      on_agent_end do |result|
        @core_fired = true
      end

      on_result_ready do |data|
        @dsl_fired = true
      end
    end.new

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(messages: [{ content: JSON.generate({ test: "data" }) }], usage: {})
    )

    hybrid_agent.run

    expect(hybrid_agent.instance_variable_get(:@core_fired)).to be true
    expect(hybrid_agent.instance_variable_get(:@dsl_fired)).to be true
  end
end
```

### Mocking Requirements

#### AI Provider Mocking

```ruby
# Mock RAAF::Runner to avoid actual AI calls
RSpec.configure do |config|
  config.before(:each, type: :unit) do
    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(
        messages: [{ content: JSON.generate({ test: "data" }) }],
        usage: { input_tokens: 10, output_tokens: 10, total_tokens: 20 }
      )
    )
  end
end
```

#### Context Mocking

```ruby
# Mock context resolution for isolated hook testing
let(:mock_context) do
  RAAF::DSL::ContextVariables.new.tap do |ctx|
    ctx.set(:product_name, "Test Product")
    ctx.set(:company_name, "Test Company")
  end
end

before do
  allow_any_instance_of(described_class).to receive(:resolve_run_context)
    .and_return(mock_context)
end
```

### Error Handling Tests

```ruby
RSpec.describe "DSL Hook Error Handling", type: :unit do
  let(:agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "ErrorTestAgent"
      model "gpt-4o"

      on_result_ready do |data|
        raise StandardError, "Hook error"
      end
    end
  end

  it "logs hook errors without crashing agent" do
    agent = agent_class.new

    allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
      double(messages: [{ content: JSON.generate({ test: "data" }) }], usage: {})
    )

    # Hook errors should be logged but not crash execution
    expect(RAAF.logger).to receive(:error).with(/Hook error/)

    expect { agent.run }.not_to raise_error
  end
end
```

## Test Execution Strategy

### Test Organization

1. **Unit Tests** - Test each hook in isolation
2. **Integration Tests** - Test complete lifecycle with multiple hooks
3. **Backward Compatibility Tests** - Ensure existing agents work unchanged
4. **Error Handling Tests** - Verify robust error handling

### Test Data

- **Mock AI Responses**: JSON-formatted responses matching expected schemas
- **Mock Context**: Pre-built context objects with test data
- **Mock Token Usage**: Realistic token counts for cost calculation testing

### Coverage Goals

- **Unit Test Coverage**: 100% of new hook code
- **Integration Test Coverage**: All hook combinations tested
- **Edge Case Coverage**: Validation failures, missing data, hook errors
- **Backward Compatibility**: All existing patterns continue working
