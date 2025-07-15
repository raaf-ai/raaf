# frozen_string_literal: true

# Custom RSpec matchers for AI Agent DSL

RSpec::Matchers.define :handoff_to do |expected_agent|
  match do |actual|
    @actual_handoff = actual["handoff_to"] || actual[:handoff_to]
    @actual_handoff == expected_agent
  end

  failure_message do |actual|
    "expected #{actual.inspect} to handoff to #{expected_agent.inspect}, but got #{@actual_handoff.inspect}"
  end

  failure_message_when_negated do |actual|
    "expected #{actual.inspect} not to handoff to #{expected_agent.inspect}, but it did"
  end

  description do
    "handoff to #{expected_agent.inspect}"
  end
end
