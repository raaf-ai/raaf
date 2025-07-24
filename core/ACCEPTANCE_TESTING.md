# RAAF Acceptance Testing Guide

## Running Acceptance Tests Against Real OpenAI API

The acceptance tests are designed to verify RAAF functionality against the real OpenAI API. By default, tests use mocked responses via WebMock/VCR. To run against the real API:

### Prerequisites

1. **Set your OpenAI API key:**
   ```bash
   export OPENAI_API_KEY='your-api-key-here'
   ```

2. **Important:** Running these tests will make real API calls and incur costs (using gpt-4o-mini model to minimize costs).

### Running Tests

#### Option 1: Using the provided script
```bash
./run_acceptance_tests.sh
```

#### Option 2: Manual execution
```bash
# Set environment variables
export OPENAI_API_KEY='your-api-key-here'
export VCR_ALLOW_HTTP=true  # Optional: allows HTTP connections
export RAAF_DISABLE_TRACING=true  # Optional: disables tracing

# Run acceptance tests
bundle exec rake spec:acceptance
```

#### Option 3: Run specific acceptance test file
```bash
export OPENAI_API_KEY='your-api-key-here'
bundle exec rspec spec/acceptance/basic_acceptance_spec.rb
```

### Test Configuration

The acceptance tests are configured to:

1. **Skip if no API key is set** - Tests will be skipped with a clear message
2. **Disable WebMock and VCR** - Allows real HTTP connections to OpenAI
3. **Use gpt-4o-mini model** - Minimizes API costs while still testing functionality
4. **Keep responses brief** - Agent instructions request concise responses

### What's Tested

The basic acceptance tests verify:

- Simple agent conversations
- Tool/function calling
- Multi-agent handoffs
- Error handling (max turns limit)
- Configuration options (temperature, response format)
- System prompts

### Troubleshooting

If you see WebMock errors:
- Ensure you're running the latest version of the code
- Check that WebMock is properly disabled in the test setup
- Make sure you're not running with VCR cassettes that might interfere

### Cost Considerations

The acceptance tests use `gpt-4o-mini` model which costs approximately:
- $0.004 per 1K tokens
- Typical test run: ~1000-2000 tokens total
- Estimated cost per full test run: < $0.01

### Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `OPENAI_API_KEY` | Your OpenAI API key | Yes |
| `VCR_ALLOW_HTTP` | Allow real HTTP connections | No (recommended) |
| `RAAF_DISABLE_TRACING` | Disable tracing during tests | No (recommended) |
| `RAAF_LOG_LEVEL` | Set to 'debug' for verbose output | No |