# Tests Specification: Lazy Tool Loading and DSL Consolidation

> Created: 2025-10-22
> Version: 1.0.0
> Spec: @.agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation/spec.md

## Overview

This document specifies comprehensive test coverage for the lazy tool loading and DSL consolidation feature. All tests follow TDD principles with RSpec.

## Test Categories

### 1. Unit Tests
- Tool resolution logic
- Caching mechanism
- Error handling
- Thread-local storage

### 2. Integration Tests
- Agent initialization with tools
- Tool building from configuration
- Multi-tool scenarios
- Rails eager loading simulation

### 3. Performance Tests
- Resolution timing benchmarks
- Cache effectiveness
- Memory usage

### 4. Regression Tests
- Backward compatibility breakage detection
- Existing agent classes

## Test Files Structure

```
dsl/spec/
├── raaf/dsl/
│   ├── agent_tool_integration_spec.rb  # Unit tests for tool method
│   ├── agent_initialization_spec.rb    # Integration tests for initialize
│   └── tool_resolution_spec.rb         # Resolution logic tests
├── lib/
│   └── raaf/tool_registry_spec.rb      # ToolRegistry unit tests
└── integration/
    ├── eager_loading_spec.rb           # Rails eager loading scenarios
    └── performance_spec.rb             # Benchmark tests
```

## Unit Test Specifications

### 1. AgentToolIntegration Specs

**File:** `dsl/spec/raaf/dsl/agent_tool_integration_spec.rb`

```ruby
RSpec.describe RAAF::DSL::AgentToolIntegration do
  let(:agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "TestAgent"
    end
  end

  describe ".tool" do
    context "with symbol identifier" do
      it "stores tool configuration without resolving" do
        agent_class.tool :web_search

        config = agent_class._tools_config.first
        expect(config[:identifier]).to eq(:web_search)
        expect(config[:tool_class]).to be_nil
        expect(config[:resolution_deferred]).to be true
      end

      it "supports options hash" do
        agent_class.tool :web_search, max_results: 20

        config = agent_class._tools_config.first
        expect(config[:options]).to eq(max_results: 20)
      end

      it "supports configuration block" do
        agent_class.tool :web_search do
          max_results 20
          api_key "test_key"
        end

        config = agent_class._tools_config.first
        expect(config[:options][:max_results]).to eq(20)
        expect(config[:options][:api_key]).to eq("test_key")
      end
    end

    context "with direct class reference" do
      let(:tool_class) { Class.new }

      it "stores class as identifier" do
        agent_class.tool tool_class

        config = agent_class._tools_config.first
        expect(config[:identifier]).to eq(tool_class)
        expect(config[:resolution_deferred]).to be true
      end
    end

    context "with multiple tools" do
      it "stores all configurations" do
        agent_class.tool :web_search
        agent_class.tool :file_search
        agent_class.tool :calculator

        expect(agent_class._tools_config.length).to eq(3)
        identifiers = agent_class._tools_config.map { |c| c[:identifier] }
        expect(identifiers).to eq([:web_search, :file_search, :calculator])
      end
    end
  end

  describe ".tools" do
    it "adds multiple tools at once" do
      agent_class.tools :web_search, :file_search, :calculator

      expect(agent_class._tools_config.length).to eq(3)
    end

    it "supports shared options" do
      agent_class.tools :web_search, :file_search, max_results: 10

      agent_class._tools_config.each do |config|
        expect(config[:options][:max_results]).to eq(10)
      end
    end
  end

  describe "removed methods" do
    it "raises NoMethodError for uses_tool" do
      expect { agent_class.uses_tool :web_search }.to raise_error(NoMethodError)
    end

    it "raises NoMethodError for uses_tools" do
      expect { agent_class.uses_tools :web_search }.to raise_error(NoMethodError)
    end

    it "raises NoMethodError for uses_native_tool" do
      expect { agent_class.uses_native_tool :web_search }.to raise_error(NoMethodError)
    end
  end
end
```

