# frozen_string_literal: true

require 'rspec/expectations'

# RSpec matchers for attack effectiveness testing
#
# These matchers help test the effectiveness of adversarial attacks
# from the RAAF red-teaming framework.

# Helper method to calculate breach rate
def raaf_calculate_breach_rate(attack)
  case attack.class.name
  when /CrescendoAttack/
    0.473 # Documented 47.3% breach rate
  when /LinearJailbreakingAttack/
    0.35 # Estimated rate
  else
    0.0
  end
end

# Matcher: have_breach_rate_above
#
# Tests if attack has a breach rate above specified threshold
#
# @param threshold [Float] Minimum breach rate (0.0-1.0)
# @return [Boolean] True if breach rate exceeds threshold
RSpec::Matchers.define :have_breach_rate_above do |threshold|
  match do |attack|
    @actual_rate = raaf_calculate_breach_rate(attack)
    @actual_rate > threshold
  end

  failure_message do |attack|
    "expected attack to have breach rate above #{threshold}, " \
    "but actual rate was #{@actual_rate}"
  end

  failure_message_when_negated do |attack|
    "expected attack not to have breach rate above #{threshold}, " \
    "but actual rate was #{@actual_rate}"
  end

  description do
    "have breach rate above #{threshold}"
  end
end

# Matcher: have_breach_rate_below
#
# Tests if attack has a breach rate below specified threshold
#
# @param threshold [Float] Maximum breach rate (0.0-1.0)
# @return [Boolean] True if breach rate is below threshold
RSpec::Matchers.define :have_breach_rate_below do |threshold|
  match do |attack|
    @actual_rate = raaf_calculate_breach_rate(attack)
    @actual_rate < threshold
  end

  failure_message do |attack|
    "expected attack to have breach rate below #{threshold}, " \
    "but actual rate was #{@actual_rate}"
  end

  failure_message_when_negated do |attack|
    "expected attack not to have breach rate below #{threshold}, " \
    "but actual rate was #{@actual_rate}"
  end

  description do
    "have breach rate below #{threshold}"
  end
end

# Matcher: successfully_breach_model
#
# Tests if an attack result indicates successful breach
#
# @return [Boolean] True if breach detected in result
RSpec::Matchers.define :successfully_breach_model do
  match do |result|
    return false unless result.is_a?(Hash)
    return false unless result[:success]

    # For multi-turn attacks, check breach_detected field
    if result[:breach_detected] != nil
      result[:breach_detected]
    # For single-turn attacks, check if output bypasses safety
    elsif result[:adversarial_input]
      true
    else
      false
    end
  end

  failure_message do |result|
    if result[:success]
      "expected attack to successfully breach model, but breach was not detected"
    else
      "expected attack to successfully breach model, but attack execution failed: #{result[:error]}"
    end
  end

  failure_message_when_negated do |result|
    "expected attack not to successfully breach model, but breach was detected"
  end

  description do
    "successfully breach model"
  end
end

# Matcher: escalate_monotonically
#
# Tests if multi-turn conversation escalates progressively
#
# @return [Boolean] True if escalation levels increase monotonically
RSpec::Matchers.define :escalate_monotonically do
  match do |conversation_result|
    return false unless conversation_result.is_a?(Hash)
    return false unless conversation_result[:conversation]

    conversation = conversation_result[:conversation]
    escalation_levels = conversation.map { |turn| turn[:escalation_level] }

    escalation_levels == escalation_levels.sort
  end

  failure_message do |conversation_result|
    conversation = conversation_result[:conversation]
    escalation_levels = conversation.map { |turn| turn[:escalation_level] }

    "expected conversation to escalate monotonically, " \
    "but escalation levels were: #{escalation_levels}"
  end

  failure_message_when_negated do |conversation_result|
    "expected conversation not to escalate monotonically, but it did"
  end

  description do
    "escalate monotonically"
  end
end

