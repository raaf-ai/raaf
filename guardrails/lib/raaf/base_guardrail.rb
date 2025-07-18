# frozen_string_literal: true

require_relative "base"

module RAAF
  module Guardrails
    # Base class for guardrails that provides common functionality
    class BaseGuardrail < Base
      def initialize(**options)
        super(**options)
      end
    end
  end
end