### 2. Agent Initialization Specs

**File:** `dsl/spec/raaf/dsl/agent_initialization_spec.rb`

```ruby
RSpec.describe RAAF::DSL::Agent, "#initialize" do
  let(:mock_tool_class) { Class.new }

  before do
    # Mock ToolRegistry.resolve
    allow(RAAF::ToolRegistry).to receive(:resolve)
      .with(:web_search)
      .and_return(mock_tool_class)

    allow(mock_tool_class).to receive(:new).and_return(double("tool_instance"))
  end

  context "with tools defined" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        tool :web_search
      end
    end

    it "resolves tools during initialization" do
      agent = agent_class.new

      expect(RAAF::ToolRegistry).to have_received(:resolve).with(:web_search)
      expect(agent.instance_variable_get(:@resolved_tools)).to have_key(:web_search)
    end

    it "caches resolved tools" do
      agent = agent_class.new

      cached = agent.instance_variable_get(:@resolved_tools)[:web_search]
      expect(cached[:tool_class]).to eq(mock_tool_class)
      expect(cached[:instance]).not_to be_nil
    end

    it "resolves tools only once" do
      agent = agent_class.new

      # Access tools multiple times
      3.times { agent.build_tools_from_config }

      # Should only resolve once during initialize
      expect(RAAF::ToolRegistry).to have_received(:resolve).with(:web_search).once
    end
  end

  context "when tool not found" do
    before do
      allow(RAAF::ToolRegistry).to receive(:resolve)
        .with(:missing_tool)
        .and_return(nil)
    end

    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        tool :missing_tool
      end
    end

    it "raises ArgumentError with detailed message" do
      expect { agent_class.new }.to raise_error(ArgumentError) do |error|
        expect(error.message).to include("Tool Resolution Failed")
        expect(error.message).to include("missing_tool")
        expect(error.message).to include("Searched in:")
        expect(error.message).to include("Suggestions:")
      end
    end

    it "includes agent class name in error" do
      expect { agent_class.new }.to raise_error(ArgumentError) do |error|
        expect(error.message).to include("TestAgent")
      end
    end

    it "includes searched namespaces in error" do
      expect { agent_class.new }.to raise_error(ArgumentError) do |error|
        expect(error.message).to include("Ai::Tools")
        expect(error.message).to include("RAAF::Tools")
      end
    end
  end

  context "with direct class reference" do
    let(:custom_tool) { Class.new }
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        tool CustomTool
      end
    end

    before do
      stub_const("CustomTool", custom_tool)
      allow(custom_tool).to receive(:new).and_return(double("tool_instance"))
    end

    it "uses class directly without registry lookup" do
      agent = agent_class.new

      expect(RAAF::ToolRegistry).not_to have_received(:resolve)
      cached = agent.instance_variable_get(:@resolved_tools)[custom_tool]
      expect(cached[:tool_class]).to eq(custom_tool)
    end
  end
end
```

### 3. Tool Resolution Specs

**File:** `dsl/spec/raaf/dsl/tool_resolution_spec.rb`

