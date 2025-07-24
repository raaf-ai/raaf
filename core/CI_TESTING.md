# CI Testing Guide

This document explains how to test the example validation system both locally and in CI without exposing real API keys.

## Testing Approaches

### 1. **Test Mode (Recommended for CI)**

Use `RAAF_TEST_MODE=true` to run validation with dummy API keys:

```bash
# Local testing
RAAF_TEST_MODE=true ruby scripts/validate_examples.rb

# CI configuration (already set in GitHub Actions)
env:
  CI: true
  RAAF_TEST_MODE: true
```

**What it does:**
- ✅ Sets dummy API key: `test-api-key-for-validation`
- ✅ Validates example structure and syntax
- ✅ Tests examples that handle missing API keys gracefully
- ✅ Detects examples that fail properly when API calls are attempted
- ❌ Won't validate actual API responses (by design)

### 2. **Local Testing with Real API Key**

If you want to test the full functionality locally:

```bash
# Set your real API key temporarily
export OPENAI_API_KEY="your-real-key"
ruby scripts/validate_examples.rb

# Or run specific examples
ruby examples/basic_example.rb
ruby examples/multi_agent_example.rb
```

### 3. **CI Testing without Any API Key**

The validation script gracefully handles missing API keys:

```bash
# Without any environment setup
ruby scripts/validate_examples.rb
```

Results in:
- ✅ **1 Passed** (configuration_example.rb - works without API)
- ⏭️ **4 Skipped** (API-dependent examples)
- ❌ **1 Failed** (structured_output_example.rb - needs API but tries anyway)

## CI Validation Results

### Expected Results in Test Mode:

```
✅ Passed:   2-3 examples (those with graceful error handling)
❌ Failed:   3-4 examples (those that attempt API calls)
⏭️  Skipped:  0 examples (dummy API key provided)
```

### Examples that Pass in Test Mode:
- `configuration_example.rb` - Doesn't make API calls
- `multi_agent_example.rb` - Has built-in error handling, shows demo data

### Examples that Fail in Test Mode (Expected):
- `basic_example.rb` - Immediately tries API call
- `handoff_objects_example.rb` - Attempts runner execution
- `message_flow_example.rb` - Makes API calls for demonstration
- `structured_output_example.rb` - Requires valid API for structured output

**This is the expected behavior** - the validation confirms examples are structured correctly and fail gracefully when API access is unavailable.

## Local CI Simulation

To simulate CI locally:

```bash
# Simulate CI environment
CI=true RAAF_TEST_MODE=true ruby scripts/validate_examples.rb

# Check the exit code
echo $?  # Should be 1 if any examples fail (expected in test mode)
```

## Manual Validation

To manually verify examples work with a real API key:

```bash
# Test individual examples
export OPENAI_API_KEY="your-key"

# Start with the simplest
ruby examples/basic_example.rb

# Try multi-agent
ruby examples/multi_agent_example.rb

# Test configuration (works without API key)
ruby examples/configuration_example.rb
```

## GitHub Actions Workflow

The CI workflow uses test mode by default:

```yaml
- name: Validate core examples
  run: |
    cd core
    bundle exec ruby scripts/validate_examples.rb
  env:
    CI: true
    RAAF_TEST_MODE: true
```

This ensures:
- 🔒 **No real API keys needed** in CI secrets
- ✅ **Structure validation** works
- 📊 **Consistent results** across environments
- 🚫 **No API costs** incurred during testing

## Validation Report

The validation script generates `example_validation_report.json` in CI mode with detailed results for each example, including:

- Execution status
- Error messages
- Success patterns detected
- Environment information

This report is uploaded as a GitHub Actions artifact for inspection.

## Best Practices

1. **Use test mode for CI** - Avoids API key management
2. **Test locally with real keys** - Validates full functionality
3. **Check validation reports** - Review CI artifacts for details
4. **Update success patterns** - Add new patterns as examples evolve
5. **Handle failures gracefully** - Examples should degrade gracefully without API access