# Tests to Move to Other Gems

## Guardrails Gem
From `spec/agent_spec.rb`:
- Lines 198-209: `#input_guardrails?` tests
- Lines 211-222: `#output_guardrails?` tests  
- Lines 253-260: `#reset_input_guardrails!` tests
- Lines 262-269: `#reset_output_guardrails!` tests
- Lines 271-285: `#reset!` tests (partial - guardrails portion)

## Tools Gem
From `spec/models_spec.rb`:
- Tests that reference `RAAF::Tools` module

## Tracing Gem
From `spec/runner_spec.rb`:
- Line 337: "traces handoff events" test (if it actually tests tracing internals)

## Streaming Gem
- No specific tests found that require moving (streaming flag test works without the gem)