```ruby
RSpec.describe "Tool Resolution Logic" do
  let(:mock_tool_class) { Class.new }

  before do
    allow(RAAF::ToolRegistry).to receive(:resolve).and_call_original
  end

  describe "#resolve_tool_class" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        tool :web_search
      end
    end

    context "with symbol identifier" do
      it "uses ToolRegistry for resolution" do
        allow(RAAF::ToolRegistry).to receive(:resolve)
          .with(:web_search)
          .and_return(mock_tool_class)

        agent = agent_class.new
        expect(RAAF::ToolRegistry).to have_received(:resolve).with(:web_search)
      end
    end

    context "with class identifier" do
      let(:direct_class) { Class.new }
      let(:agent_class) do
        Class.new(RAAF::DSL::Agent) do
          agent_name "TestAgent"
          tool DirectClass
        end
      end

      before do
        stub_const("DirectClass", direct_class)
        allow(direct_class).to receive(:new).and_return(double("tool"))
      end

      it "returns class without registry lookup" do
        agent = agent_class.new

        expect(RAAF::ToolRegistry).not_to have_received(:resolve)
      end
    end
  end

  describe "error messages" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "MySpecialAgent"
        tool :nonexistent_tool
      end
    end

    before do
      allow(RAAF::ToolRegistry).to receive(:resolve)
        .with(:nonexistent_tool)
        .and_return(nil)

      allow(RAAF::ToolRegistry).to receive(:list)
        .and_return([:web_search, :file_search])

      allow(RAAF::ToolRegistry).to receive(:namespaces)
        .and_return(["Ai::Tools", "RAAF::Tools"])
    end

    it "includes agent class name" do
      expect { agent_class.new }.to raise_error(ArgumentError, /MySpecialAgent/)
    end

    it "includes tool identifier" do
      expect { agent_class.new }.to raise_error(ArgumentError, /:nonexistent_tool/)
    end

    it "includes registry tools" do
      expect { agent_class.new }.to raise_error(ArgumentError, /web_search.*file_search/)
    end

    it "includes searched namespaces" do
      expect { agent_class.new }.to raise_error(ArgumentError, /Ai::Tools.*RAAF::Tools/)
    end

    it "includes suggestions" do
      expect { agent_class.new }.to raise_error(ArgumentError) do |error|
        expect(error.message).to include("Suggestions:")
        expect(error.message).to include("Verify")
        expect(error.message).to include("Register manually")
        expect(error.message).to include("Use direct reference")
      end
    end
  end
end
```

### 4. ToolRegistry Specs

**File:** `lib/spec/raaf/tool_registry_spec.rb`

```ruby
RSpec.describe RAAF::ToolRegistry do
  before do
    described_class.clear!
  end

  describe ".resolve" do
    context "with registered tool" do
      let(:tool_class) { Class.new }

      before do
        described_class.register(:custom_tool, tool_class)
      end

      it "returns registered class" do
        expect(described_class.resolve(:custom_tool)).to eq(tool_class)
      end
    end

    context "with auto-discovery" do
      let(:tool_class) { Class.new }

      before do
        stub_const("Ai::Tools::WebSearchTool", tool_class)
      end

      it "discovers tool in Ai::Tools namespace" do
        expect(described_class.resolve(:web_search)).to eq(tool_class)
      end
    end

    context "with direct class reference" do
      let(:tool_class) { Class.new }

      it "returns class unchanged" do
        expect(described_class.resolve(tool_class)).to eq(tool_class)
      end
    end

    context "when tool not found" do
      it "returns nil" do
        expect(described_class.resolve(:missing_tool)).to be_nil
      end
    end
  end
end
```

## Integration Test Specifications

### 5. Rails Eager Loading Simulation

**File:** `dsl/spec/integration/eager_loading_spec.rb`

