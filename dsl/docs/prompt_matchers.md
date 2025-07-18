# Custom RSpec Matchers for AI Agent DSL Prompts

This document describes the custom RSpec matchers available for testing AI Agent DSL prompts. These matchers provide a clean, expressive way to test prompt content, validation, and context handling.

## Installation

The matchers are automatically loaded when you require the spec_helper:

```ruby
require_relative "spec_helper"
```

## Available Matchers

### 1. `expect_prompt_to_include`

Tests whether prompt content includes specific text or patterns.

#### Basic Usage

```ruby
# Test content in any prompt
expect(prompt).to expect_prompt_to_include("OpenAI")

# Test content in specific prompt type
expect(prompt).to expect_prompt_to_include("system instructions").in_prompt(:system)
expect(prompt).to expect_prompt_to_include("user query").in_prompt(:user)

# Test with prompt class and context
expect(MyPrompt).to expect_prompt_to_include("document name")
  .with_context(document_name: "test.pdf")
```

#### Advanced Features

```ruby
# Multiple content expectations
expect(prompt).to expect_prompt_to_include("analysis", "report", "summary")

# Regex patterns
expect(prompt).to expect_prompt_to_include(/document.*\d{4}/)

# Negated expectations
expect(prompt).not_to expect_prompt_to_include("confidential")
```

#### Chain Methods

- `.in_prompt(type)` - Specify which prompt to check (:system or :user)
- `.with_context(hash)` - Provide context when testing prompt classes
- `.and_not_include(*content)` - Ensure content is NOT present

### 2. `validate_successfully`

Tests whether a prompt validates without errors.

#### Basic Usage

```ruby
# With prompt instance
prompt = MyPrompt.new(**context)
expect(prompt).to validate_successfully

# With prompt class
expect(MyPrompt).to validate_successfully.with_context(valid_context)
```

#### Examples

```ruby
describe "validation" do
  it "validates with complete context" do
    context = { document_name: "test.pdf", analysis_type: "basic" }
    expect(MyPrompt).to validate_successfully.with_context(context)
  end

  it "fails with incomplete context" do
    expect(MyPrompt).not_to validate_successfully.with_context({})
  end
end
```

### 3. `fail_validation`

Tests whether a prompt validation fails as expected.

#### Basic Usage

```ruby
# Expect validation to fail
expect(MyPrompt).to fail_validation.with_context({})

# Expect specific error message
expect(MyPrompt).to fail_validation
  .with_context({})
  .with_error(/Missing required variables/)
```

#### Chain Methods

- `.with_context(hash)` - Provide context for testing
- `.with_error(pattern)` - Specify expected error message (string or regex)

### 4. `have_context_variable`

Tests access to context variables and their values.

#### Basic Usage

```ruby
# Check if variable exists
expect(prompt).to have_context_variable(:document_name)

# Check variable value
expect(prompt).to have_context_variable(:document_name)
  .with_value("Annual Report 2024")

# Check default values
expect(prompt).to have_context_variable(:document_type)
  .with_default("Unknown")
```

## Complete Example

Here's a comprehensive example showing all matchers in action:

```ruby
# Define a prompt class
class DocumentAnalysisPrompt < RAAF::DSL::Prompts::Base
  requires :document_name, :analysis_type
  optional :urgency_level
  requires_from_context :document_path, path: [:document, :file_path]
  optional_from_context :page_count, path: [:document, :metadata, :pages], default: "unknown"

  def system
    <<~SYSTEM
      Analyze #{document_name} using #{analysis_type} analysis.
      Location: #{document_path}
      Pages: #{page_count}
      #{"Priority: #{context[:urgency_level]}" if context[:urgency_level]}
    SYSTEM
  end

  def user
    "Please analyze #{document_name}."
  end
end

# Test the prompt
RSpec.describe DocumentAnalysisPrompt do
  let(:context) do
    {
      document_name: "Annual Report 2024",
      analysis_type: "financial",
      document: {
        file_path: "/reports/annual_2024.pdf",
        metadata: { pages: 150 }
      }
    }
  end

  describe "content validation" do
    it "includes all required information" do
      expect(described_class).to expect_prompt_to_include(
        "Annual Report 2024",
        "financial analysis", 
        "/reports/annual_2024.pdf",
        "150"
      ).with_context(context)
    end

    it "organizes content correctly" do
      expect(described_class).to expect_prompt_to_include("Analyze")
        .in_prompt(:system)
        .with_context(context)
        
      expect(described_class).to expect_prompt_to_include("Please analyze")
        .in_prompt(:user)
        .with_context(context)
    end
  end

  describe "validation" do
    it "validates with complete context" do
      expect(described_class).to validate_successfully.with_context(context)
    end

    it "fails with missing required fields" do
      expect(described_class).to fail_validation
        .with_context({ document_name: "Test" })
        .with_error(/Missing required variables.*analysis_type/)
    end
  end

  describe "context access" do
    let(:prompt) { described_class.new(**context) }

    it "provides access to variables" do
      expect(prompt).to have_context_variable(:document_name)
        .with_value("Annual Report 2024")
      
      expect(prompt).to have_context_variable(:page_count)
        .with_value(150)
    end
  end
end
```

