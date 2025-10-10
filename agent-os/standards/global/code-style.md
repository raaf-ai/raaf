# Code Style Guide

> Version: 1.0.0
> Last Updated: 2025-01-22

## Context

This file is part of the Agent OS standards system. These global code style rules are referenced by all product codebases and provide default formatting guidelines. Individual projects may extend or override these rules in their `.agent-os/product/code-style.md` file.

## General Formatting

### File Structure
- Start every Ruby file with `# frozen_string_literal: true`
- Place all `require` statements at the top after frozen string literal
- One class or module per file generally
- File names match class/module names in snake_case

### Indentation
- Use 2 spaces for indentation (never tabs)
- Maintain consistent indentation throughout files
- Empty lines around class and module bodies
- Clear separation between method sections with blank lines

### Naming Conventions
- **Methods and Variables**: Use snake_case (e.g., `add_tool`, `max_turns`)
- **Classes and Modules**: Use CamelCase (e.g., `Agent`, `FunctionTool`)
- **Constants**: Use UPPER_SNAKE_CASE (e.g., `MAX_RETRY_COUNT`)
- **File Names**: Use snake_case.rb matching class/module names

### String Formatting
- Use double quotes for all strings: `"Hello World"`
- Use double quotes with interpolation: `"Hello #{name}"`
- Use heredocs for multi-line strings with `<<~` syntax:
  ```ruby
  description = <<~TEXT
    This is a multi-line
    string with proper indentation
  TEXT
  ```

## Ruby Code Organization

### Module and Class Structure
```ruby
# frozen_string_literal: true

require "necessary_files"

module RAAF
  # YARD documentation for the class
  # @example Usage example
  #   agent = RAAF::Agent.new(name: "Helper")
  class ClassName
    include RequiredModules
    
    attr_accessor :attribute_name
    attr_reader :read_only_attribute
    
    # Constructor comes first
    def initialize(name:, **options)
      @name = name
      @options = options
    end
    
    # Public methods follow
    def public_method
      # Implementation
    end
    
    private
    
    # Private methods at the end
    def private_method
      # Implementation
    end
  end
end
```

### Method Definitions
- Use keyword arguments for clarity: `def method(name:, age: nil)`
- Break long method signatures across multiple lines:
  ```ruby
  def complex_method(
    required_param:,
    optional_param: nil,
    another_param: DEFAULT_VALUE
  )
    # Implementation
  end
  ```

### Hash Syntax
- Use modern hash syntax with symbols: `{ name: "value", age: 30 }`
- Align hash values vertically when multi-line:
  ```ruby
  config = {
    name:        "Agent",
    temperature: 0.7,
    max_tokens:  1000
  }
  ```

### Block Syntax
- Use `do...end` for multi-line blocks
- Use `{...}` for single-line blocks
- Example:
  ```ruby
  # Multi-line
  items.each do |item|
    process(item)
    log(item)
  end
  
  # Single-line
  items.map { |item| item.name }
  ```

## Documentation

### YARD Documentation Style
- Document all public classes and methods
- Use YARD tags for parameters, returns, and examples
- Format:
  ```ruby
  # Brief description of the method
  #
  # @param name [String] Description of the parameter
  # @param options [Hash] Optional parameters
  # @option options [Integer] :timeout Timeout in seconds
  # @return [Result] Description of return value
  # @example Basic usage
  #   agent.process(name: "task", timeout: 30)
  def process(name:, **options)
    # Implementation
  end
  ```

### Inline Comments
- Use `#` for inline comments
- Place comments above the code they describe
- Focus on "why" not "what"

## Testing Conventions

### RSpec Structure
```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Agent do
  subject(:agent) { described_class.new(name: "Test Agent") }
  
  let(:tool) { instance_double(RAAF::Tool) }
  
  describe "#initialize" do
    it "creates an agent with the given name" do
      expect(agent.name).to eq("Test Agent")
    end
  end
  
  describe "#add_tool" do
    context "when tool is valid" do
      it "adds the tool to the agent" do
        agent.add_tool(tool)
        expect(agent.tools).to include(tool)
      end
    end
  end
end
```

### Test Organization
- Use `describe` blocks for methods and contexts
- Use `context` blocks for different scenarios
- Use `it` blocks with descriptive names
- Use `let` for lazy-loaded test data
- Use `subject` for the main object being tested

## Error Handling

### Custom Errors
```ruby
module RAAF
  class Error < StandardError; end
  
  # Specific error with detailed message
  class ConfigurationError < Error
    def initialize(missing_param)
      super("Configuration error: #{missing_param} is required")
    end
  end
end
```

## Code Quality Tools

### RuboCop Configuration
- Target Ruby version: 3.3
- Use project-specific `.rubocop.yml`
- Notable conventions:
  - Line length limits disabled (but keep reasonable)
  - Metrics cops disabled for flexibility
  - Documentation cop disabled (YARD used instead)

### Development Tools
- Use `binding.pry` for debugging
- Use `require "debug"` for breakpoints
- Format code before committing

## Ruby Idioms and Best Practices

### Safe Navigation
```ruby
# Use safe navigation operator
user&.profile&.name
```

### Method Chaining
```ruby
# Keep chains readable
result = data
  .select { |item| item.active? }
  .map(&:name)
  .sort
```

### Keyword Arguments
```ruby
# Prefer keyword arguments for clarity
def create_agent(name:, model: "gpt-4", temperature: 0.7)
  # Implementation
end
```

---

*Customize this file with your team's specific style preferences. These formatting rules apply to all code written by humans and AI agents.*