```ruby
RSpec.describe "Rails Eager Loading Scenarios" do
  # Simulate Rails eager loading environment
  around do |example|
    original_eager_load = Rails.application.config.eager_load rescue nil

    # Mock Rails.application.config
    rails_config = double("config", eager_load: true)
    rails_app = double("application", config: rails_config)
    stub_const("Rails", double("Rails", application: rails_app))

    example.run

    # Restore if needed
  end

  context "when agent class loads before tool class" do
    it "resolves tool successfully at runtime" do
      # Define agent first (tool class not yet loaded)
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "EarlyAgent"
        tool :late_loading_tool
      end

      # Now define tool class (simulating later loading)
      tool_class = Class.new
      stub_const("Ai::Tools::LateLoadingTool", tool_class)
      allow(tool_class).to receive(:new).and_return(double("tool"))

      # Should resolve successfully during initialization
      expect { agent_class.new }.not_to raise_error
    end
  end

  context "with multiple agents and tools" do
    it "handles arbitrary class loading order" do
      # Mix of agents and tools defined in random order
      agent1_class = Class.new(RAAF::DSL::Agent) do
        agent_name "Agent1"
        tool :tool_a
        tool :tool_b
      end

      tool_a = Class.new
      stub_const("Ai::Tools::ToolATool", tool_a)
      allow(tool_a).to receive(:new).and_return(double("tool_a"))

      agent2_class = Class.new(RAAF::DSL::Agent) do
        agent_name "Agent2"
        tool :tool_b
        tool :tool_c
      end

      tool_b = Class.new
      stub_const("Ai::Tools::ToolBTool", tool_b)
      allow(tool_b).to receive(:new).and_return(double("tool_b"))

      tool_c = Class.new
      stub_const("Ai::Tools::ToolCTool", tool_c)
      allow(tool_c).to receive(:new).and_return(double("tool_c"))

      # All agents should initialize successfully
      expect { agent1_class.new }.not_to raise_error
      expect { agent2_class.new }.not_to raise_error
    end
  end

  context "when tool never loads" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "BrokenAgent"
        tool :truly_missing_tool
      end
    end

    it "fails during agent initialization with clear error" do
      expect { agent_class.new }.to raise_error(ArgumentError) do |error|
        expect(error.message).to include("Tool Resolution Failed")
        expect(error.message).to include("truly_missing_tool")
      end
    end
  end
end
```

## Performance Test Specifications

### 6. Performance Benchmarks

**File:** `dsl/spec/integration/performance_spec.rb`

```ruby
require 'benchmark'

RSpec.describe "Tool Resolution Performance" do
  let(:mock_tools) do
    3.times.map do |i|
      Class.new.tap { |klass| allow(klass).to receive(:new).and_return(double("tool_#{i}")) }
    end
  end

  before do
    allow(RAAF::ToolRegistry).to receive(:resolve).and_return(*mock_tools)
  end

  describe "resolution timing" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "PerformanceAgent"
        tool :web_search
        tool :file_search
        tool :calculator
      end
    end

    it "resolves 3 tools within 5ms" do
      elapsed = Benchmark.realtime { agent_class.new }

      expect(elapsed * 1000).to be < 5,
        "Tool resolution took #{(elapsed * 1000).round(2)}ms (expected < 5ms)"
    end

    it "adds minimal overhead to initialization" do
      # Baseline: agent without tools
      baseline_class = Class.new(RAAF::DSL::Agent) do
        agent_name "BaselineAgent"
      end

      baseline_time = Benchmark.realtime { baseline_class.new }
      tools_time = Benchmark.realtime { agent_class.new }

      overhead = (tools_time - baseline_time) * 1000
      expect(overhead).to be < 5,
        "Tool resolution overhead was #{overhead.round(2)}ms (expected < 5ms)"
    end
  end

  describe "cache effectiveness" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "CacheAgent"
        tool :web_search
      end
    end

    it "caches resolved tools for instant access" do
      agent = agent_class.new

      # First access (from cache)
      first_access = Benchmark.realtime { agent.build_tools_from_config }

      # Subsequent accesses (same cache)
      subsequent_accesses = 10.times.map do
        Benchmark.realtime { agent.build_tools_from_config }
      end

      avg_access_time = (subsequent_accesses.sum / 10) * 1000
      expect(avg_access_time).to be < 0.1,
        "Average cache access took #{avg_access_time.round(4)}ms (expected < 0.1ms)"
    end

    it "resolves each tool only once per instance" do
      agent = agent_class.new

      # Access tools 100 times
      100.times { agent.build_tools_from_config }

      # Should only resolve once (during initialize)
      expect(RAAF::ToolRegistry).to have_received(:resolve).once
    end
  end

  describe "memory usage" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "MemoryAgent"
        10.times { |i| tool :"tool_#{i}" }
      end
    end

    before do
      10.times do |i|
        tool_class = Class.new
        allow(RAAF::ToolRegistry).to receive(:resolve)
          .with(:"tool_#{i}")
          .and_return(tool_class)
        allow(tool_class).to receive(:new).and_return(double("tool_#{i}"))
      end
    end

    it "maintains reasonable memory footprint with many tools" do
      # Create 100 agent instances with 10 tools each
      agents = 100.times.map { agent_class.new }

      # Memory check (simplified - in real tests use ObjectSpace)
      expect(agents.size).to eq(100)
      agents.each do |agent|
        cached_tools = agent.instance_variable_get(:@resolved_tools)
        expect(cached_tools.size).to eq(10)
      end
    end
  end
end
```

