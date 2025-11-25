# frozen_string_literal: true

module RAAF
  module Rails
    ##
    # Base class for all RAAF Rails background jobs
    class ApplicationJob < ActiveJob::Base
      # Automatically retry jobs on transient errors
      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      # Don't retry on permanent errors
      discard_on ActiveJob::DeserializationError
    end
  end
end
