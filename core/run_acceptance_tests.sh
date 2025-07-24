#!/bin/bash

# Script to run acceptance tests against real OpenAI API

echo "Running RAAF acceptance tests against real OpenAI API..."
echo ""

# Check if OPENAI_API_KEY is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo "ERROR: OPENAI_API_KEY environment variable is not set"
    echo ""
    echo "Please set your OpenAI API key:"
    echo "  export OPENAI_API_KEY='your-api-key-here'"
    echo ""
    exit 1
fi

echo "✓ OpenAI API key is set"
echo ""

# Set environment to allow HTTP connections
export VCR_ALLOW_HTTP=true

# Disable tracing during tests (optional, but recommended)
export RAAF_DISABLE_TRACING=true

# Run the acceptance tests
echo "Running acceptance tests..."
echo "Note: These tests will make real API calls and incur costs"
echo ""

bundle exec rake spec:acceptance

echo ""
echo "Acceptance tests completed!"