## Error Handling

The matchers provide helpful error messages when expectations fail:

```ruby
# When content is missing
Expected prompt to include: "Missing Content"
Missing content: "Missing Content"

Rendered content:
  system:
    You are analyzing Annual Report 2024...
  user:
    Please analyze Annual Report 2024.

# When validation fails unexpectedly
Expected prompt to validate successfully, but validation failed with: 
Missing required variables for MyPrompt: analysis_type
```

## Best Practices

### 1. Use Context Appropriately

```ruby
# Good: Use with_context for prompt classes
expect(MyPrompt).to expect_prompt_to_include("content")
  .with_context(valid_context)

# Good: Use instances when you have them
prompt = MyPrompt.new(**context)
expect(prompt).to expect_prompt_to_include("content")

# Bad: Don't mix contexts
prompt = MyPrompt.new(**context)
expect(prompt).to expect_prompt_to_include("content")
  .with_context(other_context)  # This will raise an error
```

### 2. Test Both Content and Structure

```ruby
describe "prompt structure" do
  it "includes content in correct sections" do
    expect(prompt).to expect_prompt_to_include("instructions").in_prompt(:system)
    expect(prompt).to expect_prompt_to_include("request").in_prompt(:user)
  end
end
```

### 3. Validate Edge Cases

```ruby
describe "edge cases" do
  it "handles missing optional fields" do
    minimal_context = { required_field: "value" }
    expect(MyPrompt).to validate_successfully.with_context(minimal_context)
    expect(MyPrompt).to expect_prompt_to_include("default_value")
      .with_context(minimal_context)
  end
end
```

### 4. Use Regex for Flexible Matching

```ruby
# Good for dynamic content
expect(prompt).to expect_prompt_to_include(/Report \d{4}/)
expect(prompt).to expect_prompt_to_include(/\d+ pages/)

# Good for flexible whitespace
expect(prompt).to expect_prompt_to_include(/analysis\s+type/)
```

## Integration with Existing Tests

These matchers work seamlessly with existing RSpec tests and can be mixed with standard expectations:

```ruby
it "creates and validates prompt" do
  # Standard RSpec
  prompt = MyPrompt.new(**context)
  expect(prompt).to be_a(MyPrompt)
  
  # Custom matchers
  expect(prompt).to validate_successfully
  expect(prompt).to expect_prompt_to_include("expected content")
  
  # Standard RSpec on rendered content
  messages = prompt.render_messages
  expect(messages[:system]).to be_a(String)
  expect(messages[:user]).to be_a(String)
end
```

## Troubleshooting

### Common Issues

1. **ArgumentError: Context required when testing prompt class**
   - Solution: Use `.with_context()` when testing prompt classes

2. **ArgumentError: Context should not be provided when testing prompt instance**
   - Solution: Don't use `.with_context()` with prompt instances

3. **VariableContractError during rendering**
   - Solution: Ensure all required variables are provided in context

4. **NoMethodError for context variables**
   - Solution: Check that variables are properly declared with `requires` or `optional`

### Debugging Tips

```ruby
# Debug rendered content
messages = prompt.render_messages
puts messages[:system]
puts messages[:user]

# Debug validation
begin
  prompt.validate!
rescue RAAF::DSL::Prompts::VariableContractError => e
  puts "Validation failed: #{e.message}"
end

# Debug context access
puts prompt.context.inspect
puts prompt.document_name  # Access specific variables
```