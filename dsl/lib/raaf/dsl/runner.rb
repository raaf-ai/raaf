# frozen_string_literal: true

# DEPRECATED: Runner extension is no longer needed with pure delegation approach
#
# The DSL now acts as a pure configuration layer that delegates to openai-agents-ruby
# instead of extending or modifying its behavior. All handoff configuration is done
# during agent creation, and openai-agents-ruby handles everything natively.
#
# This module is kept for backward compatibility but is no longer used.
#
module AiAgentDsl::Runner
  # Legacy method - no longer used
  def set_dsl_context(_context)
    Rails.logger.warn "[DEPRECATED] AiAgentDsl::Runner is deprecated. Use pure delegation instead." if defined?(Rails)
  end

  # Legacy method - no longer used
  def find_handoff(_agent_name)
    Rails.logger.warn "[DEPRECATED] AiAgentDsl::Runner is deprecated. Use pure delegation instead." if defined?(Rails)
    nil
  end
end
