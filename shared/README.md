# RAAF Shared Tools

This directory contains shared tools and utilities that are used across all RAAF gems.

## Code Validator

The `RAAF::Shared::CodeValidator` provides a consistent way to validate example files and code blocks in all markdown documentation across all gems.

### Usage in Your Gem

1. Add the shared example validation rake tasks to your gem's Rakefile:

```ruby
# In your gem's Rakefile
$LOAD_PATH.unshift(File.expand_path("../shared/lib", __dir__))
require "raaf/shared/tasks"
RAAF::Shared::Tasks.load("code")
```

2. Available rake tasks:

```bash
# Validate all code examples (requires real API keys)
bundle exec rake code:validate

# Validate code examples in test mode (no real API calls)
bundle exec rake code:validate_test

# Validate only syntax of code examples
bundle exec rake code:validate_syntax

# List all example files
bundle exec rake code:list

# Run a specific example
bundle exec rake code:run[example_name.rb]
```

3. CI Integration:

```yaml
# In your GitHub Actions workflow
- name: Validate code examples in all markdown files
  run: |
    cd your-gem
    bundle exec rake code:validate_test
  env:
    CI: true
    RAAF_TEST_MODE: true
```

### Configuration

The validator automatically configures itself based on the gem name, but you can customize the behavior by modifying the `configure_validator_options` method in the rake task.

Default configuration includes:
- Timeout: 30 seconds per example
- Required environment variables (e.g., OPENAI_API_KEY)
- Success patterns for output validation
- Files to skip or run syntax-only validation

### Example Validation Report

In CI mode, the validator generates a JSON report with detailed results:

```json
{
  "gem": "dsl",
  "summary": {
    "total": 20,
    "passed": 18,
    "failed": 0,
    "skipped": 2,
    "warnings": 0,
    "success_rate": 90.0
  },
  "results": {
    "passed": [...],
    "failed": [...],
    "skipped": [...],
    "warnings": [...]
  },
  "timestamp": "2024-07-26T10:30:00+0000",
  "environment": {
    "ruby_version": "3.4.5",
    "gem_directory": "/path/to/gem",
    "ci_mode": true,
    "test_mode": true
  }
}
```

## Adding to a New Gem

### Automatic Setup

Run the setup script from your gem directory:

```bash
cd your-gem
ruby ../shared/setup_example_validation.rb
```

This will:
- Update your Rakefile with the shared tasks
- Create an examples directory if needed
- Add a sample example file
- Update your CI workflow if it exists
- Add a CI task to your Rakefile

### Manual Setup

1. Ensure your gem has an `examples/` directory with Ruby example files
2. Add the shared tasks to your Rakefile (see above)
3. Configure gem-specific options if needed
4. Add a CI task that includes example validation:

```ruby
# In your Rakefile
desc "Run all CI checks"
task ci: [:spec, :rubocop, "code:validate_test"]
```

5. Update your GitHub Actions workflow to use the rake task

## Best Practices

1. **Example Structure**: Keep examples focused and self-contained
2. **Dependencies**: Use test mode to avoid requiring real API keys in CI
3. **Success Indicators**: Include clear output that indicates successful execution
4. **Error Handling**: Examples should handle missing dependencies gracefully
5. **Documentation**: Include comments explaining what each example demonstrates