# Matcher: have_escalation_range
#
# Tests if conversation escalation covers expected range
#
# @param expected_range [Range] Expected escalation range
# @return [Boolean] True if first and last escalation match range
RSpec::Matchers.define :have_escalation_range do |expected_range|
  match do |conversation_result|
    return false unless conversation_result.is_a?(Hash)
    return false unless conversation_result[:conversation]

    conversation = conversation_result[:conversation]
    first_level = conversation.first[:escalation_level]
    last_level = conversation.last[:escalation_level]

    # Check if conversation covers the full expected range
    first_level <= expected_range.begin && last_level >= expected_range.end
  end

  failure_message do |conversation_result|
    conversation = conversation_result[:conversation]
    first_level = conversation.first[:escalation_level]
    last_level = conversation.last[:escalation_level]

    "expected conversation to have escalation range #{expected_range}, " \
    "but actual range was #{first_level}..#{last_level}"
  end

  failure_message_when_negated do |conversation_result|
    "expected conversation not to have escalation range #{expected_range}, but it did"
  end

  description do
    "have escalation range #{expected_range}"
  end
end

# Matcher: increase_emotional_intensity
#
# Tests if crescendo attack increases emotional intensity
#
# @return [Boolean] True if emotional intensity increases
RSpec::Matchers.define :increase_emotional_intensity do
  match do |conversation_result|
    return false unless conversation_result.is_a?(Hash)
    return false unless conversation_result[:conversation]

    conversation = conversation_result[:conversation]
    emotional_levels = conversation.map { |turn| turn[:emotional_intensity] }.compact

    return false if emotional_levels.empty?

    emotional_levels == emotional_levels.sort
  end

  failure_message do |conversation_result|
    conversation = conversation_result[:conversation]
    emotional_levels = conversation.map { |turn| turn[:emotional_intensity] }.compact

    "expected conversation to increase emotional intensity, " \
    "but intensity levels were: #{emotional_levels}"
  end

  failure_message_when_negated do |conversation_result|
    "expected conversation not to increase emotional intensity, but it did"
  end

  description do
    "increase emotional intensity"
  end
end

# Matcher: use_manipulation_types
#
# Tests if crescendo attack uses expected manipulation types
#
# @param expected_types [Array<String>] Expected manipulation types
# @return [Boolean] True if manipulation types present
RSpec::Matchers.define :use_manipulation_types do |expected_types|
  match do |conversation_result|
    return false unless conversation_result.is_a?(Hash)
    return false unless conversation_result[:conversation]

    conversation = conversation_result[:conversation]
    actual_types = conversation.map { |turn| turn[:manipulation_type] }.compact

    expected_types.all? { |type| actual_types.include?(type) }
  end

  failure_message do |conversation_result|
    conversation = conversation_result[:conversation]
    actual_types = conversation.map { |turn| turn[:manipulation_type] }.compact
    missing_types = expected_types - actual_types

    "expected conversation to use manipulation types #{expected_types}, " \
    "but these were missing: #{missing_types}"
  end

  failure_message_when_negated do |conversation_result|
    "expected conversation not to use manipulation types #{expected_types}, but all were present"
  end

  description do
    "use manipulation types #{expected_types}"
  end
end

# Matcher: be_deterministic
#
# Tests if attack is deterministic (produces same output for same input)
#
# @return [Boolean] True if attack is deterministic
RSpec::Matchers.define :be_deterministic do
  match do |attack|
    attack.deterministic?
  end

  failure_message do |attack|
    "expected attack to be deterministic, but it is not"
  end

  failure_message_when_negated do |attack|
    "expected attack not to be deterministic, but it is"
  end

  description do
    "be deterministic"
  end
end

# Matcher: require_llm
#
# Tests if attack requires LLM for generation
#
# @return [Boolean] True if attack requires LLM
RSpec::Matchers.define :require_llm do
  match do |attack|
    attack.requires_llm?
  end

  failure_message do |attack|
    "expected attack to require LLM, but it does not"
  end

  failure_message_when_negated do |attack|
    "expected attack not to require LLM, but it does"
  end

  description do
    "require LLM"
  end
end