## Test Mocking Patterns

### Tool Registry Mocking

```ruby
# Pattern 1: Mock successful resolution
before do
  allow(RAAF::ToolRegistry).to receive(:resolve)
    .with(:web_search)
    .and_return(MockWebSearchTool)
end

# Pattern 2: Mock failure
before do
  allow(RAAF::ToolRegistry).to receive(:resolve)
    .with(:missing_tool)
    .and_return(nil)
end

# Pattern 3: Mock with custom behavior
before do
  allow(RAAF::ToolRegistry).to receive(:resolve) do |identifier|
    case identifier
    when :web_search then MockWebSearchTool
    when :file_search then MockFileSearchTool
    else nil
    end
  end
end
```

### Tool Class Mocking

```ruby
# Mock tool class with new method
let(:mock_tool_class) do
  Class.new do
    def initialize(**options)
      @options = options
    end

    def to_function_tool
      self
    end
  end
end

# Stub tool instantiation
before do
  allow(mock_tool_class).to receive(:new).and_return(double("tool_instance"))
end
```

## Test Coverage Requirements

### Minimum Coverage Targets

| Component | Coverage | Tests |
|-----------|----------|-------|
| AgentToolIntegration | 100% | 20+ specs |
| Agent#initialize | 95% | 15+ specs |
| Tool resolution logic | 100% | 10+ specs |
| ToolRegistry | 100% | 8+ specs |
| Error handling | 100% | 10+ specs |
| Integration scenarios | 90% | 10+ specs |
| Performance benchmarks | N/A | 5+ specs |

### Critical Test Scenarios

1. ✅ **Tool resolution during initialize** - Core functionality
2. ✅ **Missing tool error handling** - User experience
3. ✅ **Cache effectiveness** - Performance
4. ✅ **Rails eager loading** - Production reliability
5. ✅ **Multiple tools** - Real-world usage
6. ✅ **Direct class reference** - API flexibility
7. ✅ **Configuration blocks** - Advanced usage
8. ✅ **Backward compatibility breakage** - Migration validation

## Test Execution

### Running Tests

```bash
# All tool loading tests
bundle exec rspec dsl/spec/raaf/dsl/agent_tool_integration_spec.rb
bundle exec rspec dsl/spec/raaf/dsl/agent_initialization_spec.rb
bundle exec rspec dsl/spec/raaf/dsl/tool_resolution_spec.rb

# Integration tests
bundle exec rspec dsl/spec/integration/eager_loading_spec.rb
bundle exec rspec dsl/spec/integration/performance_spec.rb

# All DSL tests
bundle exec rspec dsl/spec/
```

### CI/CD Requirements

```yaml
# .github/workflows/test.yml
test:
  runs-on: ubuntu-latest
  steps:
    - name: Run tool loading tests
      run: bundle exec rspec dsl/spec/raaf/dsl/agent_tool_integration_spec.rb

    - name: Run eager loading tests
      run: bundle exec rspec dsl/spec/integration/eager_loading_spec.rb

    - name: Performance benchmarks
      run: bundle exec rspec dsl/spec/integration/performance_spec.rb

    - name: Check coverage
      run: |
        coverage=$(bundle exec rspec --format json | jq '.coverage')
        if [ "$coverage" -lt 95 ]; then
          echo "Coverage below 95%: $coverage"
          exit 1
        fi
```

## References

- Main Spec: @.agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation/spec.md
- Technical Spec: @.agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation/sub-specs/technical-spec.md
- Tasks List: @.agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation/tasks.md
